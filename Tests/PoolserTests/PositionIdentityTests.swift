import Testing
@testable import PoolserKit

private func makePosition(
    chainID: String = "ethereum",
    tokenId: String = "123456",
    isV4: Bool,
    inRange: Bool? = true,
    error: String? = nil
) -> Position {
    Position(
        chainID: chainID, chainName: "Ethereum", chainNumericID: 1,
        tokenId: tokenId, token0: "", token1: "",
        sym0: "A", sym1: "B", feePct: "0.05", feeRaw: 500,
        fees0: 0, fees1: 0, tickLower: -100, tickUpper: 100,
        liquidity: 1,
        inRange: inRange,
        error: error,
        isV4: isV4
    )
}

@Suite("Position identity")
struct PositionIdentityTests {
    @Test func v3AndV4WithSameTokenIdHaveDistinctIDs() {
        let v3 = makePosition(isV4: false)
        let v4 = makePosition(isV4: true)
        #expect(v3.id == "ethereum-v3-123456")
        #expect(v4.id == "ethereum-v4-123456")
        #expect(v3.id != v4.id)
        #expect(v3.legacyID == v4.legacyID)
    }

    @Test func sameVersionAndTokenOnDifferentChainsDiffer() {
        #expect(makePosition(chainID: "ethereum", isV4: true).id != makePosition(chainID: "base", isV4: true).id)
    }
}

@Suite("Range notification state")
struct RangeNotificationStateTests {
    @Test func v3AndV4WithSameTokenIdAreTrackedIndependently() {
        let v3 = makePosition(isV4: false, inRange: true)
        let v4 = makePosition(isV4: true, inRange: false)

        let first = NotificationService.rangeChanges(for: [v3, v4], previous: [:])
        #expect(first.next == ["ethereum-v3-123456": true, "ethereum-v4-123456": false])
        #expect(first.changes.isEmpty)

        // Same statuses, reversed order: no flip-flopping between the two.
        let second = NotificationService.rangeChanges(for: [v4, v3], previous: first.next)
        #expect(second.next == first.next)
        #expect(second.changes.isEmpty)

        // Only the v4 position changes.
        let v4Back = makePosition(isV4: true, inRange: true)
        let third = NotificationService.rangeChanges(for: [v3, v4Back], previous: second.next)
        #expect(third.changes.map(\.position.id) == ["ethereum-v4-123456"])
        #expect(third.changes.first?.inRange == true)
    }

    @Test func legacyKeyIsUsedForUnambiguousPositions() {
        let previous = ["ethereum-123456": true, "base-42": false]
        let unchanged = makePosition(isV4: false, inRange: true)
        let flipped = makePosition(chainID: "base", tokenId: "42", isV4: true, inRange: true)

        let result = NotificationService.rangeChanges(for: [unchanged, flipped], previous: previous)

        #expect(result.changes.map(\.position.id) == ["base-v4-42"])
        // Legacy keys are dropped once rewritten in the new format.
        #expect(result.next == ["ethereum-v3-123456": true, "base-v4-42": true])
    }

    @Test func ambiguousLegacyKeyFiresNothing() {
        // Old state stored only whichever of the two colliding positions was written last.
        let previous = ["ethereum-123456": false]
        let v3 = makePosition(isV4: false, inRange: true)
        let v4 = makePosition(isV4: true, inRange: false)

        let result = NotificationService.rangeChanges(for: [v3, v4], previous: previous)

        #expect(result.changes.isEmpty)
        #expect(result.next == ["ethereum-v3-123456": true, "ethereum-v4-123456": false])
    }

    @Test func newKeyTakesPrecedenceOverLegacyKey() {
        let previous = ["ethereum-v3-123456": true, "ethereum-123456": false]
        let result = NotificationService.rangeChanges(
            for: [makePosition(isV4: false, inRange: true)],
            previous: previous
        )
        #expect(result.changes.isEmpty)
    }

    @Test func errorAndUnknownRangePositionsAreSkipped() {
        let previous = ["ethereum-v3-1": true, "ethereum-v3-2": true]
        let errored = makePosition(tokenId: "1", isV4: false, inRange: false, error: "boom")
        let unknown = makePosition(tokenId: "2", isV4: false, inRange: nil)

        let result = NotificationService.rangeChanges(for: [errored, unknown], previous: previous)

        #expect(result.changes.isEmpty)
        #expect(result.next.isEmpty)
    }
}
