import Foundation

struct FeeHistoryCache: Codable {
    /// Top of the next historical chunk to scan (going backward). nil = fully bootstrapped.
    var nextScanCeiling: Int?
    /// Highest block already scanned — used to pick up new blocks each refresh.
    var lastSeenBlock: Int
    var fees: [String: PositionFees]
    /// Earliest IncreaseLiquidity block found per tokenId — used to bound backward scan.
    var knownMintBlocks: [String: Int]
    /// Exact creation block per tokenId, found from historical state. Unlike `knownMintBlocks`
    /// it cannot be a later liquidity add, so the scan can stop right at it.
    var creationBlocks: [String: Int] = [:]

    struct PositionFees: Codable {
        /// Σ Collect — principal and fees, since decreaseLiquidity() principal leaves via collect().
        var amount0: Double = 0
        var amount1: Double = 0
        /// Σ DecreaseLiquidity — principal moved into tokensOwed.
        var withdrawn0: Double = 0
        var withdrawn1: Double = 0

        var claimed0: Double { max(0, amount0 - withdrawn0) }
        var claimed1: Double { max(0, amount1 - withdrawn1) }
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
        creationBlocks = (try? c.decode([String: Int].self, forKey: .creationBlocks)) ?? [:]
    }
}

// keccak256("Collect(uint256,address,uint256,uint256)") — verified from on-chain events
private let collectEventTopic = "0x40d0efd1a53d60ecbf40971b9daf7dc90178c3aadc7aab1765632738fa8b8f01"
// keccak256("IncreaseLiquidity(uint256,uint128,uint256,uint256)") — verified known value
private let increaseLiquidityTopic = "0x3067048beee31b25b2f1681f88dac838c8bba36af25bfb2b7cf7473a5847e35f"
// keccak256("DecreaseLiquidity(uint256,uint128,uint256,uint256)") — verified with cast keccak
private let decreaseLiquidityTopic = "0x26f6a048ee9138f2c0ce266f322cb99228e8d619ae2bff30c67f8dcf9d2377b4"

private let tokenIdBatchSize = 50

/// First block whose state can be read with a historical eth_call, where it is later than the
/// v3 deployment. Optimism's pre-Bedrock blocks are not served by the regular nodes.
private let historicalStateFloor = ["optimism": 105_235_063]

/// Bump when the cache format or scan semantics change; older caches are discarded once.
/// v2: cursors only advance over successfully scanned ranges (v1 caches may have gaps).
/// v3: DecreaseLiquidity principal tracked separately (v2 caches count it as claimed fees).
private let cacheKeyPrefix = "v3FeeHistory.v3."

struct FeeHistoryService {

    struct Result {
        /// Claimed fees per tokenId: collected amounts minus withdrawn principal.
        var fees: [String: (amount0: Double, amount1: Double)]
        var bootstrapInProgress: Bool
    }

    /// eth_getLogs for the NFPM over an inclusive block range.
    typealias LogFetcher = (_ topics: [[String]?], _ fromBlock: Int, _ toBlock: Int) async throws -> [[String: Any]]
    /// Block at which a tokenId was minted, or nil when it cannot be determined.
    typealias CreationBlockFinder = (_ tokenId: String) async -> Int?

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
        wallet: String,
        chunkSize: Int,
        baseMaxChunks: Int
    ) async -> Result {
        _ = legacyCachesRemoved

        // Scale maxChunks so each refresh covers roughly the same calendar time on all chains.
        // Capped at 10× to avoid excessive RPC calls on very fast chains (Arbitrum, MegaETH).
        let blockTimeFactor = max(1, Int((12.0 / (SupportedChain.byID(chainID)?.blockTimeSeconds ?? 12)).rounded()))
        let maxChunks = baseMaxChunks * min(blockTimeFactor, 10)

        let floor = max(deployBlock, historicalStateFloor[chainID] ?? 0)
        let findCreationBlock: CreationBlockFinder = { tokenId in
            guard let id = UInt64(tokenId) else { return nil }
            let call = ABI.callPositions(tokenId: id)
            let exists: (Int) async throws -> Bool = { block in
                do {
                    // positions() returns 12 words for a minted token and reverts before.
                    return try await eth.ethCall(to: nfpm, data: call, block: block).count >= 12 * 32
                } catch EthereumClient.Err.reverted {
                    return false
                }
            }
            // A token that already existed at the floor was minted where state cannot be read.
            if floor > deployBlock {
                guard let atFloor = try? await exists(floor), !atFloor else { return nil }
            }
            return await firstBlock(after: floor - 1, upTo: currentBlock, where: exists)
        }

        return await scan(
            positions: positions,
            deployBlock: deployBlock,
            currentBlock: currentBlock,
            chainID: chainID,
            wallet: wallet,
            chunkSize: chunkSize,
            maxChunks: maxChunks,
            store: .standard,
            findCreationBlock: findCreationBlock
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
        findCreationBlock: CreationBlockFinder? = nil,
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
                store: store,
                findCreationBlock: findCreationBlock
            )
        }
    }

    /// Smallest block in `low+1...high` where `exists` is true, assuming it is false at `low`,
    /// true at `high` and stays true once it turns true. About log2(high - low) reads.
    /// nil when a read fails, so the caller falls back to scanning without a known start.
    static func firstBlock(after low: Int, upTo high: Int, where exists: (Int) async throws -> Bool) async -> Int? {
        var lo = low, hi = high
        while hi - lo > 1 {
            let mid = lo + (hi - lo) / 2
            guard let found = try? await exists(mid) else { return nil }
            if found { hi = mid } else { lo = mid }
        }
        return hi
    }

    /// NFPM token ids grow with mint order, so the smallest one is the oldest position.
    private static func oldestTokenId(_ tokenIds: [String]) -> String? {
        tokenIds.min { (UInt64($0) ?? 0) < (UInt64($1) ?? 0) }
    }

    static func cacheKey(chainID: String, wallet: String) -> String {
        "\(cacheKeyPrefix)\(chainID).\(wallet.lowercased())"
    }

    // MARK: - Private

    private struct ScanContext {
        let tokenIds: [String]
        var oldestTokenId: String? { FeeHistoryService.oldestTokenId(tokenIds) }
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
        store: UserDefaults,
        findCreationBlock: CreationBlockFinder?
    ) async -> Result {
        var cache: FeeHistoryCache = loadCache(forKey: cacheKey, store: store)
            ?? FeeHistoryCache(nextScanCeiling: currentBlock, lastSeenBlock: currentBlock, fees: [:])
        // Saved after every chunk, so quitting or a refresh that cancels a long scan loses nothing.
        let checkpoint: (FeeHistoryCache) -> Void = { saveCache($0, forKey: cacheKey, store: store) }

        // Only needed while the history is still being bootstrapped.
        if cache.nextScanCeiling != nil, let oldest = context.oldestTokenId, cache.creationBlocks[oldest] == nil,
           let findCreationBlock {
            let chainID = context.chainID
            if let block = await findCreationBlock(oldest) {
                cache.creationBlocks[oldest] = block
                checkpoint(cache)
                Task { @MainActor in
                    LogStore.shared.log("feeHistory[\(chainID)]: oldest position #\(oldest) created in block \(block)", level: .info)
                }
            } else if !Task.isCancelled {
                Task { @MainActor in
                    LogStore.shared.log("feeHistory[\(chainID)]: creation block of #\(oldest) unknown — scanning to the earliest liquidity event", level: .info)
                }
            }
        }

        // 1. Fresh scan: pick up new blocks since last refresh. lastSeenBlock advances
        // chunk by chunk, so a failure or the maxChunks cap leaves the rest for next time.
        var interrupted = false
        if currentBlock > cache.lastSeenBlock {
            interrupted = !(await scanForward(to: currentBlock, context: context, cache: &cache, checkpoint: checkpoint))
        }

        // 2. Historical bootstrap: scan backward from nextScanCeiling.
        // Stop at the earliest known position creation block rather than deployBlock,
        // so we don't scan blocks that predate the wallet.
        let lowerBound = effectiveLowerBound(cache: cache, tokenIds: context.tokenIds, deployBlock: deployBlock)
        // With the exact start known the remaining work is bounded, so the scan runs to it instead
        // of stopping at the per-refresh cap and waiting for the next refresh.
        let knowsStart = context.oldestTokenId.flatMap { cache.creationBlocks[$0] } != nil
        if !interrupted, let ceiling = cache.nextScanCeiling, ceiling >= lowerBound {
            interrupted = !(await scanBackward(
                from: ceiling, downTo: lowerBound, maxChunks: knowsStart ? .max : context.maxChunks,
                context: context, cache: &cache, checkpoint: checkpoint
            ))
        }
        // Recompute after scan — knownMintBlocks may have been updated.
        let newLower = effectiveLowerBound(cache: cache, tokenIds: context.tokenIds, deployBlock: deployBlock)
        if let ceiling = cache.nextScanCeiling, ceiling < newLower {
            cache.nextScanCeiling = nil
        }

        // Cursors only cover completed chunks, so saving after a failure or cancellation is safe.
        checkpoint(cache)
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
        // The oldest position's exact creation block bounds every position's history.
        if let oldest = oldestTokenId(tokenIds), let created = cache.creationBlocks[oldest] {
            return max(deployBlock, created)
        }
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
        cache: inout FeeHistoryCache,
        checkpoint: (FeeHistoryCache) -> Void
    ) async -> Bool {
        var chunksScanned = 0
        while cache.lastSeenBlock < upper && chunksScanned < context.maxChunks {
            let from = cache.lastSeenBlock + 1
            let to = min(from + context.chunkSize - 1, upper)
            guard let logs = await fetchChunk(from: from, to: to, context: context) else { return false }
            parseLogs(logs, decMap: context.decMap, into: &cache)
            cache.lastSeenBlock = to
            checkpoint(cache)
            chunksScanned += 1
        }
        return true
    }

    /// Scans descending chunks from `ceiling`, so completed blocks always form one contiguous
    /// range ending at the old ceiling. Returns false if stopped by an error or cancellation.
    private static func scanBackward(
        from ceiling: Int,
        downTo lowerBound: Int,
        maxChunks: Int,
        context: ScanContext,
        cache: inout FeeHistoryCache,
        checkpoint: (FeeHistoryCache) -> Void
    ) async -> Bool {
        var top = ceiling
        var chunksScanned = 0
        while top >= lowerBound && chunksScanned < maxChunks {
            let bottom = max(top - context.chunkSize + 1, lowerBound)
            guard let logs = await fetchChunk(from: bottom, to: top, context: context) else { return false }
            parseLogs(logs, decMap: context.decMap, into: &cache)
            top = bottom - 1
            cache.nextScanCeiling = top
            checkpoint(cache)
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
                logs += try await context.fetchLogs([[collectEventTopic, increaseLiquidityTopic, decreaseLiquidityTopic], batch], from, to)
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

            guard topic0 == collectEventTopic || topic0 == decreaseLiquidityTopic else { continue }
            guard let decs = decMap[tokenIdStr] else { continue }
            let dataHex = entry["data"] as? String ?? ""
            guard let logData = Data(hexString: dataHex), logData.count >= 96 else { continue }
            // Collect data:           recipient (32B) | amount0 (32B) | amount1 (32B)
            // DecreaseLiquidity data: liquidity (32B) | amount0 (32B) | amount1 (32B)
            let a0 = logData.readAmount(wordAt: 32, decimals: decs.dec0)
            let a1 = logData.readAmount(wordAt: 64, decimals: decs.dec1)
            var existing = cache.fees[tokenIdStr] ?? FeeHistoryCache.PositionFees()
            if topic0 == collectEventTopic {
                existing.amount0 += a0
                existing.amount1 += a1
            } else {
                existing.withdrawn0 += a0
                existing.withdrawn1 += a1
            }
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
        cache.fees.mapValues { ($0.claimed0, $0.claimed1) }
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
