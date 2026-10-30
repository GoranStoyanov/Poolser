import SwiftUI

public struct GraphitePositionCard: View {
    let position: Position
    /// Fees earned per day, oldest first; the mini chart is hidden while nil.
    var recentDailyFees: [Double]? = nil
    var onOpen: (() -> Void)? = nil
    var onCollect: (() -> Void)? = nil
    /// Nil when every position is on one chain or the list is already filtered to this one.
    var onShowOnlyChain: (() -> Void)? = nil

    public init(
        position: Position,
        recentDailyFees: [Double]? = nil,
        onOpen: (() -> Void)? = nil,
        onCollect: (() -> Void)? = nil,
        onShowOnlyChain: (() -> Void)? = nil
    ) {
        self.position = position
        self.recentDailyFees = recentDailyFees
        self.onOpen = onOpen
        self.onCollect = onCollect
        self.onShowOnlyChain = onShowOnlyChain
    }

    @Environment(\.colorScheme) private var colorScheme
    private var palette: GraphitePalette { .current(colorScheme) }

    public var body: some View {
        if let error = position.error {
            errorCard(error)
        } else {
            let info = PositionPresentation(position)
            let colors = palette.status(info.status)
            VStack(alignment: .leading, spacing: 10) {
                header(info)
                rangeSection(info, colors: colors)
                assetsRow(info)
                earningsRow
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
            .contextMenu { cardMenu }
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: "Open in Uniswap") { onOpen?() }
        }
    }

    @ViewBuilder
    private var cardMenu: some View {
        if let onOpen {
            Button("Open in Uniswap", action: onOpen)
            Divider()
        }
        Button("Copy Position ID") { Clipboard.copy(position.tokenId) }
        if let poolRef = position.poolReference {
            Button(position.isV4 ? "Copy Pool ID" : "Copy Pool Address") { Clipboard.copy(poolRef) }
        }
        if let onShowOnlyChain {
            Divider()
            Button("Show Only \(chainName) Positions", action: onShowOnlyChain)
        }
    }

    // MARK: - Sections

    private func header(_ info: PositionPresentation) -> some View {
        HStack(spacing: 10) {
            TokenPairAvatar(
                base: TokenPairAvatar.Token(
                    symbol: info.baseSymbol,
                    address: info.isInverted ? position.iconAddress1 : position.iconAddress0
                ),
                quote: TokenPairAvatar.Token(
                    symbol: info.quoteSymbol,
                    address: info.isInverted ? position.iconAddress0 : position.iconAddress1
                ),
                chainID: position.chainNumericID,
                chain: SupportedChain.byID(position.chainID)
            )
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

    /// Tokens the position holds now, base token first, and its NFT ID.
    private func assetsRow(_ info: PositionPresentation) -> some View {
        HStack(spacing: 8) {
            Text(assetsLabel(info))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text("#\(position.tokenId)")
                .textSelection(.enabled)
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(palette.secondaryText)
    }

    /// Claimed fees and the realized return, once the claimed-fee history is known: the
    /// position's fee pool with its level beside it, the claimed total and its APR since open.
    @ViewBuilder
    private var earningsRow: some View {
        let claimed = position.claimedUSDLabel ?? position.claimedFeesLabel
        let feeReturn = position.feeReturnOnAssets
        let apr = position.realizedAPR()
        if claimed != nil || position.feeHistoryBootstrapping || feeReturn != nil || apr != nil {
            HStack(alignment: .center, spacing: 16) {
                if let feeReturn {
                    HStack(spacing: 7) {
                        PoolGauge(level: feeReturn)
                        earningsStat(formatPercent(feeReturn), "of value earned")
                    }
                }
                if let claimed {
                    earningsStat(claimed, "claimed")
                } else if position.feeHistoryBootstrapping {
                    earningsStat("–", "claimed, syncing…")
                }
                Spacer(minLength: 4)
                if let apr {
                    earningsStat(formatPercent(apr), "APR since open", tint: palette.fees, alignment: .trailing)
                }
            }
            .help(realizedReturnHelp)
            .accessibilityElement(children: .combine)
        }
    }

    private func earningsStat(
        _ value: String,
        _ label: String,
        tint: Color? = nil,
        alignment: HorizontalAlignment = .leading
    ) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(value)
                .font(.callout.weight(.semibold).monospacedDigit())
                .fontDesign(.rounded)
                .foregroundStyle(tint ?? palette.primaryText)
            Text(label)
                .font(.caption2)
                .foregroundStyle(palette.secondaryText)
        }
        .lineLimit(1)
    }

    private func footer(_ info: PositionPresentation, colors: GraphitePalette.StatusColors) -> some View {
        HStack(spacing: 8) {
            StatusPill(status: info.status, colors: colors)
            if let stats = poolStatsLabel {
                Text(stats)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
                    .help(poolStatsHelp)
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
        .contextMenu {
            Button("Copy Error") { Clipboard.copy(error) }
            Button("Copy Position ID") { Clipboard.copy(position.tokenId) }
        }
    }

    // MARK: - Labels

    private var chainName: String {
        SupportedChain.byID(position.chainID)?.displayName ?? position.chainName
    }

    private var metaLabel: String {
        let fee = position.feeFraction == nil ? "dynamic fee" : "\(position.feePct)%"
        return "\(chainName) · \(position.versionLabel) · \(fee)"
    }

    private func assetsLabel(_ info: PositionPresentation) -> String {
        // Without pool state the amounts are unknown, not zero.
        guard position.poolStateError == nil else { return "Assets –" }
        let tokens = [
            (amount: position.amount0, label: position.amount0Label, symbol: position.sym0),
            (amount: position.amount1, label: position.amount1Label, symbol: position.sym1),
        ]
        let parts = (info.isInverted ? tokens.reversed() : tokens)
            .filter { $0.amount > 0 }
            .map { "\($0.label) \($0.symbol)" }
        return "Assets " + (parts.isEmpty ? "0" : parts.joined(separator: " + "))
    }

    /// The pool's last 24 hours, from GeckoTerminal.
    private var poolStatsLabel: String? {
        var parts: [String] = []
        if let volume = position.volumeUSD24h { parts.append("Vol \(PositionPresentation.compactUSD(volume))") }
        if let apr = position.feeAPR { parts.append(String(format: "Yield %.1f%%", apr)) }
        if let tvl = position.tvlUSD { parts.append("TVL \(PositionPresentation.compactUSD(tvl))") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var realizedReturnHelp: String {
        let opened = position.openedAt.map { " on \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ""
        return """
        All-time fees (claimed + unclaimed) as a share of the position's current value, and that \
        return per year since the position was opened\(opened). Compare with Yield below, the \
        pool's estimate from the last 24 hours, also per year.
        Claimed fees are valued at today's prices. If liquidity was added or removed, the current \
        value is not the capital the fees were earned on.
        """
    }

    private var poolStatsHelp: String {
        """
        The pool over the last 24 hours: trading volume, yield and total liquidity (TVL).
        Yield: if the last 24h repeated for a year, this is the estimated return. Calculated from \
        24h trading volume × fee rate, divided by TVL. It is the pool's figure; an out-of-range \
        position earns none of it.
        """
    }

    private func feeHistoryHelp(_ values: [Double]) -> String {
        let today = formatUSD(values.last ?? 0)
        let best = formatUSD(values.max() ?? 0)
        return "Fees this position earned per day, last \(values.count) days.\nToday \(today) · best day \(best). The rightmost bar is today."
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

// MARK: - Fee pool

/// The fee pool: water in the logo's colours filling its container from the bottom to `level`,
/// the share of the value already earned back in fees. Pours in and sloshes from side to side
/// when shown or when the level changes, then settles; it stays still otherwise, so an open
/// popover costs nothing.
public struct PoolWater: View {
    /// All-time fees over value, clamped to 0…1. Drawn above a fixed `base` so the bottom of the
    /// container always sits in water; 1 fills it.
    let level: Double
    var base = 0.14
    var amplitude: CGFloat = 3.5

    public init(level: Double, base: Double = 0.14, amplitude: CGFloat = 3.5) {
        self.level = level
        self.base = base
        self.amplitude = amplitude
    }

    @State private var shownLevel = 0.0
    @State private var restPhase = 0.0
    @State private var sloshStart: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        let palette = GraphitePalette.current(colorScheme)
        TimelineView(.animation(paused: sloshStart == nil)) { context in
            let elapsed = sloshStart.map { context.date.timeIntervalSince($0) }
            let front = Slosh(elapsed: elapsed)
            // The back layer trails the front a little, which reads as depth.
            let back = Slosh(elapsed: elapsed.map { max($0 - 0.12, 0) })
            GeometryReader { geo in
                let height = geo.size.height * shownLevel
                ZStack(alignment: .bottom) {
                    Wave(phase: restPhase + back.travel + .pi * 0.8,
                         amplitude: amplitude * back.swell, tilt: back.tilt)
                        .fill(palette.brand)
                        .opacity(palette.waterBack)
                        .frame(height: height > 0 ? height + amplitude * 1.6 : 0)
                    Wave(phase: restPhase + front.travel,
                         amplitude: amplitude * front.swell, tilt: front.tilt)
                        .fill(palette.brand)
                        .opacity(palette.waterFront)
                        .frame(height: height)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { pour() }
        .onChange(of: level) { pour() }
        .task(id: sloshStart) {
            guard sloshStart != nil else { return }
            try? await Task.sleep(for: .seconds(Slosh.duration))
            guard !Task.isCancelled else { return }
            restPhase = (restPhase + Slosh.fullTravel).truncatingRemainder(dividingBy: .pi * 2)
            sloshStart = nil
        }
    }

    private var target: Double { Self.fill(level: level, base: base) }

    /// The share of the container a pool at `level` fills, starting from `base`.
    static func fill(level: Double, base: Double) -> Double {
        base + (1 - base) * min(max(level, 0), 1)
    }

    private func pour() {
        guard !reduceMotion else {
            shownLevel = target
            return
        }
        withAnimation(.easeOut(duration: 1.2)) {
            shownLevel = target
        }
        sloshStart = .now
    }
}

/// The surface's motion `elapsed` seconds into a slosh: a damped side-to-side tilt, waves that
/// start tall and calm down, and a crest that drifts across and slows to a stop. Nil is at rest.
struct Slosh {
    static let duration: TimeInterval = 3
    static let fullTravel = Double.pi * 3

    /// Points the right edge sits below the middle of the surface; negative tilts the other way.
    var tilt: CGFloat = 0
    /// Multiplier on the resting wave height.
    var swell: CGFloat = 1
    /// Phase the waves have moved so far, reaching `fullTravel` at the end; at rest it is folded
    /// into `PoolWater.restPhase`.
    var travel: Double = 0

    init(elapsed: TimeInterval?) {
        guard let t = elapsed.map({ min($0, Self.duration) }) else { return }
        tilt = 9 * CGFloat(exp(-t / 0.7) * sin(2 * .pi * t / 0.95))
        swell = 1 + 1.3 * CGFloat(exp(-t / 0.8))
        let progress = t / Self.duration
        travel = Self.fullTravel * (1 - pow(1 - progress, 3))
    }
}

/// A filled shape whose top edge is a sine wave, one and a half periods across, tilted by `tilt`
/// points from the middle to each side.
struct Wave: Shape {
    var phase: Double
    var amplitude: CGFloat
    var tilt: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard rect.height > 0 else { return path }
        let wavelength = rect.width / 1.5
        let crest = min(amplitude, rect.height / 2)
        let halfWidth = max(rect.width / 2, 1)
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for x in stride(from: rect.minX, through: rect.maxX, by: 2) {
            let angle = Double((x - rect.minX) / wavelength) * 2 * .pi + phase
            let lean = tilt * (x - rect.midX) / halfWidth
            path.addLine(to: CGPoint(x: x, y: rect.minY + crest + crest * CGFloat(sin(angle)) + lean))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A small upright tank showing a position's fee pool, for rows too small for `PoolWater`.
struct PoolGauge: View {
    let level: Double

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = GraphitePalette.current(colorScheme)
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(palette.control)
            .overlay(alignment: .bottom) {
                GeometryReader { geo in
                    LinearGradient(colors: [palette.brandStart, palette.brandEnd], startPoint: .top, endPoint: .bottom)
                        .frame(height: geo.size.height * PoolWater.fill(level: level, base: 0.1))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(palette.cardLine, lineWidth: 1))
            .frame(width: 10, height: 26)
            .accessibilityHidden(true)
    }
}

/// The logo's eyes, small enough to sit beside a caption.
public struct PoolEyes: View {
    public init() {}

    public var body: some View {
        HStack(spacing: 1.5) {
            eye
            eye
        }
        .accessibilityHidden(true)
    }

    private var eye: some View {
        Ellipse()
            .fill(.white)
            .overlay(Ellipse().strokeBorder(Color(white: 0.2), lineWidth: 1.2))
            .overlay(alignment: .bottomTrailing) {
                Ellipse()
                    .fill(Color(white: 0.07))
                    .frame(width: 4, height: 5)
                    .padding(.trailing, 1.5)
                    .padding(.bottom, 1.5)
            }
            .frame(width: 8, height: 10)
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
    struct Token {
        let symbol: String
        let address: String
    }

    let base: Token
    let quote: Token
    let chainID: Int
    let chain: SupportedChain?

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var iconStore = TokenIconStore.shared

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
        .task(id: "\(chainID)-\(base.address)-\(quote.address)") {
            await iconStore.fetchIfNeeded(chainID: chainID, address: base.address)
            await iconStore.fetchIfNeeded(chainID: chainID, address: quote.address)
        }
    }

    private func token(_ token: Token, ring: Color) -> some View {
        let style = Self.style(for: token.symbol)
        return ZStack {
            Circle().fill(style.color)
            if let icon = iconStore.icon(chainID: chainID, address: token.address) {
                // Logos with transparent corners sit on white rather than the letter's colour.
                Circle().fill(.white)
                Image(platformImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .clipShape(Circle())
            } else {
                glyph(style.glyph)
            }
        }
        .frame(width: 26, height: 26)
        .overlay(Circle().strokeBorder(ring, lineWidth: 2))
    }

    private func glyph(_ text: String) -> some View {
        Text(text)
            .font(.callout.weight(.bold))
            .foregroundStyle(.white)
    }

    /// Letter avatars until a token's logo loads, or when it has none; well-known tokens get
    /// their usual colour.
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
public struct GraphiteChipButtonStyle: ButtonStyle {
    let foreground: Color
    let background: Color
    let border: Color

    public init(foreground: Color, background: Color, border: Color) {
        self.foreground = foreground
        self.background = background
        self.border = border
    }

    public func makeBody(configuration: Configuration) -> some View {
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

public struct GraphiteStrongButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
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
