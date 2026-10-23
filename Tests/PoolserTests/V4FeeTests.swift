import Foundation
import Testing
@testable import Poolser

@Suite("V4Fee")
struct V4FeeTests {
    @Test("Static fee tiers render as percent", arguments: [
        (0, "0"), (100, "0.01"), (500, "0.05"), (3000, "0.3"), (10_000, "1"),
    ])
    func staticLabel(fee: Int, expected: String) {
        #expect(!V4Fee.isDynamic(fee))
        #expect(V4Fee.label(fee) == expected)
    }

    @Test func dynamicFlagRendersAsDyn() {
        #expect(V4Fee.isDynamic(0x800000))
        #expect(V4Fee.label(0x800000) == "dyn")
    }

    @Test func dynamicV4PoolHasNoFeeFraction() {
        #expect(position(feeRaw: 0x800000, isV4: true).feeFraction == nil)
    }

    @Test func zeroFeeV4PoolIsStatic() {
        #expect(position(feeRaw: 0, isV4: true).feeFraction == 0)
    }

    @Test func v3FeeFractionUnchanged() {
        #expect(position(feeRaw: 3000, isV4: false).feeFraction == 0.003)
        #expect(position(feeRaw: 500, isV4: true).feeFraction == 0.0005)
    }

    @Test func unknownFeeSkipsAPRButKeepsVolumeAndTVL() throws {
        let json = #"{"data":{"attributes":{"volume_usd":{"h24":"500000"},"reserve_in_usd":"1000000"}}}"#
        let service = PoolStatsService()

        let dynamic = try #require(service.parse(data: Data(json.utf8), feePct: nil))
        #expect(dynamic.feeAPR == nil)
        #expect(dynamic.volumeUSD24h == 500_000)
        #expect(dynamic.tvlUSD == 1_000_000)

        let stat = try #require(service.parse(data: Data(json.utf8), feePct: 0.003))
        let apr = try #require(stat.feeAPR)
        #expect(abs(apr - 54.75) < 1e-9)
    }

    private func position(feeRaw: Int, isV4: Bool) -> Position {
        Position(
            chainID: "test", chainName: "Test", chainNumericID: 1, tokenId: "1",
            token0: "0x0", token1: "0x1", sym0: "A", sym1: "B",
            feePct: V4Fee.label(feeRaw), feeRaw: feeRaw,
            fees0: 0, fees1: 0, tickLower: 0, tickUpper: 0, liquidity: 0,
            isV4: isV4
        )
    }
}
