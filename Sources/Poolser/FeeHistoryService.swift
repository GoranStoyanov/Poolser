import Foundation

struct FeeHistoryCache: Codable {
    /// Top of the next historical chunk to scan (going backward). nil = fully bootstrapped.
    var nextScanCeiling: Int?
    /// Highest block already scanned — used to pick up new blocks each refresh.
    var lastSeenBlock: Int
    var fees: [String: PositionFees]
    /// Earliest IncreaseLiquidity block found per tokenId — used to bound backward scan.
    var knownMintBlocks: [String: Int]

    struct PositionFees: Codable {
        var amount0: Double
        var amount1: Double
    }

    // Custom decode so old caches without knownMintBlocks don't fail.
    init(nextScanCeiling: Int?, lastSeenBlock: Int, fees: [String: PositionFees], knownMintBlocks: [String: Int] = [:]) {
        self.nextScanCeiling = nextScanCeiling
        self.lastSeenBlock = lastSeenBlock
        self.fees = fees
        self.knownMintBlocks = knownMintBlocks
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nextScanCeiling = try c.decodeIfPresent(Int.self, forKey: .nextScanCeiling)
        lastSeenBlock = try c.decode(Int.self, forKey: .lastSeenBlock)
        fees = try c.decode([String: PositionFees].self, forKey: .fees)
        knownMintBlocks = (try? c.decode([String: Int].self, forKey: .knownMintBlocks)) ?? [:]
    }
}

// keccak256("Collect(uint256,address,uint256,uint256)") — verified from on-chain events
private let collectEventTopic = "0x40d0efd1a53d60ecbf40971b9daf7dc90178c3aadc7aab1765632738fa8b8f01"
// keccak256("IncreaseLiquidity(uint256,uint128,uint256,uint256)") — verified known value
private let increaseLiquidityTopic = "0x3067048beee31b25b2f1681f88dac838c8bba36af25bfb2b7cf7473a5847e35f"

private let tokenIdBatchSize = 50

/// Bump when the cache format or scan semantics change; older caches are discarded once.
/// v2: cursors only advance over successfully scanned ranges (v1 caches may have gaps).
private let cacheKeyPrefix = "v3FeeHistory.v2."

struct FeeHistoryService {

    struct Result {
        var fees: [String: (amount0: Double, amount1: Double)]
        var bootstrapInProgress: Bool
    }

    /// eth_getLogs for the NFPM over an inclusive block range.
    typealias LogFetcher = (_ topics: [[String]?], _ fromBlock: Int, _ toBlock: Int) async throws -> [[String: Any]]

    private static let scanQueue = ScanQueue()

    private static let legacyCachesRemoved: Void = {
        let ud = UserDefaults.standard
        for key in ud.dictionaryRepresentation().keys
        where key.hasPrefix("v3FeeHistory.") && !key.hasPrefix(cacheKeyPrefix) {
            ud.removeObject(forKey: key)
        }
    }()

    static func scan(
        positions: [Position],
        nfpm: String,
        deployBlock: Int,
        currentBlock: Int,
        eth: EthereumClient,
        chainID: String,
        wallet: String
    ) async -> Result {
        _ = legacyCachesRemoved

        let chunkSize = AppSettings.shared.v4LogChunkSize
        let baseMaxChunks = AppSettings.shared.v4BootstrapMaxChunksPerRefresh
        // Scale maxChunks so each refresh covers roughly the same calendar time on all chains.
        // Capped at 10× to avoid excessive RPC calls on very fast chains (Arbitrum, MegaETH).
        let blockTimeFactor = max(1, Int((12.0 / (SupportedChain.byID(chainID)?.blockTimeSeconds ?? 12)).rounded()))
        let maxChunks = baseMaxChunks * min(blockTimeFactor, 10)

        return await scan(
            positions: positions,
            deployBlock: deployBlock,
            currentBlock: currentBlock,
            chainID: chainID,
            wallet: wallet,
            chunkSize: chunkSize,
            maxChunks: maxChunks,
            store: .standard
        ) { topics, fromBlock, toBlock in
            try await eth.ethGetLogsOR(
                address: nfpm,
                topics: topics,
                fromBlock: "0x" + String(fromBlock, radix: 16),
                toBlock: "0x" + String(toBlock, radix: 16),
                context: "feeHist[\(chainID)]"
            )
        }
    }

    /// Scans for one wallet/chain are serialized: a scan starts only after the previous one
    /// for the same cache key has saved, so a cancelled scan still unwinding can never
    /// overwrite newer progress with older cursors.
    static func scan(
        positions: [Position],
        deployBlock: Int,
        currentBlock: Int,
        chainID: String,
        wallet: String,
        chunkSize: Int,
        maxChunks: Int,
        store: UserDefaults,
        fetchLogs: @escaping LogFetcher
    ) async -> Result {
        guard !positions.isEmpty else {
            return Result(fees: [:], bootstrapInProgress: false)
        }
        let cacheKey = cacheKey(chainID: chainID, wallet: wallet)
        let context = ScanContext(
            positions: positions,
            chunkSize: max(1, chunkSize),
            maxChunks: max(1, maxChunks),
            chainID: chainID,
            fetchLogs: fetchLogs
        )
        return await scanQueue.run(key: cacheKey) {
            await performScan(
                context: context,
                deployBlock: deployBlock,
                currentBlock: currentBlock,
                cacheKey: cacheKey,
                store: store
            )
        }
    }

    static func cacheKey(chainID: String, wallet: String) -> String {
        "\(cacheKeyPrefix)\(chainID).\(wallet.lowercased())"
    }

    // MARK: - Private

    private struct ScanContext {
        let tokenIds: [String]
        let decMap: [String: (dec0: Int, dec1: Int)]
        let tokenTopicBatches: [[String]]
        let chunkSize: Int
        let maxChunks: Int
        let chainID: String
        let fetchLogs: LogFetcher

        init(positions: [Position], chunkSize: Int, maxChunks: Int, chainID: String, fetchLogs: @escaping LogFetcher) {
            tokenIds = positions.map(\.tokenId)
            decMap = Dictionary(positions.map { ($0.tokenId, ($0.dec0, $0.dec1)) }, uniquingKeysWith: { first, _ in first })
            let topics = Array(Set(tokenIds)).sorted().map { "0x" + String(format: "%064x", UInt64($0) ?? 0) }
            tokenTopicBatches = stride(from: 0, to: topics.count, by: tokenIdBatchSize).map {
                Array(topics[$0..<min($0 + tokenIdBatchSize, topics.count)])
            }
            self.chunkSize = chunkSize
            self.maxChunks = maxChunks
            self.chainID = chainID
            self.fetchLogs = fetchLogs
        }
    }

    private static func performScan(
        context: ScanContext,
        deployBlock: Int,
        currentBlock: Int,
        cacheKey: String,
        store: UserDefaults
    ) async -> Result {
        var cache: FeeHistoryCache = loadCache(forKey: cacheKey, store: store)
            ?? FeeHistoryCache(nextScanCeiling: currentBlock, lastSeenBlock: currentBlock, fees: [:])

        // 1. Fresh scan: pick up new blocks since last refresh. lastSeenBlock advances
        // chunk by chunk, so a failure or the maxChunks cap leaves the rest for next time.
        var interrupted = false
        if currentBlock > cache.lastSeenBlock {
            interrupted = !(await scanForward(to: currentBlock, context: context, cache: &cache))
        }

        // 2. Historical bootstrap: scan backward from nextScanCeiling.
        // Stop at the earliest known position creation block rather than deployBlock,
        // so we don't scan blocks that predate the wallet.
        let lowerBound = effectiveLowerBound(cache: cache, tokenIds: context.tokenIds, deployBlock: deployBlock)
        if !interrupted, let ceiling = cache.nextScanCeiling, ceiling >= lowerBound {
            interrupted = !(await scanBackward(from: ceiling, downTo: lowerBound, context: context, cache: &cache))
        }
        // Recompute after scan — knownMintBlocks may have been updated.
        let newLower = effectiveLowerBound(cache: cache, tokenIds: context.tokenIds, deployBlock: deployBlock)
        if let ceiling = cache.nextScanCeiling, ceiling < newLower {
            cache.nextScanCeiling = nil
        }

        // Cursors only cover completed chunks, so saving after a failure or cancellation is safe.
        saveCache(cache, forKey: cacheKey, store: store)
        let bootstrapInProgress = cache.nextScanCeiling != nil || cache.lastSeenBlock < currentBlock
        return Result(fees: feeDict(from: cache), bootstrapInProgress: bootstrapInProgress)
    }

    /// Returns the block we can safely stop scanning at.
    /// Once we know when every tracked position was created, we stop at the earliest
    /// creation block — no Collect event can exist before a position's mint.
    private static func effectiveLowerBound(
        cache: FeeHistoryCache,
        tokenIds: [String],
        deployBlock: Int
    ) -> Int {
        guard !tokenIds.isEmpty,
              tokenIds.allSatisfy({ cache.knownMintBlocks[$0] != nil }),
              let earliest = tokenIds.compactMap({ cache.knownMintBlocks[$0] }).min()
        else { return deployBlock }
        return max(deployBlock, earliest)
    }

    /// Scans ascending chunks after `lastSeenBlock`. Returns false if stopped by an error or cancellation.
    private static func scanForward(
        to upper: Int,
        context: ScanContext,
        cache: inout FeeHistoryCache
    ) async -> Bool {
        var chunksScanned = 0
        while cache.lastSeenBlock < upper && chunksScanned < context.maxChunks {
            let from = cache.lastSeenBlock + 1
            let to = min(from + context.chunkSize - 1, upper)
            guard let logs = await fetchChunk(from: from, to: to, context: context) else { return false }
            parseLogs(logs, decMap: context.decMap, into: &cache)
            cache.lastSeenBlock = to
            chunksScanned += 1
        }
        return true
    }

    /// Scans descending chunks from `ceiling`, so completed blocks always form one contiguous
    /// range ending at the old ceiling. Returns false if stopped by an error or cancellation.
    private static func scanBackward(
        from ceiling: Int,
        downTo lowerBound: Int,
        context: ScanContext,
        cache: inout FeeHistoryCache
    ) async -> Bool {
        var top = ceiling
        var chunksScanned = 0
        while top >= lowerBound && chunksScanned < context.maxChunks {
            let bottom = max(top - context.chunkSize + 1, lowerBound)
            guard let logs = await fetchChunk(from: bottom, to: top, context: context) else { return false }
            parseLogs(logs, decMap: context.decMap, into: &cache)
            top = bottom - 1
            cache.nextScanCeiling = top
            chunksScanned += 1
        }
        return true
    }

    /// Fetches every tokenId batch for one chunk. Returns nil unless all batches succeed,
    /// so a chunk is applied to the cache all at once or not at all.
    private static func fetchChunk(from: Int, to: Int, context: ScanContext) async -> [[String: Any]]? {
        var logs: [[String: Any]] = []
        do {
            for batch in context.tokenTopicBatches {
                try Task.checkCancellation()
                logs += try await context.fetchLogs([[collectEventTopic, increaseLiquidityTopic], batch], from, to)
            }
            try Task.checkCancellation()
            return logs
        } catch {
            if !Task.isCancelled {
                let chainID = context.chainID
                Task { @MainActor in
                    LogStore.shared.log("feeHistory[\(chainID)] \(from)–\(to): \(error.localizedDescription)", level: .error)
                }
            }
            return nil
        }
    }

    private static func parseLogs(
        _ logs: [[String: Any]],
        decMap: [String: (dec0: Int, dec1: Int)],
        into cache: inout FeeHistoryCache
    ) {
        for entry in logs {
            guard let topics = entry["topics"] as? [String], topics.count >= 2 else { continue }
            let tidHex = topics[1]
            let clean = tidHex.hasPrefix("0x") ? String(tidHex.dropFirst(2)) : tidHex
            guard let tokenIdVal = UInt64(clean, radix: 16) else { continue }
            let tokenIdStr = String(tokenIdVal)
            guard decMap[tokenIdStr] != nil else { continue }

            let topic0 = topics[0]

            if topic0 == increaseLiquidityTopic {
                // Track the earliest block we've seen this position exist.
                if let blockHex = entry["blockNumber"] as? String,
                   let blockNum = Int(blockHex.hasPrefix("0x") ? String(blockHex.dropFirst(2)) : blockHex, radix: 16) {
                    let prev = cache.knownMintBlocks[tokenIdStr] ?? Int.max
                    cache.knownMintBlocks[tokenIdStr] = min(prev, blockNum)
                }
                continue
            }

            guard topic0 == collectEventTopic else { continue }
            guard let decs = decMap[tokenIdStr] else { continue }
            let dataHex = entry["data"] as? String ?? ""
            guard let logData = Data(hexString: dataHex), logData.count >= 96 else { continue }
            // Collect data: recipient (32B) | amount0 (32B) | amount1 (32B)
            let a0 = logData.readAmount(wordAt: 32, decimals: decs.dec0)
            let a1 = logData.readAmount(wordAt: 64, decimals: decs.dec1)
            var existing = cache.fees[tokenIdStr] ?? FeeHistoryCache.PositionFees(amount0: 0, amount1: 0)
            existing.amount0 += a0
            existing.amount1 += a1
            cache.fees[tokenIdStr] = existing
        }
    }

    static func loadCache(forKey key: String, store: UserDefaults = .standard) -> FeeHistoryCache? {
        guard let data = store.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(FeeHistoryCache.self, from: data)
    }

    private static func saveCache(_ cache: FeeHistoryCache, forKey key: String, store: UserDefaults) {
        if let data = try? JSONEncoder().encode(cache) {
            store.set(data, forKey: key)
        }
    }

    private static func feeDict(from cache: FeeHistoryCache) -> [String: (amount0: Double, amount1: Double)] {
        cache.fees.mapValues { ($0.amount0, $0.amount1) }
    }

    /// Clears ALL cached fee history (call when scan logic changes to force a fresh scan).
    static func clearAllCaches() {
        let ud = UserDefaults.standard
        for key in ud.dictionaryRepresentation().keys where key.hasPrefix("v3FeeHistory.") {
            ud.removeObject(forKey: key)
        }
    }

    /// Clears cached fee history for a wallet across all chains (call on wallet change).
    static func clearCache(wallet: String) {
        let prefix = cacheKeyPrefix
        let suffix = ".\(wallet.lowercased())"
        let ud = UserDefaults.standard
        for key in ud.dictionaryRepresentation().keys where key.hasPrefix(prefix) && key.hasSuffix(suffix) {
            ud.removeObject(forKey: key)
        }
    }
}

/// Runs operations for the same key one after another, in call order.
private actor ScanQueue {
    private var tails: [String: Task<Void, Never>] = [:]

    func run<T>(key: String, _ operation: @escaping () async -> T) async -> T {
        let previous = tails[key]
        let task = Task<T, Never> {
            await previous?.value
            return await operation()
        }
        tails[key] = Task { _ = await task.value }
        // The queued task is unstructured, so forward the caller's cancellation to it.
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
