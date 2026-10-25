import Foundation
import Testing
@testable import Poolser

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

/// "2026-10-20T06:00" in UTC.
private func at(_ string: String) -> Date {
    let parts = string.split(whereSeparator: { "-T:".contains($0) }).map { Int($0)! }
    return utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: parts[3], minute: parts[4]))!
}

private func amounts(_ token0: Double, _ token1: Double = 0) -> DailyFeeLedger.Amounts {
    DailyFeeLedger.Amounts(token0: token0, token1: token1)
}

private func position(id tokenId: String = "1", price0: Double? = 2, price1: Double? = nil) -> Position {
    var pos = Position(
        chainID: "ethereum", chainName: "Ethereum", chainNumericID: 1, tokenId: tokenId,
        token0: "0x0", token1: "0x1", sym0: "A", sym1: "B",
        feePct: "0.3", feeRaw: 3_000, fees0: 0, fees1: 0,
        tickLower: 0, tickUpper: 100, liquidity: 1
    )
    pos.price0USD = price0
    pos.price1USD = price1
    return pos
}

@Suite("Daily fee ledger")
struct DailyFeeLedgerTests {
    let id = position().id

    @Test func firstSampleRecordsNoEarnings() {
        var ledger = DailyFeeLedger()
        ledger.record(id: id, unclaimed: amounts(5), at: at("2026-10-20T06:00"), calendar: utc)
        #expect(ledger.entries[id]?.days.isEmpty == true)
    }

    @Test func growthWithinADayGoesToThatDay() {
        var ledger = DailyFeeLedger()
        ledger.record(id: id, unclaimed: amounts(5, 1), at: at("2026-10-20T06:00"), calendar: utc)
        ledger.record(id: id, unclaimed: amounts(8, 1.5), at: at("2026-10-20T12:00"), calendar: utc)
        #expect(ledger.entries[id]?.days["2026-10-20"] == amounts(3, 0.5))
    }

    @Test func intervalOverMidnightIsSplitByTime() {
        var ledger = DailyFeeLedger()
        ledger.record(id: id, unclaimed: amounts(0), at: at("2026-10-20T18:00"), calendar: utc)
        ledger.record(id: id, unclaimed: amounts(12), at: at("2026-10-21T06:00"), calendar: utc)
        #expect(ledger.entries[id]?.days["2026-10-20"] == amounts(6))
        #expect(ledger.entries[id]?.days["2026-10-21"] == amounts(6))
    }

    @Test func dropCountsAsCollect() {
        // 10 unclaimed, collected, then 2 more accrued: at least 2 earned since the last sample.
        #expect(DailyFeeLedger.earned(previous: 10, current: 2) == 2)
        #expect(DailyFeeLedger.earned(previous: 10, current: 13) == 3)
    }

    @Test func longGapIsNotSpread() {
        var ledger = DailyFeeLedger()
        ledger.record(id: id, unclaimed: amounts(0), at: at("2026-10-10T12:00"), calendar: utc)
        ledger.record(id: id, unclaimed: amounts(40), at: at("2026-10-20T12:00"), calendar: utc)
        #expect(ledger.entries[id]?.days.isEmpty == true)
        #expect(ledger.entries[id]?.lastUnclaimed == amounts(40))
    }

    @Test func pruneDropsOldDaysAndStalePositions() {
        var ledger = DailyFeeLedger()
        ledger.entries[id] = .init(lastTime: at("2026-10-20T12:00"), lastUnclaimed: amounts(0),
                                   days: ["2026-08-01": amounts(1), "2026-10-19": amounts(2)])
        ledger.entries["stale"] = .init(lastTime: at("2026-08-01T12:00"), lastUnclaimed: amounts(0))
        ledger.prune(now: at("2026-10-20T12:00"), calendar: utc)
        #expect(ledger.entries[id]?.days == ["2026-10-19": amounts(2)])
        #expect(ledger.entries["stale"] == nil)
    }

    @Test func seriesStartsAtFirstKnownDayAndFillsGaps() {
        var ledger = DailyFeeLedger()
        ledger.entries[id] = .init(lastTime: at("2026-10-20T12:00"), lastUnclaimed: amounts(0),
                                   days: ["2026-10-17": amounts(1), "2026-10-19": amounts(3), "2026-10-20": amounts(0.5)])
        let series = ledger.dailyUSD(for: position(), days: 7, endingAt: at("2026-10-20T12:00"), calendar: utc)
        // price0 = $2; Oct 18 has no data after the first known day, so it reads as 0.
        #expect(series == [2, 0, 6, 1])
    }

    @Test func seriesNeedsTwoDaysAndAPrice() {
        var ledger = DailyFeeLedger()
        ledger.entries[id] = .init(lastTime: at("2026-10-20T12:00"), lastUnclaimed: amounts(0),
                                   days: ["2026-10-20": amounts(1)])
        #expect(ledger.dailyUSD(for: position(), days: 7, endingAt: at("2026-10-20T12:00"), calendar: utc) == nil)
        ledger.entries[id]?.days["2026-10-19"] = amounts(1)
        #expect(ledger.dailyUSD(for: position(price0: nil), days: 7, endingAt: at("2026-10-20T12:00"), calendar: utc) == nil)
    }

    @Test func walletSeriesCanStartFromOneDay() {
        let a = position(id: "1", price0: 2)
        var ledger = DailyFeeLedger()
        ledger.entries[a.id] = .init(lastTime: at("2026-10-20T12:00"), lastUnclaimed: amounts(0),
                                     days: ["2026-10-20": amounts(1.5)])
        #expect(ledger.walletDailyUSD([a], days: 7, endingAt: at("2026-10-20T12:00"), calendar: utc) == nil)
        #expect(ledger.walletDailyUSD([a], days: 7, minDays: 1, endingAt: at("2026-10-20T12:00"), calendar: utc) == [3])
    }

    @Test func walletSeriesSumsPositions() {
        let a = position(id: "1", price0: 1)
        let b = position(id: "2", price0: 10)
        var ledger = DailyFeeLedger()
        ledger.entries[a.id] = .init(lastTime: at("2026-10-20T12:00"), lastUnclaimed: amounts(0),
                                     days: ["2026-10-19": amounts(1), "2026-10-20": amounts(2)])
        ledger.entries[b.id] = .init(lastTime: at("2026-10-20T12:00"), lastUnclaimed: amounts(0),
                                     days: ["2026-10-20": amounts(0.5)])
        let series = ledger.walletDailyUSD([a, b], days: 3, endingAt: at("2026-10-20T12:00"), calendar: utc)
        #expect(series == [1, 7])
    }

    @Test func recordSkipsPositionsWithUnknownFees() {
        var ok = position(id: "1")
        ok.fees0 = 1
        var failed = position(id: "2")
        failed.feesError = "timeout"
        var ledger = DailyFeeLedger()
        ledger.record([ok, failed], at: at("2026-10-20T12:00"), calendar: utc)
        #expect(ledger.entries[ok.id] != nil)
        #expect(ledger.entries[failed.id] == nil)
    }

    @Test func survivesARoundTrip() throws {
        let defaults = try #require(UserDefaults(suiteName: "DailyFeeLedgerTests-\(UUID().uuidString)"))
        var ledger = DailyFeeLedger()
        ledger.record(id: id, unclaimed: amounts(1), at: at("2026-10-20T06:00"), calendar: utc)
        ledger.record(id: id, unclaimed: amounts(2), at: at("2026-10-20T07:00"), calendar: utc)
        ledger.save(to: defaults)
        #expect(DailyFeeLedger.load(from: defaults) == ledger)
    }
}
