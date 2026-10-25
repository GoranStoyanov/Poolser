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
