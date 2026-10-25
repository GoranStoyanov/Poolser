import Foundation

/// Uniswap v4 `PoolKey.fee` helpers.
enum V4Fee {
    /// `LPFeeLibrary.DYNAMIC_FEE_FLAG`: the pool's LP fee is set by its hook, not by `PoolKey.fee`.
    static let dynamicFlag = 0x800000

    static func isDynamic(_ fee: Int) -> Bool { fee == dynamicFlag }

    /// Fee tier label in percent, e.g. "0.3" for 3000, or "dyn" for a dynamic-fee pool.
    static func label(_ fee: Int) -> String {
        isDynamic(fee) ? "dyn" : String(format: "%.4g", Double(fee) / 10_000)
    }
}

struct Position: Identifiable {
    /// v3 and v4 token IDs are independent sequences, so the version is part of the identity.
    var id: String { "\(chainID)-\(versionLabel)-\(tokenId)" }
    /// Pre-version id format, still present in persisted notification state.
    var legacyID: String { "\(chainID)-\(tokenId)" }
    let chainID: String
    let chainName: String
    let chainNumericID: Int
    let tokenId: String
    let token0: String
    let token1: String
    let sym0: String
    let sym1: String
    let feePct: String   // e.g. "0.05"
    let feeRaw: Int      // e.g. 500
    var fees0: Double
    var fees1: Double
    let tickLower: Int
    let tickUpper: Int
    let liquidity: Double
    var amount0: Double = 0   // current token0 in position (decimal-adjusted)
    var amount1: Double = 0   // current token1 in position
    var dec0: Int = 18
    var dec1: Int = 18
    var usd: Double?          // fees value in USD
    /// USD per whole token at the last refresh; nil when no price source had the token.
    var price0USD: Double?
    var price1USD: Double?
    var positionUSD: Double?  // total position liquidity value in USD
    var claimedFees0: Double = 0
    var claimedFees1: Double = 0
    var claimedUSD: Double? = nil
    var feeHistoryBootstrapping: Bool = false
    /// When the position was opened; set once its claimed-fee history is complete.
    var openedAt: Date? = nil
    var currentTick: Int?
    var inRange: Bool?
    var error: String?
    // v4-specific
    var isV4: Bool = false
    var poolId: Data? = nil   // keccak256(PoolKey) — used for StateView queries
    /// The pool's currencies as the PoolKey has them: address(0) for native ETH, which
    /// `token0`/`token1` replace with the wrapped token for price lookups.
    var currency0: String? = nil
    var currency1: String? = nil
    var feesError: String? = nil  // set when fee computation fails
    /// Why the pool's price could not be read; amounts and range are unknown while set.
    var poolStateError: String? = nil
    // pool stats (GeckoTerminal)
    var poolAddress: String? = nil  // v3 pool contract address
    var volumeUSD24h: Double? = nil
    var feeAPR: Double? = nil
    var tvlUSD: Double? = nil

    var isFullRange: Bool {
        tickLower <= -887200 && tickUpper >= 887200
    }

    /// Uniswap semantics: a position is active iff `tickLower <= tick < tickUpper`.
    /// At `tick == tickUpper` it holds only token1 and earns no fees.
    static func isInRange(tick: Int, lower: Int, upper: Int) -> Bool {
        tick >= lower && tick < upper
    }

    var rangeLabel: String {
        if error != nil { return "ERROR" }
        if isFullRange   { return "FULL RANGE" }
        switch inRange {
        case true:  return "IN RANGE"
        case false: return "OUT RANGE"
        case nil:   return "RANGE ?"
        }
    }

    var feesLabel: String {
        var parts: [String] = []
        if fees0 > 0 { parts.append(trimNum(fees0) + " " + sym0) }
        if fees1 > 0 { parts.append(trimNum(fees1) + " " + sym1) }
        return parts.isEmpty ? "0" : parts.joined(separator: " + ")
    }

    /// USD value of unclaimed fees, formatted.
    var feesUSDLabel: String? {
        guard let usd else { return nil }
        return formatUSD(usd)
    }


    var claimedUSDLabel: String? {
        guard let usd = claimedUSD, usd > 0 else { return nil }
        return formatUSD(usd)
    }

    var claimedFeesLabel: String? {
        var parts: [String] = []
        if claimedFees0 > 0 { parts.append(trimNum(claimedFees0) + " " + sym0) }
        if claimedFees1 > 0 { parts.append(trimNum(claimedFees1) + " " + sym1) }
        return parts.isEmpty ? nil : parts.joined(separator: " + ")
    }

    /// Pool fee as a fraction (0.003 for 0.3%), or nil for a v4 dynamic-fee pool whose
    /// `feeRaw` is the dynamic flag rather than a fee.
    var feeFraction: Double? {
        isV4 && V4Fee.isDynamic(feeRaw) ? nil : Double(feeRaw) / 1_000_000
    }

    var versionLabel: String { isV4 ? "v4" : "v3" }
    var chainLabel: String { chainName }

    /// Total position liquidity value in USD, formatted.
    var positionUSDLabel: String? {
        guard let positionUSD, positionUSD > 0 else { return nil }
        return formatUSD(positionUSD)
    }

    var volumeLabel: String? {
        volumeUSD24h.map { "Vol(24h): \(formatCompact($0))" }
    }
    var yieldLabel: String? {
        feeAPR.map { String(format: "Yield (24h): %.1f%%", $0) }
    }
    var tvlLabel: String? {
        tvlUSD.map { "TVL: \(formatCompact($0))" }
    }
    var hasPoolStats: Bool { volumeUSD24h != nil || feeAPR != nil || tvlUSD != nil }

    /// Positions younger than this get no annualized figure: a few hours of fees scaled to a
    /// year is noise.
    static let minAgeForAPR: TimeInterval = 24 * 3600

    /// Claimed plus unclaimed fees in USD. Needs the complete claimed history (`openedAt` is set
    /// with it) and prices for both parts.
    var allTimeFeesUSD: Double? {
        guard error == nil, openedAt != nil, let unclaimed = usd else { return nil }
        let hasClaims = claimedFees0 > 0 || claimedFees1 > 0
        if hasClaims && claimedUSD == nil { return nil }
        return unclaimed + (claimedUSD ?? 0)
    }

    /// All-time fees as a share of the position's current value (0.18 = 18%).
    var feeReturnOnAssets: Double? {
        guard let fees = allTimeFeesUSD, let value = positionUSD, value > 0 else { return nil }
        return fees / value
    }

    func yearsOpen(at now: Date) -> Double? {
        guard let openedAt else { return nil }
        let age = now.timeIntervalSince(openedAt)
        guard age >= Self.minAgeForAPR else { return nil }
        return age / (365.25 * 24 * 3600)
    }

    /// `feeReturnOnAssets` per year since the position was opened, as a fraction. Comparable
    /// with the pool's 24h yield (`feeAPR`, in percent), which is also annualized.
    func realizedAPR(at now: Date = Date()) -> Double? {
        guard let feeReturn = feeReturnOnAssets, let years = yearsOpen(at: now) else { return nil }
        return feeReturn / years
    }

    /// Current token amounts held in the position, e.g. "0.05 WBTC + 1,200 USDC".
    var distributionLabel: String {
        var parts: [String] = []
        if amount0 > 0 { parts.append(trimNum(amount0) + " " + sym0) }
        if amount1 > 0 { parts.append(trimNum(amount1) + " " + sym1) }
        return parts.joined(separator: " + ")
    }

    var amount0Label: String { poolStateError != nil ? "–" : amount0 > 0 ? trimNum(amount0) : "0" }
    var amount1Label: String { poolStateError != nil ? "–" : amount1 > 0 ? trimNum(amount1) : "0" }
}

/// Fees across every loaded position of the wallet, including ones the list filters hide.
/// Claimed fees come from the v3 Collect history; v4 claimed fees are not tracked.
struct WalletFeeSummary: Equatable {
    var unclaimedUSD: Double
    var claimedUSD: Double
    /// True while a claimed-fee history scan is still catching up, so the claimed total is partial.
    var isSyncing: Bool
    /// All-time fees ÷ current value, over the positions where both are known.
    var returnOnAssets: Double?
    /// Σ fees ÷ Σ (value × years open): an APR weighted by capital and time, so a large or old
    /// position counts for more than a small new one.
    var realizedAPR: Double?

    var allTimeUSD: Double { unclaimedUSD + claimedUSD }

    init(positions: [Position], now: Date = Date()) {
        let loaded = positions.filter { $0.error == nil }
        unclaimedUSD = loaded.compactMap(\.usd).reduce(0, +)
        claimedUSD = loaded.compactMap(\.claimedUSD).reduce(0, +)
        isSyncing = loaded.contains(where: \.feeHistoryBootstrapping)

        var fees = 0.0, value = 0.0, aprFees = 0.0, valueYears = 0.0
        for p in loaded {
            guard p.feeReturnOnAssets != nil, let f = p.allTimeFeesUSD, let v = p.positionUSD else { continue }
            fees += f
            value += v
            if let years = p.yearsOpen(at: now) {
                aprFees += f
                valueYears += v * years
            }
        }
        returnOnAssets = value > 0 ? fees / value : nil
        realizedAPR = valueYears > 0 ? aprFees / valueYears : nil
    }
}

private func formatCompact(_ x: Double) -> String {
    switch x {
    case 1_000_000_000...: return String(format: "$%.2fB", x / 1_000_000_000)
    case 1_000_000...:     return String(format: "$%.2fM", x / 1_000_000)
    case 1_000...:         return String(format: "$%.1fK", x / 1_000)
    default:               return formatUSD(x)
    }
}

/// "$12,400.00". US separators regardless of the system locale: the UI is English and the
/// compact amounts ("$3.40M") use a decimal point, so a locale such as en_BG would show
/// "$12 400,00" next to them.
/// "18.0%" from a fraction (0.18).
func formatPercent(_ fraction: Double) -> String {
    String(format: "%.1f%%", fraction * 100)
}

func formatUSD(_ x: Double) -> String {
    x.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US")))
}

private func trimNum(_ x: Double) -> String {
    var s = String(format: "%.6f", x)
    while s.hasSuffix("0") { s = String(s.dropLast()) }
    if s.hasSuffix(".") { s = String(s.dropLast()) }
    return s
}
