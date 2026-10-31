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
                    Picker("Wallet", selection: activeWallet) {
                        ForEach(settings.wallets) { wallet in
                            Text(wallet.displayName).tag(wallet.id)
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
        settings.wallets.count > 1 ? settings.activeWallet?.displayName ?? "Poolser" : "Poolser"
    }

    /// The page on screen, by `SavedWallet.id`.
    private var activeWallet: Binding<String> {
        Binding(
            get: { settings.walletAddress.lowercased() },
            set: { id in
                guard let wallet = settings.wallets.first(where: { $0.id == id }),
                      !wallet.matches(settings.walletAddress) else { return }
                settings.walletAddress = wallet.address
                service.activeWalletChanged()
            }
        )
    }

    /// One page per saved wallet; swiping sideways makes the next one active.
    private var portfolio: some View {
        TabView(selection: activeWallet) {
            ForEach(settings.wallets) { wallet in
                walletPage(wallet)
                    .tag(wallet.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: settings.wallets.count > 1 ? .always : .never))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .background(palette.popover)
    }

    private func walletPage(_ wallet: SavedWallet) -> some View {
        // The active wallet reads the service's published values, which hidden positions update.
        let isActive = wallet.matches(settings.walletAddress)
        let loaded = service.portfolio(for: wallet.address)
        return WalletPageContent(
            positions: isActive ? service.positions : loaded?.positions ?? [],
            lastError: isActive ? service.lastError : loaded?.lastError,
            lastUpdated: isActive ? service.lastUpdated : loaded?.lastUpdated,
            isLoading: service.isLoading,
            showsPageIndicator: settings.wallets.count > 1,
            palette: palette,
            open: { if let url = $0.uniswapURL { openURL(url) } },
            hide: { settings.hide($0) }
        )
        .refreshable { await service.refreshAndWait() }
    }
}

private struct WalletPageContent: View {
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
                        GraphitePositionCard(position: position, onOpen: { open(position) }, onHide: { hide(position) })
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
                Text("\(positions.count) positions")
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
