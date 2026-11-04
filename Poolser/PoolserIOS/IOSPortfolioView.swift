import SwiftUI
import PoolserKit
#if DEBUG
import WidgetKit
#endif

struct IOSPortfolioView: View {
    @EnvironmentObject private var service: UniswapService
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var settings = AppSettings.shared
    @State private var showingSettings = false

    private var palette: GraphitePalette { .current(colorScheme) }
    private var isConfigured: Bool {
        WalletAddress.normalize(settings.walletAddress) != nil
            && !settings.infuraAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !settings.enabledChainIDs.isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if isConfigured {
                    portfolio
                } else {
                    IOSConnectionView()
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if isConfigured && settings.wallets.count > 1 {
                        Menu {
                            Picker("Wallet", selection: shownPage) {
                                ForEach(settings.walletPages) { page in
                                    Text(page.title).tag(page.id)
                                }
                            }
                        } label: {
                            navigationBrand
                        }
                        .accessibilityLabel("Switch wallet, \(title)")
                    } else {
                        navigationBrand
                    }
                }
                if isConfigured {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Settings", systemImage: "gearshape") { showingSettings = true }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Refresh", systemImage: "arrow.clockwise") { service.refresh() }
                            .disabled(service.isLoading)
                    }
                }
            }
        }
        .tint(palette.fees)
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                IOSConnectionView()
                    .navigationTitle("Settings")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showingSettings = false }
                        }
                    }
            }
            .environmentObject(service)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && isConfigured { service.refresh() }
            if phase == .background && isConfigured { IOSBackgroundRefresh.schedule() }
        }
    }

    private var navigationBrand: some View {
        HStack(spacing: 7) {
            PoolBrandMark()
            Text(title).font(PoolTypography.heading(18)).lineLimit(1)
            if isConfigured && settings.wallets.count > 1 {
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
            }
        }
        .foregroundStyle(palette.primaryText)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        settings.wallets.count > 1 ? settings.shownPage?.title ?? "Poolser" : "Poolser"
    }

    /// The page on screen, by `WalletPage.id`.
    private var shownPage: Binding<String> {
        Binding(
            get: { settings.shownPage?.id ?? "" },
            set: { id in
                guard id != settings.shownPage?.id,
                      let page = settings.walletPages.first(where: { $0.id == id }) else { return }
                settings.show(page)
                service.activeWalletChanged()
            }
        )
    }

    /// One page per saved wallet, after All Wallets; swiping sideways shows the next one.
    private var portfolio: some View {
        TabView(selection: shownPage) {
            ForEach(settings.walletPages) { page in
                walletPage(page)
                    .tag(page.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: settings.wallets.count > 1 ? .always : .never))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .background(palette.popover)
    }

    private func walletPage(_ page: WalletPage) -> some View {
        // The page on screen reads the service's published values, which hidden positions update.
        let isActive = page.id == settings.shownPage?.id
        let loaded: WalletPortfolio? = switch page {
        case .allWallets: service.allWalletsPortfolio
        case .wallet(let wallet): service.portfolio(for: wallet.address)
        }
        return WalletPageContent(
            overview: page == .allWallets ? service.walletOverview : nil,
            positions: isActive ? service.positions : loaded?.positions ?? [],
            lastError: isActive ? service.lastError : loaded?.lastError,
            lastUpdated: isActive ? service.lastUpdated : loaded?.lastUpdated,
            dailyFees: service.dailyFees,
            tracksClaimedFees: settings.trackClaimedFees,
            isLoading: service.isLoading,
            showsPageIndicator: settings.wallets.count > 1,
            palette: palette,
            open: { if let url = $0.uniswapURL { openURL(url) } },
            hide: { settings.hide($0, wallet: service.wallet(of: $0) ?? settings.walletAddress) },
            openWallet: { shownPage.wrappedValue = WalletPage.wallet($0).id }
        )
        .refreshable { await service.refreshAndWait() }
    }
}

#if DEBUG
/// The real iOS layout with fictional positions, used only for native simulator captures.
struct IOSReleasePreview: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var page: Int

    init() {
        let requested = Int(ProcessInfo.processInfo.environment["POOLSER_SCREENSHOT_PAGE"] ?? "") ?? 0
        _page = State(initialValue: (0...2).contains(requested) ? requested : 0)
    }

    private let wallets = [
        SavedWallet(address: "0x7a3f9c2e81b54d06a1f3e8b2c97d40e5f1a6c41e", name: "Mine"),
        SavedWallet(address: "0x1111111111111111111111111111111111111111", name: "Team"),
    ]

    private var palette: GraphitePalette { .current(colorScheme) }
    private var positions: [Position] {
        ReleaseDemoData.positions.sorted { ($0.positionUSD ?? 0) > ($1.positionUSD ?? 0) }
    }
    private var mine: [Position] { positions.filter { $0.chainID != "arbitrum" } }
    private var team: [Position] { positions.filter { $0.chainID == "arbitrum" } }
    private var title: String { page == 0 ? "All wallets" : wallets[page - 1].displayName }

    var body: some View {
        NavigationStack {
            TabView(selection: $page) {
                ForEach(0..<3, id: \.self) { index in
                    let shown = index == 0 ? positions : (index == 1 ? mine : team)
                    WalletPageContent(
                        overview: index == 0 ? WalletOverview(wallets: [
                            (wallets[0], mine), (wallets[1], team)
                        ], tracksClaimedFees: true) : nil,
                        positions: shown, lastError: nil, lastUpdated: .now.addingTimeInterval(-90),
                        dailyFees: ReleaseDemoData.dailyFees, tracksClaimedFees: true,
                        isLoading: false, showsPageIndicator: true, palette: palette,
                        open: { _ in }, hide: { _ in },
                        openWallet: { wallet in page = wallet.id == wallets[0].id ? 1 : 2 }
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .background(palette.popover)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Menu {
                        Picker("Wallet", selection: $page) {
                            Text("All wallets").tag(0)
                            Text(wallets[0].displayName).tag(1)
                            Text(wallets[1].displayName).tag(2)
                        }
                    } label: {
                        HStack(spacing: 7) {
                            PoolBrandMark()
                            Text(title).font(PoolTypography.heading(18))
                            Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(palette.primaryText)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Image(systemName: "gearshape")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .tint(palette.fees)
        .task {
            assert(abs(positions.compactMap(\.positionUSD).reduce(0, +) - PortfolioSnapshot.preview.totalValueUSD) < 0.01)
            PortfolioSnapshotStore.save(.preview)
            WidgetCenter.shared.reloadAllTimelines()
            for position in positions {
                await TokenIconStore.shared.fetchIfNeeded(chainID: position.chainNumericID, address: position.iconAddress0)
                await TokenIconStore.shared.fetchIfNeeded(chainID: position.chainNumericID, address: position.iconAddress1)
            }
            await NetworkIconStore.shared.prefetch(for: positions.compactMap { SupportedChain.byID($0.chainID) })
        }
    }
}
#endif

private struct WalletPageContent: View {
    /// Every wallet with its totals; set on the All Wallets page only.
    let overview: WalletOverview?
    let positions: [Position]
    let lastError: String?
    let lastUpdated: Date?
    let dailyFees: DailyFees
    let tracksClaimedFees: Bool
    let isLoading: Bool
    let showsPageIndicator: Bool
    let palette: GraphitePalette
    let open: (Position) -> Void
    let hide: (Position) -> Void
    let openWallet: (SavedWallet) -> Void

    /// The wallet tapped in the share bar or the list, by `SavedWallet.id`.
    @State private var highlightedWallet: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if let overview, !positions.isEmpty {
                    AllWalletsSummaryCard(overview: overview, highlighted: $highlightedWallet)
                        .zIndex(1)
                    updatedLabel
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    summary
                }
                if let error = lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(palette.outOfRange.tint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if isLoading && positions.isEmpty {
                    ProgressView("Loading positions…")
                        .frame(maxWidth: .infinity, minHeight: 140)
                } else if positions.isEmpty {
                    ContentUnavailableView(
                        "No positions yet",
                        systemImage: "chart.bar.xaxis",
                        description: Text("Pull down or tap Refresh to check again.")
                    )
                } else if let overview {
                    WalletGroupList(
                        overview: overview,
                        highlighted: $highlightedWallet,
                        actions: WalletOverviewActions(openWallet: openWallet, open: open, hide: hide)
                    )
                    .padding(.top, 4)
                } else {
                    HStack {
                        Text("Positions").font(PoolTypography.heading(19))
                        Spacer()
                        Text("\(positions.count) total").font(.caption).foregroundStyle(palette.secondaryText)
                    }
                    .foregroundStyle(palette.primaryText)
                    ForEach(positions) { position in
                        GraphitePositionCard(
                            position: position,
                            recentDailyFees: dailyFees.dailyUSD(for: position, days: 7, endingAt: .now),
                            onOpen: { open(position) }, onHide: { hide(position) }
                        )
                    }
                }
            }
            .padding(16)
            // Room for the page dots.
            .padding(.bottom, showsPageIndicator ? 24 : 0)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            PortfolioSummaryCard(
                positions: positions,
                dailyFees: dailyFees.walletDailyUSD(positions, days: 30, minDays: 1, endingAt: .now),
                feeSummary: tracksClaimedFees && !positions.isEmpty ? WalletFeeSummary(positions: positions) : nil
            ) { EmptyView() }
            updatedLabel
        }
    }

    @ViewBuilder
    private var updatedLabel: some View {
        if let lastUpdated {
            HStack(spacing: 4) {
                Text("Updated")
                Text(lastUpdated, style: .relative)
            }
            .font(.caption)
            .foregroundStyle(palette.secondaryText)
        }
    }
}
