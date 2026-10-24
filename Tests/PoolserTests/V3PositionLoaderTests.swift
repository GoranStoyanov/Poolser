import Foundation
import Testing
@testable import Poolser

private let wallet = "0x1111111111111111111111111111111111111111"
private let usdc   = "0x00000000000000000000000000000000000000a0"
private let weth   = "0x00000000000000000000000000000000000000a1"
private let odd    = "0x00000000000000000000000000000000000000a2"
private let pool1  = "0x00000000000000000000000000000000000000b1"
private let pool2  = "0x00000000000000000000000000000000000000b2"

private func abiString(_ s: String) -> Data {
    let bytes = Data(s.utf8)
    return word(32) + word(bytes.count) + padded(bytes)
}

/// positions() result: nonce, operator, token0, token1, fee, ticks, liquidity, fee growth, owed.
private func positionsResult(_ token0: String, _ token1: String, fee: Int, lower: Int, upper: Int, liquidity: UInt64) -> Data {
    let words: [Data] = [
        word(0), word(0), ABI.encodeAddress(token0), ABI.encodeAddress(token1), word(fee),
        ABI.encodeInt24(lower), ABI.encodeInt24(upper), ABI.encodeUInt256(liquidity),
        word(0), word(0), word(0), word(0),
    ]
    return words.reduce(Data(), +)
}

/// slot0() with sqrtPriceX96 = 2^96 (price 1) and the given tick.
private func slot0Result(tick: Int) -> Data {
    var sqrtPrice = Data(count: 32)
    sqrtPrice[19] = 1
    return sqrtPrice + ABI.encodeInt24(tick) + Data(count: 32 * 5)
}

/// A wallet with five v3 positions on Base:
/// - #11 USDC/WETH 0.05%, in range; #12 same pool, out of range, collect() needs an
///   authorized msg.sender (as on mainnet), so it only works as a plain eth_call
/// - index 2: tokenOfOwnerByIndex reverts → error row
/// - #13 USDC/ODD 0.3%: ODD's symbol() reverts and the pool's slot0() reverts
/// - #14 closed with nothing owed → skipped
private func makeChain(_ chain: SupportedChain) async -> FakeChain {
    let fake = FakeChain()
    let nfpm = chain.v3NFPM!, factory = chain.v3Factory!
    await fake.set(nfpm, ABI.callBalanceOf(owner: wallet), .value(word(5)))
    for (index, tokenId) in [0: 11, 1: 12, 3: 13, 4: 14] {
        await fake.set(nfpm, ABI.callTokenOfOwnerByIndex(owner: wallet, index: UInt64(index)), .value(word(tokenId)))
    }
    await fake.set(nfpm, ABI.callTokenOfOwnerByIndex(owner: wallet, index: 2), .revert("boom"))

    await fake.set(nfpm, ABI.callPositions(tokenId: 11), .value(positionsResult(usdc, weth, fee: 500, lower: -100, upper: 100, liquidity: 1_000_000_000_000)))
    await fake.set(nfpm, ABI.callPositions(tokenId: 12), .value(positionsResult(usdc, weth, fee: 500, lower: 200, upper: 300, liquidity: 500_000_000_000)))
    await fake.set(nfpm, ABI.callPositions(tokenId: 13), .value(positionsResult(usdc, odd, fee: 3000, lower: -60, upper: 60, liquidity: 2_000_000_000_000)))
    await fake.set(nfpm, ABI.callPositions(tokenId: 14), .value(positionsResult(weth, odd, fee: 3000, lower: -60, upper: 60, liquidity: 0)))

    await fake.set(nfpm, ABI.callCollectStatic(tokenId: 11, recipient: wallet), .value(word(1_500_000) + word(2_000_000_000_000_000)), checksSender: true)
    await fake.set(nfpm, ABI.callCollectStatic(tokenId: 12, recipient: wallet), .value(word(250_000) + word(0)), checksSender: true)
    await fake.set(nfpm, ABI.callCollectStatic(tokenId: 13, recipient: wallet), .value(word(0) + word(300_000_000)), checksSender: true)
    await fake.set(nfpm, ABI.callCollectStatic(tokenId: 14, recipient: wallet), .value(word(0) + word(0)), checksSender: true)

    await fake.set(factory, ABI.callGetPool(token0: usdc, token1: weth, fee: 500), .value(ABI.encodeAddress(pool1)))
    await fake.set(factory, ABI.callGetPool(token0: usdc, token1: odd, fee: 3000), .value(ABI.encodeAddress(pool2)))
    await fake.set(pool1, ABI.callSlot0(), .value(slot0Result(tick: 50)))
    await fake.set(pool2, ABI.callSlot0(), .revert("locked"))

    await fake.set(usdc, ABI.callSymbol(), .value(abiString("USDC")))
    await fake.set(usdc, ABI.callDecimals(), .value(word(6)))
    await fake.set(weth, ABI.callSymbol(), .value(abiString("WETH")))
    await fake.set(weth, ABI.callDecimals(), .value(word(18)))
    await fake.set(odd, ABI.callSymbol(), .revert("no symbol"))
    await fake.set(odd, ABI.callDecimals(), .value(word(8)))
    return fake
}

private func prices() -> PriceService {
    PriceService(fetcher: { _, _, _ in [usdc: 1.0, weth: 3000.0] })
}

private func snapshot(_ p: Position) -> String {
    let fields: [String] = [
        p.tokenId, p.sym0, p.sym1, p.feePct, "\(p.fees0)", "\(p.fees1)", "\(p.dec0)", "\(p.dec1)",
        "\(p.tickLower)", "\(p.tickUpper)", "\(p.liquidity)", "\(String(describing: p.currentTick))",
        "\(String(describing: p.inRange))", p.poolAddress ?? "-", "\(p.amount0)", "\(p.amount1)",
        "\(String(describing: p.usd))", p.error ?? "-",
    ]
    return fields.joined(separator: " ")
}

@Suite("V3PositionLoader")
struct V3PositionLoaderTests {
    private func load(multicall3: String?) async -> (LoaderOutput, [FakeChain.Request]) {
        var chain = SupportedChain.byID("base")!
        chain.multicall3 = multicall3
        let fake = await makeChain(chain)
        let output = await V3PositionLoader(
            eth: fake.client(), chain: chain, prices: prices(), trackClaimedFees: false
        ).load(wallet: wallet)
        return (output, await fake.requests)
    }

    @Test func multicallAndPerCallPathsLoadTheSamePositions() async throws {
        let (batched, batchedRequests) = await load(multicall3: SupportedChain.canonicalMulticall3)
        let (single, singleRequests) = await load(multicall3: nil)

        #expect(batched.positions.map(snapshot) == single.positions.map(snapshot))
        #expect(batched.feesUSD == single.feesUSD)
        #expect(batched.error == nil && single.error == nil)

        // balanceOf, tokenOfOwnerByIndex, positions, tokens+pools, slot0, plus 4 collect()s.
        #expect(batchedRequests.count == 9)
        // balanceOf, 5 tokenOfOwnerByIndex, 4 positions, 6 symbol/decimals, 3 getPool (one per
        // distinct pool), 4 collect, 2 slot0.
        #expect(singleRequests.count == 25)
    }

    @Test func degradedReadsAffectOnlyTheirOwnPosition() async throws {
        let (output, requests) = await load(multicall3: SupportedChain.canonicalMulticall3)
        let byId = Dictionary(uniqueKeysWithValues: output.positions.map { ($0.tokenId, $0) })

        #expect(output.positions.map(\.tokenId) == ["11", "12", "err-2", "13"])

        let inRange = try #require(byId["11"])
        #expect(inRange.sym0 == "USDC" && inRange.sym1 == "WETH")
        #expect(inRange.fees0 == 1.5 && inRange.fees1 == 0.002)
        #expect(inRange.inRange == true && inRange.currentTick == 50)
        #expect(inRange.poolAddress == pool1)
        #expect(inRange.usd == 1.5 + 0.002 * 3000)

        #expect(byId["12"]?.inRange == false)
        #expect(byId["12"]?.fees0 == 0.25)

        let failed = try #require(byId["err-2"])
        #expect(failed.error == "RPC: execution reverted: boom")

        let degraded = try #require(byId["13"])
        #expect(degraded.sym1 == "0x0000…00a2")
        #expect(degraded.dec1 == 8)
        #expect(degraded.fees1 == 3.0)
        #expect(degraded.inRange == nil && degraded.poolAddress == nil)

        // collect() never goes through Multicall3: from there it reverts with "Not approved".
        let collect = ABI.callCollectStatic(tokenId: 11, recipient: wallet).prefix(4)
        #expect(requests.filter { $0.data.prefix(4) == collect }.allSatisfy { $0.subcalls == nil })
    }
}
