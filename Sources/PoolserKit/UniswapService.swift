import Foundation
import Combine
#if canImport(WidgetKit)
import WidgetKit
#endif

/// The last load of one saved wallet.
public struct WalletPortfolio {
    /// Positions that are not hidden.
    public internal(set) var positions: [Position] = []
    var allPositions: [Position] = []
    public internal(set) var lastUpdated: Date?
    public internal(set) var lastError: String?
    var chainResultsByID: [String: ChainLoadResult] = [:]
}

/// Drives refreshes of every saved wallet across the enabled chains and publishes the merged
/// result to the UI. `positions`, `lastError` and `lastUpdated` follow the page on screen (one
/// wallet, or all of them together); every wallet stays in `portfolios`, so switching pages
/// needs no reload. The menu bar title and the widgets choose their wallets separately.
/// Reading positions is delegated to `V3PositionLoader` and `V4PositionLoader`.
@MainActor
public final class UniswapService: ObservableObject {
    @Published public var titleText      = "… 👀"
    @Published public var positions:     [Position] = []
    /// By lowercased wallet address.
    @Published public private(set) var portfolios: [String: WalletPortfolio] = [:]
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
    /// What the title last showed, so a source change does not flash and a republish of the
    /// same title leaves a running flash alone.
    private var titleSourceKey = ""
    private var baseTitle = ""
    private var flashTask: Task<Void, Never>?

    private let priceService = PriceService()
    private let poolStatsService = PoolStatsService()
    private let bootstrapFollowUpSeconds: UInt64 = 75
    private var timer: Timer?
    private var refreshIntervalCancellable: AnyCancellable?
    private var visibilityCancellable: AnyCancellable?
    private var otherWalletVisibilityCancellable: AnyCancellable?
    private var activeLoadTask: Task<Void, Never>?
    private var bootstrapFollowUpTask: Task<Void, Never>?
    /// Chains still bootstrapping, by wallet address.
    private var bootstrapChainIDsByWallet: [String: [String]] = [:]
    private var feeHistoryTask: Task<Void, Never>?
    private var dailyFeeTask: Task<Void, Never>?
    private var bootstrapCountdownTimer: Timer?
    private var bootstrapFollowUpDeadlineByChainID: [String: Date] = [:]
    private var loadGeneration: UInt64 = 0
    private var widgetReload = WidgetReloadThrottle()

    public init() {
        visibilityCancellable = AppSettings.shared.$hiddenPositions
            .dropFirst()
            .sink { [weak self] hidden in
                // Published before the value is stored, so the new list is passed along.
                self?.hiddenPositionsChanged(wallet: AppSettings.shared.walletAddress, hidden: hidden)
            }
        otherWalletVisibilityCancellable = AppSettings.shared.otherWalletHiddenPositionsChanged
            .sink { [weak self] wallet in
                self?.hiddenPositionsChanged(wallet: wallet, hidden: AppSettings.shared.hiddenPositions(for: wallet))
            }
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

    public func portfolio(for wallet: String) -> WalletPortfolio? {
        portfolios[wallet.lowercased()]
    }

    /// Settings changed the saved wallets: drops removed ones and reloads them all.
    public func refreshForWalletChange() {
        let saved = Set(AppSettings.shared.walletAddresses.map { $0.lowercased() })
        portfolios = portfolios.filter { saved.contains($0.key) }
        publish(flash: false)
        startLoad()
    }

    /// Shows the new page's last load at once. A wallet that has not been loaded yet is
    /// loaded now.
    public func activeWalletChanged() {
        publish(flash: false)
        let settings = AppSettings.shared
        if !settings.isShowingAllWallets, portfolio(for: settings.walletAddress) == nil { startLoad() }
    }

    private func hiddenPositionsChanged(wallet: String, hidden: [HiddenPosition]) {
        updateVisiblePositions(wallet: wallet, hidden: hidden)
        publish(flash: false)
    }

    /// Every saved wallet together; nil until one has loaded.
    public var allWalletsPortfolio: WalletPortfolio? {
        let wallets = AppSettings.shared.wallets
        let loaded = wallets.compactMap { wallet in portfolio(for: wallet.address).map { (wallet, $0) } }
        guard !loaded.isEmpty else { return nil }
        let byValue = { (lhs: Position, rhs: Position) in (lhs.positionUSD ?? lhs.usd ?? 0) > (rhs.positionUSD ?? rhs.usd ?? 0) }
        var merged = WalletPortfolio()
        merged.allPositions = loaded.flatMap(\.1.allPositions).sorted(by: byValue)
        merged.positions = loaded.flatMap(\.1.positions).sorted(by: byValue)
        merged.lastUpdated = loaded.compactMap(\.1.lastUpdated).min()
        let errors = loaded.compactMap { wallet, portfolio in
            portfolio.lastError.map { wallets.count > 1 ? "\(wallet.displayName): \($0)" : $0 }
        }
        merged.lastError = errors.isEmpty ? nil : errors.joined(separator: "\n")
        return merged
    }

    /// The saved wallet holding `position`, for actions that need its owner.
    public func wallet(of position: Position) -> String? {
        AppSettings.shared.wallets.first { wallet in
            portfolio(for: wallet.address)?.allPositions.contains { $0.id == position.id } == true
        }?.address
    }

    private var pagePortfolio: WalletPortfolio? {
        let settings = AppSettings.shared
        return settings.isShowingAllWallets ? allWalletsPortfolio : portfolio(for: settings.walletAddress)
    }

    private var menuBarSourceKey: String {
        let settings = AppSettings.shared
        switch settings.menuBarSource {
        case .wallet(let id) where settings.wallets.contains(where: { $0.id == id }): return id
        case .shownPage where !settings.isShowingAllWallets: return settings.walletAddress.lowercased()
        default: return PortfolioSnapshotStore.allWalletsID
        }
    }

    private var menuBarPortfolio: WalletPortfolio? {
        let key = menuBarSourceKey
        return key == PortfolioSnapshotStore.allWalletsID ? allWalletsPortfolio : portfolios[key]
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

        let wallets = Self.walletsToLoad()
        let key = AppSettings.shared.infuraAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let chains = AppSettings.shared.enabledChains()
        guard !wallets.isEmpty, !key.isEmpty, !chains.isEmpty else {
            guard isCurrentGeneration(generation) else { return }
            portfolios = [:]
            positions = []
            titleText = "– 👀"
            baseTitle = titleText
            clearWidgets()
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

        let prefetches = await prefetchChains(chains, wallets: wallets)
        guard isCurrentGeneration(generation), !Task.isCancelled else { return }

        // The active wallet first, so the page on screen fills in before the others load.
        var bootstrapping: [String: [String]] = [:]
        for wallet in wallets {
            let results = await loadChains(chains, wallet: wallet, prefetches: prefetches)
            guard isCurrentGeneration(generation), !Task.isCancelled else { return }
            let enrichedResults = await enrichChainResults(results)
            guard isCurrentGeneration(generation), !Task.isCancelled else { return }
            applyChainResults(enrichedResults, wallet: wallet, activeChains: chains)
            bootstrapping[wallet] = enrichedResults.filter(\.bootstrapInProgress).map { $0.chain.id }
        }

        let loaded = wallets.compactMap { portfolio(for: $0) }
        LogStore.shared.log(
            "refresh done — \(loaded.map(\.positions.count).reduce(0, +)) positions in \(wallets.count) wallet(s) across \(chains.count) chain(s)",
            level: .info
        )
        scheduleBootstrapFollowUpIfNeeded(chainIDsByWallet: bootstrapping, generation: generation)

        NotificationService.fireRangeChangeNotificationsIfNeeded(for: loaded.flatMap(\.positions))

        // Launch fee history scan in background — positions are already displayed.
        let v3ByWallet = wallets.map { wallet in
            (wallet: wallet, positions: portfolio(for: wallet)?.positions.filter { !$0.isV4 && $0.error == nil } ?? [])
        }
        if AppSettings.shared.trackClaimedFees {
            startFeeHistoryLoad(v3ByWallet.filter { !$0.positions.isEmpty }, generation: generation)
        }
        startDailyFeeLoad(
            v3Positions: v3ByWallet.flatMap(\.positions).filter { $0.poolAddress != nil },
            generation: generation
        )
    }

    /// Valid saved wallets, the active one first.
    private static func walletsToLoad() -> [String] {
        let active = AppSettings.shared.walletAddress
        guard WalletAddress.normalize(active) != nil else { return [] }
        return [active] + AppSettings.shared.walletAddresses.filter {
            $0.caseInsensitiveCompare(active) != .orderedSame && WalletAddress.normalize($0) != nil
        }
    }

    private func scheduleBootstrapFollowUpIfNeeded(chainIDsByWallet: [String: [String]], generation: UInt64) {
        bootstrapFollowUpTask?.cancel()
        bootstrapChainIDsByWallet = chainIDsByWallet.filter { !$0.value.isEmpty }
        let ids = Array(Set(bootstrapChainIDsByWallet.values.flatMap { $0 }))
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
            await self.runBootstrapFollowUp(generation: generation, chainIDsByWallet: self.bootstrapChainIDsByWallet)
        }
    }

    private func runBootstrapFollowUp(generation: UInt64, chainIDsByWallet: [String: [String]]) async {
        guard isCurrentGeneration(generation), !Task.isCancelled else { return }
        let saved = Self.walletsToLoad()
        let key = AppSettings.shared.infuraAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let activeChains = AppSettings.shared.enabledChains()
        guard !saved.isEmpty, !key.isEmpty, !activeChains.isEmpty else { return }
        await EthereumClient.setCreditBudget(perSecond: AppSettings.shared.rpcCreditsPerSecondBudget)

        var bootstrapping: [String: [String]] = [:]
        for wallet in saved {
            let idSet = Set(chainIDsByWallet[wallet] ?? [])
            let targetChains = activeChains.filter { idSet.contains($0.id) }
            guard !targetChains.isEmpty else { continue }
            LogStore.shared.log(
                "v4 bootstrap in progress — running accelerated follow-up for \(targetChains.map(\.displayName).joined(separator: ", "))",
                level: .info
            )

            let results = await loadChains(targetChains, wallet: wallet)
            guard isCurrentGeneration(generation), !Task.isCancelled else { return }
            let enrichedResults = await enrichChainResults(results)
            guard isCurrentGeneration(generation), !Task.isCancelled else { return }
            applyChainResults(enrichedResults, wallet: wallet, activeChains: activeChains)
            bootstrapping[wallet] = activeChains
                .compactMap { portfolio(for: wallet)?.chainResultsByID[$0.id] }
                .filter(\.bootstrapInProgress)
                .map { $0.chain.id }
        }
        NotificationService.fireRangeChangeNotificationsIfNeeded(
            for: saved.compactMap { portfolio(for: $0) }.flatMap(\.positions)
        )

        scheduleBootstrapFollowUpIfNeeded(chainIDsByWallet: bootstrapping, generation: generation)
        LogStore.shared.log(
            "accelerated follow-up done — \(bootstrapping.values.map(\.count).reduce(0, +)) chain(s) still bootstrapping",
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

    /// Writes a snapshot with a week of daily fees for every wallet and for all of them
    /// together, then reloads the widgets when what they show changed.
    private func publishWidgets() {
        guard PortfolioSnapshotStore.fileURL != nil else { return }
        let settings = AppSettings.shared
        let now = Date()
        func snapshot(_ portfolio: WalletPortfolio, name: String?) -> PortfolioSnapshot? {
            // A wallet that failed to load keeps what the widget showed before.
            guard !(portfolio.positions.isEmpty && portfolio.lastError != nil) else { return nil }
            return PortfolioSnapshot(
                positions: portfolio.positions,
                dailyFeesUSD: dailyFees.walletDailyUSD(portfolio.positions, days: 7, minDays: 1, endingAt: now),
                updatedAt: portfolio.lastUpdated ?? now,
                walletName: name
            )
        }
        var snapshots: [String: PortfolioSnapshot] = [:]
        if let all = allWalletsPortfolio {
            let single = settings.wallets.count == 1 ? settings.wallets.first : nil
            snapshots[PortfolioSnapshotStore.allWalletsID] = snapshot(all, name: single.map { $0.name } ?? WalletPage.allWallets.title)
        }
        for wallet in settings.wallets {
            if let portfolio = portfolio(for: wallet.address) {
                snapshots[wallet.id] = snapshot(portfolio, name: wallet.displayName)
            }
        }
        if !PortfolioSnapshotStore.save(snapshots, wallets: settings.wallets) {
            LogStore.shared.log("Could not write the widget snapshot", level: .error)
        }
        guard widgetReload.shouldReload(for: snapshots, now: now) else { return }
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    private func clearWidgets() {
        guard PortfolioSnapshotStore.fileURL != nil else { return }
        PortfolioSnapshotStore.removeAll()
        guard widgetReload.shouldReload(for: [:], now: Date()) else { return }
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    private func applyChainResults(_ results: [ChainLoadResult], wallet: String, activeChains: [SupportedChain]) {
        let activeIDs = Set(activeChains.map(\.id))
        var portfolio = portfolio(for: wallet) ?? WalletPortfolio()
        for result in results {
            portfolio.chainResultsByID[result.chain.id] = result
        }
        portfolio.chainResultsByID = portfolio.chainResultsByID.filter { activeIDs.contains($0.key) }

        let snapshot = activeChains.compactMap { portfolio.chainResultsByID[$0.id] }
        let all = snapshot
            .flatMap(\.positions)
            .sorted { lhs, rhs in (lhs.positionUSD ?? lhs.usd ?? 0) > (rhs.positionUSD ?? rhs.usd ?? 0) }
        portfolio.allPositions = all
        feeLedger.record(all, at: Date())
        feeLedger.save()
        dailyFees = feeLedger.dailyFees.overlaid(with: chainDailyFees)

        let errors = snapshot.compactMap(\.error)
        let errorText = composedErrorText(snapshot: snapshot, fallbackErrors: errors)
        portfolio.lastError = errorText
        portfolio.lastUpdated = Date()
        if let err = errorText { LogStore.shared.log(err, level: .error) }
        portfolios[wallet.lowercased()] = portfolio
        updateVisiblePositions(wallet: wallet, hidden: AppSettings.shared.hiddenPositions(for: wallet))
        publish(flash: true)
    }

    private func updateVisiblePositions(wallet: String, hidden: [HiddenPosition]) {
        let key = wallet.lowercased()
        guard let all = portfolios[key]?.allPositions else { return }
        portfolios[key]?.positions = HiddenPositionStore.visible(all, hidden: hidden)
    }

    /// Publishes the page on screen, the menu bar title and the widget snapshots.
    private func publish(flash: Bool, publishWidgets: Bool = true) {
        let page = pagePortfolio
        positions = page?.positions ?? []
        lastError = page?.lastError
        lastUpdated = page?.lastUpdated
        updateTitle(flash: flash)
        if publishWidgets { self.publishWidgets() }
    }

    private func updateTitle(flash: Bool) {
        let key = menuBarSourceKey
        if key != titleSourceKey {
            titleSourceKey = key
            previousTotal = -1
        }
        guard let portfolio = menuBarPortfolio else {
            // Not loaded yet.
            flashTask?.cancel()
            titleText = "… 👀"
            baseTitle = titleText
            return
        }
        let positions = portfolio.positions
        let total = positions.compactMap(\.usd).reduce(0, +)
        let value = positions.compactMap(\.positionUSD).reduce(0, +)
        let title = positions.isEmpty ? "$0.00 👀" : MenuBarTitle.text(valueUSD: value, feesUSD: total)
        // A republish of the same title leaves a running flash alone.
        guard flash || title != baseTitle else { return }
        flashTask?.cancel()
        baseTitle = title
        titleText = title
        let displayChanged = String(format: "%.2f", total) != String(format: "%.2f", previousTotal)
        if flash, !positions.isEmpty, previousTotal >= 0, displayChanged, AppSettings.shared.flashOnValueChange {
            let flashEmoji = total > previousTotal ? "🔼" : "🔽"
            let flashTitle = MenuBarTitle.text(valueUSD: value, feesUSD: total, trend: flashEmoji)
            flashTask = Task {
                for i in 0..<10 {
                    guard !Task.isCancelled else { return }
                    titleText = i % 2 == 0 ? flashTitle : title
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
                titleText = title
            }
        }
        previousTotal = total
    }

    // MARK: - Fee history (background)

    private func startFeeHistoryLoad(_ v3ByWallet: [(wallet: String, positions: [Position])], generation: UInt64) {
        feeHistoryTask?.cancel()
        let chunkSize = AppSettings.shared.v4LogChunkSize
        let baseMaxChunks = AppSettings.shared.v4BootstrapMaxChunksPerRefresh
        feeHistoryTask = Task { [weak self] in
            guard let self else { return }
            for (wallet, v3Positions) in v3ByWallet {
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
                    applyFeeHistory(feeResult, priceMap: priceMap, chainID: chainID, wallet: wallet)
                    if feeResult.bootstrapInProgress {
                        LogStore.shared.log("fee history [\(chain.displayName)]: syncing…", level: .info)
                    } else {
                        LogStore.shared.log("fee history [\(chain.displayName)]: complete", level: .info)
                    }
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
                publishWidgets()
            }
        }
    }

    private func applyFeeHistory(
        _ result: FeeHistoryService.Result,
        priceMap: [String: Double],
        chainID: String,
        wallet: String
    ) {
        let key = wallet.lowercased()
        guard var allPositions = portfolios[key]?.allPositions else { return }
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
        portfolios[key]?.allPositions = allPositions
        updateVisiblePositions(wallet: wallet, hidden: AppSettings.shared.hiddenPositions(for: wallet))
        publish(flash: false, publishWidgets: false)
    }

    // MARK: - Per-chain load

    private var v4ScanSettings: V4ScanSettings {
        V4ScanSettings(
            logChunkSize: AppSettings.shared.v4LogChunkSize,
            maxConcurrentLogRequests: AppSettings.shared.v4LogMaxConcurrentRequests,
            maxChunksPerRefresh: AppSettings.shared.v4BootstrapMaxChunksPerRefresh
        )
    }

    /// The reads every wallet shares, once per chain, so each further wallet costs only its own
    /// positions.
    private func prefetchChains(_ chains: [SupportedChain], wallets: [String]) async -> [String: ChainPrefetch] {
        await withTaskGroup(of: (String, ChainPrefetch?).self, returning: [String: ChainPrefetch].self) { group in
            for chain in chains {
                group.addTask { (chain.id, await self.prefetchChain(chain, wallets: wallets)) }
            }
            var collected: [String: ChainPrefetch] = [:]
            for await (chainID, prefetch) in group { collected[chainID] = prefetch }
            return collected
        }
    }

    private func prefetchChain(_ chain: SupportedChain, wallets: [String]) async -> ChainPrefetch? {
        guard let rpcURL = AppSettings.shared.infuraRPCURL(for: chain) else { return nil }
        let prefetch = await ChainPrefetch.load(
            chain: chain, wallets: wallets, eth: EthereumClient(rpcURL: rpcURL), scanSettings: v4ScanSettings
        )
        if prefetch.accessDenied { AppSettings.shared.disableChain(chain.id) }
        return prefetch
    }

    private func loadChains(
        _ chains: [SupportedChain], wallet: String, prefetches: [String: ChainPrefetch] = [:]
    ) async -> [ChainLoadResult] {
        await withTaskGroup(of: ChainLoadResult.self, returning: [ChainLoadResult].self) { group in
            for chain in chains {
                group.addTask {
                    await self.loadChain(wallet: wallet, chain: chain, prefetch: prefetches[chain.id])
                }
            }
            var collected: [ChainLoadResult] = []
            for await result in group { collected.append(result) }
            return collected
        }
    }

    private func loadChain(wallet: String, chain: SupportedChain, prefetch: ChainPrefetch?) async -> ChainLoadResult {
        guard let rpcURL = AppSettings.shared.infuraRPCURL(for: chain) else {
            return .failed(chain, error: "\(chain.displayName): invalid Infura API key")
        }
        let eth = EthereumClient(rpcURL: rpcURL)

        // Without a prefetch (the bootstrap follow-up) the chain is probed here.
        if let error = prefetch?.error {
            return .failed(chain, error: error)
        } else if prefetch == nil, let failure = await ChainPrefetch.probe(chain: chain, eth: eth) {
            if failure.accessDenied { AppSettings.shared.disableChain(chain.id) }
            return .failed(chain, error: failure.error ?? "\(chain.displayName): RPC unavailable")
        }
        let key = wallet.lowercased()

        var v3 = LoaderOutput()
        if chain.supportsV3 {
            v3 = await V3PositionLoader(
                eth: eth,
                chain: chain,
                prices: priceService,
                trackClaimedFees: AppSettings.shared.trackClaimedFees
            ).load(wallet: wallet, balance: prefetch?.v3Balances[key])
        }
        var v4 = LoaderOutput()
        if chain.supportsV4 {
            v4 = await V4PositionLoader(
                eth: eth,
                chain: chain,
                prices: priceService,
                scanSettings: v4ScanSettings
            ).load(wallet: wallet, balance: prefetch?.v4Balances[key], shared: prefetch?.v4Transfers)
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
        var bootstrapping = false
        for (key, portfolio) in portfolios {
            let snapshot = activeChains.compactMap { portfolio.chainResultsByID[$0.id] }
            guard snapshot.contains(where: \.bootstrapInProgress) else { continue }
            bootstrapping = true
            portfolios[key]?.lastError = composedErrorText(snapshot: snapshot, fallbackErrors: snapshot.compactMap(\.error))
        }
        guard bootstrapping else {
            stopBootstrapCountdownTimer()
            return
        }
        lastError = pagePortfolio?.lastError
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
