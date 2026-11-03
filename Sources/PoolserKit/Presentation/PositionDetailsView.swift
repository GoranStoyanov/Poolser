import SwiftUI

/// Supplementary position data; prices, status and fee returns stay on the main card.
struct PositionDetailsView: View {
    let position: Position
    let onOpen: (() -> Void)?
    let onDone: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private var palette: GraphitePalette { .current(scheme) }

    var body: some View {
#if os(iOS)
        NavigationStack {
            fittedContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(palette.card)
                .foregroundStyle(palette.primaryText)
                .navigationTitle("Position details")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: onDone)
                    }
                }
        }
        .tint(palette.fees)
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(palette.card)
#else
        fittedContent
            .frame(idealWidth: 320, maxWidth: 360, maxHeight: 520)
            .background(palette.card)
            .foregroundStyle(palette.primaryText)
#endif
    }

    private var fittedContent: some View {
        ViewThatFits(in: .vertical) {
            content.fixedSize(horizontal: false, vertical: true)
            // Keep every detail reachable when large text or a short screen cannot fit it.
            ScrollView { content }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
#if !os(iOS)
            HStack {
                Text("Position details").font(PoolTypography.heading(16))
                Spacer(minLength: 8)
                Button("Done", action: onDone)
                    .buttonStyle(.plain).foregroundStyle(palette.fees)
            }
#endif
            VStack(alignment: .leading, spacing: 6) {
                Text("Assets").font(.caption).foregroundStyle(palette.secondaryText)
                if position.poolStateError == nil {
                    let inverted = PositionPresentation(position).isInverted
                    holding(inverted ? position.sym1 : position.sym0, amount: inverted ? position.amount1Label : position.amount0Label)
                    holding(inverted ? position.sym0 : position.sym1, amount: inverted ? position.amount0Label : position.amount1Label)
                } else {
                    Text("Unavailable").font(.callout).foregroundStyle(palette.secondaryText)
                }
            }
            VStack(spacing: 5) {
                detail("Position", value: "#\(position.tokenId)")
                if let openedAt = position.openedAt {
                    detail("Opened", value: openedAt.formatted(date: .abbreviated, time: .omitted))
                }
            }
            if let error = position.feesError { errorMessage(error) }
            if let error = position.poolStateError { errorMessage(error) }
            if !position.feeHistoryBootstrapping, let level = position.feeReturnOnAssets {
                HStack(spacing: 8) {
                    PoolGauge(level: level)
                    PositionMetric(title: "Pool level", value: formatPercent(level),
                                   explanation: "All-time fees (claimed + unclaimed) divided by the position’s current value. Claimed fees use current token prices; changes in prices or liquidity also change this percentage.")
                }
            }
            if position.hasPoolStats {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pool · last 24h").font(.caption).foregroundStyle(palette.secondaryText)
                    poolStats
                }
            }
            if let onOpen {
                Button("Open in Uniswap", action: onOpen)
                    .buttonStyle(GraphiteStrongButtonStyle())
            }
        }
        .padding(16)
    }

    private var poolStats: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
        return layout {
            if let volume = position.volumeUSD24h {
                PositionMetric(title: "Volume", value: PositionPresentation.compactUSD(volume),
                               explanation: "The pool’s trading volume over the last 24 hours.")
            }
            if let tvl = position.tvlUSD {
                PositionMetric(title: "TVL", value: PositionPresentation.compactUSD(tvl),
                               explanation: "Total value of liquidity in the pool.")
            }
            if let yield = position.feeAPR {
                PositionMetric(title: "Pool yield", value: String(format: "%.1f%%", yield),
                               explanation: "Estimated annual yield if the pool’s last 24 hours repeated for a year: trading volume × fee rate ÷ TVL. This is the pool’s estimate, distinct from your realized APR. An out-of-range position earns none of it.")
            }
        }
    }

    private func holding(_ symbol: String, amount: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(symbol).font(.caption).foregroundStyle(palette.secondaryText)
            Spacer(minLength: 0)
            Text(amount).font(.callout.weight(.medium).monospacedDigit())
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private func detail(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).foregroundStyle(palette.secondaryText)
            Spacer(minLength: 0)
            Text(value).monospacedDigit().textSelection(.enabled)
        }
        .font(.caption)
    }

    private func errorMessage(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.caption).foregroundStyle(palette.outOfRange.tint)
            .fixedSize(horizontal: false, vertical: true)
    }
}
