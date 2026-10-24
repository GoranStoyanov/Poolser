import Testing
@testable import Poolser

@Suite("USD formatting")
struct USDFormatTests {
    @Test(arguments: [
        (0.0, "$0.00"),
        (2.1, "$2.10"),
        (999.999, "$1,000.00"),
        (12_400, "$12,400.00"),
        (1_234_567.891, "$1,234,567.89"),
    ])
    func groupsThousandsWithTwoDecimals(value: Double, expected: String) {
        #expect(formatUSD(value) == expected)
    }

    @Test func positionLabelsUseGrouping() {
        var p = Position(
            chainID: "ethereum", chainName: "Ethereum", chainNumericID: 1,
            tokenId: "1", token0: "", token1: "",
            sym0: "A", sym1: "B", feePct: "0.05", feeRaw: 500,
            fees0: 0, fees1: 0, tickLower: -100, tickUpper: 100,
            liquidity: 1
        )
        p.positionUSD = 12_400
        p.usd = 1_520.5
        p.claimedUSD = 3_000
        p.volumeUSD24h = 640
        #expect(p.positionUSDLabel == "$12,400.00")
        #expect(p.feesUSDLabel == "$1,520.50")
        #expect(p.claimedUSDLabel == "$3,000.00")
        #expect(p.volumeLabel == "Vol(24h): $640.00")
    }
}
