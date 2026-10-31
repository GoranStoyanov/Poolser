import SwiftUI
import PoolserKit

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
            .navigationBarTitleDisplayMode(settings.wallets.count > 1 ? .inline : .automatic)
            .toolbarTitleMenu {
                if isConfigured && settings.wallets.count > 1 {
                    Picker("Wallet", selection: shownPage) {
                        ForEach(settings.walletPages) { page in
                            Text(page.title).tag(page.id)
                        }
                    }
                }
            }
            .toolbar {
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
            isAllWallets: page == .allWallets,
            walletNames: page == .allWallets ? service.walletNamesByPosition : [:],
            positions: isActive ? service.positions : loaded?.positions ?? [],
            lastError: isActive ? service.lastError : loaded?.lastError,
            lastUpdated: isActive ? service.lastUpdated : loaded?.lastUpdated,
            isLoading: service.isLoading,
            showsPageIndicator: settings.wallets.count > 1,
            palette: palette,
            open: { if let url = $0.uniswapURL { openURL(url) } },
            hide: { settings.hide($0, wallet: service.wallet(of: $0) ?? settings.walletAddress) }
        )
        .refreshable { await service.refreshAndWait() }
    }
}

private struct WalletPageContent: View {
    let isAllWallets: Bool
    /// The wallet holding each position, by `Position.id`, on the All Wallets page.
    let walletNames: [String: String]
    let positions: [Position]
    let lastError: String?
    let lastUpdated: Date?
    let isLoading: Bool
    let showsPageIndicator: Bool
    let palette: GraphitePalette
    let open: (Position) -> Void
    let hide: (Position) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                summary
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
                } else {
                    ForEach(positions) { position in
                        GraphitePositionCard(
                            position: position, walletName: walletNames[position.id],
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

    private var countsLabel: String {
        let wallets = Set(walletNames.values).count
        return wallets > 1 ? "\(positions.count) positions · \(wallets) wallets" : "\(positions.count) positions"
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isAllWallets {
                AllWalletsBadge()
            }
            Text("Portfolio value")
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText)
            Text(PositionPresentation.compactUSD(positions.compactMap(\.positionUSD).reduce(0, +)))
                .font(.largeTitle.bold().monospacedDigit())
                .foregroundStyle(palette.primaryText)
            HStack {
                Text("+\(formatUSD(positions.compactMap(\.usd).reduce(0, +))) fees")
                    .foregroundStyle(palette.fees)
                Spacer()
                Text(countsLabel)
                    .foregroundStyle(palette.secondaryText)
            }
            .font(.subheadline.weight(.medium))
            if let lastUpdated {
                HStack(spacing: 4) {
                    Text("Updated")
                    Text(lastUpdated, style: .relative)
                }
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(palette.card))
    }
}
