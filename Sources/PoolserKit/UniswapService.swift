import Foundation
import Combine
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Drives refreshes across the enabled chains and publishes the merged result to the UI.
/// Reading positions is delegated to `V3PositionLoader` and `V4PositionLoader`.
@MainActor
public final class UniswapService: ObservableObject {
    @Published public var titleText      = "… 👀"
    @Published public var positions:     [Position] = []
    private var allPositions: [Position] = []
    @Published public var isLoading      = false
    @Published public var lastError:     String?
    @Published public var lastUpdated:   Date? = nil
    /// Fees earned per day: the chain history for v3 positions where the node serves past
    /// state, otherwise what the ledger saw between refreshes.
    @Published public private(set) var dailyFees = DailyFees()
    /// Fees earned per day, from the unclaimed fees seen at each refresh.
    private var feeLedger = DailyFeeLedger.load()
    /// Fees earned per day from chain state, by position id.
    private var chainDailyFees = DailyFees()
    private var previousTotal: Double = -1
    private var flashTask: Task<Void, Never>?

    private let priceService = PriceService()
    private let poolStatsService = PoolStatsService()
    private let bootstrapFollowUpSeconds: UInt64 = 75
    private var timer: Timer?
    private var refreshIntervalCancellable: AnyCancellable?
    private var visibilityCancellable: AnyCancellable?
    private var activeLoadTask: Task<Void, Never>?
    private var bootstrapFollowUpTask: Task<Void, Never>?
    private var feeHistoryTask: Task<Void, Never>?
    private var dailyFeeTask: Task<Void, Never>?
    private var bootstrapCountdownTimer: Timer?
    private var bootstrapFollowUpDeadlineByChainID: [String: Date] = [:]
    private var loadGeneration: UInt64 = 0
    private var chainResultsByID: [String: ChainLoadResult] = [:]
    private var widgetReload = WidgetReloadThrottle()

    public init() {
        visibilityCancellable = AppSettings.shared.$hiddenPositions
            .dropFirst()
            .sink { [weak self] hidden in self?.applyVisibility(hidden: hidden, flash: false) }
        #if os(macOS)
        configureTimer()
        refreshIntervalCancellable = AppSettings.shared.$refreshIntervalMinutes
            .removeDuplicates()
            .sink { [weak self] _ in self?.configureTimer() }
        #endif
        dailyFees = feeLedger.dailyFees
        startLoad()
    }

    public func refresh() { startLoad() }

    public func refreshAndWait() async {
        startLoad()
        await activeLoadTask?.value
    }

    public func cancelRefresh() { activeLoadTask?.cancel() }

    public func refreshForWalletChange() {
        allPositions = []
        positions = []
        chainDailyFees = DailyFees()
        titleText = "… 👀"
        previousTotal = -1
        chainResultsByID = [:]
        startLoad()
    }

    // MARK: - Orchestrator

    private func startLoad() {
        activeLoadTask?.cancel()
        bootstrapFollowUpTask?.cancel()
        feeHistoryTask?.cancel()
        dailyFeeTask?.cancel()
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
        // The current generation owns isLoading: every exit (config error, cancellation,
        // success) clears it, while a superseded load leaves it to the newer one.
        defer { if isCurrentGeneration(generation) { isLoading = false } }

        let wallet = AppSettings.shared.walletAddress
        let key = AppSettings.shared.infuraAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let chains = AppSettings.shared.enabledChains()
        guard WalletAddress.normalize(wallet) != nil, !key.isEmpty, !chains.isEmpty else {
            guard isCurrentGeneration(generation) else { return }
            chainResultsByID = [:]
            positions = []
            titleText = "– 👀"
            publishWidgetSnapshot(nil, updatedAt: Date())
            #if os(macOS)
            lastError = "Configure wallet, Infura API key, and at least one enabled network in Settings (⌘,)"
            #else
            lastError = "Configure wallet, Infura API key, and at least one enabled network in Settings"
            #endif
            return
        }

        guard isCurrentGeneration(generation), !Task.isCancelled else { return }
        isLoading = true
        lastError = nil
        LogStore.shared.log("refresh started", level: .info)
        await EthereumClient.setCreditBudget(perSecond: AppSettings.shared.rpcCreditsPerSecondBudget)

        let results = await loadChains(chains, wallet: wallet)

        guard isCurrentGeneration(generation), !Task.isCancelled else { return }
        let enrichedResults = await enrichChainResults(results)
        guard isCurrentGeneration(generation), !Task.isCancelled else { return }

        applyChainResults(enrichedResults, activeChains: chains)

        LogStore.shared.log("refresh done — \(positions.count) positions across \(chains.count) chain(s)", level: .info)
        scheduleBootstrapFollowUpIfNeeded(
            chainIDs: enrichedResults.filter(\.bootstrapInProgress).map { $0.chain.id },
            generation: generation
        )
        lastUpdated = Date()

        NotificationService.fireRangeChangeNotificationsIfNeeded(for: positions)

        // Launch fee history scan in background — positions are already displayed.
        let v3Positions = positions.filter { !$0.isV4 && $0.error == nil }
        if !v3Positions.isEmpty && AppSettings.shared.trackClaimedFees {
            startFeeHistoryLoad(v3Positions: v3Positions, wallet: wallet, generation: generation)
        }
        startDailyFeeLoad(v3Positions: v3Positions.filter { $0.poolAddress != nil }, generation: generation)
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
        guard WalletAddress.normalize(wallet) != nil, !key.isEmpty, !activeChains.isEmpty else { return }

        let idSet = Set(chainIDs)
        let targetChains = activeChains.filter { idSet.contains($0.id) }
        guard !targetChains.isEmpty else { return }
        await EthereumClient.setCreditBudget(perSecond: AppSettings.shared.rpcCreditsPerSecondBudget)

        LogStore.shared.log(
            "v4 bootstrap in progress — running accelerated follow-up for \(targetChains.map(\.displayName).joined(separator: ", "))",
            level: .info
        )

        let results = await loadChains(targetChains, wallet: wallet)
        guard isCurrentGeneration(generation), !Task.isCancelled else { return }

        let enrichedResults = await enrichChainResults(results)
        guard isCurrentGeneration(generation), !Task.isCancelled else { return }
        applyChainResults(enrichedResults, activeChains: activeChains)
        NotificationService.fireRangeChangeNotificationsIfNeeded(for: positions)

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
                    var enriched = result
                    enriched.positions = await self.enrichPositionsWithPoolStats(result.positions)
                    return enriched
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
                    if let stats = await self.poolStatsService.stats(
                        network: network,
                        poolAddress: addr,
                        feePct: p.feeFraction
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

    /// Hands the widgets what the menu shows, with a week of daily fees. Nil clears them.
    private func publishWidgetSnapshot(_ positions: [Position]?, updatedAt: Date) {
        guard let url = PortfolioSnapshotStore.fileURL else { return }
        let now = Date()
        let snapshot = positions.map {
            PortfolioSnapshot(
                positions: $0,
                dailyFeesUSD: dailyFees.walletDailyUSD($0, days: 7, minDays: 1, endingAt: now),
                updatedAt: updatedAt
            )
        }
        if !PortfolioSnapshotStore.save(snapshot, to: url) {
            LogStore.shared.log("Could not write the widget snapshot", level: .error)
        }
        guard widgetReload.shouldReload(for: snapshot, now: now) else { return }
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
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
        allPositions = all
        feeLedger.record(all, at: Date())
        feeLedger.save()
        dailyFees = feeLedger.dailyFees.overlaid(with: chainDailyFees)

        let errors = snapshot.compactMap(\.error)
        let errorText = composedErrorText(snapshot: snapshot, fallbackErrors: errors)
        lastError = errorText
        if let err = errorText { LogStore.shared.log(err, level: .error) }
        applyVisibility(flash: true, publishWidget: !(all.isEmpty && errorText != nil))
    }

    private func applyVisibility(hidden: [HiddenPosition]? = nil, flash: Bool, publishWidget: Bool = true) {
        positions = HiddenPositionStore.visible(allPositions, hidden: hidden ?? AppSettings.shared.hiddenPositions)
        if publishWidget {
            publishWidgetSnapshot(positions, updatedAt: flash ? Date() : (lastUpdated ?? Date()))
        }

        if positions.isEmpty {
            flashTask?.cancel()
            titleText = "$0.00 👀"
            previousTotal = 0
        } else {
            let total = positions.compactMap(\.usd).reduce(0, +)
            let value = positions.compactMap(\.positionUSD).reduce(0, +)
            let baseTitle = MenuBarTitle.text(valueUSD: value, feesUSD: total)
            flashTask?.cancel()
            titleText = baseTitle
            let displayChanged = String(format: "%.2f", total) != String(format: "%.2f", previousTotal)
            if flash, previousTotal >= 0, displayChanged, AppSettings.shared.flashOnValueChange {
                let flashEmoji = total > previousTotal ? "🔼" : "🔽"
                let flashTitle = MenuBarTitle.text(valueUSD: value, feesUSD: total, trend: flashEmoji)
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

    // MARK: - Fee history (background)

    private func startFeeHistoryLoad(v3Positions: [Position], wallet: String, generation: UInt64) {
        feeHistoryTask?.cancel()
        let chunkSize = AppSettings.shared.v4LogChunkSize
        let baseMaxChunks = AppSettings.shared.v4BootstrapMaxChunksPerRefresh
        feeHistoryTask = Task { [weak self] in
            guard let self else { return }
            let byChain = Dictionary(grouping: v3Positions, by: \.chainID)
            for (chainID, chainPositions) in byChain {
                guard !Task.isCancelled, isCurrentGeneration(generation) else { return }
                guard let chain = SupportedChain.byID(chainID),
                      let deployBlock = chain.v3DeployBlock,
                      let nfpm = chain.v3NFPM,
                      let rpcURL = AppSettings.shared.infuraRPCURL(for: chain) else { continue }
                let eth = EthereumClient(rpcURL: rpcURL)
                guard let currentBlock = try? await eth.ethBlockNumber() else { continue }
                guard !Task.isCancelled, isCurrentGeneration(generation) else { return }
                let feeResult = await FeeHistoryService.scan(
                    positions: chainPositions,
                    nfpm: nfpm,
                    deployBlock: deployBlock,
                    currentBlock: currentBlock,
                    eth: eth,
                    chainID: chainID,
                    wallet: wallet,
                    chunkSize: chunkSize,
                    baseMaxChunks: baseMaxChunks
                )
                guard !Task.isCancelled, isCurrentGeneration(generation) else { return }
                let tokenAddrs = Array(Set(chainPositions.flatMap { [$0.token0.lowercased(), $0.token1.lowercased()] }))
                let priceMap = await priceService.fetchPrices(
                    for: tokenAddrs,
                    coingeckoPlatformID: chain.coingeckoPlatformID,
                    defiLlamaChainKey: chain.defiLlamaChainKey
                )
                guard !Task.isCancelled, isCurrentGeneration(generation) else { return }
                applyFeeHistory(feeResult, priceMap: priceMap, chainID: chainID)
                if feeResult.bootstrapInProgress {
                    LogStore.shared.log("fee history [\(chain.displayName)]: syncing…", level: .info)
                } else {
                    LogStore.shared.log("fee history [\(chain.displayName)]: complete", level: .info)
                }
            }
        }
    }

    private func startDailyFeeLoad(v3Positions: [Position], generation: UInt64) {
        dailyFeeTask?.cancel()
        guard !v3Positions.isEmpty else { return }
        dailyFeeTask = Task { [weak self] in
            guard let self else { return }
            for (chainID, chainPositions) in Dictionary(grouping: v3Positions, by: \.chainID) {
                guard !Task.isCancelled, isCurrentGeneration(generation) else { return }
                guard let chain = SupportedChain.byID(chainID),
                      let nfpm = chain.v3NFPM,
                      let rpcURL = AppSettings.shared.infuraRPCURL(for: chain) else { continue }
                let days = await DailyFeeHistory.refresh(
                    positions: chainPositions, chain: chain, nfpm: nfpm, eth: EthereumClient(rpcURL: rpcURL)
                )
                guard isCurrentGeneration(generation) else { return }
                for pos in chainPositions {
                    chainDailyFees.byPosition[pos.id] = days.byPosition[pos.id]
                }
                dailyFees = feeLedger.dailyFees.overlaid(with: chainDailyFees)
                publishWidgetSnapshot(positions, updatedAt: lastUpdated ?? Date())
            }
        }
    }

    private func applyFeeHistory(
        _ result: FeeHistoryService.Result,
        priceMap: [String: Double],
        chainID: String
    ) {
        for i in allPositions.indices {
            guard allPositions[i].chainID == chainID, !allPositions[i].isV4, allPositions[i].error == nil else { continue }
            allPositions[i].feeHistoryBootstrapping = result.bootstrapInProgress
            allPositions[i].openedAt = result.openedAt[allPositions[i].tokenId]
            guard let claimed = result.fees[allPositions[i].tokenId] else { continue }
            allPositions[i].claimedFees0 = claimed.amount0
            allPositions[i].claimedFees1 = claimed.amount1
            var claimedUSD = 0.0; var hasUSD = false
            if let px = priceMap[allPositions[i].token0.lowercased()], claimed.amount0 > 0 { claimedUSD += claimed.amount0 * px; hasUSD = true }
            if let px = priceMap[allPositions[i].token1.lowercased()], claimed.amount1 > 0 { claimedUSD += claimed.amount1 * px; hasUSD = true }
            if hasUSD { allPositions[i].claimedUSD = claimedUSD }
        }
        positions = HiddenPositionStore.visible(allPositions, hidden: AppSettings.shared.hiddenPositions)
    }

    // MARK: - Per-chain load

    private func loadChains(_ chains: [SupportedChain], wallet: String) async -> [ChainLoadResult] {
        await withTaskGroup(of: ChainLoadResult.self, returning: [ChainLoadResult].self) { group in
            for chain in chains {
                group.addTask {
                    await self.loadChain(wallet: wallet, chain: chain)
                }
            }
            var collected: [ChainLoadResult] = []
            for await result in group { collected.append(result) }
            return collected
        }
    }

    private func loadChain(wallet: String, chain: SupportedChain) async -> ChainLoadResult {
        guard let rpcURL = AppSettings.shared.infuraRPCURL(for: chain) else {
            return .failed(chain, error: "\(chain.displayName): invalid Infura API key")
        }
        let eth = EthereumClient(rpcURL: rpcURL)

        do {
            let probedChainID = try await eth.ethChainId()
            if probedChainID != chain.chainId {
                return .failed(
                    chain,
                    error: "\(chain.displayName): RPC chain mismatch (expected \(chain.chainId), got \(probedChainID))"
                )
            }
        } catch {
            let msg = error.localizedDescription
            if msg.lowercased().contains("does not have access") ||
                msg.lowercased().contains("not available for project") {
                AppSettings.shared.disableChain(chain.id)
                return .failed(
                    chain,
                    error: "\(chain.displayName): Infura access denied for this API key (network auto-disabled)"
                )
            }
            return .failed(chain, error: "\(chain.displayName): RPC unavailable – \(msg)")
        }

        var v3 = LoaderOutput()
        if chain.supportsV3 {
            v3 = await V3PositionLoader(
                eth: eth,
                chain: chain,
                prices: priceService,
                trackClaimedFees: AppSettings.shared.trackClaimedFees
            ).load(wallet: wallet)
        }
        var v4 = LoaderOutput()
        if chain.supportsV4 {
            v4 = await V4PositionLoader(
                eth: eth,
                chain: chain,
                prices: priceService,
                scanSettings: V4ScanSettings(
                    logChunkSize: AppSettings.shared.v4LogChunkSize,
                    maxConcurrentLogRequests: AppSettings.shared.v4LogMaxConcurrentRequests,
                    maxChunksPerRefresh: AppSettings.shared.v4BootstrapMaxChunksPerRefresh
                )
            ).load(wallet: wallet)
        }

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

    // MARK: - Error text and bootstrap countdown

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

    #if os(macOS)
    private func configureTimer() {
        timer?.invalidate()
        let interval = TimeInterval(AppSettings.shared.refreshIntervalMinutes * 60)
        timer = .scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.startLoad() }
        }
    }
    #endif
}
