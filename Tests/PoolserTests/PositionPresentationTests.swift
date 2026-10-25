import Foundation
import Testing
@testable import Poolser

private func makePosition(
    sym0: String = "WBTC", sym1: String = "WETH", dec0: Int = 18, dec1: Int = 18,
    lower: Int = 0, upper: Int = 1_000, tick: Int? = 500
) -> Position {
    var pos = Position(
        chainID: "ethereum", chainName: "Ethereum", chainNumericID: 1, tokenId: "1",
        token0: "0x0", token1: "0x1", sym0: sym0, sym1: sym1,
        feePct: "0.3", feeRaw: 3_000, fees0: 0, fees1: 0,
        tickLower: lower, tickUpper: upper, liquidity: 1
    )
    pos.dec0 = dec0
    pos.dec1 = dec1
    pos.currentTick = tick
    pos.inRange = tick.map { Position.isInRange(tick: $0, lower: lower, upper: upper) }
    return pos
}

@Suite("Price orientation")
struct PriceOrientationTests {
    @Test(arguments: [
        ("USDC", "WETH", true),
        ("WETH", "USDC", false),
        ("WBTC", "WETH", false),
        ("UNI", "WETH", false),
        ("PEPE", "UNI", false),
    ])
    func quoteTokenPricesTheOther(sym0: String, sym1: String, inverted: Bool) {
        #expect(PositionPresentation.showsInverted(sym0: sym0, sym1: sym1) == inverted)
    }

    @Test func invertedPairReadsInTheStablecoin() {
        // WETH per USDC at 1/3544, as a USDC/WETH pool stores it.
        let tick = Int((log(1 / 3_544.0) - Double(6 - 18) * log(10)) / log(1.0001))
        let info = PositionPresentation(makePosition(sym0: "USDC", sym1: "WETH", dec0: 6, dec1: 18,
                                                     lower: tick - 1_000, upper: tick + 1_000, tick: tick))
        #expect(info.pairLabel == "WETH/USDC")
        #expect(info.currentPrice == "3,544")
    }
}

@Suite("Range status")
struct RangeStatusTests {
    @Test(arguments: [
        (500, RangeStatus.inRange),
        (50, .nearMin),
        (950, .nearMax),
        (-1, .outOfRange),
        (1_000, .outOfRange),  // tickUpper itself is out of range
    ])
    func status(tick: Int, expected: RangeStatus) {
        #expect(PositionPresentation(makePosition(tick: tick)).status == expected)
    }

    @Test func invertedPairSwapsNearMinAndMax() {
        let pos = makePosition(sym0: "USDC", sym1: "WETH", tick: 50)
        #expect(PositionPresentation(pos).status == .nearMax)
    }

    @Test func fullRangeAndErrors() {
        #expect(PositionPresentation(makePosition(lower: -887_220, upper: 887_220, tick: 10)).status == .fullRange)
        var failed = makePosition()
        failed.error = "boom"
        #expect(PositionPresentation(failed).status == .unknown)
    }

    @Test func poolStateErrorHidesPriceAndGauge() {
        var pos = makePosition()
        pos.poolStateError = "timeout"
        let info = PositionPresentation(pos)
        #expect(info.currentPrice == nil)
        #expect(info.gauge == nil)
    }

    @Test func distanceFollowsDisplayedDirection() {
        // ~4.2% below the lower tick.
        let diff = Int((log(1.042) / log(1.0001)).rounded())
        #expect(PositionPresentation.distanceLabel(tick: -diff, lower: 0, upper: 1_000, inverted: false) == "4.2% below")
        #expect(PositionPresentation.distanceLabel(tick: -diff, lower: 0, upper: 1_000, inverted: true) == "4.2% above")
        #expect(PositionPresentation.distanceLabel(tick: 200_000, lower: 0, upper: 1_000, inverted: false) == "far above")
    }
}

@Suite("Range gauge layout")
struct RangeGaugeLayoutTests {
    @Test func centredPositionPadsBothSides() {
        let layout = RangeGaugeLayout(lower: 0, upper: 100, current: 50)
        #expect(abs(layout.bandStart - 10.0 / 120) < 1e-9)
        #expect(abs(layout.bandEnd - 110.0 / 120) < 1e-9)
        #expect(abs(layout.marker - 0.5) < 1e-9)
        #expect(!layout.isMarkerClamped)
    }

    @Test func distantPriceIsClampedToTheEdge() {
        let layout = RangeGaugeLayout(lower: 0, upper: 100, current: -1_000)
        #expect(layout.marker == 0)
        #expect(layout.isMarkerClamped)
        // The window stops 1.5 range widths out, so the band keeps a readable width.
        #expect(layout.bandEnd - layout.bandStart > 0.3)
    }

    @Test func mirroringFlipsAroundTheCentre() {
        let layout = RangeGaugeLayout(bandStart: 0.2, bandEnd: 0.6, marker: 0.3, isMarkerClamped: false)
        let mirrored = layout.mirrored()
        #expect(abs(mirrored.bandStart - 0.4) < 1e-9)
        #expect(abs(mirrored.bandEnd - 0.8) < 1e-9)
        #expect(abs(mirrored.marker - 0.7) < 1e-9)
    }
}

@Suite("Menu bar title")
struct MenuBarTitleTests {
    @Test func valueThenFees() {
        #expect(MenuBarTitle.text(valueUSD: 48_213.40, feesUSD: 312.58, outOfRange: false) == "$48.2k │ $312.58")
    }

    @Test func trendAndWarningAreAppended() {
        #expect(MenuBarTitle.text(valueUSD: 48_213.40, feesUSD: 312.58, outOfRange: true, trend: "🔼")
                == "$48.2k │ $312.58 🔼 ⚠︎")
    }

    @Test func onlyRangedPositionsCountAsOutOfRange() {
        let inRange = makePosition(tick: 500)
        let out = makePosition(tick: -1)
        let fullRange = makePosition(lower: -887_220, upper: 887_220, tick: 10)
        var failed = makePosition(tick: -1)
        failed.error = "boom"
        #expect(!MenuBarTitle.hasOutOfRange([inRange, fullRange, failed]))
        #expect(MenuBarTitle.hasOutOfRange([inRange, out]))
    }
}

@Suite("Presentation formatting")
struct PresentationFormattingTests {
    @Test(arguments: [
        (3_544.2, "3,544"),
        (25.957, "25.96"),
        (0.0020612, "0.002061"),
        (0, "0"),
    ])
    func price(value: Double, expected: String) {
        #expect(PositionPresentation.formatPrice(value) == expected)
    }

    @Test(arguments: [
        (48_213.40, "$48.2k"),
        (4_611.33, "$4.61k"),
        (312.58, "$313"),
        (1_260_000, "$1.3M"),
    ])
    func compactUSD(value: Double, expected: String) {
        #expect(PositionPresentation.compactUSD(value) == expected)
    }
}
