import Foundation
import Testing
@testable import PoolserKit

private func makePosition(
    _ tokenId: String,
    chainID: String = "ethereum",
    pair: (String, String) = ("A", "B"),
    isV4: Bool = false,
    ticks: (Int, Int) = (-100, 100),
    inRange: Bool? = true,
    value: Double? = nil,
    fees: Double? = nil,
    apr: Double? = nil,
    error: String? = nil
) -> Position {
    var p = Position(
        chainID: chainID, chainName: chainID, chainNumericID: 1,
        tokenId: tokenId, token0: "", token1: "",
        sym0: pair.0, sym1: pair.1, feePct: "0.05", feeRaw: 500,
        fees0: 0, fees1: 0, tickLower: ticks.0, tickUpper: ticks.1,
        liquidity: 1,
        inRange: inRange,
        error: error,
        isV4: isV4
    )
    p.positionUSD = value
    p.usd = fees
    p.feeAPR = apr
    return p
}

@Suite("Position list sorting")
struct PositionListSortTests {
    @Test func valueSortsLargestFirstWithUnpricedLast() {
        let positions = [
            makePosition("1", value: 10),
            makePosition("2"),
            makePosition("3", value: 300),
            makePosition("4", value: 50),
        ]
        let ids = PositionListOptions(sort: .value).apply(to: positions).map(\.tokenId)
        #expect(ids == ["3", "4", "1", "2"])
    }

    @Test func valueFallsBackToFeesWhenPositionValueIsMissing() {
        let positions = [makePosition("1", value: 5), makePosition("2", fees: 20)]
        #expect(PositionListOptions(sort: .value).apply(to: positions).map(\.tokenId) == ["2", "1"])
    }

    @Test func feesAndYieldSortDescending() {
        let positions = [
            makePosition("1", fees: 1, apr: 40),
            makePosition("2", fees: 9, apr: 5),
            makePosition("3", apr: 12),
        ]
        #expect(PositionListOptions(sort: .fees).apply(to: positions).map(\.tokenId) == ["2", "1", "3"])
        #expect(PositionListOptions(sort: .yield).apply(to: positions).map(\.tokenId) == ["1", "3", "2"])
    }

    @Test func pairSortsAlphabeticallyIgnoringCase() {
        let positions = [
            makePosition("1", pair: ("WETH", "USDC")),
            makePosition("2", pair: ("cbBTC", "WETH")),
            makePosition("3", pair: ("UNI", "WETH")),
        ]
        #expect(PositionListOptions(sort: .pair).apply(to: positions).map(\.tokenId) == ["2", "3", "1"])
    }

    @Test func tiesKeepLoadedOrder() {
        let positions = (1...6).map { makePosition(String($0), value: 100) }
        #expect(PositionListOptions(sort: .value).apply(to: positions).map(\.tokenId) == ["1", "2", "3", "4", "5", "6"])
    }
}

@Suite("Position list filtering")
struct PositionListFilterTests {
    @Test func inRangeOnlyKeepsInRangeAndFullRange() {
        let positions = [
            makePosition("in", inRange: true),
            makePosition("out", inRange: false),
            makePosition("unknown", inRange: nil),
            makePosition("full", ticks: (-887_272, 887_272), inRange: true),
            makePosition("broken", inRange: true, error: "read failed"),
        ]
        let ids = PositionListOptions(inRangeOnly: true).apply(to: positions).map(\.tokenId)
        #expect(ids == ["in", "full"])
    }

    @Test(arguments: [
        (PositionVersionFilter.all, ["1", "2"]),
        (.v3, ["1"]),
        (.v4, ["2"]),
    ])
    func versionFilter(version: PositionVersionFilter, expected: [String]) {
        let positions = [makePosition("1", isV4: false), makePosition("2", isV4: true)]
        #expect(PositionListOptions(version: version).apply(to: positions).map(\.tokenId) == expected)
    }

    @Test func chainFilter() {
        let positions = [makePosition("1", chainID: "ethereum"), makePosition("2", chainID: "base")]
        #expect(PositionListOptions(chainID: "base").apply(to: positions).map(\.tokenId) == ["2"])
    }

    @Test func filtersCombine() {
        let positions = [
            makePosition("1", chainID: "base", isV4: true, inRange: true),
            makePosition("2", chainID: "base", isV4: true, inRange: false),
            makePosition("3", chainID: "base", isV4: false, inRange: true),
            makePosition("4", chainID: "ethereum", isV4: true, inRange: true),
        ]
        let options = PositionListOptions(inRangeOnly: true, version: .v4, chainID: "base")
        #expect(options.apply(to: positions).map(\.tokenId) == ["1"])
    }

    @Test func clearFiltersKeepsSort() {
        var options = PositionListOptions(sort: .pair, inRangeOnly: true, version: .v3, chainID: "base")
        #expect(options.isFiltering)
        options.clearFilters()
        #expect(!options.isFiltering)
        #expect(options.sort == .pair)
    }
}

@Suite("Position list options persistence")
struct PositionListOptionsPersistenceTests {
    private func makeDefaults() -> UserDefaults {
        let name = "PositionListOptionsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func emptyDefaultsGiveDefaultOptions() {
        #expect(PositionListOptions(defaults: makeDefaults()) == PositionListOptions())
    }

    @Test func roundTrip() {
        let defaults = makeDefaults()
        let options = PositionListOptions(sort: .yield, inRangeOnly: true, version: .v4, chainID: "arbitrum")
        options.save(to: defaults)
        #expect(PositionListOptions(defaults: defaults) == options)

        var cleared = options
        cleared.clearFilters()
        cleared.save(to: defaults)
        #expect(PositionListOptions(defaults: defaults) == cleared)
    }

    @Test func unknownStoredValuesFallBackToDefaults() {
        let defaults = makeDefaults()
        defaults.set("bogus", forKey: "positionSort")
        defaults.set("v5", forKey: "positionFilterVersion")
        let options = PositionListOptions(defaults: defaults)
        #expect(options.sort == .value)
        #expect(options.version == .all)
    }
}
