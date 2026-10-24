import Foundation

enum PositionSort: String, CaseIterable, Identifiable {
    case value
    case fees
    case yield
    case pair

    var id: String { rawValue }

    var title: String {
        switch self {
        case .value: return "Value"
        case .fees:  return "Unclaimed Fees"
        case .yield: return "Yield (24h)"
        case .pair:  return "Pair"
        }
    }
}

enum PositionVersionFilter: String, CaseIterable, Identifiable {
    case all
    case v3
    case v4

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All Versions"
        case .v3:  return "v3 Only"
        case .v4:  return "v4 Only"
        }
    }
}

/// How the menu lists positions. Only affects display: the menu bar total and range
/// notifications still cover every position.
struct PositionListOptions: Equatable {
    var sort: PositionSort = .value
    var inRangeOnly = false
    var version: PositionVersionFilter = .all
    /// `SupportedChain.id`, or nil for every chain.
    var chainID: String?

    var isFiltering: Bool { inRangeOnly || version != .all || chainID != nil }

    mutating func clearFilters() {
        inRangeOnly = false
        version = .all
        chainID = nil
    }

    func apply(to positions: [Position]) -> [Position] {
        positions.enumerated()
            .filter { matches($0.element) }
            .sorted { lhs, rhs in
                switch Self.compare(lhs.element, rhs.element, by: sort) {
                case .orderedAscending:  return true
                case .orderedDescending: return false
                // Ties keep the loaded order, so equal rows do not swap between refreshes.
                case .orderedSame:       return lhs.offset < rhs.offset
                }
            }
            .map(\.element)
    }

    func matches(_ pos: Position) -> Bool {
        if inRangeOnly {
            // A position whose range could not be read is not known to be earning.
            guard pos.error == nil, pos.isFullRange || pos.inRange == true else { return false }
        }
        switch version {
        case .all: break
        case .v3:  if pos.isV4 { return false }
        case .v4:  if !pos.isV4 { return false }
        }
        if let chainID, pos.chainID != chainID { return false }
        return true
    }

    /// Ascending means `lhs` is listed first. Numeric sorts put the largest first and
    /// positions without a value (no price, failed read) last.
    private static func compare(_ lhs: Position, _ rhs: Position, by sort: PositionSort) -> ComparisonResult {
        switch sort {
        case .value: return descending(lhs.positionUSD ?? lhs.usd, rhs.positionUSD ?? rhs.usd)
        case .fees:  return descending(lhs.usd, rhs.usd)
        case .yield: return descending(lhs.feeAPR, rhs.feeAPR)
        case .pair:
            return "\(lhs.sym0)/\(lhs.sym1)".localizedStandardCompare("\(rhs.sym0)/\(rhs.sym1)")
        }
    }

    private static func descending(_ lhs: Double?, _ rhs: Double?) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (l?, r?): return l > r ? .orderedAscending : (l < r ? .orderedDescending : .orderedSame)
        case (_?, nil):    return .orderedAscending
        case (nil, _?):    return .orderedDescending
        case (nil, nil):   return .orderedSame
        }
    }
}

extension PositionListOptions {
    private enum Key {
        static let sort        = "positionSort"
        static let inRangeOnly = "positionFilterInRangeOnly"
        static let version     = "positionFilterVersion"
        static let chainID     = "positionFilterChainID"
    }

    init(defaults: UserDefaults) {
        sort = defaults.string(forKey: Key.sort).flatMap(PositionSort.init(rawValue:)) ?? .value
        inRangeOnly = defaults.bool(forKey: Key.inRangeOnly)
        version = defaults.string(forKey: Key.version).flatMap(PositionVersionFilter.init(rawValue:)) ?? .all
        chainID = defaults.string(forKey: Key.chainID)
    }

    func save(to defaults: UserDefaults) {
        defaults.set(sort.rawValue, forKey: Key.sort)
        defaults.set(inRangeOnly, forKey: Key.inRangeOnly)
        defaults.set(version.rawValue, forKey: Key.version)
        if let chainID { defaults.set(chainID, forKey: Key.chainID) } else { defaults.removeObject(forKey: Key.chainID) }
    }
}
