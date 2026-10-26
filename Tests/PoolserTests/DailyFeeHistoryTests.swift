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

/// With liquidity 2^64, a fee growth of `units` × 2^64 earns exactly `units` raw tokens.
private let unitLiquidity: Double = 18_446_744_073_709_551_616

private func growth(_ units: UInt64) -> Data {
    var word = Data(count: 32)
    for i in 0..<8 { word[23 - i] = UInt8((units >> (8 * UInt64(i))) & 0xff) }
    return word
}

private func snapshot(_ inside: UInt64, last: UInt64 = 0, liquidity: Double = unitLiquidity) -> FeeGrowthSnapshot {
    FeeGrowthSnapshot(
        liquidity: liquidity, inside0: growth(inside), inside1: growth(0),
        insideLast0: growth(last), insideLast1: growth(0)
    )
}

private func position(tokenId: String = "7", now: FeeGrowthSnapshot? = nil) -> Position {
    var pos = Position(
        chainID: "ethereum", chainName: "Ethereum", chainNumericID: 1, tokenId: tokenId,
        token0: "0x0", token1: "0x1", sym0: "A", sym1: "B",
        feePct: "0.3", feeRaw: 3_000, fees0: 0, fees1: 0,
        tickLower: -100, tickUpper: 100, liquidity: unitLiquidity
    )
    pos.dec0 = 0
    pos.dec1 = 0
    pos.poolAddress = "0x00000000000000000000000000000000000000b1"
    pos.feeGrowth = now
    return pos
}

@Suite("Fee growth snapshot")
struct FeeGrowthSnapshotTests {
    @Test func unchangedLiquidityEarnsTheGrowthInBetween() {
        #expect(snapshot(13).earned(since: snapshot(10)) == (3, 0))
    }

    @Test func collectInBetweenDoesNotMatter() {
        // A collect moves insideLast but not inside.
        #expect(snapshot(13, last: 12).earned(since: snapshot(10, last: 4)) == (3, 0))
    }

    @Test func positionMintedInBetweenEarnsSinceItsMint() {
        #expect(snapshot(13, last: 10).earned(since: nil) == (3, 0))
    }

    @Test func liquidityChangeSplitsAtTheChange() {
        let start = snapshot(10, liquidity: unitLiquidity)
        let end = snapshot(20, last: 14, liquidity: 2 * unitLiquidity)
        // 1 × (14 − 10) before the change, 2 × (20 − 14) after it.
        #expect(end.earned(since: start) == (16, 0))
    }

    @Test func growthGoingBackwardCountsAsNothing() {
        #expect(snapshot(10).earned(since: snapshot(13)) == (0, 0))
        #expect(snapshot(13, liquidity: 0).earned(since: snapshot(10, liquidity: 0)) == (0, 0))
    }

    @Test func readsFromPoolState() throws {
        let positions = [Data](repeating: Data(count: 32), count: 5).reduce(Data(), +)
            + ABI.encodeInt24(-100) + ABI.encodeInt24(100) + ABI.encodeUInt256(1_000)
            + growth(4) + growth(0) + Data(count: 64)
        func slot0(_ tick: Int) -> Data { Data(count: 32) + ABI.encodeInt24(tick) + Data(count: 32 * 5) }
        func tick(outside0: UInt64) -> Data { Data(count: 64) + growth(outside0) + growth(0) }

        let inRange = try #require(FeeGrowthSnapshot(
            positions: positions, slot0: slot0(0), global0: growth(100), global1: growth(0),
            lowerTick: tick(outside0: 30), upperTick: tick(outside0: 20)
        ))
        #expect(inRange.liquidity == 1_000)
        #expect(inRange.inside0 == growth(50))
        #expect(inRange.insideLast0 == growth(4))

        // Below the range the lower tick's outside value is the growth above it.
        let below = try #require(FeeGrowthSnapshot(
            positions: positions, slot0: slot0(-150), global0: growth(100), global1: growth(0),
            lowerTick: tick(outside0: 30), upperTick: tick(outside0: 20)
        ))
        #expect(below.inside0 == growth(10))
    }
}

/// Chain state per day start, with counters for the reads the history makes.
private final class FakeHistory {
    /// Fee growth inside at the start of each day, by day key; days before `mintedOn` revert.
    var growthAtDayStart: [String: UInt64] = [:]
    var mintedOn = "0000-00-00"
    var hasHistory = true
    var lookups = 0
    var reads = 0
    private var dayByBlock: [Int: String] = [:]

    func block(_ date: Date) -> Int? {
        lookups += 1
        let day = DailyFeeLedger.dayKey(date, calendar: utc)
        let block = Int(day.replacingOccurrences(of: "-", with: ""))!
        dayByBlock[block] = day
        return block
    }

    func read(_ block: Int, _ positions: [Position]) -> [String: DailyFeeHistory.DayStart] {
        reads += 1
        guard hasHistory, let day = dayByBlock[block] else { return [:] }
        var states: [String: DailyFeeHistory.DayStart] = [:]
        for pos in positions {
            states[pos.tokenId] = day < mintedOn ? .notMinted : .minted(snapshot(growthAtDayStart[day] ?? 0))
        }
        return states
    }

    func update(_ cache: inout DailyFeeHistory.Cache, _ positions: [Position], days: Int = 4, now: Date) async {
        await DailyFeeHistory.update(
            &cache, positions: positions, days: days, now: now, calendar: utc,
            dayStartBlock: { self.block($0) },
            readDayStart: { self.read($0, $1) }
        )
    }
}

@Suite("Daily fee history")
struct DailyFeeHistoryTests {
    @Test func backfillsFinishedDaysAndMeasuresToday() async {
        let chain = FakeHistory()
        chain.growthAtDayStart = ["2026-10-17": 10, "2026-10-18": 13, "2026-10-19": 20, "2026-10-20": 26]
        let pos = position(now: snapshot(30))
        var cache = DailyFeeHistory.Cache(timeZone: "UTC")

        await chain.update(&cache, [pos], now: at("2026-10-20T15:00"))

        let fees = DailyFeeHistory.dailyFees(from: cache, positions: [pos], now: at("2026-10-20T15:00"), calendar: utc)
        #expect(fees.byPosition[pos.id] == [
            "2026-10-17": .init(token0: 3), "2026-10-18": .init(token0: 7),
            "2026-10-19": .init(token0: 6), "2026-10-20": .init(token0: 4),
        ])
        #expect(chain.lookups == 4 && chain.reads == 4)
    }

    @Test func laterRefreshesReadNothingUntilTheNextDay() async {
        let chain = FakeHistory()
        chain.growthAtDayStart = ["2026-10-17": 10, "2026-10-18": 13, "2026-10-19": 20, "2026-10-20": 26, "2026-10-21": 33]
        var cache = DailyFeeHistory.Cache(timeZone: "UTC")
        await chain.update(&cache, [position()], now: at("2026-10-20T15:00"))

        await chain.update(&cache, [position()], now: at("2026-10-20T23:00"))
        #expect(chain.lookups == 4 && chain.reads == 4)

        // After midnight only the new day's start is read; yesterday's start was kept for "today".
        await chain.update(&cache, [position()], now: at("2026-10-21T01:00"))
        #expect(chain.lookups == 5 && chain.reads == 5)
        #expect(cache.positions["7"]?.days["2026-10-20"] == .init(token0: 7))
        #expect(cache.positions["7"]?.days["2026-10-17"] == nil)
    }

    @Test func positionMintedInsideTheWindowStartsThere() async {
        let chain = FakeHistory()
        chain.growthAtDayStart = ["2026-10-19": 5, "2026-10-20": 9]
        // Minted during Oct 18: earlier day starts revert.
        chain.mintedOn = "2026-10-19"
        let pos = position(now: snapshot(12))
        var cache = DailyFeeHistory.Cache(timeZone: "UTC")
        await chain.update(&cache, [pos], now: at("2026-10-20T15:00"))

        #expect(cache.positions["7"]?.emptyBefore == "2026-10-18")
        let fees = DailyFeeHistory.dailyFees(from: cache, positions: [pos], now: at("2026-10-20T15:00"), calendar: utc)
        // The mint day earns from the mint (insideLast 0) to the next day's start.
        #expect(fees.byPosition[pos.id] == [
            "2026-10-18": .init(token0: 5), "2026-10-19": .init(token0: 4), "2026-10-20": .init(token0: 3),
        ])

        // Days before the mint are settled, so the next refresh reads nothing.
        await chain.update(&cache, [pos], now: at("2026-10-20T16:00"))
        #expect(chain.reads == 4)
    }

    @Test func nodeWithoutHistoryRecordsNothingAndBacksOff() async {
        let chain = FakeHistory()
        chain.hasHistory = false
        let pos = position(now: snapshot(30))
        var cache = DailyFeeHistory.Cache(timeZone: "UTC")
        await chain.update(&cache, [pos], now: at("2026-10-20T15:00"))

        #expect(chain.reads == 1)
        #expect(cache.retryAfter == at("2026-10-20T16:00"))
        #expect(DailyFeeHistory.dailyFees(from: cache, positions: [pos], now: at("2026-10-20T15:00"), calendar: utc).byPosition.isEmpty)
    }

    @Test func chainHistoryReplacesTheLedgerPerPosition() {
        let a = position(tokenId: "1"), b = position(tokenId: "2")
        let ledger = DailyFees(byPosition: [a.id: ["2026-10-20": .init(token0: 25)], b.id: ["2026-10-20": .init(token0: 1)]])
        let chain = DailyFees(byPosition: [a.id: ["2026-10-20": .init(token0: 2)]])
        let merged = ledger.overlaid(with: chain)
        #expect(merged.byPosition[a.id]?["2026-10-20"] == .init(token0: 2))
        #expect(merged.byPosition[b.id]?["2026-10-20"] == .init(token0: 1))
    }

    @Test func readsDayStartThroughMulticall() async throws {
        let chain = SupportedChain.byID("ethereum")!
        let nfpm = chain.v3NFPM!
        let pool = "0x00000000000000000000000000000000000000b1"
        let fake = FakeChain()
        let positionsResult = [Data](repeating: Data(count: 32), count: 5).reduce(Data(), +)
            + ABI.encodeInt24(-100) + ABI.encodeInt24(100) + ABI.encodeUInt256(1) + Data(count: 32 * 4)
        await fake.set(nfpm, ABI.callPositions(tokenId: 7), .value(positionsResult))
        await fake.set(nfpm, ABI.callPositions(tokenId: 8), .revert("Invalid token ID"))
        await fake.set(pool, ABI.callSlot0(), .value(Data(count: 32 * 7)))
        await fake.set(pool, ABI.callFeeGrowthGlobal0(), .value(growth(9)))
        await fake.set(pool, ABI.callFeeGrowthGlobal1(), .value(growth(0)))
        await fake.set(pool, ABI.callTicks(-100), .value(Data(count: 32 * 8)))
        await fake.set(pool, ABI.callTicks(100), .value(Data(count: 32 * 8)))

        let states = await DailyFeeHistory.readDayStart(
            block: 100, positions: [position(tokenId: "7"), position(tokenId: "8")], nfpm: nfpm,
            reader: ContractReader(eth: fake.client(), multicall3: chain.multicall3, block: 100), context: "test"
        )
        #expect(states["7"]?.snapshot?.inside0 == growth(9))
        #expect(states["8"] == .notMinted)
        #expect(await fake.requests.count == 1)
    }

    @Test func dayStartSearchLandsWithinMinutesOfMidnight() async throws {
        // 12 s slots from block 1,000,000 with every 50th slot missed.
        let genesis = Int(at("2026-09-01T00:00").timeIntervalSince1970)
        func time(_ block: Int) -> Int {
            let n = block - 1_000_000
            return genesis + (n + n / 49) * 12
        }
        let head = 1_000_000 + 30 * 86_400 / 12
        let search = DayStartBlockSearch(blockTime: 12, latestBlock: { head }, timestamp: { time($0) })
        for day in ["2026-09-25", "2026-09-24", "2026-09-10"] {
            let midnight = at("\(day)T00:00")
            let block = try #require(await search.firstBlock(at: midnight))
            #expect(abs(time(block) - Int(midnight.timeIntervalSince1970)) <= 120)
        }
    }
}
