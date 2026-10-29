import Foundation

/// Fees each position earned per calendar day, built from the unclaimed fees seen at every
/// refresh. Amounts are kept in token units and valued at current prices when shown, so a price
/// move does not look like earnings.
///
/// Claimed fees are not used: they arrive later, only for v3 and only with claimed-fee tracking
/// on. A drop in unclaimed fees is taken as a collect instead (see `earned(previous:current:)`).
struct DailyFeeLedger: Codable, Equatable {
    struct Amounts: Codable, Equatable {
        var token0 = 0.0
        var token1 = 0.0
    }

    struct Entry: Codable, Equatable {
        var lastTime: Date
        var lastUnclaimed: Amounts
        /// Earned per day, keyed by `dayKey`. A day is present once a sample interval covered it,
        /// so a missing key means unknown rather than nothing earned.
        var days: [String: Amounts] = [:]
    }

    static let retentionDays = 35
    /// Longer gaps (app quit, Mac asleep for days) are not spread over the days they cover.
    static let maxGap: TimeInterval = 3 * 86_400

    var entries: [String: Entry] = [:]

    // MARK: - Recording

    mutating func record(_ positions: [Position], at now: Date, calendar: Calendar = .current) {
        for pos in positions where pos.error == nil && pos.feesError == nil {
            record(id: pos.id, unclaimed: Amounts(token0: pos.fees0, token1: pos.fees1), at: now, calendar: calendar)
        }
        prune(now: now, calendar: calendar)
    }

    mutating func record(id: String, unclaimed: Amounts, at now: Date, calendar: Calendar = .current) {
        guard var entry = entries[id] else {
            entries[id] = Entry(lastTime: now, lastUnclaimed: unclaimed)
            return
        }
        let interval = now.timeIntervalSince(entry.lastTime)
        guard interval > 0 else { return }
        if interval <= Self.maxGap {
            let earned = Amounts(
                token0: Self.earned(previous: entry.lastUnclaimed.token0, current: unclaimed.token0),
                token1: Self.earned(previous: entry.lastUnclaimed.token1, current: unclaimed.token1)
            )
            Self.spread(earned, from: entry.lastTime, to: now, into: &entry.days, calendar: calendar)
        }
        entry.lastTime = now
        entry.lastUnclaimed = unclaimed
        entries[id] = entry
    }

    /// Unclaimed fees only grow until they are collected. A drop means a collect happened in
    /// between; what is unclaimed now has been earned since then, so it is a lower bound.
    static func earned(previous: Double, current: Double) -> Double {
        current >= previous ? current - previous : current
    }

    /// Splits `earned` over the calendar days between the two samples, by time.
    static func spread(
        _ earned: Amounts, from start: Date, to end: Date,
        into days: inout [String: Amounts], calendar: Calendar
    ) {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return }
        var cursor = start
        while cursor < end {
            let dayStart = calendar.startOfDay(for: cursor)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return }
            let sliceEnd = min(nextDay, end)
            let share = sliceEnd.timeIntervalSince(cursor) / total
            let key = dayKey(cursor, calendar: calendar)
            var amounts = days[key] ?? Amounts()
            amounts.token0 += earned.token0 * share
            amounts.token1 += earned.token1 * share
            days[key] = amounts
            cursor = sliceEnd
        }
    }

    mutating func prune(now: Date, calendar: Calendar = .current) {
        guard let cutoff = calendar.date(byAdding: .day, value: -Self.retentionDays, to: now) else { return }
        let cutoffKey = Self.dayKey(cutoff, calendar: calendar)
        for (id, entry) in entries {
            if entry.lastTime < cutoff {
                entries[id] = nil
            } else {
                // ISO day keys sort chronologically as strings.
                entries[id]?.days = entry.days.filter { $0.key >= cutoffKey }
            }
        }
    }

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    // MARK: - Series

    /// Each position's days, by `Position.id`.
    var dailyFees: DailyFees { DailyFees(byPosition: entries.mapValues(\.days)) }

    func dailyUSD(
        for position: Position, days: Int, minDays: Int = 2, endingAt now: Date, calendar: Calendar = .current
    ) -> [Double]? {
        dailyFees.dailyUSD(for: position, days: days, minDays: minDays, endingAt: now, calendar: calendar)
    }

    func walletDailyUSD(
        _ positions: [Position], days: Int, minDays: Int = 2, endingAt now: Date, calendar: Calendar = .current
    ) -> [Double]? {
        dailyFees.walletDailyUSD(positions, days: days, minDays: minDays, endingAt: now, calendar: calendar)
    }
}

/// Fees earned per position and calendar day, in token units: days keyed by
/// `DailyFeeLedger.dayKey`, positions by `Position.id`. A missing day means unknown.
public struct DailyFees: Equatable {
    var byPosition: [String: [String: DailyFeeLedger.Amounts]] = [:]

    /// Per position, the chain history where it has one, the refresh ledger otherwise.
    func overlaid(with other: DailyFees) -> DailyFees {
        DailyFees(byPosition: byPosition.merging(other.byPosition) { _, preferred in preferred })
    }

    /// USD earned per day for the last `days` days ending today, oldest first, starting at the
    /// first day with data. Nil with fewer than `minDays` days, or without a price for either token.
    public func dailyUSD(
        for position: Position, days: Int, minDays: Int = 2, endingAt now: Date, calendar: Calendar = .current
    ) -> [Double]? {
        guard let values = rawDailyUSD(for: position, days: days, endingAt: now, calendar: calendar) else { return nil }
        return Self.trimmed(values, minDays: minDays)
    }

    /// The same summed over positions; a day counts once any position has data for it.
    public func walletDailyUSD(
        _ positions: [Position], days: Int, minDays: Int = 2, endingAt now: Date, calendar: Calendar = .current
    ) -> [Double]? {
        var sums = [Double?](repeating: nil, count: days)
        for pos in positions {
            guard let values = rawDailyUSD(for: pos, days: days, endingAt: now, calendar: calendar) else { continue }
            for (i, value) in values.enumerated() {
                if let value { sums[i] = (sums[i] ?? 0) + value }
            }
        }
        return Self.trimmed(sums, minDays: minDays)
    }

    private func rawDailyUSD(for position: Position, days: Int, endingAt now: Date, calendar: Calendar) -> [Double?]? {
        guard let positionDays = byPosition[position.id],
              position.price0USD != nil || position.price1USD != nil else { return nil }
        let price0 = position.price0USD ?? 0
        let price1 = position.price1USD ?? 0
        return (0..<days).reversed().map { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { return nil }
            return positionDays[DailyFeeLedger.dayKey(date, calendar: calendar)].map { $0.token0 * price0 + $0.token1 * price1 }
        }
    }

    /// Drops the days before the first one with data; later gaps count as nothing earned.
    private static func trimmed(_ values: [Double?], minDays: Int) -> [Double]? {
        guard let first = values.firstIndex(where: { $0 != nil }) else { return nil }
        let series = values[first...].map { $0 ?? 0 }
        return series.count >= max(minDays, 1) ? series : nil
    }
}

// MARK: - Persistence

extension DailyFeeLedger {
    private static let defaultsKey = "dailyFeeLedger.v1"

    static func load(from defaults: UserDefaults = PoolserDefaults.store) -> DailyFeeLedger {
        guard let data = defaults.data(forKey: defaultsKey),
              let ledger = try? JSONDecoder().decode(DailyFeeLedger.self, from: data) else { return DailyFeeLedger() }
        return ledger
    }

    func save(to defaults: UserDefaults = PoolserDefaults.store) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
