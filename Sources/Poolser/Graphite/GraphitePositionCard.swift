import SwiftUI

struct GraphitePositionCard: View {
    let position: Position
    /// Fees earned per day, oldest first; the mini chart is hidden while nil.
    var recentDailyFees: [Double]? = nil
    var onOpen: (() -> Void)? = nil
    var onCollect: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    private var palette: GraphitePalette { .current(colorScheme) }

    var body: some View {
        if let error = position.error {
            errorCard(error)
        } else {
            let info = PositionPresentation(position)
            let colors = palette.status(info.status)
            VStack(alignment: .leading, spacing: 10) {
                header(info)
                rangeSection(info, colors: colors)
                footer(info, colors: colors)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.card))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(info.status == .outOfRange ? colors.bandEdge : palette.cardLine, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onTapGesture { onOpen?() }
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: "Open in Uniswap") { onOpen?() }
        }
    }

    // MARK: - Sections

    private func header(_ info: PositionPresentation) -> some View {
        HStack(spacing: 10) {
            TokenPairAvatar(base: info.baseSymbol, quote: info.quoteSymbol, chain: SupportedChain.byID(position.chainID))
            VStack(alignment: .leading, spacing: 1) {
                Text(info.pairLabel)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(palette.primaryText)
                Text(metaLabel)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                // Without pool state the amounts, and so the value, are unknown.
                Text(position.poolStateError == nil ? (position.positionUSDLabel ?? "–") : "–")
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(palette.primaryText)
                feesLabel
            }
        }
    }

    @ViewBuilder
    private var feesLabel: some View {
        if let usd = position.feesUSDLabel {
            Text("+\(usd) fees")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(palette.fees)
        } else if let error = position.feesError {
            Text("fees –")
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
                .help(error)
        } else {
            Text(position.feesLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(palette.secondaryText)
        }
    }

    @ViewBuilder
    private func rangeSection(_ info: PositionPresentation, colors: GraphitePalette.StatusColors) -> some View {
        if let gauge = info.gauge, let price = info.currentPrice {
            VStack(spacing: 3) {
                PriceRangeGauge(
                    layout: gauge,
                    colors: colors,
                    bubble: [price, info.distanceLabel].compactMap { $0 }.joined(separator: " · ")
                )
                HStack {
                    Text("Min \(info.minPrice)")
                    Spacer()
                    Text("Max \(info.maxPrice)")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(palette.secondaryText)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Range \(info.minPrice) to \(info.maxPrice) \(info.quoteSymbol), current price \(price)")
        } else if let reason = position.poolStateError {
            Label("Pool data unavailable", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(palette.outOfRange.tint)
                .help("\(reason)\nRetried on the next refresh.")
        }
    }

    private func footer(_ info: PositionPresentation, colors: GraphitePalette.StatusColors) -> some View {
        HStack(spacing: 8) {
            StatusPill(status: info.status, colors: colors)
            if let apr = aprLabel(info) {
                Text(apr)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(palette.secondaryText)
                    .help("If the last 24h repeated for a year, this is the estimated return.\nCalculated from 24h trading volume × fee rate, divided by total pool liquidity (TVL).")
            }
            Spacer(minLength: 4)
            if let recentDailyFees, !recentDailyFees.isEmpty {
                HStack(spacing: 4) {
                    MiniFeeBars(values: recentDailyFees, today: colors.tint, earlier: colors.bandEdge)
                    Text("\(recentDailyFees.count)d")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(palette.secondaryText)
                }
                .help(feeHistoryHelp(recentDailyFees))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Fees per day, last \(recentDailyFees.count) days")
                .accessibilityValue("Today \(formatUSD(recentDailyFees.last ?? 0))")
            }
            if let onCollect {
                Button("Collect", action: onCollect)
                    .buttonStyle(GraphiteStrongButtonStyle())
            }
        }
        .padding(.top, 9)
        .overlay(alignment: .top) {
            Rectangle().fill(palette.hairline).frame(height: 1)
        }
    }

    private func errorCard(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(palette.outOfRange.tint)
            Text("Position #\(position.tokenId): \(error)")
                .foregroundStyle(palette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.caption)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.card))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.outOfRange.bandEdge, lineWidth: 1)
        )
    }

    // MARK: - Labels

    private var metaLabel: String {
        let chain = SupportedChain.byID(position.chainID)?.displayName ?? position.chainName
        let fee = position.feeFraction == nil ? "dynamic fee" : "\(position.feePct)%"
        return "\(chain) · \(position.versionLabel) · \(fee)"
    }

    private func feeHistoryHelp(_ values: [Double]) -> String {
        let today = formatUSD(values.last ?? 0)
        let best = formatUSD(values.max() ?? 0)
        return "Fees this position earned per day, last \(values.count) days.\nToday \(today) · best day \(best). The rightmost bar is today."
    }

    /// The pool's yield is not this position's while it earns nothing.
    private func aprLabel(_ info: PositionPresentation) -> String? {
        if info.status == .outOfRange { return "APR —" }
        return position.feeAPR.map { String(format: "APR %.1f%%", $0) }
    }
}

// MARK: - Range gauge

struct PriceRangeGauge: View {
    let layout: RangeGaugeLayout
    let colors: GraphitePalette.StatusColors
    let bubble: String

    @Environment(\.colorScheme) private var colorScheme
    @State private var bubbleWidth: CGFloat = 0

    var body: some View {
        let palette = GraphitePalette.current(colorScheme)
        GeometryReader { geo in
            let width = geo.size.width
            let markerX = layout.marker * width
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(palette.track)
                    .frame(width: width, height: 4)
                    .offset(y: 24)
                Capsule()
                    .fill(colors.bandFill)
                    .overlay(Capsule().strokeBorder(colors.bandEdge, lineWidth: 1.5))
                    .frame(width: max((layout.bandEnd - layout.bandStart) * width, 8), height: 12)
                    .offset(x: layout.bandStart * width, y: 20)
                Capsule()
                    .fill(colors.tint)
                    .frame(width: 4, height: 18)
                    .padding(2)
                    .background(Capsule().fill(palette.card))
                    .offset(x: markerX - 4, y: 15)
                Text(bubble)
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(palette.onStatus)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(colors.tint))
                    .fixedSize()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { bubbleWidth = $0 }
                    // Centred on the marker, but kept inside the card near either end.
                    .offset(x: min(max(markerX - bubbleWidth / 2, 0), max(width - bubbleWidth, 0)))
            }
            .animation(.easeInOut(duration: 0.35), value: layout)
        }
        .frame(height: 36)
    }
}

// MARK: - Small parts

struct StatusPill: View {
    let status: RangeStatus
    let colors: GraphitePalette.StatusColors

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(colors.tint).frame(width: 6, height: 6)
            Text(status.title)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(colors.tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(Capsule().fill(colors.background))
    }
}

/// Fees per day, scaled to the series' own best day; the last bar is today.
struct MiniFeeBars: View {
    let values: [Double]
    let today: Color
    let earlier: Color

    var body: some View {
        let peak = values.max() ?? 0
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(index == values.count - 1 ? today : earlier)
                    .frame(width: 4, height: max(2, peak > 0 ? 16 * value / peak : 2))
            }
        }
        .frame(height: 16, alignment: .bottom)
    }
}

struct TokenPairAvatar: View {
    let base: String
    let quote: String
    let chain: SupportedChain?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let ring = GraphitePalette.current(colorScheme).card
        ZStack(alignment: .topLeading) {
            token(base, ring: ring)
            token(quote, ring: ring).offset(x: 14)
            if let chain {
                ChainIconView(chain: chain, size: 13)
                    .padding(1.5)
                    .background(RoundedRectangle(cornerRadius: 4.5, style: .continuous).fill(ring))
                    .offset(x: 28, y: 14)
            }
        }
        .frame(width: 44, height: 30, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private func token(_ symbol: String, ring: Color) -> some View {
        let style = Self.style(for: symbol)
        return Text(style.glyph)
            .font(.callout.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(Circle().fill(style.color))
            .overlay(Circle().strokeBorder(ring, lineWidth: 2))
    }

    /// Letter avatars until token logos are fetched; well-known tokens get their usual colour.
    static func style(for symbol: String) -> (glyph: String, color: Color) {
        switch symbol.lowercased() {
        case "eth", "weth":                        return ("Ξ", Color(red: 0.36, green: 0.42, blue: 0.84))
        case "usdc", "usdc.e", "usdbc":            return ("$", Color(red: 0.15, green: 0.46, blue: 0.79))
        case "usdt", "usdt0":                      return ("$", Color(red: 0.15, green: 0.63, blue: 0.48))
        case "wbtc", "cbbtc", "btcb", "tbtc":      return ("₿", Color(red: 0.91, green: 0.51, blue: 0.10))
        case "uni":                                return ("U", Color(red: 0.86, green: 0.05, blue: 0.47))
        default:
            let fallbacks: [Color] = [
                Color(red: 0.36, green: 0.40, blue: 0.47), Color(red: 0.42, green: 0.33, blue: 0.62),
                Color(red: 0.16, green: 0.50, blue: 0.53), Color(red: 0.62, green: 0.36, blue: 0.24),
            ]
            // Unicode scalar sum, not hashValue: hashValue is seeded per launch.
            let seed = symbol.unicodeScalars.reduce(0) { $0 + Int($1.value) }
            return (String(symbol.prefix(1)).uppercased(), fallbacks[seed % fallbacks.count])
        }
    }
}

/// Capsule chip. A custom style rather than `.plain` with a background on the label, which
/// clips the capsule's rounded ends on macOS.
struct GraphiteChipButtonStyle: ButtonStyle {
    let foreground: Color
    let background: Color
    let border: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(background))
            .overlay(Capsule().strokeBorder(border, lineWidth: 1))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct GraphiteStrongButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let palette = GraphitePalette.current(colorScheme)
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(palette.onStrong)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(palette.strong))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
