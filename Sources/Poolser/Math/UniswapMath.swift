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

    let fg0Inside = feeGrowthInside(global: fg0Global, outsideLower: fg0OutLo, outsideUpper: fg0OutHi,
                                    currentTick: currentTick, tickLower: tickLower, tickUpper: tickUpper)
    let fg1Inside = feeGrowthInside(global: fg1Global, outsideLower: fg1OutLo, outsideUpper: fg1OutHi,
                                    currentTick: currentTick, tickLower: tickLower, tickUpper: tickUpper)

    // Delta since last collection (wrapping — handles the fgInside < fgLast case gracefully)
    let delta0 = u256Sub(fg0Inside, fg0Last)
    let delta1 = u256Sub(fg1Inside, fg1Last)

    // Only now convert to Double — the delta is small (fees since last touch) so precision is fine.
    // unclaimed = (fgInsideDelta × liquidity) ÷ 2¹²⁸
    let fees0 = u256ToDouble(delta0) * liquidityRaw / pow(2.0, 128)
    let fees1 = u256ToDouble(delta1) * liquidityRaw / pow(2.0, 128)
    return (fees0: fees0, fees1: fees1)
}

// MARK: - Fee growth inside a range

/// Standard feeGrowthInside = global − feeGrowthBelow(lower) − feeGrowthAbove(upper), for one
/// token, from the ticks' feeGrowthOutside. All subtractions wrap mod 2^256, matching Solidity
/// unchecked arithmetic.
func feeGrowthInside(
    global: Data, outsideLower: Data, outsideUpper: Data,
    currentTick: Int, tickLower: Int, tickUpper: Int
) -> Data {
    let below = currentTick >= tickLower ? outsideLower : u256Sub(global, outsideLower)
    let above = currentTick <  tickUpper ? outsideUpper : u256Sub(global, outsideUpper)
    return u256Sub(u256Sub(global, below), above)
}

/// A v3 position's fee state at one block. Two of them tell what the position earned in
/// between without Collect events: collect() moves owed tokens, never fee growth.
struct FeeGrowthSnapshot: Codable, Equatable {
    var liquidity: Double
    var inside0: Data
    var inside1: Data
    /// feeGrowthInside when the position's liquidity last changed or it last collected.
    var insideLast0: Data
    var insideLast1: Data

    /// Raw token amounts earned since `start`; a nil `start` means the position was minted in
    /// between. With one liquidity change in between, `insideLast` marks when it happened: the
    /// new liquidity earned after it and the old one before. A collect after that change moves
    /// `insideLast` too, so that rare case is approximate.
    func earned(since start: FeeGrowthSnapshot?) -> (amount0: Double, amount1: Double) {
        guard let start else {
            return (Self.grown(from: insideLast0, to: inside0, liquidity: liquidity),
                    Self.grown(from: insideLast1, to: inside1, liquidity: liquidity))
        }
        if start.liquidity == liquidity {
            return (Self.grown(from: start.inside0, to: inside0, liquidity: liquidity),
                    Self.grown(from: start.inside1, to: inside1, liquidity: liquidity))
        }
        return (
            Self.grown(from: insideLast0, to: inside0, liquidity: liquidity)
                + Self.grown(from: start.inside0, to: insideLast0, liquidity: start.liquidity),
            Self.grown(from: insideLast1, to: inside1, liquidity: liquidity)
                + Self.grown(from: start.inside1, to: insideLast1, liquidity: start.liquidity)
        )
    }

    /// liquidity × Δgrowth ÷ 2¹²⁸. A delta with the top bit set is a "negative" one: the two
    /// reads do not describe the same accumulator (e.g. a tick was cleared and re-initialised),
    /// so it counts as nothing rather than as an enormous amount.
    private static func grown(from start: Data, to end: Data, liquidity: Double) -> Double {
        guard liquidity > 0 else { return 0 }
        let delta = u256Sub(end, start)
        guard let top = delta.first, top < 0x80 else { return 0 }
        return u256ToDouble(delta) * liquidity / pow(2.0, 128)
    }
}

extension FeeGrowthSnapshot {
    /// From a NonfungiblePositionManager positions() result and the pool's slot0(),
    /// feeGrowthGlobal0X128(), feeGrowthGlobal1X128() and ticks() at both ends of the range,
    /// all read at the same block.
    init?(positions pos: Data, slot0: Data, global0: Data, global1: Data, lowerTick: Data, upperTick: Data) {
        guard pos.count >= 12 * 32, slot0.count >= 64, global0.count >= 32, global1.count >= 32,
              lowerTick.count >= 128, upperTick.count >= 128 else { return nil }
        // positions(): word 5 tickLower, 6 tickUpper, 7 liquidity, 8–9 feeGrowthInside{0,1}LastX128.
        // ticks(): word 2–3 feeGrowthOutside{0,1}X128.
        let tickLower = pos.readInt24(wordAt: 160)
        let tickUpper = pos.readInt24(wordAt: 192)
        let tick = slot0.readInt24(wordAt: 32)
        liquidity = pos.readAmount(wordAt: 224, decimals: 0)
        insideLast0 = pos.readWord(at: 256)
        insideLast1 = pos.readWord(at: 288)
        inside0 = feeGrowthInside(
            global: global0.readWord(at: 0), outsideLower: lowerTick.readWord(at: 64), outsideUpper: upperTick.readWord(at: 64),
            currentTick: tick, tickLower: tickLower, tickUpper: tickUpper
        )
        inside1 = feeGrowthInside(
            global: global1.readWord(at: 0), outsideLower: lowerTick.readWord(at: 96), outsideUpper: upperTick.readWord(at: 96),
            currentTick: tick, tickLower: tickLower, tickUpper: tickUpper
        )
    }
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
