import SwiftUI

public struct GraphitePositionCard: View {
    let position: Position
    /// Fees earned per day, oldest first; the mini chart is hidden while nil.
    var recentDailyFees: [Double]? = nil
    var onOpen: (() -> Void)? = nil
    var onCollect: (() -> Void)? = nil
    var onHide: (() -> Void)? = nil
    /// Nil when every position is on one chain or the list is already filtered to this one.
    var onShowOnlyChain: (() -> Void)? = nil

    public init(
        position: Position,
        recentDailyFees: [Double]? = nil,
        onOpen: (() -> Void)? = nil,
        onCollect: (() -> Void)? = nil,
        onHide: (() -> Void)? = nil,
        onShowOnlyChain: (() -> Void)? = nil
    ) {
        self.position = position
        self.recentDailyFees = recentDailyFees
        self.onOpen = onOpen
        self.onCollect = onCollect
        self.onHide = onHide
        self.onShowOnlyChain = onShowOnlyChain
    }

    @State private var showingDetails = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
                footer
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(palette.card))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(palette.cardLine, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .onTapGesture { showingDetails = true }
            .popover(isPresented: $showingDetails) {
                PositionDetailsView(position: position, onOpen: onOpen) { showingDetails = false }
            }
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
        if let onHide {
            Divider()
            Button("Hide Position", action: onHide)
        }
    }

    // MARK: - Sections

    private func header(_ info: PositionPresentation) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) { identity(info); value }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        identity(info).fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 8)
                        value.fixedSize(horizontal: true, vertical: false)
                    }
                    VStack(alignment: .leading, spacing: 10) { identity(info); value }
                }
            }
        }
    }

    private func identity(_ info: PositionPresentation) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 10))
        return layout {
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
                    .font(PoolTypography.heading(15, relativeTo: .body))
                    .foregroundStyle(palette.primaryText)
                Text(metaLabel)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }
        }
    }

    private var value: some View {
        VStack(alignment: .trailing, spacing: 2) {
            // Without pool state the amounts, and so the value, are unknown.
            Text(position.poolStateError == nil ? (position.positionUSDLabel ?? "–") : "–")
                .font(PoolTypography.amount(15, relativeTo: .body))
                .foregroundStyle(palette.primaryText)
            feesLabel
        }
    }

    @ViewBuilder
    private var feesLabel: some View {
        if let label = position.unclaimedCardLabel {
            let hasPricedFees = (position.usd ?? 0) > 0
            Text(label)
                .font(.caption.weight(hasPricedFees ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(hasPricedFees ? palette.fees : palette.secondaryText)
        } else if let error = position.feesError {
            Text("fees –")
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
                .help(error)
        }
    }

    private func rangeSection(_ info: PositionPresentation, colors: GraphitePalette.StatusColors) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("Price range · \(info.quoteSymbol)")
                        .font(.caption2).foregroundStyle(palette.secondaryText)
                    Spacer(minLength: 8)
                    StatusPill(status: info.status, colors: colors)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Price range · \(info.quoteSymbol)")
                        .font(.caption2).foregroundStyle(palette.secondaryText)
                    StatusPill(status: info.status, colors: colors)
                }
            }
            if let gauge = info.gauge, let price = info.currentPrice {
                VStack(spacing: 4) {
                    RangePriceLabelLayout(gauge: gauge) {
                        Text("\(price) \(info.quoteSymbol)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .multilineTextAlignment(.center)
                            .foregroundStyle(palette.onBarToday)
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(palette.barToday))
                    }
                    PositionRangeTrack(gauge: gauge, colors: colors, palette: palette)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Current price \(price) \(info.quoteSymbol), range \(info.minPrice) to \(info.maxPrice)")
                .accessibilityHint(gauge.isMarkerClamped ? "Price is beyond the displayed scale" : "")
                .help("Price in \(info.quoteSymbol) per \(info.baseSymbol). The coloured band is this position’s active price range.")
            } else if let reason = position.poolStateError {
                Label("Pool data unavailable", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(palette.outOfRange.tint)
                    .help("\(reason)\nRetried on the next refresh.")
            } else {
                Text("Current price unavailable")
                    .font(.caption).foregroundStyle(palette.secondaryText)
            }
            ViewThatFits(in: .horizontal) {
                HStack {
                    priceBound("Min", info.minPrice).fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 12)
                    priceBound("Max", info.maxPrice).fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 4) {
                    priceBound("Min", info.minPrice)
                    priceBound("Max", info.maxPrice)
                }
            }
            if let distance = info.distanceLabel, let gauge = info.gauge {
                Label("\(distance) range", systemImage: gauge.marker < gauge.bandStart ? "arrow.down.left" : "arrow.up.right")
                    .font(.caption2.weight(.semibold)).foregroundStyle(colors.tint)
            }
        }
        .padding(.top, 6)
    }

    private func priceBound(_ title: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(title).foregroundStyle(palette.secondaryText)
            Text(value).foregroundStyle(palette.primaryText)
        }
        .font(.caption2.monospacedDigit())
    }

    private var earnings: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) { earningsMetrics }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) { earningsMetrics }
                        .fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 10) { earningsMetrics }
                }
            }
        }
    }

    private var earningsMetrics: some View {
        let claimed = position.claimedCardLabel
        let syncing = position.feeHistoryBootstrapping
        let apr = syncing ? nil : position.realizedAPR()
        return Group {
            PositionMetric(title: syncing ? "Claimed · syncing" : "Claimed", value: claimed ?? (syncing ? "Syncing…" : "–"),
                           explanation: claimedHelp)
            PositionMetric(title: "APR since open", value: apr.map { formatPercent($0) } ?? "–",
                           explanation: realizedReturnHelp, tint: apr == nil ? palette.secondaryText : palette.fees)
            dailyFees
        }
    }

    @ViewBuilder
    private var dailyFees: some View {
        if let values = recentDailyFees, !values.isEmpty {
            HStack(alignment: .bottom, spacing: 6) {
                PositionMetric(title: "Daily fees", value: "\(values.count) days",
                               explanation: "Fees earned per day, oldest first; the rightmost bar is today. Today \(formatUSD(values.last ?? 0)) · best day \(formatUSD(values.max() ?? 0)).")
                MiniFeeBars(values: values, today: palette.barToday, earlier: palette.bar)
            }
        }
    }

    private var footer: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                stackedFooter
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 12) {
                        earnings.fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 0)
                        cardActions.fixedSize(horizontal: true, vertical: false)
                    }
                    if onCollect != nil {
                        VStack(alignment: .trailing, spacing: 12) {
                            HStack(spacing: 12) {
                                earnings.fixedSize(horizontal: true, vertical: false)
                                Spacer(minLength: 0)
                                detailsButton
                            }
                            collectButton
                        }
                    }
                    stackedFooter
                }
            }
        }
        .padding(.top, 11)
        .overlay(alignment: .top) {
            Rectangle().fill(palette.hairline).frame(height: 1)
        }
    }

    private var stackedFooter: some View {
        VStack(alignment: .leading, spacing: 12) {
            earnings
            HStack { Spacer(minLength: 0); cardActions }
        }
    }

    private var cardActions: some View {
        HStack(spacing: 10) {
            detailsButton
            collectButton
        }
    }

    private var detailsButton: some View {
        Button { showingDetails = true } label: {
            Label("Details", systemImage: "info.circle")
                .labelStyle(.iconOnly)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(palette.secondaryText)
        .help("Position details: holdings, opening date and pool statistics")
    }

    @ViewBuilder
    private var collectButton: some View {
        if let onCollect {
            Button("Collect", action: onCollect)
                .buttonStyle(GraphiteStrongButtonStyle())
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
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(palette.card))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(palette.outOfRange.bandEdge, lineWidth: 1)
        )
        .contextMenu {
            Button("Copy Error") { Clipboard.copy(error) }
            Button("Copy Position ID") { Clipboard.copy(position.tokenId) }
            if let onHide { Button("Hide Position", action: onHide) }
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

    private var realizedReturnHelp: String {
        let opened = position.openedAt.map { " on \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ""
        return """
        All-time fees (claimed + unclaimed) as a share of the position's current value, and that \
        return per year since the position was opened\(opened). Compare with Yield in Details, the \
        pool's estimate from the last 24 hours, also per year.
        Claimed fees are valued at today's prices. If liquidity was added or removed, the current \
        value is not the capital the fees were earned on.
        APR is unavailable while history is syncing, before one full day, or when required data \
        is missing. It is not a forecast.
        """
    }

    private var claimedHelp: String {
        if position.isV4 { return "Claimed v4 fees are not tracked. A dash means unavailable, not zero." }
        return "Fees already collected from this position, valued at current token prices. When USD prices are unavailable, token amounts are shown. While history is syncing, the amount may be partial. A dash means the amount is unavailable, not zero."
    }

}

struct PositionMetric: View {
    let title: String
    let value: String
    let explanation: String
    var tint: Color? = nil
    @State private var showingExplanation = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = GraphitePalette.current(scheme)
        Button { showingExplanation.toggle() } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 3) {
                    Text(title)
                    Image(systemName: "info.circle").imageScale(.small)
                }
                .font(.caption2).foregroundStyle(palette.secondaryText)
                Text(value).font(PoolTypography.amount(13, relativeTo: .callout))
                    .foregroundStyle(tint ?? palette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(value)")
        .accessibilityHint("Show explanation")
        .popover(isPresented: $showingExplanation) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(PoolTypography.heading(16))
                Text(explanation).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(idealWidth: 280, maxWidth: 320, alignment: .leading)
            .foregroundStyle(palette.primaryText)
            .background(palette.card)
            .presentationCompactAdaptation(.popover)
        }
    }
}

// MARK: - Fee pool

/// The fee pool: turquoise water filling its container from the bottom to `level`,
/// the share of the value already earned back in fees. Pours in and sloshes from side to side
/// when shown or when the level changes, then settles; it stays still otherwise, so an open
/// popover costs nothing.
public struct PoolWater: View {
    /// All-time fees over value: 0 is empty, 1 fills the container, and higher returns stay full.
    let level: Double
    var base = 0.0
    var amplitude: CGFloat = 3.5
    /// Water colour for a pool drawn over a coloured card; nil uses the turquoise fee-pool gradient.
    var color: Color? = nil

    public init(level: Double, base: Double = 0, amplitude: CGFloat = 3.5, color: Color? = nil) {
        self.level = level
        self.base = base
        self.amplitude = amplitude
        self.color = color
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
                ZStack(alignment: .bottom) {
                    Wave(level: shownLevel, phase: restPhase + back.travel + .pi * 0.8,
                         amplitude: amplitude * back.swell, tilt: back.tilt)
                        .fill(color.map(AnyShapeStyle.init) ?? AnyShapeStyle(palette.water))
                        .opacity(palette.waterBack)
                    Wave(level: shownLevel, phase: restPhase + front.travel,
                         amplitude: amplitude * front.swell, tilt: front.tilt)
                        .fill(color.map(AnyShapeStyle.init) ?? AnyShapeStyle(palette.water))
                        .opacity(palette.waterFront)
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
        guard !level.isNaN else { return 0 }
        return base + (1 - base) * min(max(level, 0), 1)
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
    var level: Double
    var phase: Double
    var amplitude: CGFloat
    var tilt: CGFloat = 0

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard rect.height > 0, rect.width > 0, level > 0 else { return path }
        if level >= 1 { return Path(rect) }
        let wavelength = rect.width / 1.5
        let surface = rect.maxY - rect.height * min(level, 1)
        // Taper both motions near empty/full so neither layer crosses the container limits.
        let room = max(0, min(surface - rect.minY, rect.maxY - surface))
        let crest = min(amplitude, room / 2)
        let lean = min(max(tilt, -room / 2), room / 2)
        let halfWidth = max(rect.width / 2, 1)
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for x in stride(from: rect.minX, through: rect.maxX, by: 2) {
            let angle = Double((x - rect.minX) / wavelength) * 2 * .pi + phase
            let y = surface + crest * CGFloat(sin(angle)) + lean * (x - rect.midX) / halfWidth
            path.addLine(to: CGPoint(x: x, y: y))
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
