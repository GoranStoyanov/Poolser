import Testing
@testable import Poolser

@Suite("Position in-range check")
struct PositionRangeTests {
    @Test(arguments: [
        (-201, false),
        (-200, true),   // lower bound is inclusive
        (0, true),
        (199, true),
        (200, false),   // upper bound is exclusive: token1 only, no fees
        (201, false),
    ])
    func boundaries(tick: Int, expected: Bool) {
        #expect(Position.isInRange(tick: tick, lower: -200, upper: 200) == expected)
    }

    @Test func singleTickSpacingRange() {
        #expect(Position.isInRange(tick: 60, lower: 60, upper: 120))
        #expect(Position.isInRange(tick: 119, lower: 60, upper: 120))
        #expect(!Position.isInRange(tick: 120, lower: 60, upper: 120))
    }
}

@Suite("Range bar label order")
struct RangeBarLabelOrderTests {
    @Test(arguments: [
        (-900, [TickRangeBar.LabelSlot.current, .lower, .upper]),  // below the range
        (-600, [.lower, .current, .upper]),                        // lower bound is in range
        (10, [.lower, .current, .upper]),
        (600, [.lower, .upper, .current]),                         // upper bound is out of range
        (900, [.lower, .upper, .current]),
    ])
    func currentTickSitsOnItsSide(tick: Int, expected: [TickRangeBar.LabelSlot]) {
        #expect(TickRangeBar.labelOrder(tick: tick, lower: -600, upper: 600) == expected)
    }
}
