import Foundation

/// Fees each v3 position earned per local calendar day, read from chain state: the position's
/// fee growth at the first block of each day. Unlike `DailyFeeLedger` it covers days the app was
/// not running and is filled in on first launch. Finished days are cached for good, so after the
/// backfill a day costs one block lookup and one Multicall3 read per chain; today runs from the
/// first block of the day to the fee growth the latest refresh read (`Position.feeGrowth`).
///
/// Needs a node that serves historical state. Where it does not (Infura on Base), reads fail,
/// nothing is recorded, and the chart keeps using `DailyFeeLedger` for those positions.
struct DailyFeeHistory {
    typealias Amounts = DailyFeeLedger.Amounts

    /// A position's state at the first block of a day.
    enum DayStart: Codable, Equatable {
        /// positions() reverted: the token was not minted yet.
        case notMinted
        case minted(FeeGrowthSnapshot)

        var snapshot: FeeGrowthSnapshot? {
            if case .minted(let snapshot) = self { return snapshot }
            return nil
        }
    }

    struct PositionDays: Codable, Equatable {
        /// Raw token amounts earned per finished day.
        var days: [String: Amounts] = [:]
        /// Days before this one ended before the position was minted, so they hold nothing.
        var emptyBefore: String?
        /// Where today's fees are measured from, and the day it belongs to.
        var startOfToday: DayStart?
        var startOfTodayKey: String?
    }

    struct Cache: Codable, Equatable {
        /// Day boundaries are local midnights; a different zone needs new ones.
        var timeZone: String
        /// First block of each day, by day key.
        var dayStartBlocks: [String: Int] = [:]
        /// By tokenId.
        var positions: [String: PositionDays] = [:]
        /// Set after the node had no state for a past block, so a chain without history is not
        /// asked again on every refresh.
        var retryAfter: Date?
    }

    /// First block of the day starting at `date`, or nil when it cannot be found.
    typealias DayStartBlockFinder = (_ date: Date) async -> Int?
    /// Each position's state at `block`, by tokenId; a position whose reads failed is missing.
    typealias DayStartReader = (_ block: Int, _ positions: [Position]) async -> [String: DayStart]

    static let retryDelay: TimeInterval = 3_600

    // MARK: - Update

    /// Reads the day starts that finished days still need, newest first, and records those days.
    /// Stops at the first day start it cannot read; a cancelled update keeps what it has.
    static func update(
        _ cache: inout Cache,
        positions: [Position],
        days: Int,
        now: Date,
        calendar: Calendar,
        dayStartBlock: DayStartBlockFinder,
        readDayStart: DayStartReader
    ) async {
        let starts = dayStarts(days: days, now: now, calendar: calendar)
        guard let today = starts.first, let oldest = starts.last else { return }
        let key = { DailyFeeLedger.dayKey($0, calendar: calendar) }

        // The day start kept for measuring "today" is still valid once that day has passed.
        var read: [Date: [String: DayStart]] = [:]
        for pos in positions {
            guard let state = cache.positions[pos.tokenId], let start = state.startOfToday,
                  let date = starts.first(where: { key($0) == state.startOfTodayKey }) else { continue }
            read[date, default: [:]][pos.tokenId] = start
        }

        var needed = Set<Date>()
        for pos in positions {
            let state = cache.positions[pos.tokenId] ?? PositionDays()
            for i in starts.indices.dropFirst() where !state.isKnown(key(starts[i])) {
                needed.insert(starts[i])
                needed.insert(starts[i - 1])
            }
            needed.insert(today)
        }
        needed = needed.filter { date in positions.contains { read[date]?[$0.tokenId] == nil } }

        for start in needed.sorted(by: >) {
            guard !Task.isCancelled else { break }
            let dayKey = key(start)
            var block = cache.dayStartBlocks[dayKey]
            if block == nil { block = await dayStartBlock(start) }
            guard let block else { break }
            cache.dayStartBlocks[dayKey] = block
            let states = await readDayStart(block, positions)
            guard !states.isEmpty else {
                cache.retryAfter = now.addingTimeInterval(retryDelay)
                break
            }
            read[start, default: [:]].merge(states) { _, fresh in fresh }
        }

        for pos in positions {
            var state = cache.positions[pos.tokenId] ?? PositionDays()
            for i in starts.indices.dropFirst() {
                let dayKey = key(starts[i])
                guard !state.isKnown(dayKey),
                      let start = read[starts[i]]?[pos.tokenId],
                      let end = read[starts[i - 1]]?[pos.tokenId] else { continue }
                if start == .notMinted { state.markEmpty(before: dayKey) }
                switch end {
                case .notMinted:
                    state.markEmpty(before: key(starts[i - 1]))
                case .minted(let snapshot):
                    state.days[dayKey] = amounts(snapshot.earned(since: start.snapshot), of: pos)
                }
            }
            if let start = read[today]?[pos.tokenId], state.startOfTodayKey != key(today) {
                state.startOfToday = start
                state.startOfTodayKey = key(today)
            }
            let oldestKey = key(oldest)
            state.days = state.days.filter { $0.key >= oldestKey }
            cache.positions[pos.tokenId] = state
        }

        let oldestKey = key(oldest)
        cache.dayStartBlocks = cache.dayStartBlocks.filter { $0.key >= oldestKey }
        // Positions sold or burned stop being refreshed; drop them once their window has passed.
        cache.positions = cache.positions.filter { ($0.value.startOfTodayKey ?? "") >= oldestKey }
    }

    /// Fees per day by `Position.id`, today included where both its ends are known.
    static func dailyFees(from cache: Cache, positions: [Position], now: Date, calendar: Calendar) -> DailyFees {
        let todayKey = DailyFeeLedger.dayKey(now, calendar: calendar)
        var byPosition: [String: [String: Amounts]] = [:]
        for pos in positions {
            guard let state = cache.positions[pos.tokenId] else { continue }
            var days = state.days
            if state.startOfTodayKey == todayKey, let start = state.startOfToday, let current = pos.feeGrowth {
                days[todayKey] = amounts(current.earned(since: start.snapshot), of: pos)
            }
            if !days.isEmpty { byPosition[pos.id] = days }
        }
        return DailyFees(byPosition: byPosition)
    }

    /// Local midnights, today's first.
    static func dayStarts(days: Int, now: Date, calendar: Calendar) -> [Date] {
        let today = calendar.startOfDay(for: now)
        return (0..<max(days, 1)).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }

    private static func amounts(_ raw: (amount0: Double, amount1: Double), of pos: Position) -> Amounts {
        Amounts(token0: raw.amount0 / pow(10.0, Double(pos.dec0)), token1: raw.amount1 / pow(10.0, Double(pos.dec1)))
    }
}

extension DailyFeeHistory.PositionDays {
    func isKnown(_ dayKey: String) -> Bool {
        // ISO day keys sort chronologically as strings.
        days[dayKey] != nil || emptyBefore.map { dayKey < $0 } == true
    }

    mutating func markEmpty(before dayKey: String) {
        emptyBefore = max(emptyBefore ?? dayKey, dayKey)
    }
}

// MARK: - Chain reads

extension DailyFeeHistory {
    /// Matches the wallet chart's 30 days.
    static let windowDays = 30

    /// Brings one chain's cached history up to date and returns its days. `positions` are that
    /// chain's v3 positions with a known pool.
    static func refresh(
        positions: [Position],
        chain: SupportedChain,
        nfpm: String,
        eth: EthereumClient,
        now: Date = Date(),
        calendar: Calendar = .current,
        store: UserDefaults = .standard
    ) async -> DailyFees {
        var cache = load(chainID: chain.id, calendar: calendar, from: store)
        if cache.retryAfter.map({ now < $0 }) != true {
            cache.retryAfter = nil
            let finder = DayStartBlockSearch(blockTime: chain.blockTimeSeconds, latestBlock: {
                try await eth.ethBlockNumber()
            }, timestamp: {
                try await eth.ethBlockTimestamp($0)
            })
            await update(
                &cache, positions: positions, days: windowDays, now: now, calendar: calendar,
                dayStartBlock: { await finder.firstBlock(at: $0) },
                readDayStart: { block, positions in
                    await readDayStart(
                        block: block, positions: positions, nfpm: nfpm,
                        reader: ContractReader(eth: eth, multicall3: chain.multicall3, block: block),
                        context: "daily fees [\(chain.id)]"
                    )
                }
            )
            save(cache, chainID: chain.id, to: store)
        }
        return dailyFees(from: cache, positions: positions, now: now, calendar: calendar)
    }

    static func readDayStart(
        block: Int, positions: [Position], nfpm: String, reader: ContractReader, context: String
    ) async -> [String: DayStart] {
        let tracked = positions.compactMap { pos -> (pos: Position, call: ContractCall, pool: String)? in
            guard let tokenId = UInt64(pos.tokenId), let pool = pos.poolAddress else { return nil }
            return (pos, ContractCall(target: nfpm, data: ABI.callPositions(tokenId: tokenId)), pool)
        }
        let calls = tracked.flatMap { entry in
            [entry.call] + V3FeeGrowthReads.calls(pool: entry.pool, tickLower: entry.pos.tickLower, tickUpper: entry.pos.tickUpper)
        }
        let results = await reader.readRetryingFailures(calls, context: context)
        let byCall = Dictionary(zip(calls, results), uniquingKeysWith: { first, _ in first })

        var states: [String: DayStart] = [:]
        for entry in tracked {
            switch byCall[entry.call] {
            case .success(let data)?:
                let snapshot = V3FeeGrowthReads.snapshot(
                    positions: data, pool: entry.pool, tickLower: entry.pos.tickLower, tickUpper: entry.pos.tickUpper,
                    results: byCall
                )
                if let snapshot { states[entry.pos.tokenId] = .minted(snapshot) }
            case .failure(EthereumClient.Err.reverted)?:
                states[entry.pos.tokenId] = .notMinted
            default:
                break
            }
        }
        return states
    }
}

// MARK: - Persistence

extension DailyFeeHistory {
    private static let keyPrefix = "dailyFeeHistory.v1."

    static func load(chainID: String, calendar: Calendar, from store: UserDefaults = .standard) -> Cache {
        let zone = calendar.timeZone.identifier
        guard let data = store.data(forKey: keyPrefix + chainID),
              let cache = try? JSONDecoder().decode(Cache.self, from: data),
              cache.timeZone == zone else { return Cache(timeZone: zone) }
        return cache
    }

    static func save(_ cache: Cache, chainID: String, to store: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        store.set(data, forKey: keyPrefix + chainID)
    }
}

// MARK: - Day start blocks

/// Finds the first block at or after a time from block timestamps: a guess from the chain's
/// block time, then one correction from the timestamp actually found there. Days are searched
/// newest first, each from the block read for the previous one, so a guess is at most a day off
/// and the correction lands within a few blocks.
actor DayStartBlockSearch {
    private let blockTime: Double
    private let latestBlock: () async throws -> Int
    private let timestamp: (Int) async throws -> Int
    private var anchor: (block: Int, time: Int)?

    init(blockTime: Double, latestBlock: @escaping () async throws -> Int, timestamp: @escaping (Int) async throws -> Int) {
        self.blockTime = blockTime
        self.latestBlock = latestBlock
        self.timestamp = timestamp
    }

    func firstBlock(at date: Date) async -> Int? {
        do {
            if anchor == nil {
                let block = try await latestBlock()
                anchor = (block, try await timestamp(block))
            }
            guard let known = anchor else { return nil }
            let target = Int(date.timeIntervalSince1970)
            guard target < known.time else { return known.block }

            let guess = max(1, known.block - Int((Double(known.time - target) / blockTime).rounded()))
            let guessTime = try await timestamp(guess)
            anchor = (guess, guessTime)
            let secondsPerBlock = guess < known.block && known.time > guessTime
                ? Double(known.time - guessTime) / Double(known.block - guess)
                : blockTime
            let corrected = guess + Int((Double(target - guessTime) / secondsPerBlock).rounded(.up))
            return min(max(1, corrected), known.block)
        } catch {
            return nil
        }
    }
}
