import UserNotifications

struct NotificationService {

    private static let stateKey = "rangeNotificationState"

    /// Requests macOS notification permission. Safe to call multiple times.
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Compares current positions against last known range state and fires
    /// notifications for any that changed. Persists new state for next call.
    static func fireRangeChangeNotificationsIfNeeded(for positions: [Position]) {
        guard AppSettings.shared.notifyOnRangeChange else { return }

        let previous = loadState()
        var next: [String: Bool] = [:]
        var notifications: [UNNotificationRequest] = []

        for position in positions {
            guard position.error == nil, let inRange = position.inRange else { continue }
            next[position.id] = inRange
            guard let wasInRange = previous[position.id], wasInRange != inRange else { continue }

            let content = UNMutableNotificationContent()
            let pair = "\(position.sym0)/\(position.sym1)"
            if inRange {
                content.title = "🟢 \(pair) back in range"
                content.body = "Your \(position.chainName) position is now in range."
            } else {
                content.title = "🔴 \(pair) out of range"
                content.body = "Your \(position.chainName) position is no longer in range."
            }
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "range-\(position.id)-\(inRange)-\(Date().timeIntervalSince1970)",
                content: content,
                trigger: nil
            )
            notifications.append(request)
        }

        for request in notifications {
            UNUserNotificationCenter.current().add(request) { _ in }
        }

        saveState(next)
    }

    // MARK: - Persistence

    private static func loadState() -> [String: Bool] {
        UserDefaults.standard.dictionary(forKey: stateKey) as? [String: Bool] ?? [:]
    }

    private static func saveState(_ state: [String: Bool]) {
        UserDefaults.standard.set(state, forKey: stateKey)
    }
}
