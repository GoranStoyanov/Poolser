import Foundation
import Combine

private let v4ReorgLookbackBlocks = 24

private struct V4OwnershipCache: Codable {
    let lastScannedBlock: Int
    let candidateTokenIds: [UInt64]
    let ownedTokenIds: [UInt64]
    let nextBootstrapFromBlock: Int?
    let bootstrapPassCounter: Int?
}

/// Native token in Uniswap v4 is represented as address(0).
private let nativeTokenAddress = "0x0000000000000000000000000000000000000000"

// MARK: - Service

@MainActor
final class UniswapService: ObservableObject {
    @Published var titleText      = "… 👀"
    @Published var positions:     [Position] = []
    @Published var isLoading      = false
    @Published var lastError:     String?
    @Published var lastUpdated:   Date? = nil
    private var previousTotal: Double = -1
    private var flashTask: Task<Void, Never>?

    private let priceService = PriceService()
    private let poolStatsService = PoolStatsService()
    private let bootstrapFollowUpSeconds: UInt64 = 75
    private var timer: Timer?
    private var refreshIntervalCancellable: AnyCancellable?
    private var activeLoadTask: Task<Void, Never>?
    private var bootstrapFollowUpTask: Task<Void, Never>?
    private var bootstrapCountdownTimer: Timer?
    private var bootstrapFollowUpDeadlineByChainID: [String: Date] = [:]
    private var loadGeneration: UInt64 = 0
    private var chainResultsByID: [String: ChainLoadResult] = [:]

    private struct ChainLoadResult {
        let chain: SupportedChain
        let positions: [Position]
        let feesUSD: Double
        let error: String?
        let bootstrapInProgress: Bool
        let bootstrapNextFromBlock: Int?
    }

    init() {
        configureTimer()
        refreshIntervalCancellable = AppSettings.shared.$refreshIntervalMinutes
            .removeDuplicates()
            .sink { [weak self] _ in self?.configureTimer() }
        startLoad()
    }

    func refresh() { startLoad() }

    func refreshForWalletChange() {
        positions = []
        titleText = "… 👀"
        previousTotal = -1
        chainResultsByID = [:]
        startLoad()
    }

    // MARK: - Orchestrator

    private func startLoad() {
        activeLoadTask?.cancel()
        bootstrapFollowUpTask?.cancel()
        bootstrapFollowUpDeadlineByChainID = [:]
        stopBootstrapCountdownTimer()
        loadGeneration &+= 1
        let generation = loadGeneration
        activeLoadTask = Task { [weak self] in
            await self?.load(generation: generation)
        }
    }

    private func isCurrentGeneration(_ generation: UInt64) -> Bool {
        generation == loadGeneration
    }

    private func load(generation: UInt64) async {
        let wallet = AppSettings.shared.walletAddress
        let key = AppSettings.shared.infuraAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let chains = AppSettings.shared.enabledChains()
        guard !wallet.isEmpty, !key.isEmpty, !chains.isEmpty else {
            guard isCurrentGeneration(generation) else { return }
            chainResultsByID = [:]
            positions = []
            titleText = "– 👀"
            lastError = "Configure wallet, Infura API key, and at least one enabled network in Settings (⌘,)"
            return
        }

        guard isCurrentGeneration(generation), !Task.isCancelled else { return }
        isLoading = true
        lastError = nil
        LogStore.shared.log("refresh started", level: .info)

        let results = await withTaskGroup(of: ChainLoadResult.self, returning: [ChainLoadResult].self) { group in
            for chain in chains {
                group.addTask { [wallet] in
                    await self.loadChain(wallet: wallet, chain: chain)
                }
            }
            var collected: [ChainLoadResult] = []
            for await result in group { collected.append(result) }
            return collected
        }

        guard isCurrentGeneration(generation), !Task.isCancelled else { return }
        let enrichedResults = await enrichChainResults(results)
        guard isCurrentGeneration(generation), !Task.isCancelled else { return }

        applyChainResults(enrichedResults, activeChains: chains)

        LogStore.shared.log("refresh done — \(positions.count) positions across \(chains.count) chain(s)", level: .info)
        scheduleBootstrapFollowUpIfNeeded(
            chainIDs: enrichedResults.filter(\.bootstrapInProgress).map { $0.chain.id },
            generation: generation
        )
        isLoading = false
        lastUpdated = Date()
    }

    private func scheduleBootstrapFollowUpIfNeeded(chainIDs: [String], generation: UInt64) {
        bootstrapFollowUpTask?.cancel()
        let ids = Array(Set(chainIDs))
        guard !ids.isEmpty else {
            bootstrapFollowUpDeadlineByChainID = [:]
            stopBootstrapCountdownTimer()
            return
        }
        let fireDate = Date().addingTimeInterval(TimeInterval(bootstrapFollowUpSeconds))
        bootstrapFollowUpDeadlineByChainID = Dictionary(
            uniqueKeysWithValues: ids.map { ($0, fireDate) }
        )
        startBootstrapCountdownTimer()
        refreshBootstrapCountdownMessage()
        bootstrapFollowUpTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.bootstrapFollowUpSeconds * 1_000_000_000)
            await self.runBootstrapFollowUp(generation: generation, chainIDs: ids)
        }
    }

    private func runBootstrapFollowUp(generation: UInt64, chainIDs: [String]) async {
        guard isCurrentGeneration(generation), !Task.isCancelled else { return }
        let wallet = AppSettings.shared.walletAddress
        let key = AppSettings.shared.infuraAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let activeChains = AppSettings.shared.enabledChains()
        guard !wallet.isEmpty, !key.isEmpty, !activeChains.isEmpty else { return }

        let idSet = Set(chainIDs)
        let targetChains = activeChains.filter { idSet.contains($0.id) }
        guard !targetChains.isEmpty else { return }

        LogStore.shared.log(
            "v4 bootstrap in progress — running accelerated follow-up for \(targetChains.map(\.displayName).joined(separator: ", "))",
            level: .info
        )

        let results = await withTaskGroup(of: ChainLoadResult.self, returning: [ChainLoadResult].self) { group in
            for chain in targetChains {
                group.addTask { [wallet] in
                    await self.loadChain(wallet: wallet, chain: chain)
                }
            }
            var collected: [ChainLoadResult] = []
            for await result in group { collected.append(result) }
            return collected
        }
        guard isCurrentGeneration(generation), !Task.isCancelled else { return }

        let enrichedResults = await enrichChainResults(results)
        guard isCurrentGeneration(generation), !Task.isCancelled else { return }
        applyChainResults(enrichedResults, activeChains: activeChains)

        let snapshot = activeChains.compactMap { chainResultsByID[$0.id] }
        scheduleBootstrapFollowUpIfNeeded(
            chainIDs: snapshot.filter(\.bootstrapInProgress).map { $0.chain.id },
            generation: generation
        )
        LogStore.shared.log(
            "accelerated follow-up done — \(positions.count) positions, \(snapshot.filter(\.bootstrapInProgress).count) chain(s) still bootstrapping",
            level: .info
        )
    }

    private func enrichChainResults(_ results: [ChainLoadResult]) async -> [ChainLoadResult] {
        await withTaskGroup(of: ChainLoadResult.self, returning: [ChainLoadResult].self) { group in
            for result in results {
                group.addTask {
                    let enriched = await self.enrichPositionsWithPoolStats(result.positions)
                    return ChainLoadResult(
                        chain: result.chain,
                        positions: enriched,
                        feesUSD: result.feesUSD,
                        error: result.error,
                        bootstrapInProgress: result.bootstrapInProgress,
                        bootstrapNextFromBlock: result.bootstrapNextFromBlock
                    )
                }
            }
            var collected: [ChainLoadResult] = []
            for await result in group { collected.append(result) }
            return collected
        }
    }

    private func enrichPositionsWithPoolStats(_ input: [Position]) async -> [Position] {
        await withTaskGroup(of: Position.self, returning: [Position].self) { group in
            for pos in input {
                let resolvedAddr: String? = pos.isV4
                    ? pos.poolId.map { "0x" + $0.hexString }
                    : pos.poolAddress
                group.addTask { [pos, resolvedAddr] in
                    var p = pos
                    guard let addr = resolvedAddr,
                          let network = SupportedChain.byID(p.chainID)?.geckoterminalNetworkID else { return p }
                    let feePct = Double(p.feeRaw) / 1_000_000
                    if let stats = await self.poolStatsService.stats(
                        network: network,
                        poolAddress: addr,
                        feePct: feePct
                    ) {
                        p.volumeUSD24h = stats.volumeUSD24h
                        p.feeAPR = stats.feeAPR
                        p.tvlUSD = stats.tvlUSD
                    }
                    return p
                }
            }
            var enriched: [Position] = []
            for await p in group { enriched.append(p) }
            return enriched
        }
    }

    private func applyChainResults(_ results: [ChainLoadResult], activeChains: [SupportedChain]) {
        let activeIDs = Set(activeChains.map(\.id))
        for result in results {
            chainResultsByID[result.chain.id] = result
        }
        chainResultsByID = chainResultsByID.filter { activeIDs.contains($0.key) }

        let snapshot = activeChains.compactMap { chainResultsByID[$0.id] }
        let all = snapshot
            .flatMap(\.positions)
            .sorted { lhs, rhs in (lhs.positionUSD ?? lhs.usd ?? 0) > (rhs.positionUSD ?? rhs.usd ?? 0) }
        positions = all

        let errors = snapshot.compactMap(\.error)
        let errorText = composedErrorText(snapshot: snapshot, fallbackErrors: errors)
        lastError = errorText
        if let err = errorText { LogStore.shared.log(err, level: .error) }

        if all.isEmpty {
            titleText = "$0.00 👀"
        } else {
            let total = snapshot.reduce(0.0) { $0 + $1.feesUSD }
            let baseTitle = String(format: "$%.2f 👀", total)
            titleText = baseTitle
            let displayChanged = String(format: "%.2f", total) != String(format: "%.2f", previousTotal)
            if previousTotal >= 0, displayChanged, AppSettings.shared.flashOnValueChange {
                let flashEmoji = total > previousTotal ? "🔼" : "🔽"
                let flashTitle = String(format: "$%.2f \(flashEmoji)", total)
                flashTask?.cancel()
                flashTask = Task {
                    for i in 0..<10 {
                        guard !Task.isCancelled else { return }
                        titleText = i % 2 == 0 ? flashTitle : baseTitle
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                    titleText = baseTitle
                }
            }
            previousTotal = total
        }
    }

    private func loadChain(wallet: String, chain: SupportedChain) async -> ChainLoadResult {
        guard let rpcURL = AppSettings.shared.infuraRPCURL(for: chain) else {
            return ChainLoadResult(
                chain: chain,
                positions: [],
                feesUSD: 0,
                error: "\(chain.displayName): invalid Infura API key",
                bootstrapInProgress: false,
                bootstrapNextFromBlock: nil
            )
        }
        let eth = EthereumClient(rpcURL: rpcURL)

        do {
            let probedChainID = try await eth.ethChainId()
            if probedChainID != chain.chainId {
                return ChainLoadResult(
                    chain: chain,
                    positions: [],
                    feesUSD: 0,
                    error: "\(chain.displayName): RPC chain mismatch (expected \(chain.chainId), got \(probedChainID))",
                    bootstrapInProgress: false,
                    bootstrapNextFromBlock: nil
                )
            }
        } catch {
            let msg = error.localizedDescription
            if msg.lowercased().contains("does not have access") ||
                msg.lowercased().contains("not available for project") {
                AppSettings.shared.disableChain(chain.id)
                return ChainLoadResult(
                    chain: chain,
                    positions: [],
                    feesUSD: 0,
                    error: "\(chain.displayName): Infura access denied for this API key (network auto-disabled)",
                    bootstrapInProgress: false,
                    bootstrapNextFromBlock: nil
                )
            }
            return ChainLoadResult(
                chain: chain,
                positions: [],
                feesUSD: 0,
                error: "\(chain.displayName): RPC unavailable – \(msg)",
                bootstrapInProgress: false,
                bootstrapNextFromBlock: nil
            )
        }

        let v3: (positions: [Position], feesUSD: Double, error: String?) = await {
            guard chain.supportsV3 else { return ([], 0, nil) }
            return await loadV3(wallet: wallet, eth: eth, chain: chain)
        }()
        let v4: (
            positions: [Position],
            feesUSD: Double,
            error: String?,
            bootstrapInProgress: Bool,
            bootstrapNextFromBlock: Int?
        ) = await {
            guard chain.supportsV4 else { return ([], 0, nil, false, nil) }
            return await loadV4(wallet: wallet, eth: eth, chain: chain)
        }()

        let errors = [v3.error, v4.error].compactMap { $0 }.map { "\(chain.displayName): \($0)" }
        return ChainLoadResult(
            chain: chain,
            positions: v3.positions + v4.positions,
            feesUSD: v3.feesUSD + v4.feesUSD,
            error: errors.isEmpty ? nil : errors.joined(separator: "\n"),
            bootstrapInProgress: v4.bootstrapInProgress,
            bootstrapNextFromBlock: v4.bootstrapNextFromBlock
        )
    }

    // MARK: - v3

    private func loadV3(
        wallet: String, eth: EthereumClient, chain: SupportedChain
    ) async -> (positions: [Position], feesUSD: Double, error: String?) {
        guard let v3Factory = chain.v3Factory, let v3NFPM = chain.v3NFPM else {
            return ([], 0, nil)
        }

        var metaCache:      [String: (symbol: String, decimals: Int)] = [:]
        var poolTicks:      [String: Int]    = [:]
        var poolSqrtPrices: [String: Double] = [:]
        var tokenAddrs = Set<String>()
        var rawPositions: [Position] = []

        // 1 · balance
        let numPos: Int
        do {
            let d = try await eth.ethCall(to: v3NFPM, data: ABI.callBalanceOf(owner: wallet))
            numPos = Int(d.readUInt64(wordAt: 0))
        } catch EthereumClient.Err.noResult {
            return ([], 0, "v3: balanceOf returned no result (RPC did not return a usable payload)")
        } catch {
            return ([], 0, error.localizedDescription)
        }
        guard numPos > 0 else { return ([], 0, nil) }

        // 2 · per-position
        for i in 0..<numPos {
            do {
                let idData = try await eth.ethCall(
                    to: v3NFPM,
                    data: ABI.callTokenOfOwnerByIndex(owner: wallet, index: UInt64(i))
                )
                let tokenId = idData.readUInt64(wordAt: 0)

                // positions() returns 12 × 32-byte words:
                //  0:nonce 1:operator 2:token0 3:token1 4:fee
                //  5:tickLower 6:tickUpper 7:liquidity 8-9:feeGrowth 10-11:tokensOwed
                let pos = try await eth.ethCall(to: v3NFPM, data: ABI.callPositions(tokenId: tokenId))
                let token0    = pos.readAddress(wordAt: 64)
                let token1    = pos.readAddress(wordAt: 96)
                let feeRaw    = Int(pos.readUInt64(wordAt: 128))
                let tickLower = pos.readInt24(wordAt: 160)
                let tickUpper = pos.readInt24(wordAt: 192)
                let liqZero   = pos.isZeroWord(at: 224)
                let liquidity = liqZero ? 0.0 : pos.readAmount(wordAt: 224, decimals: 0)

                let m0 = await resolve(addr: token0, eth: eth, cache: &metaCache)
                let m1 = await resolve(addr: token1, eth: eth, cache: &metaCache)

                var fees0 = 0.0, fees1 = 0.0
                if let c = try? await eth.ethCall(
                    to: v3NFPM,
                    data: ABI.callCollectStatic(tokenId: tokenId, recipient: wallet)
                ), c.count >= 64 {
                    fees0 = c.readAmount(wordAt: 0,  decimals: m0.decimals)
                    fees1 = c.readAmount(wordAt: 32, decimals: m1.decimals)
                }

                if liqZero && fees0 == 0 && fees1 == 0 { continue }

                tokenAddrs.insert(token0.lowercased())
                tokenAddrs.insert(token1.lowercased())

                rawPositions.append(Position(
                    chainID: chain.id,
                    chainName: chain.displayName,
                    chainNumericID: chain.chainId,
                    tokenId:   String(tokenId),
                    token0:    token0,    token1:    token1,
                    sym0:      m0.symbol, sym1:      m1.symbol,
                    feePct:    String(format: "%.2f", Double(feeRaw) / 10_000),
                    feeRaw:    feeRaw,
                    fees0:     fees0,     fees1:     fees1,
                    tickLower: tickLower, tickUpper: tickUpper,
                    liquidity: liquidity
                ))
            } catch {
                rawPositions.append(Position(
                    chainID: chain.id,
                    chainName: chain.displayName,
                    chainNumericID: chain.chainId,
                    tokenId: "err-\(i)", token0: "", token1: "",
                    sym0: "", sym1: "", feePct: "", feeRaw: 0,
                    fees0: 0, fees1: 0, tickLower: 0, tickUpper: 0,
                    liquidity: 0,
                    error: error.localizedDescription
                ))
            }
        }

        guard !rawPositions.isEmpty else { return ([], 0, nil) }

        // 3 · prices
        let priceMap = await priceService.fetchPrices(
            for: Array(tokenAddrs),
            coingeckoPlatformID: chain.coingeckoPlatformID,
            defiLlamaChainKey: chain.defiLlamaChainKey
        )

        // 4 · USD + in-range + amounts
        var totalFeesUSD = 0.0
        var finalPositions: [Position] = []

        for var p in rawPositions {
            guard p.error == nil else { finalPositions.append(p); continue }

            var usd = 0.0; var hasUsd = false
            if let px = priceMap[p.token0.lowercased()], p.fees0 > 0 { usd += p.fees0 * px; hasUsd = true }
            if let px = priceMap[p.token1.lowercased()], p.fees1 > 0 { usd += p.fees1 * px; hasUsd = true }
            if hasUsd { p.usd = usd; totalFeesUSD += usd }

            do {
                let pd   = try await eth.ethCall(to: v3Factory, data: ABI.callGetPool(token0: p.token0, token1: p.token1, fee: p.feeRaw))
                let pool = pd.readAddress(wordAt: 0)
                guard pool.dropFirst(2).lowercased() != String(repeating: "0", count: 40) else {
                    finalPositions.append(p); continue
                }
                let key = pool.lowercased()
                let tick: Int; let sqrtPrice: Double
                if let ct = poolTicks[key], let sp = poolSqrtPrices[key] {
                    tick = ct; sqrtPrice = sp
                } else {
                    let s0 = try await eth.ethCall(to: pool, data: ABI.callSlot0())
                    tick      = s0.readInt24(wordAt: 32)
                    sqrtPrice = s0.readAmount(wordAt: 0, decimals: 0) / pow(2.0, 96)
                    poolTicks[key] = tick; poolSqrtPrices[key] = sqrtPrice
                }
                p.currentTick = tick
                p.inRange = tick >= p.tickLower && tick <= p.tickUpper
                p.poolAddress = pool.lowercased()
                computeAmounts(position: &p, sqrtPrice: sqrtPrice, metaCache: metaCache, priceMap: priceMap)
            } catch { /* inRange stays nil */ }

            finalPositions.append(p)
        }

        return (finalPositions, totalFeesUSD, nil)
    }

    // MARK: - v4

    private func loadV4(
        wallet: String, eth: EthereumClient, chain: SupportedChain
    ) async -> (
        positions: [Position],
        feesUSD: Double,
        error: String?,
        bootstrapInProgress: Bool,
        bootstrapNextFromBlock: Int?
    ) {
        guard let v4PM = chain.v4PM, let v4SV = chain.v4SV else {
            return ([], 0, nil, false, nil)
        }
        guard let deployHex = chain.v4DeployBlockHex,
              let deployBlock = Int(deployHex.dropFirst(2), radix: 16) else {
            return ([], 0, nil, false, nil)
        }

        var metaCache: [String: (symbol: String, decimals: Int)] = [:]
        var poolCache: [String: (sqrtPrice: Double, tick: Int)] = [:]
        var tokenAddrs = Set<String>()
        var rawPositions: [Position] = []

        // 1 · Quick balance check (cheap — avoids log queries when wallet has no v4 positions)
        let v4Balance: UInt64
        do {
            let numData = try await eth.ethCall(to: v4PM, data: ABI.callBalanceOf(owner: wallet))
            guard numData.count >= 32 else { return ([], 0, "v4: unexpected balanceOf response", false, nil) }
            v4Balance = numData.readUInt64(wordAt: 0)
        } catch EthereumClient.Err.noResult {
            return ([], 0, "v4: balanceOf returned no result (RPC did not return a usable payload)", false, nil)
        } catch {
            return ([], 0, "v4: balanceOf failed – \(error.localizedDescription)", false, nil)
        }
        guard v4Balance > 0 else { return ([], 0, nil, false, nil) }

        // 2 · Enumerate owned tokenIds via ERC-721 Transfer events.
        //     The v4 PositionManager does NOT implement ERC-721 Enumerable,
        //     so tokenOfOwnerByIndex() does not exist. We reconstruct ownership
        //     from Transfer(to=wallet) minus Transfer(from=wallet).
        //     Note: requires an RPC that supports large eth_getLogs block ranges
        //     (Alchemy/Infura paid tiers work; very restricted free-tier nodes may not).
        let walletPadded: String = {
            let hex = (wallet.hasPrefix("0x") ? String(wallet.dropFirst(2)) : wallet).lowercased()
            return "0x" + String(repeating: "0", count: 64 - min(hex.count, 64)) + hex
        }()

        // Get all tokenIds ever transferred TO this wallet (mints + incoming transfers).
        // transferSig is hardcoded (known keccak256) to avoid any keccak implementation variance.
        let transferSig = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

        // Pull block head once, then only scan deltas from the last successful sync
        // (with a short reorg lookback).
        let currentBlock: Int
        do { currentBlock = try await eth.ethBlockNumber() }
        catch { return ([], 0, "v4: eth_blockNumber failed – \(error.localizedDescription)", false, nil) }

        let previousCache = loadV4OwnershipCache(wallet: wallet, chain: chain)
        let hasCache = previousCache != nil
        let chunkSize = AppSettings.shared.v4LogChunkSize
        let maxConcurrentLogs = AppSettings.shared.v4LogMaxConcurrentRequests
        let bootstrapMaxChunksPerRefresh = AppSettings.shared.v4BootstrapMaxChunksPerRefresh
        let bootstrapFrom = previousCache?.nextBootstrapFromBlock ?? (hasCache ? nil : deployBlock)
        let scanStartBlock = bootstrapFrom ?? max(
            deployBlock,
            (previousCache?.lastScannedBlock ?? deployBlock) - v4ReorgLookbackBlocks
        )
        let scanEndBlock: Int = {
            guard let b = bootstrapFrom else { return currentBlock }
            let maxSpan = chunkSize * bootstrapMaxChunksPerRefresh
            return min(b + maxSpan - 1, currentBlock)
        }()
        let chunks = stride(from: scanStartBlock, through: scanEndBlock, by: chunkSize).map { start -> (String, String) in
            let end = min(start + chunkSize - 1, scanEndBlock)
            return ("0x" + String(start, radix: 16), "0x" + String(end, radix: 16))
        }

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
                                address: v4PM,
                                topics: [transferSig, nil, walletPadded],
                                fromBlock: from,
                                toBlock: to,
                                context: "[to]"
                            )
                            let outgoing: [[String: Any]]
                            if hasCache && bootstrapFrom == nil {
                                outgoing = try await eth.ethGetLogs(
                                    address: v4PM,
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
                return ([], 0, "v4: Transfer log query failed near \(sampleRange) – \(error.localizedDescription)", false, nil)
            }
        }

        func extractTokenId(_ log: [String: Any]) -> UInt64? {
            guard let topics = log["topics"] as? [String], topics.count >= 4 else { return nil }
            let hex = topics[3].hasPrefix("0x") ? String(topics[3].dropFirst(2)) : topics[3]
            guard let val = UInt64(hex.suffix(16), radix: 16) else { return nil }
            return val
        }
        let toIds = Set(toLogs.compactMap(extractTokenId))
        let fromIds = Set(fromLogs.compactMap(extractTokenId))
        var candidateIds = Set(previousCache?.candidateTokenIds ?? [])
        candidateIds.formUnion(toIds)
        candidateIds.formUnion(fromIds)

        var ownedIds = Set(previousCache?.ownedTokenIds ?? [])

        let nextBootstrapFromBlock: Int? = {
            guard bootstrapFrom != nil else { return nil }
            let reachedHead = scanEndBlock >= currentBlock
            if reachedHead { return nil }
            return scanEndBlock + 1
        }()
        let bootstrapPassCounter: Int? = {
            guard bootstrapFrom != nil else { return nil }
            return (previousCache?.bootstrapPassCounter ?? 0) + 1
        }()

        if candidateIds.isEmpty {
            saveV4OwnershipCache(
                V4OwnershipCache(
                    lastScannedBlock: scanEndBlock,
                    candidateTokenIds: [],
                    ownedTokenIds: [],
                    nextBootstrapFromBlock: nextBootstrapFromBlock,
                    bootstrapPassCounter: nextBootstrapFromBlock == nil ? nil : bootstrapPassCounter
                ),
                wallet: wallet,
                chain: chain
            )
            if let next = nextBootstrapFromBlock {
                return ([], 0, nil, true, next)
            }
            return ([], 0, "v4: no Transfer events found for this wallet (balance=\(v4Balance))", false, nil)
        }

        // Verify ownership only for tokenIds that changed since the last scan.
        // First sync verifies all candidates once.
        let idsToVerify: [UInt64] = {
            if previousCache == nil { return Array(candidateIds) }
            return Array(toIds.union(fromIds))
        }()

        let ownershipUpdates = await withTaskGroup(of: (UInt64, Bool)?.self) { group -> [(UInt64, Bool)] in
            for tokenId in idsToVerify {
                group.addTask {
                    guard let data = try? await eth.ethCall(
                        to: v4PM, data: ABI.callOwnerOf(tokenId: tokenId)
                    ) else { return nil }
                    let isOwner = data.readAddress(wordAt: 0).lowercased() == wallet.lowercased()
                    return (tokenId, isOwner)
                }
            }
            var result: [(UInt64, Bool)] = []
            for await update in group { if let update { result.append(update) } }
            return result
        }
        for (tokenId, isOwner) in ownershipUpdates {
            if isOwner { ownedIds.insert(tokenId) }
            else { ownedIds.remove(tokenId) }
        }

        // Safety net: if cache and live balance diverge, do one full ownership reconciliation.
        if Int(v4Balance) != ownedIds.count {
            let fullOwned = await withTaskGroup(of: Optional<UInt64>.self) { group -> [UInt64] in
                for tokenId in candidateIds {
                    group.addTask {
                        guard let data = try? await eth.ethCall(
                            to: v4PM, data: ABI.callOwnerOf(tokenId: tokenId)
                        ) else { return nil }
                        return data.readAddress(wordAt: 0).lowercased() == wallet.lowercased()
                            ? tokenId : nil
                    }
                }
                var result: [UInt64] = []
                for await id in group { if let id { result.append(id) } }
                return result
            }
            ownedIds = Set(fullOwned)
        }

        guard !ownedIds.isEmpty else {
            return ([], 0, "v4: balance=\(v4Balance), found \(candidateIds.count) candidate tokenIds but none pass ownerOf check", false, nil)
        }

        saveV4OwnershipCache(
            V4OwnershipCache(
                lastScannedBlock: scanEndBlock,
                candidateTokenIds: Array(candidateIds).sorted(),
                ownedTokenIds: Array(ownedIds).sorted(),
                nextBootstrapFromBlock: nextBootstrapFromBlock,
                bootstrapPassCounter: nextBootstrapFromBlock == nil ? nil : bootstrapPassCounter
            ),
            wallet: wallet,
            chain: chain
        )

        // 3 · per-position
        for tokenId in ownedIds.sorted() {
            do {
                // getPoolAndPositionInfo returns:
                //   word 0: currency0 (address)   word 1: currency1 (address)
                //   word 2: fee (uint24)           word 3: tickSpacing (int24)
                //   word 4: hooks (address)
                //   word 5: positionInfo (bytes32)
                //     bytes32 layout: [25 bytes poolId][3 bytes tickUpper][3 bytes tickLower][1 byte flags]
                //     i.e. tickUpper at word+25, tickLower at word+28
                let posData = try await eth.ethCall(
                    to: v4PM,
                    data: ABI.v4CallGetPoolAndPositionInfo(tokenId: tokenId)
                )
                guard posData.count >= 192 else { continue }

                let currency0   = posData.readAddress(wordAt: 0)
                let currency1   = posData.readAddress(wordAt: 32)
                let fee         = Int(posData.readUInt64(wordAt: 64))
                let tickSpacing = posData.readInt24(wordAt: 96)
                let hooks       = posData.readAddress(wordAt: 128)
                let tickLower   = posData.readInt24At(byteOffset: 160 + 28)
                let tickUpper   = posData.readInt24At(byteOffset: 160 + 25)

                // Liquidity
                let liqData = try await eth.ethCall(
                    to: v4PM,
                    data: ABI.v4CallGetPositionLiquidity(tokenId: tokenId)
                )
                let liquidity = liqData.readAmount(wordAt: 0, decimals: 0)
                guard liquidity > 0 else { continue }

                // Map native ETH → WETH for metadata/price lookups; keep original for PoolId
                let priceAddr0 = isNativeToken(currency0) ? chain.wrappedNativeToken : currency0
                let priceAddr1 = isNativeToken(currency1) ? chain.wrappedNativeToken : currency1

                let m0 = isNativeToken(currency0)
                    ? (symbol: "ETH", decimals: 18)
                    : await resolve(addr: currency0, eth: eth, cache: &metaCache)
                let m1 = isNativeToken(currency1)
                    ? (symbol: "ETH", decimals: 18)
                    : await resolve(addr: currency1, eth: eth, cache: &metaCache)

                tokenAddrs.insert(priceAddr0.lowercased())
                tokenAddrs.insert(priceAddr1.lowercased())

                let poolId = ABI.computeV4PoolId(
                    currency0: currency0, currency1: currency1,
                    fee: fee, tickSpacing: tickSpacing, hooks: hooks
                )

                let feePct = fee == 0
                    ? "dyn"
                    : String(format: "%.4g", Double(fee) / 10_000)

                rawPositions.append(Position(
                    chainID: chain.id,
                    chainName: chain.displayName,
                    chainNumericID: chain.chainId,
                    tokenId:   String(tokenId),
                    token0:    priceAddr0, token1:    priceAddr1,
                    sym0:      m0.symbol,  sym1:      m1.symbol,
                    feePct:    feePct,     feeRaw:    fee,
                    fees0:     0,          fees1:     0,
                    tickLower: tickLower,  tickUpper: tickUpper,
                    liquidity: liquidity,
                    isV4:      true,
                    poolId:    poolId
                ))
            } catch EthereumClient.Err.noResult {
                continue // stale tokenId — contract returned null, position no longer exists
            } catch {
                rawPositions.append(Position(
                    chainID: chain.id,
                    chainName: chain.displayName,
                    chainNumericID: chain.chainId,
                    tokenId: String(tokenId), token0: "", token1: "",
                    sym0: "", sym1: "", feePct: "", feeRaw: 0,
                    fees0: 0, fees1: 0, tickLower: 0, tickUpper: 0,
                    liquidity: 0,
                    error: "v4 #\(tokenId): \(error.localizedDescription)"
                ))
            }
        }

        guard !rawPositions.isEmpty else {
            return ([], 0, nil, nextBootstrapFromBlock != nil, nextBootstrapFromBlock)
        }

        // 4 · prices
        let priceMap = await priceService.fetchPrices(
            for: Array(tokenAddrs),
            coingeckoPlatformID: chain.coingeckoPlatformID,
            defiLlamaChainKey: chain.defiLlamaChainKey
        )

        // 5 · in-range + amounts + fees
        var finalPositions: [Position] = []
        var totalFeesUSD = 0.0

        for var p in rawPositions {
            guard let pid = p.poolId else { finalPositions.append(p); continue }

            let cacheKey = pid.hexString
            let tick: Int; let sqrtPrice: Double
            if let c = poolCache[cacheKey] {
                tick = c.tick; sqrtPrice = c.sqrtPrice
            } else {
                guard let s0 = try? await eth.ethCall(to: v4SV, data: ABI.v4CallGetSlot0(poolId: pid)),
                      s0.count >= 64 else { finalPositions.append(p); continue }
                tick      = s0.readInt24(wordAt: 32)
                sqrtPrice = s0.readAmount(wordAt: 0, decimals: 0) / pow(2.0, 96)
                poolCache[cacheKey] = (sqrtPrice: sqrtPrice, tick: tick)
            }

            p.currentTick = tick
            p.inRange = tick >= p.tickLower && tick <= p.tickUpper
            computeAmounts(position: &p, sqrtPrice: sqrtPrice, metaCache: metaCache, priceMap: priceMap)

            // Unclaimed fees via StateView feeGrowth math (4 concurrent RPC calls)
            if let tokenId = UInt64(p.tokenId) {
                do {
                    let fees = try await computeV4Fees(
                        poolId: pid, tokenId: tokenId,
                        tickLower: p.tickLower, tickUpper: p.tickUpper,
                        currentTick: tick, liquidityRaw: p.liquidity, eth: eth, v4SV: v4SV, v4PM: v4PM)
                    let dec0 = metaCache[p.token0.lowercased()]?.decimals ?? 18
                    let dec1 = metaCache[p.token1.lowercased()]?.decimals ?? 18
                    p.fees0 = fees.fees0 / pow(10.0, Double(dec0))
                    p.fees1 = fees.fees1 / pow(10.0, Double(dec1))
                    var feeUSD = 0.0; var hasFeeUSD = false
                    if let px = priceMap[p.token0.lowercased()], p.fees0 > 0 { feeUSD += p.fees0 * px; hasFeeUSD = true }
                    if let px = priceMap[p.token1.lowercased()], p.fees1 > 0 { feeUSD += p.fees1 * px; hasFeeUSD = true }
                    if hasFeeUSD { p.usd = feeUSD; totalFeesUSD += feeUSD }
                } catch {
                    p.feesError = error.localizedDescription
                }
            }

            finalPositions.append(p)
        }

        return (finalPositions, totalFeesUSD, nil, nextBootstrapFromBlock != nil, nextBootstrapFromBlock)
    }

    private func composedErrorText(snapshot: [ChainLoadResult], fallbackErrors: [String]) -> String? {
        var messages: [String] = []
        for result in snapshot {
            if result.bootstrapInProgress, let next = result.bootstrapNextFromBlock {
                let remaining = bootstrapRemainingSeconds(for: result.chain.id)
                if remaining <= 0 {
                    messages.append(
                        "\(result.chain.displayName): v4: bootstrap refresh in progress (from 0x\(String(next, radix: 16)))"
                    )
                } else {
                    messages.append(
                        "\(result.chain.displayName): v4: bootstrap scan in progress (auto-refresh in ~\(remaining)s from 0x\(String(next, radix: 16)))"
                    )
                }
            } else if let error = result.error {
                messages.append(error)
            }
        }
        if messages.isEmpty {
            return fallbackErrors.isEmpty ? nil : fallbackErrors.joined(separator: "\n")
        }
        return messages.joined(separator: "\n")
    }

    private func bootstrapRemainingSeconds(for chainID: String) -> Int {
        guard let deadline = bootstrapFollowUpDeadlineByChainID[chainID] else {
            return Int(bootstrapFollowUpSeconds)
        }
        return max(0, Int(ceil(deadline.timeIntervalSinceNow)))
    }

    private func startBootstrapCountdownTimer() {
        guard bootstrapCountdownTimer == nil else { return }
        bootstrapCountdownTimer = .scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshBootstrapCountdownMessage()
            }
        }
    }

    private func stopBootstrapCountdownTimer() {
        bootstrapCountdownTimer?.invalidate()
        bootstrapCountdownTimer = nil
    }

    private func refreshBootstrapCountdownMessage() {
        let activeChains = AppSettings.shared.enabledChains()
        let snapshot = activeChains.compactMap { chainResultsByID[$0.id] }
        guard snapshot.contains(where: \.bootstrapInProgress) else {
            stopBootstrapCountdownTimer()
            return
        }
        let errors = snapshot.compactMap(\.error)
        lastError = composedErrorText(snapshot: snapshot, fallbackErrors: errors)
    }

    // MARK: - v4 fee computation

    /// Computes unclaimed v4 fees for a single position using the standard Uniswap feeGrowthInside formula.
    /// Makes 4 concurrent calls to StateView: getPosition, getTickInfo×2, getFeeGrowthGlobals.
    /// Returns raw fee amounts (before decimal conversion). Throws with a descriptive message if any call fails.
    ///
    /// All feeGrowth arithmetic is done in exact uint256 (wrapping) to avoid catastrophic cancellation
    /// when the accumulators are large (they can be ~2^150+ for active pools, which destroys double
    /// precision if you subtract two nearly-equal large doubles).
    private func computeV4Fees(
        poolId: Data, tokenId: UInt64,
        tickLower: Int, tickUpper: Int,
        currentTick: Int, liquidityRaw: Double,
        eth: EthereumClient,
        v4SV: String,
        v4PM: String
    ) async throws -> (fees0: Double, fees1: Double) {
        async let posTask  = eth.ethCall(to: v4SV, data: ABI.v4CallGetPosition(
            poolId: poolId, owner: v4PM,
            tickLower: tickLower, tickUpper: tickUpper, salt: tokenId))
        async let loTask   = eth.ethCall(to: v4SV, data: ABI.v4CallGetTickInfo(poolId: poolId, tick: tickLower))
        async let hiTask   = eth.ethCall(to: v4SV, data: ABI.v4CallGetTickInfo(poolId: poolId, tick: tickUpper))
        async let globTask = eth.ethCall(to: v4SV, data: ABI.v4CallGetFeeGrowthGlobals(poolId: poolId))

        let pos  = try? await posTask
        let lo   = try? await loTask
        let hi   = try? await hiTask
        let glob = try? await globTask

        // Collect specific failures for diagnosis
        var failures: [String] = []
        if pos  == nil { failures.append("getPosition: no response") }
        else if pos!.count < 96  { failures.append("getPosition: \(pos!.count)B < 96B") }
        if lo   == nil { failures.append("getTickInfo(lo \(tickLower)): no response") }
        else if lo!.count < 128  { failures.append("getTickInfo(lo): \(lo!.count)B < 128B") }
        if hi   == nil { failures.append("getTickInfo(hi \(tickUpper)): no response") }
        else if hi!.count < 128  { failures.append("getTickInfo(hi): \(hi!.count)B < 128B") }
        if glob == nil { failures.append("getFeeGrowthGlobals: no response") }
        else if glob!.count < 64 { failures.append("getFeeGrowthGlobals: \(glob!.count)B < 64B") }

        if !failures.isEmpty {
            throw V4FeesError("poolId=\(poolId.hexString.prefix(8))… tokenId=\(tokenId) ticks=[\(tickLower),\(tickUpper)]: \(failures.joined(separator: "; "))")
        }
        let posD = pos!, loD = lo!, hiD = hi!, globD = glob!

        // Read all feeGrowth values as exact 32-byte (uint256) words.
        // Do NOT use readAmount() here — those values are ~2^150+ for active pools,
        // causing catastrophic cancellation if converted to Double before subtraction.
        let fg0Last   = posD.readWord(at: 32)
        let fg1Last   = posD.readWord(at: 64)

        let fg0OutLo  = loD.readWord(at: 64)
        let fg1OutLo  = loD.readWord(at: 96)
        let fg0OutHi  = hiD.readWord(at: 64)
        let fg1OutHi  = hiD.readWord(at: 96)

        let fg0Global = globD.readWord(at: 0)
        let fg1Global = globD.readWord(at: 32)

        // Standard feeGrowthInside = global − feeGrowthBelow(lower) − feeGrowthAbove(upper)
        // All subtractions wrap mod 2^256, matching Solidity unchecked arithmetic.
        let fg0Below = currentTick >= tickLower ? fg0OutLo : u256Sub(fg0Global, fg0OutLo)
        let fg1Below = currentTick >= tickLower ? fg1OutLo : u256Sub(fg1Global, fg1OutLo)
        let fg0Above = currentTick <  tickUpper ? fg0OutHi : u256Sub(fg0Global, fg0OutHi)
        let fg1Above = currentTick <  tickUpper ? fg1OutHi : u256Sub(fg1Global, fg1OutHi)

        let fg0Inside = u256Sub(u256Sub(fg0Global, fg0Below), fg0Above)
        let fg1Inside = u256Sub(u256Sub(fg1Global, fg1Below), fg1Above)

        // Delta since last collection (wrapping — handles the fgInside < fgLast case gracefully)
        let delta0 = u256Sub(fg0Inside, fg0Last)
        let delta1 = u256Sub(fg1Inside, fg1Last)

        // Only now convert to Double — the delta is small (fees since last touch) so precision is fine.
        // unclaimed = (fgInsideDelta × liquidity) ÷ 2¹²⁸
        let fees0 = u256ToDouble(delta0) * liquidityRaw / pow(2.0, 128)
        let fees1 = u256ToDouble(delta1) * liquidityRaw / pow(2.0, 128)
        return (fees0: fees0, fees1: fees1)
    }

    // MARK: - Shared helpers

    /// Standard Uniswap v3/v4 amount calculation from sqrtPrice and liquidity.
    private func computeAmounts(
        position p: inout Position,
        sqrtPrice: Double,
        metaCache: [String: (symbol: String, decimals: Int)],
        priceMap: [String: Double]
    ) {
        guard p.liquidity > 0, sqrtPrice > 0 else { return }
        let dec0 = metaCache[p.token0.lowercased()]?.decimals ?? 18
        let dec1 = metaCache[p.token1.lowercased()]?.decimals ?? 18
        let half = log(1.0001) / 2.0
        let sqrtLower = exp(Double(p.tickLower) * half)
        let sqrtUpper = exp(Double(p.tickUpper) * half)
        let L = p.liquidity
        var raw0 = 0.0, raw1 = 0.0
        if sqrtPrice <= sqrtLower {
            raw0 = L * (1.0 / sqrtLower - 1.0 / sqrtUpper)
        } else if sqrtPrice >= sqrtUpper {
            raw1 = L * (sqrtUpper - sqrtLower)
        } else {
            raw0 = L * (1.0 / sqrtPrice - 1.0 / sqrtUpper)
            raw1 = L * (sqrtPrice - sqrtLower)
        }
        p.amount0 = raw0 / pow(10.0, Double(dec0))
        p.amount1 = raw1 / pow(10.0, Double(dec1))

        var posUSD = 0.0; var has = false
        if let px = priceMap[p.token0.lowercased()], p.amount0 > 0 { posUSD += p.amount0 * px; has = true }
        if let px = priceMap[p.token1.lowercased()], p.amount1 > 0 { posUSD += p.amount1 * px; has = true }
        if has { p.positionUSD = posUSD }
    }

    /// Fetches and caches ERC-20 symbol and decimals for a token address.
    private func resolve(
        addr: String,
        eth: EthereumClient,
        cache: inout [String: (symbol: String, decimals: Int)]
    ) async -> (symbol: String, decimals: Int) {
        let key = addr.lowercased()
        if let hit = cache[key] { return hit }
        var sym = shortenAddr(addr), dec = 18
        if let d = try? await eth.ethCall(to: addr, data: ABI.callSymbol()), !d.isEmpty {
            let s = d.readABIString(); if !s.isEmpty { sym = s }
        }
        if let d = try? await eth.ethCall(to: addr, data: ABI.callDecimals()), !d.isEmpty {
            dec = Int(d.readUInt64(wordAt: 0))
        }
        let meta = (symbol: sym, decimals: dec)
        cache[key] = meta
        return meta
    }

    private func loadV4OwnershipCache(wallet: String, chain: SupportedChain) -> V4OwnershipCache? {
        let key = v4OwnershipCacheKey(wallet: wallet, chain: chain)
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(V4OwnershipCache.self, from: data)
    }

    private func saveV4OwnershipCache(_ cache: V4OwnershipCache, wallet: String, chain: SupportedChain) {
        let key = v4OwnershipCacheKey(wallet: wallet, chain: chain)
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func v4OwnershipCacheKey(wallet: String, chain: SupportedChain) -> String {
        let normalized = wallet.lowercased()
        return "v4OwnershipCache.\(chain.id).\(normalized)"
    }

    private func configureTimer() {
        timer?.invalidate()
        let interval = TimeInterval(AppSettings.shared.refreshIntervalMinutes * 60)
        timer = .scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.startLoad() }
        }
    }
}

// MARK: - Exact uint256 arithmetic (for feeGrowth accumulators)

/// Wrapping 256-bit subtraction (mod 2^256), matching Solidity `unchecked { a - b }`.
private func u256Sub(_ a: Data, _ b: Data) -> Data {
    var r = [UInt8](repeating: 0, count: 32)
    var borrow: Int = 0
    for i in stride(from: 31, through: 0, by: -1) {
        let diff = Int(a[i]) - Int(b[i]) - borrow
        r[i] = UInt8((diff + 256) & 0xFF)
        borrow = diff < 0 ? 1 : 0
    }
    return Data(r)
}

/// Convert a 32-byte big-endian uint256 to Double.
/// Only call this on values known to be small (e.g. feeGrowth deltas), where precision loss is acceptable.
private func u256ToDouble(_ d: Data) -> Double {
    var v = 0.0
    for byte in d { v = v * 256.0 + Double(byte) }
    return v
}

// MARK: - Error types

private struct V4FeesError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

// MARK: - Utilities

private func isNativeToken(_ addr: String) -> Bool {
    addr.lowercased() == nativeTokenAddress
}

private func shortenAddr(_ addr: String) -> String {
    let a = addr.hasPrefix("0x") ? addr : "0x\(addr)"
    guard a.count >= 10 else { return a }
    return "\(a.prefix(6))…\(a.suffix(4))"
}
