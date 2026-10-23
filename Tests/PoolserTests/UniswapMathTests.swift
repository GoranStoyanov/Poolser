import Foundation
import Testing
@testable import Poolser

/// Two's-complement 256-bit word for a small signed value (negative values wrap mod 2^256).
private func u256(_ value: Int64) -> Data {
    var out = Data(repeating: value < 0 ? 0xff : 0x00, count: 32)
    for i in 0..<8 { out[31 - i] = UInt8(truncatingIfNeeded: value >> (8 * i)) }
    return out
}

@Suite("uint256 arithmetic")
struct U256Tests {
    @Test func zeroMinusOneWrapsToMax() {
        #expect(u256Sub(u256(0), u256(1)) == Data(repeating: 0xff, count: 32))
    }

    @Test func equalHighValuesSubtractToZero() {
        var half = Data(count: 32)
        half[0] = 0x80  // 2^255
        #expect(u256Sub(half, half) == Data(count: 32))
    }

    @Test func borrowPropagatesAcrossBytes() {
        var a = Data(count: 32)
        a[0] = 0x01  // 2^248
        var expected = Data(repeating: 0xff, count: 32)
        expected[0] = 0x00  // 2^248 - 1
        #expect(u256Sub(a, u256(1)) == expected)
        #expect(u256Sub(u256(1_000), u256(1)) == u256(999))
    }

    @Test func toDouble() {
        #expect(u256ToDouble(u256(0)) == 0)
        #expect(u256ToDouble(u256(123_456_789)) == 123_456_789)
        var big = Data(count: 32)
        big[15] = 0x01  // 2^128
        #expect(u256ToDouble(big) == pow(2.0, 128))
    }

    /// Mirrors the v4 feeGrowthInside computation: the intermediate values underflow, but
    /// Solidity's unchecked arithmetic still yields the right delta mod 2^256.
    @Test func feeGrowthInsideWrapsLikeSolidity() {
        let global = u256(100)
        let below = u256(150)  // outside value recorded when the tick was crossed, can exceed global
        let above = u256(20)
        let inside = u256Sub(u256Sub(global, below), above)
        #expect(inside == u256(-70))

        let last = u256(-100)  // the last snapshot wrapped too
        let delta = u256Sub(inside, last)
        #expect(delta == u256(30))
        #expect(u256ToDouble(delta) == 30)
    }
}

@Suite("Uniswap v4 pool identity")
struct V4PoolIdTests {
    private static let usdc = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
    private static let weth = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
    private static let zero = "0x0000000000000000000000000000000000000000"

    /// Mainnet ETH/USDC 0.05% pool (native ETH, tickSpacing 10, no hooks). StateView.getSlot0
    /// returns a non-zero sqrtPriceX96 for this id, so the pool is initialized on chain.
    @Test func nativeEthUsdcPool() {
        let id = ABI.computeV4PoolId(currency0: Self.zero, currency1: Self.usdc, fee: 500, tickSpacing: 10, hooks: Self.zero)
        #expect(id.hexString == "21c67e77068de97969ba93d4aab21826d33ca12bb9f565d8496e8fda8a82ca27")
    }

    @Test func wethUsdcPool() {
        let id = ABI.computeV4PoolId(currency0: Self.usdc, currency1: Self.weth, fee: 500, tickSpacing: 10, hooks: Self.zero)
        #expect(id.hexString == "4f88f7c99022eace4740c6898f59ce6a2e798a1e64ce54589720b7153eb224a7")
        let unprefixed = ABI.computeV4PoolId(
            currency0: String(Self.usdc.dropFirst(2)).lowercased(), currency1: String(Self.weth.dropFirst(2)),
            fee: 500, tickSpacing: 10, hooks: "0x0")
        #expect(unprefixed == id)
    }

    @Test func negativeTickSpacingIsSignExtended() {
        // Not a valid pool, but the encoding must match abi.encode(int24(-1)).
        let a = ABI.computeV4PoolId(currency0: Self.zero, currency1: Self.usdc, fee: 500, tickSpacing: -1, hooks: Self.zero)
        var input = Data(count: 160)
        input.replaceSubrange(32..<64, with: ABI.encodeAddress(Self.usdc))
        input.replaceSubrange(64..<96, with: ABI.encodeUInt256(500))
        input.replaceSubrange(96..<128, with: ABI.encodeInt24(-1))
        #expect(a == keccak256(input))
    }

    /// PositionManager.getPoolAndPositionInfo(1) on mainnet: the USDC/WETH 0.05% PoolKey followed by
    /// PositionInfo = [25 bytes poolId][tickUpper int24][tickLower int24][hasSubscriber byte].
    @Test func decodesRealGetPoolAndPositionInfo() throws {
        let response = try #require(Data(hexString:
            "000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
          + "000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"
          + "00000000000000000000000000000000000000000000000000000000000001f4"
          + "000000000000000000000000000000000000000000000000000000000000000a"
          + "0000000000000000000000000000000000000000000000000000000000000000"
          + "4f88f7c99022eace4740c6898f59ce6a2e798a1e64ce5458970d89e6f2761a00"))

        let currency0 = response.readAddress(wordAt: 0)
        let currency1 = response.readAddress(wordAt: 32)
        let fee = Int(response.readUInt64(wordAt: 64))
        let tickSpacing = response.readInt24(wordAt: 96)
        let hooks = response.readAddress(wordAt: 128)
        #expect(currency0 == Self.usdc.lowercased())
        #expect(currency1 == Self.weth.lowercased())
        #expect(fee == 500)
        #expect(tickSpacing == 10)
        #expect(hooks == Self.zero)

        // Same offsets loadV4 uses.
        #expect(response.readInt24At(byteOffset: 160 + 28) == -887_270)
        #expect(response.readInt24At(byteOffset: 160 + 25) == 887_270)

        let poolId = ABI.computeV4PoolId(currency0: currency0, currency1: currency1, fee: fee, tickSpacing: tickSpacing, hooks: hooks)
        #expect(poolId.prefix(25) == response.subdata(in: 160..<185))
    }

    @Test func positionInfoTicksIgnoreSubscriberFlag() throws {
        // tickUpper 887220 = 0x0d89b4, tickLower -887220 = 0xf2764c, hasSubscriber = 1
        let info = try #require(Data(hexString: String(repeating: "11", count: 25) + "0d89b4" + "f2764c" + "01"))
        #expect(info.readInt24At(byteOffset: 25) == 887_220)
        #expect(info.readInt24At(byteOffset: 28) == -887_220)
    }
}

@MainActor
@Suite("Position amounts")
struct ComputeAmountsTests {
    // Range [0, 13864]: sqrt(1.0001^0) = 1, sqrt(1.0001^13864) ≈ 2.0
    nonisolated private static let tickUpper = 13_864
    nonisolated private static let sqrtLower = 1.0
    nonisolated private static let sqrtUpper = pow(1.0001, Double(tickUpper) / 2)
    nonisolated private static let liquidity = 1e18

    private func amounts(
        sqrtPrice: Double,
        liquidity: Double = liquidity,
        meta: [String: (symbol: String, decimals: Int)] = [:],
        prices: [String: Double] = [:]
    ) -> Position {
        var p = Position(
            chainID: "test", chainName: "Test", chainNumericID: 1, tokenId: "1",
            token0: "0xAAAA", token1: "0xBBBB", sym0: "A", sym1: "B",
            feePct: "0.05", feeRaw: 500,
            fees0: 0, fees1: 0, tickLower: 0, tickUpper: Self.tickUpper, liquidity: liquidity
        )
        UniswapService.computeAmounts(position: &p, sqrtPrice: sqrtPrice, metaCache: meta, priceMap: prices)
        return p
    }

    private func close(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) <= 1e-9 * max(abs(a), abs(b))
    }

    @Test func belowRangeHoldsOnlyToken0() {
        let p = amounts(sqrtPrice: 0.5)
        let expected = Self.liquidity * (1 / Self.sqrtLower - 1 / Self.sqrtUpper) / 1e18
        #expect(close(p.amount0, expected))
        #expect(p.amount1 == 0)
    }

    @Test func aboveRangeHoldsOnlyToken1() {
        let p = amounts(sqrtPrice: 3)
        let expected = Self.liquidity * (Self.sqrtUpper - Self.sqrtLower) / 1e18
        #expect(p.amount0 == 0)
        #expect(close(p.amount1, expected))
    }

    @Test func inRangeHoldsBothTokens() {
        let s = 1.5
        let p = amounts(sqrtPrice: s)
        #expect(close(p.amount0, Self.liquidity * (1 / s - 1 / Self.sqrtUpper) / 1e18))
        #expect(close(p.amount1, Self.liquidity * (s - Self.sqrtLower) / 1e18))
    }

    @Test func appliesTokenDecimalsAndUSDPrices() throws {
        let meta: [String: (symbol: String, decimals: Int)] = ["0xaaaa": ("A", 6), "0xbbbb": ("B", 18)]
        let p = amounts(sqrtPrice: 1.5, meta: meta, prices: ["0xaaaa": 2, "0xbbbb": 3])
        let raw0 = Self.liquidity * (1 / 1.5 - 1 / Self.sqrtUpper)
        let raw1 = Self.liquidity * (1.5 - Self.sqrtLower)
        #expect(close(p.amount0, raw0 / 1e6))
        #expect(close(p.amount1, raw1 / 1e18))
        let usd = try #require(p.positionUSD)
        #expect(close(usd, p.amount0 * 2 + p.amount1 * 3))
    }

    @Test func missingPricesLeaveUSDUnset() {
        #expect(amounts(sqrtPrice: 1.5).positionUSD == nil)
    }

    @Test func zeroLiquidityOrPriceLeavesPositionUntouched() {
        let empty = amounts(sqrtPrice: 1.5, liquidity: 0)
        #expect(empty.amount0 == 0 && empty.amount1 == 0)
        let noPrice = amounts(sqrtPrice: 0)
        #expect(noPrice.amount0 == 0 && noPrice.amount1 == 0)
    }
}
