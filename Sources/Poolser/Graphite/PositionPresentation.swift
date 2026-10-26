import Foundation

/// Range state in the displayed price orientation: "near max" means near the bound shown as Max,
/// which is the lower tick when the pair is shown inverted.
enum RangeStatus: Equatable {
    case inRange, nearMin, nearMax, outOfRange, fullRange, unknown

    var title: String {
        switch self {
        case .inRange:    return "In range"
        case .nearMin:    return "Near min"
        case .nearMax:    return "Near max"
        case .outOfRange: return "Out of range"
        case .fullRange:  return "Full range"
        case .unknown:    return "Range unknown"
        }
    }

    var needsAttention: Bool {
        switch self {
        case .nearMin, .nearMax, .outOfRange, .unknown: return true
        case .inRange, .fullRange: return false
        }
    }
}

/// Where the range band and the current-price marker sit on a 0…1 gauge.
struct RangeGaugeLayout: Equatable {
    var bandStart: Double
    var bandEnd: Double
    var marker: Double
    /// The current price is further away than the gauge shows; the marker sits at the edge.
    var isMarkerClamped: Bool

    /// The window covers the range plus the current tick, capped at 1.5 range widths on each
    /// side so a price far outside the range does not shrink the band to a sliver.
    init(lower: Int, upper: Int, current: Int) {
        let span = Double(max(upper - lower, 1))
        let tick = Double(current)
        var lo = max(min(Double(lower), tick), Double(lower) - 1.5 * span)
        var hi = min(max(Double(upper), tick), Double(upper) + 1.5 * span)
        let pad = (hi - lo) * 0.1
        lo -= pad
        hi += pad
        let width = hi - lo
        bandStart = (Double(lower) - lo) / width
        bandEnd = (Double(upper) - lo) / width
        let raw = (tick - lo) / width
        marker = min(max(raw, 0), 1)
        isMarkerClamped = raw < 0 || raw > 1
    }

    init(bandStart: Double, bandEnd: Double, marker: Double, isMarkerClamped: Bool) {
        self.bandStart = bandStart
        self.bandEnd = bandEnd
        self.marker = marker
        self.isMarkerClamped = isMarkerClamped
    }

    static func fullRange(lower: Int, upper: Int, current: Int) -> RangeGaugeLayout {
        let raw = Double(current - lower) / Double(max(upper - lower, 1))
        return RangeGaugeLayout(bandStart: 0, bandEnd: 1, marker: min(max(raw, 0), 1), isMarkerClamped: false)
    }

    /// Ticks grow with token1/token0; an inverted pair runs the other way.
    func mirrored() -> RangeGaugeLayout {
        RangeGaugeLayout(bandStart: 1 - bandEnd, bandEnd: 1 - bandStart, marker: 1 - marker, isMarkerClamped: isMarkerClamped)
    }
}

/// Status item text. Range problems are left to the popover's Needs attention chip.
enum MenuBarTitle {
    /// "$48.2k │ $312.58", with `trend` (an arrow while the fees change).
    static func text(valueUSD: Double, feesUSD: Double, trend: String? = nil) -> String {
        let title = "\(PositionPresentation.compactUSD(valueUSD)) │ \(formatUSD(feesUSD))"
        return trend.map { "\(title) \($0)" } ?? title
    }
}

extension Position {
    /// The position's page on app.uniswap.org.
    var uniswapURL: URL? {
        let slug = SupportedChain.byID(chainID)?.uniswapChainSlug ?? chainID
        return URL(string: isV4
            ? "https://app.uniswap.org/positions/v4/\(slug)/\(tokenId)"
            : "https://app.uniswap.org/pools/\(tokenId)?chain=\(slug)")
    }

    /// v4 pools have no contract of their own; they are identified by the PoolKey hash.
    var poolReference: String? {
        isV4 ? poolId.map { "0x" + $0.hexString } : poolAddress
    }
}

/// Display values for one position: which token prices the other, range bounds as prices,
/// status and gauge geometry.
struct PositionPresentation {
    /// Share of the range width next to either bound that counts as near the edge.
    static let nearEdgeFraction = 0.03

    /// Quote tokens, strongest first. A pair is priced in whichever token ranks higher, so
    /// WETH/USDC reads in USDC and WBTC/WETH in WETH.
    static let quotePriority = [
        "usdc", "usdt", "dai", "usdc.e", "usdbc", "usdt0", "pyusd", "usds", "frax", "lusd",
        "weth", "eth", "wbtc", "cbbtc", "btcb",
    ]

    let pairLabel: String
    let baseSymbol: String
    let quoteSymbol: String
    let isInverted: Bool
    let status: RangeStatus
    let minPrice: String
    let maxPrice: String
    let currentPrice: String?
    /// "4.2% below" while out of range.
    let distanceLabel: String?
    let gauge: RangeGaugeLayout?

    init(_ pos: Position) {
        let inverted = Self.showsInverted(sym0: pos.sym0, sym1: pos.sym1)
        isInverted = inverted
        baseSymbol = inverted ? pos.sym1 : pos.sym0
        quoteSymbol = inverted ? pos.sym0 : pos.sym1
        pairLabel = "\(baseSymbol)/\(quoteSymbol)"

        func displayPrice(_ tick: Int) -> Double {
            let price = Self.price(tick: tick, dec0: pos.dec0, dec1: pos.dec1)
            return inverted ? 1 / price : price
        }

        if pos.isFullRange {
            minPrice = "0"
            maxPrice = "∞"
        } else {
            let lowerPrice = displayPrice(pos.tickLower)
            let upperPrice = displayPrice(pos.tickUpper)
            minPrice = Self.formatPrice(min(lowerPrice, upperPrice))
            maxPrice = Self.formatPrice(max(lowerPrice, upperPrice))
        }

        let tick = pos.poolStateError == nil ? pos.currentTick : nil
        currentPrice = tick.map { Self.formatPrice(displayPrice($0)) }
        status = Self.status(pos, tick: tick, inverted: inverted)

        if let tick, status == .outOfRange {
            distanceLabel = Self.distanceLabel(tick: tick, lower: pos.tickLower, upper: pos.tickUpper, inverted: inverted)
        } else {
            distanceLabel = nil
        }

        if let tick {
            let layout = pos.isFullRange
                ? RangeGaugeLayout.fullRange(lower: pos.tickLower, upper: pos.tickUpper, current: tick)
                : RangeGaugeLayout(lower: pos.tickLower, upper: pos.tickUpper, current: tick)
            gauge = inverted ? layout.mirrored() : layout
        } else {
            gauge = nil
        }
    }

    static func showsInverted(sym0: String, sym1: String) -> Bool {
        rank(sym0) < rank(sym1)
    }

    private static func rank(_ symbol: String) -> Int {
        quotePriority.firstIndex(of: symbol.lowercased()) ?? Int.max
    }

    /// token1 per token0 in whole tokens.
    static func price(tick: Int, dec0: Int, dec1: Int) -> Double {
        pow(1.0001, Double(tick)) * pow(10, Double(dec0 - dec1))
    }

    static func status(_ pos: Position, tick: Int?, inverted: Bool) -> RangeStatus {
        if pos.error != nil { return .unknown }
        if pos.isFullRange { return .fullRange }
        guard let tick else {
            switch pos.inRange {
            case true:  return .inRange
            case false: return .outOfRange
            case nil:   return .unknown
            }
        }
        guard Position.isInRange(tick: tick, lower: pos.tickLower, upper: pos.tickUpper) else { return .outOfRange }
        let fraction = Double(tick - pos.tickLower) / Double(max(pos.tickUpper - pos.tickLower, 1))
        if fraction < nearEdgeFraction { return inverted ? .nearMax : .nearMin }
        if fraction > 1 - nearEdgeFraction { return inverted ? .nearMin : .nearMax }
        return .inRange
    }

    static func distanceLabel(tick: Int, lower: Int, upper: Int, inverted: Bool) -> String {
        let belowLowerTick = tick < lower
        let diff = belowLowerTick ? lower - tick : tick - upper
        let direction = belowLowerTick != inverted ? "below" : "above"
        let exponent = Double(diff) * log(1.0001)
        // Past a 1000× move a percentage is noise.
        if exponent > log(1_000) { return "far \(direction)" }
        let pct = (exp(exponent) - 1) * 100
        return (pct >= 100 ? String(format: "%.0f%%", pct) : String(format: "%.1f%%", pct)) + " \(direction)"
    }

    static func formatPrice(_ x: Double) -> String {
        guard x.isFinite else { return "∞" }
        if x == 0 { return "0" }
        if x >= 1e9 || x < 1e-6 { return String(format: "%.2e", x) }
        let locale = Locale(identifier: "en_US")
        if x >= 1_000 { return x.formatted(.number.precision(.fractionLength(0)).locale(locale)) }
        if x >= 1 { return x.formatted(.number.precision(.fractionLength(2)).locale(locale)) }
        return x.formatted(.number.precision(.significantDigits(4)).locale(locale))
    }

    /// "$48.2k" for the menu bar, where width is scarce.
    static func compactUSD(_ x: Double) -> String {
        switch x {
        case 1_000_000...: return String(format: "$%.1fM", x / 1_000_000)
        case 10_000...:    return String(format: "$%.1fk", x / 1_000)
        case 1_000...:     return String(format: "$%.2fk", x / 1_000)
        default:           return String(format: "$%.0f", x)
        }
    }
}
