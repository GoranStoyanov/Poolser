import Foundation

/// What the widgets show, written by the app after each refresh. Widgets render it as is: an
/// extension has neither the memory nor the run time to read positions from the chain.
public struct PortfolioSnapshot: Codable, Equatable, Sendable {
    public struct PoolSeed: Codable, Equatable, Sendable {
        public let chainID: String
        public let reference: String
        public let isV4: Bool
        public let tickLower: Int
        public let tickUpper: Int
        public let liquidity: Double
        public let token0Decimals: Int
        public let token1Decimals: Int

        init?(_ position: Position) {
            guard let reference = position.poolReference else { return nil }
            chainID = position.chainID
            self.reference = reference
            isV4 = position.isV4
            tickLower = position.tickLower
            tickUpper = position.tickUpper
            liquidity = position.liquidity
            token0Decimals = position.dec0
            token1Decimals = position.dec1
        }
    }

    public struct Item: Codable, Equatable, Sendable, Identifiable {
        /// `Position.id`.
        public let id: String
        public let pairLabel: String
        public let chainName: String
        public let valueUSD: Double?
        public let feesUSD: Double?
        public let status: RangeStatus
        /// "4.2% below" while out of range.
        public let distanceLabel: String?
        public let gauge: RangeGaugeLayout?
        /// Present when the pool was identified, so a future light refresh can reuse it.
        public let pool: PoolSeed?

        public init(
            id: String, pairLabel: String, chainName: String, valueUSD: Double?, feesUSD: Double?,
            status: RangeStatus, distanceLabel: String? = nil, gauge: RangeGaugeLayout? = nil,
            pool: PoolSeed? = nil
        ) {
            self.id = id
            self.pairLabel = pairLabel
            self.chainName = chainName
            self.valueUSD = valueUSD
            self.feesUSD = feesUSD
            self.status = status
            self.distanceLabel = distanceLabel
            self.gauge = gauge
            self.pool = pool
        }
    }

    public let updatedAt: Date
    public let totalValueUSD: Double
    public let unclaimedFeesUSD: Double
    /// USD fees earned per day, oldest first and ending today; nil until daily history exists.
    public let dailyFeesUSD: [Double]?
    public let positionCount: Int
    /// Positions near a bound, out of range or unreadable.
    public let attentionCount: Int
    public let chainCount: Int
    /// Every position, with those needing attention first, then by value. Widgets show the top three.
    public let items: [Item]

    public init(
        updatedAt: Date, totalValueUSD: Double, unclaimedFeesUSD: Double, dailyFeesUSD: [Double]?,
        positionCount: Int, attentionCount: Int, chainCount: Int, items: [Item]
    ) {
        self.updatedAt = updatedAt
        self.totalValueUSD = totalValueUSD
        self.unclaimedFeesUSD = unclaimedFeesUSD
        self.dailyFeesUSD = dailyFeesUSD
        self.positionCount = positionCount
        self.attentionCount = attentionCount
        self.chainCount = chainCount
        self.items = items
    }

    public init(positions: [Position], dailyFeesUSD: [Double]?, updatedAt: Date) {
        let presented = positions.map { ($0, PositionPresentation($0)) }
        let ranked = presented.enumerated().sorted { lhs, rhs in
            let (l, r) = (lhs.element, rhs.element)
            if l.1.status.needsAttention != r.1.status.needsAttention { return l.1.status.needsAttention }
            let (lv, rv) = (l.0.positionUSD ?? 0, r.0.positionUSD ?? 0)
            return lv != rv ? lv > rv : lhs.offset < rhs.offset
        }
        self.init(
            updatedAt: updatedAt,
            totalValueUSD: positions.compactMap(\.positionUSD).reduce(0, +),
            unclaimedFeesUSD: positions.compactMap(\.usd).reduce(0, +),
            dailyFeesUSD: dailyFeesUSD,
            positionCount: positions.count,
            attentionCount: presented.filter { $0.1.status.needsAttention }.count,
            chainCount: Set(positions.map(\.chainID)).count,
            items: ranked.map { entry in
                let (pos, view) = entry.element
                return Item(
                    id: pos.id, pairLabel: view.pairLabel, chainName: pos.chainName,
                    valueUSD: pos.positionUSD, feesUSD: pos.usd, status: view.status,
                    distanceLabel: view.distanceLabel, gauge: view.gauge,
                    pool: PoolSeed(pos)
                )
            }
        )
    }

    /// Whether a widget showing `previous` would now show a different range picture, which is
    /// worth a reload even when the last one was recent.
    func rangeChanged(from previous: PortfolioSnapshot) -> Bool {
        positionCount != previous.positionCount
            || attentionCount != previous.attentionCount
            || items.map(\.id) != previous.items.map(\.id)
            || items.map(\.status) != previous.items.map(\.status)
    }
}

/// The snapshot file in the App Group container.
public enum PortfolioSnapshotStore {
    static let fileName = "PortfolioSnapshot.json"

    /// Nil when the app names no App Group (the SwiftPM build) or the container is unavailable.
    public static var fileURL: URL? {
        guard let group = PoolserDefaults.appGroup,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        else { return nil }
        return container.appendingPathComponent(fileName, isDirectory: false)
    }

    public static func load(from url: URL? = fileURL) -> PortfolioSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(PortfolioSnapshot.self, from: data)
    }

    /// Writes `snapshot`, or removes the file for nil so widgets stop showing a wallet that is gone.
    @discardableResult
    public static func save(_ snapshot: PortfolioSnapshot?, to url: URL? = fileURL) -> Bool {
        guard let url else { return false }
        guard let snapshot else {
            try? FileManager.default.removeItem(at: url)
            return true
        }
        do {
            try encoder.encode(snapshot).write(to: url, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
}

/// Widget reloads come out of a daily budget, so a refresh every few minutes cannot reload on
/// each one. A changed range picture reloads at once; drifting values wait for `minimumInterval`
/// and are otherwise picked up by the widget's own timeline.
struct WidgetReloadThrottle {
    static let minimumInterval: TimeInterval = 15 * 60

    private(set) var lastReload: Date?
    private var lastSnapshot: PortfolioSnapshot?
    private var hasReloaded = false

    /// Records the reload when it returns true.
    mutating func shouldReload(for snapshot: PortfolioSnapshot?, now: Date) -> Bool {
        let reload: Bool
        switch (lastSnapshot, snapshot) {
        case (nil, nil):
            reload = !hasReloaded
        case (nil, _), (_, nil):
            reload = true
        case let (previous?, current?):
            reload = current.rangeChanged(from: previous)
                || lastReload.map { now.timeIntervalSince($0) >= Self.minimumInterval } ?? true
        }
        if reload {
            lastReload = now
            lastSnapshot = snapshot
            hasReloaded = true
        }
        return reload
    }
}
