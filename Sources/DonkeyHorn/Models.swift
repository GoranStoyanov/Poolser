import Foundation

struct Position: Identifiable {
    var id: String { tokenId }
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
    var usd: Double?          // fees value in USD
    var positionUSD: Double?  // total position liquidity value in USD
    var currentTick: Int?
    var inRange: Bool?
    var error: String?
    // v4-specific
    var isV4: Bool = false
    var poolId: Data? = nil   // keccak256(PoolKey) — used for StateView queries
    var feesError: String? = nil  // set when fee computation fails

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

    var versionLabel: String { isV4 ? "v4" : "v3" }

    /// Total position liquidity value in USD, formatted.
    var positionUSDLabel: String? {
        guard let positionUSD, positionUSD > 0 else { return nil }
        return String(format: "$%.2f", positionUSD)
    }

    /// Current token amounts held in the position, e.g. "0.05 WBTC + 1,200 USDC".
    var distributionLabel: String {
        var parts: [String] = []
        if amount0 > 0 { parts.append(trimNum(amount0) + " " + sym0) }
        if amount1 > 0 { parts.append(trimNum(amount1) + " " + sym1) }
        return parts.joined(separator: " + ")
    }
}

private func trimNum(_ x: Double) -> String {
    var s = String(format: "%.6f", x)
    while s.hasSuffix("0") { s = String(s.dropLast()) }
    if s.hasSuffix(".") { s = String(s.dropLast()) }
    return s
}
