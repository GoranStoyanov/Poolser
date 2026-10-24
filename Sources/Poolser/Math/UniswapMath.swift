import Foundation

// MARK: - Position amounts

/// Standard Uniswap v3/v4 amount calculation from sqrtPrice and liquidity.
func computeAmounts(
    position p: inout Position,
    sqrtPrice: Double,
    metaCache: [String: TokenMetadata],
    priceMap: [String: Double]
) {
    guard p.liquidity > 0, sqrtPrice > 0 else { return }
    let dec0 = metaCache[p.token0.lowercased()]?.decimals ?? 18
    let dec1 = metaCache[p.token1.lowercased()]?.decimals ?? 18
    let half = log(1.0001) / 2.0
    let sqrtLower = exp(Double(p.tickLower) * half)
    let sqrtUpper = exp(Double(p.tickUpper) * half)
    let L = p.liquidity
    var raw0 = 0.0, raw1 = 0.0
    if sqrtPrice <= sqrtLower {
        raw0 = L * (1.0 / sqrtLower - 1.0 / sqrtUpper)
    } else if sqrtPrice >= sqrtUpper {
        raw1 = L * (sqrtUpper - sqrtLower)
    } else {
        raw0 = L * (1.0 / sqrtPrice - 1.0 / sqrtUpper)
        raw1 = L * (sqrtPrice - sqrtLower)
    }
    p.amount0 = raw0 / pow(10.0, Double(dec0))
    p.amount1 = raw1 / pow(10.0, Double(dec1))

    var posUSD = 0.0; var has = false
    if let px = priceMap[p.token0.lowercased()], p.amount0 > 0 { posUSD += p.amount0 * px; has = true }
    if let px = priceMap[p.token1.lowercased()], p.amount1 > 0 { posUSD += p.amount1 * px; has = true }
    if has { p.positionUSD = posUSD }
}

// MARK: - v4 unclaimed fees

/// Unclaimed v4 fees for one position using the standard Uniswap feeGrowthInside formula.
/// Takes the raw StateView responses of getPosition (≥ 96 B), getTickInfo for both range
/// ticks (≥ 128 B each) and getFeeGrowthGlobals (≥ 64 B); returns raw fee amounts (before
/// decimal conversion).
///
/// All feeGrowth arithmetic is done in exact uint256 (wrapping) to avoid catastrophic cancellation
/// when the accumulators are large (they can be ~2^150+ for active pools, which destroys double
/// precision if you subtract two nearly-equal large doubles).
func v4UnclaimedFees(
    position posD: Data,
    lowerTickInfo loD: Data,
    upperTickInfo hiD: Data,
    feeGrowthGlobals globD: Data,
    tickLower: Int, tickUpper: Int,
    currentTick: Int, liquidityRaw: Double
) -> (fees0: Double, fees1: Double) {
    // Read all feeGrowth values as exact 32-byte (uint256) words.
    // Do NOT use readAmount() here — those values are ~2^150+ for active pools,
    // causing catastrophic cancellation if converted to Double before subtraction.
    let fg0Last   = posD.readWord(at: 32)
    let fg1Last   = posD.readWord(at: 64)

    let fg0OutLo  = loD.readWord(at: 64)
    let fg1OutLo  = loD.readWord(at: 96)
    let fg0OutHi  = hiD.readWord(at: 64)
    let fg1OutHi  = hiD.readWord(at: 96)

    let fg0Global = globD.readWord(at: 0)
    let fg1Global = globD.readWord(at: 32)

    // Standard feeGrowthInside = global − feeGrowthBelow(lower) − feeGrowthAbove(upper)
    // All subtractions wrap mod 2^256, matching Solidity unchecked arithmetic.
    let fg0Below = currentTick >= tickLower ? fg0OutLo : u256Sub(fg0Global, fg0OutLo)
    let fg1Below = currentTick >= tickLower ? fg1OutLo : u256Sub(fg1Global, fg1OutLo)
    let fg0Above = currentTick <  tickUpper ? fg0OutHi : u256Sub(fg0Global, fg0OutHi)
    let fg1Above = currentTick <  tickUpper ? fg1OutHi : u256Sub(fg1Global, fg1OutHi)

    let fg0Inside = u256Sub(u256Sub(fg0Global, fg0Below), fg0Above)
    let fg1Inside = u256Sub(u256Sub(fg1Global, fg1Below), fg1Above)

    // Delta since last collection (wrapping — handles the fgInside < fgLast case gracefully)
    let delta0 = u256Sub(fg0Inside, fg0Last)
    let delta1 = u256Sub(fg1Inside, fg1Last)

    // Only now convert to Double — the delta is small (fees since last touch) so precision is fine.
    // unclaimed = (fgInsideDelta × liquidity) ÷ 2¹²⁸
    let fees0 = u256ToDouble(delta0) * liquidityRaw / pow(2.0, 128)
    let fees1 = u256ToDouble(delta1) * liquidityRaw / pow(2.0, 128)
    return (fees0: fees0, fees1: fees1)
}

// MARK: - Exact uint256 arithmetic (for feeGrowth accumulators)

/// Wrapping 256-bit subtraction (mod 2^256), matching Solidity `unchecked { a - b }`.
func u256Sub(_ a: Data, _ b: Data) -> Data {
    var r = [UInt8](repeating: 0, count: 32)
    var borrow: Int = 0
    for i in stride(from: 31, through: 0, by: -1) {
        let diff = Int(a[i]) - Int(b[i]) - borrow
        r[i] = UInt8((diff + 256) & 0xFF)
        borrow = diff < 0 ? 1 : 0
    }
    return Data(r)
}

/// Convert a 32-byte big-endian uint256 to Double.
/// Only call this on values known to be small (e.g. feeGrowth deltas), where precision loss is acceptable.
func u256ToDouble(_ d: Data) -> Double {
    var v = 0.0
    for byte in d { v = v * 256.0 + Double(byte) }
    return v
}
