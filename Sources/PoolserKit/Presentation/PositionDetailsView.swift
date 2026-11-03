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
            ViewThatFits(in: .vertical) {
                sheetContent.fixedSize(horizontal: false, vertical: true)
                ScrollView { sheetContent }
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(palette.card)
                .foregroundStyle(palette.primaryText)
                .safeAreaInset(edge: .bottom, spacing: 0) { sheetAction }
                .navigationTitle("Position details")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: onDone)
                    }
                }
        }
        .tint(palette.fees)
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.fraction(0.7), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(palette.card)
#else
        fittedContent
            .frame(idealWidth: 320, maxWidth: 360, maxHeight: 520)
            .background(palette.card)
            .foregroundStyle(palette.primaryText)
#endif
    }

    private var sheetContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Assets").font(.headline)
                if position.poolStateError == nil {
                    if typeSize.isAccessibilitySize {
                        sheetHoldings(horizontal: false)
                    } else {
                        ViewThatFits(in: .horizontal) {
                            sheetHoldings(horizontal: true)
                            sheetHoldings(horizontal: false)
                        }
                    }
                } else {
                    Text("Unavailable").font(.body).foregroundStyle(palette.secondaryText)
                }
            }
            VStack(spacing: 12) {
                sheetDetail("Position", value: "#\(position.tokenId)")
                if let openedAt = position.openedAt {
                    sheetDetail("Opened", value: openedAt.formatted(date: .abbreviated, time: .omitted))
                }
            }
            if let error = position.feesError { errorMessage(error, prominent: true) }
            if let error = position.poolStateError { errorMessage(error, prominent: true) }
            if !position.feeHistoryBootstrapping, let level = position.feeReturnOnAssets {
                HStack(spacing: 12) {
                    PoolGauge(level: level)
                    PositionMetric(title: "Pool level", value: formatPercent(level),
                                   explanation: poolLevelHelp, prominent: true)
                }
            }
            if position.hasPoolStats {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Pool · last 24h").font(.headline)
                    poolStats(prominent: true)
                }
            }
        }
        .padding(24)
    }

    private func sheetHoldings(horizontal: Bool) -> some View {
        let inverted = PositionPresentation(position).isInverted
        let layout = horizontal ? AnyLayout(HStackLayout(alignment: .top, spacing: 12)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
        return layout {
            sheetHolding(inverted ? position.sym1 : position.sym0, amount: inverted ? position.amount1Label : position.amount0Label, allowsWrapping: !horizontal)
            sheetHolding(inverted ? position.sym0 : position.sym1, amount: inverted ? position.amount0Label : position.amount1Label, allowsWrapping: !horizontal)
        }
    }

    private func sheetHolding(_ symbol: String, amount: String, allowsWrapping: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(symbol).font(.subheadline).foregroundStyle(palette.secondaryText)
            Text(amount).font(PoolTypography.amount(24, relativeTo: .title2))
                .fixedSize(horizontal: !allowsWrapping, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(palette.control, in: RoundedRectangle(cornerRadius: 16))
    }

    private func sheetDetail(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title).foregroundStyle(palette.secondaryText)
            Spacer(minLength: 0)
            Text(value).monospacedDigit().textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.body)
    }

    @ViewBuilder
    private var sheetAction: some View {
        if let onOpen {
            Button(action: onOpen) {
                Label("Open in Uniswap", systemImage: "arrow.up.right")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(GraphiteStrongButtonStyle())
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(palette.card)
        }
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
                                   explanation: poolLevelHelp)
                }
            }
            if position.hasPoolStats {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pool · last 24h").font(.caption).foregroundStyle(palette.secondaryText)
                    poolStats()
                }
            }
            if let onOpen {
                Button("Open in Uniswap", action: onOpen)
                    .buttonStyle(GraphiteStrongButtonStyle())
            }
        }
        .padding(16)
    }

    private func poolStats(prominent: Bool = false) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
        return ViewThatFits(in: .horizontal) {
            layout { poolStatMetrics(prominent: prominent) }
            VStack(alignment: .leading, spacing: 16) { poolStatMetrics(prominent: prominent) }
        }
    }

    private func poolStatMetrics(prominent: Bool) -> some View {
        Group {
            if let volume = position.volumeUSD24h {
                PositionMetric(title: "Volume", value: PositionPresentation.compactUSD(volume),
                               explanation: "The pool’s trading volume over the last 24 hours.", prominent: prominent)
            }
            if let tvl = position.tvlUSD {
                PositionMetric(title: "TVL", value: PositionPresentation.compactUSD(tvl),
                               explanation: "Total value of liquidity in the pool.", prominent: prominent)
            }
            if let yield = position.feeAPR {
                PositionMetric(title: "Pool yield", value: String(format: "%.1f%%", yield),
                               explanation: "Estimated annual yield if the pool’s last 24 hours repeated for a year: trading volume × fee rate ÷ TVL. This is the pool’s estimate, distinct from your realized APR. An out-of-range position earns none of it.", prominent: prominent)
            }
        }
    }

    private var poolLevelHelp: String {
        "All-time fees (claimed + unclaimed) divided by the position’s current value. Claimed fees use current token prices; changes in prices or liquidity also change this percentage."
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

    private func errorMessage(_ message: String, prominent: Bool = false) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(prominent ? .body : .caption).foregroundStyle(palette.outOfRange.tint)
            .fixedSize(horizontal: false, vertical: true)
    }
}
