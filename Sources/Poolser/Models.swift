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
    var id: String { "\(chainID)-\(tokenId)" }
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
    var positionUSD: Double?  // total position liquidity value in USD
    var claimedFees0: Double = 0
    var claimedFees1: Double = 0
    var claimedUSD: Double? = nil
    var feeHistoryBootstrapping: Bool = false
    var currentTick: Int?
    var inRange: Bool?
    var error: String?
    // v4-specific
    var isV4: Bool = false
    var poolId: Data? = nil   // keccak256(PoolKey) — used for StateView queries
    var feesError: String? = nil  // set when fee computation fails
    // pool stats (GeckoTerminal)
    var poolAddress: String? = nil  // v3 pool contract address
    var volumeUSD24h: Double? = nil
    var feeAPR: Double? = nil
    var tvlUSD: Double? = nil

    var isFullRange: Bool {
        tickLower <= -887200 && tickUpper >= 887200
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
        return String(format: "$%.2f", usd)
    }


    var claimedUSDLabel: String? {
        guard let usd = claimedUSD, usd > 0 else { return nil }
        return String(format: "$%.2f", usd)
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
        return String(format: "$%.2f", positionUSD)
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

    /// Current token amounts held in the position, e.g. "0.05 WBTC + 1,200 USDC".
    var distributionLabel: String {
        var parts: [String] = []
        if amount0 > 0 { parts.append(trimNum(amount0) + " " + sym0) }
        if amount1 > 0 { parts.append(trimNum(amount1) + " " + sym1) }
        return parts.joined(separator: " + ")
    }

    var amount0Label: String { amount0 > 0 ? trimNum(amount0) : "0" }
    var amount1Label: String { amount1 > 0 ? trimNum(amount1) : "0" }
}

private func formatCompact(_ x: Double) -> String {
    switch x {
    case 1_000_000_000...: return String(format: "$%.2fB", x / 1_000_000_000)
    case 1_000_000...:     return String(format: "$%.2fM", x / 1_000_000)
    case 1_000...:         return String(format: "$%.1fK", x / 1_000)
    default:               return String(format: "$%.2f", x)
    }
}

private func trimNum(_ x: Double) -> String {
    var s = String(format: "%.6f", x)
    while s.hasSuffix("0") { s = String(s.dropLast()) }
    if s.hasSuffix(".") { s = String(s.dropLast()) }
    return s
}
