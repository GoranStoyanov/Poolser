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
            .navigationTitle("Poolser")
            .toolbar {
                if isConfigured {
                    if settings.walletAddresses.count > 1 {
                        ToolbarItem(placement: .topBarLeading) {
                            Menu {
                                ForEach(settings.walletAddresses, id: \.self) { address in
                                    Button {
                                        guard address != settings.walletAddress else { return }
                                        settings.walletAddress = address
                                        service.refreshForWalletChange()
                                    } label: {
                                        if address.caseInsensitiveCompare(settings.walletAddress) == .orderedSame {
                                            Label(address, systemImage: "checkmark")
                                        } else {
                                            Text(address)
                                        }
                                    }
                                }
                            } label: {
                                Text("\(settings.walletAddress.prefix(6))…\(settings.walletAddress.suffix(4))")
                                    .font(.system(.caption, design: .monospaced))
                            }
                        }
                    }
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

    private var portfolio: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                summary
                if let error = service.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(palette.outOfRange.tint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if service.isLoading && service.positions.isEmpty {
                    ProgressView("Loading positions…")
                        .frame(maxWidth: .infinity, minHeight: 140)
                } else if service.positions.isEmpty {
                    ContentUnavailableView(
                        "No positions yet",
                        systemImage: "chart.bar.xaxis",
                        description: Text("Pull down or tap Refresh to check again.")
                    )
                } else {
                    ForEach(service.positions) { position in
                        GraphitePositionCard(position: position, onOpen: {
                            if let url = position.uniswapURL { openURL(url) }
                        }, onHide: { settings.hide(position) })
                    }
                }
            }
            .padding(16)
        }
        .background(palette.popover)
        .refreshable { await service.refreshAndWait() }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Portfolio value")
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText)
            Text(PositionPresentation.compactUSD(service.positions.compactMap(\.positionUSD).reduce(0, +)))
                .font(.largeTitle.bold().monospacedDigit())
                .foregroundStyle(palette.primaryText)
            HStack {
                Text("+\(formatUSD(service.positions.compactMap(\.usd).reduce(0, +))) fees")
                    .foregroundStyle(palette.fees)
                Spacer()
                Text("\(service.positions.count) positions")
                    .foregroundStyle(palette.secondaryText)
            }
            .font(.subheadline.weight(.medium))
            if let lastUpdated = service.lastUpdated {
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
