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

    /// Throws `LoaderError` with a user-facing message when the scan cannot complete.
    func scan(wallet: String, balance: UInt64) async throws -> V4Ownership {
        let walletPadded: String = {
            let hex = (wallet.hasPrefix("0x") ? String(wallet.dropFirst(2)) : wallet).lowercased()
            return "0x" + String(repeating: "0", count: 64 - min(hex.count, 64)) + hex
        }()

        // Pull block head once, then only scan deltas from the last successful sync
        // (with a short reorg lookback).
        let currentBlock: Int
        do { currentBlock = try await eth.ethBlockNumber() }
        catch { throw LoaderError("v4: eth_blockNumber failed – \(error.localizedDescription)") }

        let previousCache = loadCache(wallet: wallet)
        let plan = planV4LogScan(
            deployBlock: deployBlock,
            currentBlock: currentBlock,
            lastScannedBlock: previousCache?.lastScannedBlock,
            nextBootstrapFromBlock: previousCache?.nextBootstrapFromBlock,
            chunkSize: settings.logChunkSize,
            maxChunks: settings.maxChunksPerRefresh,
            reorgLookbackBlocks: v4ReorgLookbackBlocks
        )
        if !plan.isBootstrap, let next = plan.nextFromBlock {
            await LogStore.shared.log(
                "v4 [\(chain.displayName)]: catching up Transfer logs, \(currentBlock - next + 1) blocks behind head",
                level: .info
            )
        }

        let logs = try await fetchTransferLogs(plan: plan, walletPadded: walletPadded)

        func extractTokenId(_ log: [String: Any]) -> UInt64? {
            guard let topics = log["topics"] as? [String], topics.count >= 4 else { return nil }
            let hex = topics[3].hasPrefix("0x") ? String(topics[3].dropFirst(2)) : topics[3]
            guard let val = UInt64(hex.suffix(16), radix: 16) else { return nil }
            return val
        }
        let toIds = Set(logs.to.compactMap(extractTokenId))
        let fromIds = Set(logs.from.compactMap(extractTokenId))
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

    private func fetchTransferLogs(
        plan: V4LogScanPlan,
        walletPadded: String
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
                            let incoming = try await eth.ethGetLogs(
                                address: positionManager,
                                topics: [transferSig, nil, walletPadded],
                                fromBlock: from,
                                toBlock: to,
                                context: "[to]"
                            )
                            let outgoing: [[String: Any]]
                            if !plan.isBootstrap {
                                outgoing = try await eth.ethGetLogs(
                                    address: positionManager,
                                    topics: [transferSig, walletPadded, nil],
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
        return "v4OwnershipCache.\(chain.id).\(normalized)"
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
