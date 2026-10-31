import Foundation

private let v4ReorgLookbackBlocks = 24

/// Transfer event signature, hardcoded (known keccak256) to avoid any keccak implementation variance.
private let transferSig = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

struct V4OwnershipCache: Codable {
    let lastScannedBlock: Int
    let candidateTokenIds: [UInt64]
    let ownedTokenIds: [UInt64]
    let nextBootstrapFromBlock: Int?
    let bootstrapPassCounter: Int?
}

/// Log scan limits, passed in so the tracker does not depend on `AppSettings`.
struct V4ScanSettings {
    let logChunkSize: Int
    let maxConcurrentLogRequests: Int
    let maxChunksPerRefresh: Int
}

/// Transfer tokenIds of several wallets, read with one pair of `eth_getLogs` per chunk for
/// wallets whose scans cover the same blocks. Keyed by lowercased wallet address.
struct V4SharedTransfers {
    let currentBlock: Int
    let chunks: [ClosedRange<Int>]
    var to: [String: Set<UInt64>] = [:]
    var from: [String: Set<UInt64>] = [:]
}

struct V4Ownership {
    let ownedTokenIds: [UInt64]
    /// Every tokenId ever transferred to or from the wallet in the scanned range.
    let candidateCount: Int
    /// First unscanned block when this refresh did not reach the head.
    let nextFromBlock: Int?
}

/// Works out which v4 position NFTs a wallet owns. The v4 PositionManager does NOT implement
/// ERC-721 Enumerable, so tokenOfOwnerByIndex() does not exist. Ownership is reconstructed
/// from Transfer(to=wallet) minus Transfer(from=wallet), confirmed with ownerOf, and the
/// result is persisted per wallet and chain so later refreshes only scan new blocks.
/// Note: requires an RPC that supports large eth_getLogs block ranges
/// (Alchemy/Infura paid tiers work; very restricted free-tier nodes may not).
struct V4OwnershipTracker {
    let eth: EthereumClient
    let chain: SupportedChain
    let positionManager: String
    let deployBlock: Int
    let settings: V4ScanSettings
    var defaults: UserDefaults = PoolserDefaults.store

    /// Throws `LoaderError` with a user-facing message when the scan cannot complete. `shared`
    /// answers the log query when it covers the blocks this wallet's scan needs.
    func scan(wallet: String, balance: UInt64, shared: V4SharedTransfers? = nil) async throws -> V4Ownership {
        // Pull block head once, then only scan deltas from the last successful sync
        // (with a short reorg lookback).
        let currentBlock: Int
        if let shared {
            currentBlock = shared.currentBlock
        } else {
            do { currentBlock = try await eth.ethBlockNumber() }
            catch { throw LoaderError("v4: eth_blockNumber failed – \(error.localizedDescription)") }
        }

        let previousCache = loadCache(wallet: wallet)
        let plan = plan(cache: previousCache, currentBlock: currentBlock)
        if !plan.isBootstrap, let next = plan.nextFromBlock {
            await LogStore.shared.log(
                "v4 [\(chain.displayName)]: catching up Transfer logs, \(currentBlock - next + 1) blocks behind head",
                level: .info
            )
        }

        let toIds: Set<UInt64>
        let fromIds: Set<UInt64>
        if let shared, !plan.isBootstrap, plan.chunks == shared.chunks, let to = shared.to[wallet.lowercased()] {
            toIds = to
            fromIds = shared.from[wallet.lowercased()] ?? []
        } else {
            let logs = try await fetchTransferLogs(plan: plan, walletPads: [Self.padded(wallet)])
            toIds = Set(logs.to.compactMap(Self.tokenId))
            fromIds = Set(logs.from.compactMap(Self.tokenId))
        }
        var candidateIds = Set(previousCache?.candidateTokenIds ?? [])
        candidateIds.formUnion(toIds)
        candidateIds.formUnion(fromIds)

        var ownedIds = Set(previousCache?.ownedTokenIds ?? [])

        // Bootstrap progress is persisted explicitly; incremental catch-up resumes from
        // lastScannedBlock. Both report nextFromBlock so the accelerated follow-up continues.
        let nextFromBlock = plan.nextFromBlock
        let nextBootstrapFromBlock = plan.isBootstrap ? nextFromBlock : nil
        let bootstrapPassCounter: Int? = {
            guard plan.isBootstrap else { return nil }
            return (previousCache?.bootstrapPassCounter ?? 0) + 1
        }()

        // Failed checks leave the id's current ownership untouched so it is retried
        // later (via the balance reconciliation below) instead of being dropped.
        var failedOwnerChecks = Set<UInt64>()
        func apply(_ updates: [(tokenId: UInt64, isOwner: Bool?)]) {
            for (tokenId, isOwner) in updates {
                switch isOwner {
                case true?:  ownedIds.insert(tokenId); failedOwnerChecks.remove(tokenId)
                case false?: ownedIds.remove(tokenId); failedOwnerChecks.remove(tokenId)
                case nil:    failedOwnerChecks.insert(tokenId)
                }
            }
        }

        // Verify ownership only for tokenIds that changed since the last scan.
        // First sync verifies all candidates once.
        let idsToVerify: [UInt64] = {
            if previousCache == nil { return Array(candidateIds) }
            return Array(toIds.union(fromIds))
        }()
        apply(await checkOwnership(idsToVerify, wallet: wallet))

        // Safety net: if cache and live balance diverge, do one full ownership reconciliation.
        if Int(balance) != ownedIds.count {
            apply(await checkOwnership(candidateIds, wallet: wallet))
        }

        if !failedOwnerChecks.isEmpty {
            await LogStore.shared.log(
                "v4 [\(chain.displayName)]: ownerOf failed for \(failedOwnerChecks.count) tokenId(s), will retry next refresh",
                level: .error
            )
        }

        // Persist scan progress on every path that completed the log scan, so an
        // empty owned set mid-bootstrap does not restart the scan at the deploy block.
        saveCache(
            V4OwnershipCache(
                lastScannedBlock: plan.scanEndBlock,
                candidateTokenIds: Array(candidateIds).sorted(),
                ownedTokenIds: Array(ownedIds).sorted(),
                nextBootstrapFromBlock: nextBootstrapFromBlock,
                bootstrapPassCounter: nextBootstrapFromBlock == nil ? nil : bootstrapPassCounter
            ),
            wallet: wallet
        )

        return V4Ownership(
            ownedTokenIds: ownedIds.sorted(),
            candidateCount: candidateIds.count,
            nextFromBlock: nextFromBlock
        )
    }

    // MARK: - Transfer logs

    private func plan(cache: V4OwnershipCache?, currentBlock: Int) -> V4LogScanPlan {
        planV4LogScan(
            deployBlock: deployBlock,
            currentBlock: currentBlock,
            lastScannedBlock: cache?.lastScannedBlock,
            nextBootstrapFromBlock: cache?.nextBootstrapFromBlock,
            chunkSize: settings.logChunkSize,
            maxChunks: settings.maxChunksPerRefresh,
            reorgLookbackBlocks: v4ReorgLookbackBlocks
        )
    }

    /// Once their bootstrap is done, the scans of every wallet on a chain cover the same new
    /// blocks, so one query with all of them in the topic answers each. Nil when fewer than two
    /// wallets share a plan or the query fails; each wallet then scans on its own.
    func sharedTransfers(wallets: [String]) async -> V4SharedTransfers? {
        guard wallets.count > 1, let currentBlock = try? await eth.ethBlockNumber() else { return nil }
        let plans = wallets
            .map { (wallet: $0, plan: plan(cache: loadCache(wallet: $0), currentBlock: currentBlock)) }
            .filter { !$0.plan.isBootstrap && !$0.plan.chunks.isEmpty }
        guard let group = Dictionary(grouping: plans, by: \.plan.chunks).values.max(by: { $0.count < $1.count }),
              group.count > 1 else { return nil }

        let walletByPad = Dictionary(group.map { (Self.padded($0.wallet), $0.wallet.lowercased()) }, uniquingKeysWith: { a, _ in a })
        guard let logs = try? await fetchTransferLogs(plan: group[0].plan, walletPads: Array(walletByPad.keys)) else {
            return nil
        }
        var shared = V4SharedTransfers(currentBlock: currentBlock, chunks: group[0].plan.chunks)
        for wallet in walletByPad.values {
            shared.to[wallet] = []
            shared.from[wallet] = []
        }
        // Topic 1 is the sender, topic 2 the recipient.
        for log in logs.to {
            guard let wallet = Self.topic(2, of: log).flatMap({ walletByPad[$0] }), let id = Self.tokenId(log) else { continue }
            shared.to[wallet]?.insert(id)
        }
        for log in logs.from {
            guard let wallet = Self.topic(1, of: log).flatMap({ walletByPad[$0] }), let id = Self.tokenId(log) else { continue }
            shared.from[wallet]?.insert(id)
        }
        return shared
    }

    static func padded(_ wallet: String) -> String {
        let hex = (wallet.hasPrefix("0x") ? String(wallet.dropFirst(2)) : wallet).lowercased()
        return "0x" + String(repeating: "0", count: 64 - min(hex.count, 64)) + hex
    }

    private static func topic(_ index: Int, of log: [String: Any]) -> String? {
        guard let topics = log["topics"] as? [String], topics.count > index else { return nil }
        return topics[index].lowercased()
    }

    static func tokenId(_ log: [String: Any]) -> UInt64? {
        guard let topics = log["topics"] as? [String], topics.count >= 4 else { return nil }
        let hex = topics[3].hasPrefix("0x") ? String(topics[3].dropFirst(2)) : topics[3]
        return UInt64(hex.suffix(16), radix: 16)
    }

    private func fetchTransferLogs(
        plan: V4LogScanPlan,
        walletPads: [String]
    ) async throws -> (to: [[String: Any]], from: [[String: Any]]) {
        let chunks = plan.chunks.map { range -> (String, String) in
            ("0x" + String(range.lowerBound, radix: 16), "0x" + String(range.upperBound, radix: 16))
        }
        let maxConcurrentLogs = settings.maxConcurrentLogRequests

        var toLogs: [[String: Any]] = []
        var fromLogs: [[String: Any]] = []
        for batchStart in stride(from: 0, to: chunks.count, by: maxConcurrentLogs) {
            let batchEnd = min(batchStart + maxConcurrentLogs, chunks.count)
            let batch = Array(chunks[batchStart..<batchEnd])

            do {
                let batchLogs = try await withThrowingTaskGroup(of: (to: [[String: Any]], from: [[String: Any]]).self) { group in
                    for (from, to) in batch {
                        group.addTask {
                            let incoming = try await eth.ethGetLogsOR(
                                address: positionManager,
                                topics: [[transferSig], nil, walletPads],
                                fromBlock: from,
                                toBlock: to,
                                context: "[to]"
                            )
                            let outgoing: [[String: Any]]
                            if !plan.isBootstrap {
                                outgoing = try await eth.ethGetLogsOR(
                                    address: positionManager,
                                    topics: [[transferSig], walletPads, nil],
                                    fromBlock: from,
                                    toBlock: to,
                                    context: "[from]"
                                )
                            } else {
                                // First full bootstrap does not need "from" logs:
                                // every outgoing token must have appeared in a prior incoming event.
                                outgoing = []
                            }
                            return (to: incoming, from: outgoing)
                        }
                    }
                    var allTo: [[String: Any]] = []
                    var allFrom: [[String: Any]] = []
                    for try await part in group {
                        allTo.append(contentsOf: part.to)
                        allFrom.append(contentsOf: part.from)
                    }
                    return (to: allTo, from: allFrom)
                }
                toLogs.append(contentsOf: batchLogs.to)
                fromLogs.append(contentsOf: batchLogs.from)
            } catch {
                let sampleRange = batch.first.map { "\($0.0)-\($0.1)" } ?? "unknown-range"
                throw LoaderError("v4: Transfer log query failed near \(sampleRange) – \(error.localizedDescription)")
            }
        }
        return (to: toLogs, from: fromLogs)
    }

    // MARK: - ownerOf

    /// ownerOf for each id; nil means the call failed (e.g. HTTP 429), not "not owned".
    private func checkOwnership(
        _ ids: some Sequence<UInt64>,
        wallet: String
    ) async -> [(tokenId: UInt64, isOwner: Bool?)] {
        let tokenIds = Array(ids)
        let results = await ContractReader(eth: eth, multicall3: chain.multicall3).read(
            tokenIds.map { ContractCall(target: positionManager, data: ABI.callOwnerOf(tokenId: $0)) },
            context: "v4 \(chain.displayName) ownerOf"
        )
        return zip(tokenIds, results).map { tokenId, result in
            (tokenId, v4OwnerCheck(result, wallet: wallet))
        }
    }

    // MARK: - Cache persistence

    private func loadCache(wallet: String) -> V4OwnershipCache? {
        guard let data = defaults.data(forKey: cacheKey(wallet: wallet)) else { return nil }
        return try? JSONDecoder().decode(V4OwnershipCache.self, from: data)
    }

    private func saveCache(_ cache: V4OwnershipCache, wallet: String) {
        if let data = try? JSONEncoder().encode(cache) {
            defaults.set(data, forKey: cacheKey(wallet: wallet))
        }
    }

    private func cacheKey(wallet: String) -> String {
        let normalized = wallet.lowercased()
        return "\(Self.cacheKeyPrefix)\(chain.id).\(normalized)"
    }

    private static let cacheKeyPrefix = "v4OwnershipCache."

    /// Clears the wallet's ownership caches on every chain.
    static func clearCaches(wallet: String, in defaults: UserDefaults) {
        let suffix = ".\(wallet.lowercased())"
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(cacheKeyPrefix) && key.hasSuffix(suffix) {
            defaults.removeObject(forKey: key)
        }
    }
}

/// Interprets a v4 `ownerOf` call: true/false when the answer is known, nil when the
/// call failed transiently and should be retried. A revert means the token no longer
/// exists (burned), so it is definitely not owned.
func v4OwnerCheck(_ result: Result<Data, Error>, wallet: String) -> Bool? {
    switch result {
    case .success(let data):
        return data.readAddress(wordAt: 0).lowercased() == wallet.lowercased()
    case .failure(EthereumClient.Err.reverted):
        return false
    case .failure:
        return nil
    }
}

/// Block range one refresh scans for v4 Transfer logs.
struct V4LogScanPlan: Equatable {
    let chunks: [ClosedRange<Int>]
    /// Persisted as the cache's `lastScannedBlock`.
    let scanEndBlock: Int
    /// Initial bootstrap from the deploy block only needs incoming (`[to]`) logs.
    let isBootstrap: Bool
    /// First unscanned block when the head was not reached; a follow-up continues from here.
    let nextFromBlock: Int?
}

/// Plans the v4 Transfer log scan for one refresh. Both the initial bootstrap and the
/// incremental scan are capped at `maxChunks` chunks, so catching up after long downtime
/// spreads over several follow-ups instead of one large burst of `eth_getLogs`.
/// Catch-up passes are stateless: each starts from the persisted `lastScannedBlock`
/// minus the reorg lookback, so consecutive passes leave no gap between them.
func planV4LogScan(
    deployBlock: Int,
    currentBlock: Int,
    lastScannedBlock: Int?,
    nextBootstrapFromBlock: Int?,
    chunkSize: Int,
    maxChunks: Int,
    reorgLookbackBlocks: Int
) -> V4LogScanPlan {
    let bootstrapFrom = nextBootstrapFromBlock ?? (lastScannedBlock == nil ? deployBlock : nil)
    let isBootstrap = bootstrapFrom != nil
    let start = bootstrapFrom ?? max(deployBlock, (lastScannedBlock ?? deployBlock) - reorgLookbackBlocks)
    let end = min(start + chunkSize * maxChunks - 1, currentBlock)

    guard end >= start else {
        // Head is behind our progress (lagging RPC node): scan nothing and keep progress.
        return V4LogScanPlan(
            chunks: [],
            scanEndBlock: lastScannedBlock ?? start - 1,
            isBootstrap: isBootstrap,
            nextFromBlock: bootstrapFrom
        )
    }

    let chunks = stride(from: start, through: end, by: chunkSize).map { $0...min($0 + chunkSize - 1, end) }
    return V4LogScanPlan(
        chunks: chunks,
        scanEndBlock: end,
        isBootstrap: isBootstrap,
        nextFromBlock: end < currentBlock ? end + 1 : nil
    )
}
