import UserNotifications

struct NotificationService {

    private static let stateKey = "rangeNotificationState"

    /// A position whose in-range status flipped since the last refresh.
    struct RangeChange {
        let position: Position
        let inRange: Bool
    }

    /// `UNUserNotificationCenter.current()` raises when the process has no `.app` bundle,
    /// which is the case for the bare executable produced by `swift build` / `swift run`.
    /// Evaluated once, so the unavailability is logged once per launch.
    private static let isAvailable: Bool = {
        let available = Bundle.main.bundleIdentifier != nil
            && Bundle.main.bundleURL.pathExtension == "app"
        if !available {
            Task { @MainActor in
                LogStore.shared.log(
                    "notifications unavailable: not running from an .app bundle (SPM build)",
                    level: .info
                )
            }
        }
        return available
    }()

    /// Requests macOS notification permission. Safe to call multiple times.
    static func requestAuthorization() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Compares current positions against last known range state and fires
    /// notifications for any that changed. Persists new state for next call.
    @MainActor
    static func fireRangeChangeNotificationsIfNeeded(for positions: [Position]) {
        guard AppSettings.shared.notifyOnRangeChange else { return }

        let (next, changes) = rangeChanges(for: positions, previous: loadState())

        for change in changes where isAvailable {
            let position = change.position
            let content = UNMutableNotificationContent()
            let pair = "\(position.sym0)/\(position.sym1)"
            if change.inRange {
                content.title = "🟢 \(pair) back in range"
                content.body = "Your \(position.chainName) position is now in range."
            } else {
                content.title = "🔴 \(pair) out of range"
                content.body = "Your \(position.chainName) position is no longer in range."
            }
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "range-\(position.id)-\(change.inRange)-\(Date().timeIntervalSince1970)",
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request) { _ in }
        }

        saveState(next)
    }

    /// Pure state transition: returns the state to persist (keyed by `Position.id`)
    /// and the positions whose range status changed relative to `previous`.
    ///
    /// `previous` may still hold keys in the old `<chain>-<tokenId>` format. Those are
    /// used as a fallback so upgrading neither drops nor invents transitions — except
    /// when a v3 and a v4 position share that legacy key, since its stored value was
    /// written by whichever of the two came last and can't be attributed.
    static func rangeChanges(
        for positions: [Position],
        previous: [String: Bool]
    ) -> (next: [String: Bool], changes: [RangeChange]) {
        let tracked = positions.filter { $0.error == nil && $0.inRange != nil }
        let legacyCounts = Dictionary(tracked.map { ($0.legacyID, 1) }, uniquingKeysWith: +)

        var next: [String: Bool] = [:]
        var changes: [RangeChange] = []

        for position in tracked {
            guard let inRange = position.inRange else { continue }
            next[position.id] = inRange

            let wasInRange = previous[position.id]
                ?? (legacyCounts[position.legacyID] == 1 ? previous[position.legacyID] : nil)
            guard let wasInRange, wasInRange != inRange else { continue }
            changes.append(RangeChange(position: position, inRange: inRange))
        }

        return (next, changes)
    }

    // MARK: - Persistence

    private static func loadState() -> [String: Bool] {
        UserDefaults.standard.dictionary(forKey: stateKey) as? [String: Bool] ?? [:]
    }

    private static func saveState(_ state: [String: Bool]) {
        UserDefaults.standard.set(state, forKey: stateKey)
    }
}
