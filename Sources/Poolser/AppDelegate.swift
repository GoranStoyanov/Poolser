import AppKit
import PoolserKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide the dock icon; the app lives only in the menu bar
        NSApp.setActivationPolicy(.accessory)
        NotificationService.requestAuthorization()
#if DEBUG
        StoreScreenshots.runIfRequested()
#endif
    }

    /// `poolser://open`, sent by a widget click.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme == "poolser" }) else { return }
        MenuBarPanel.open()
    }

    /// Opening the app again while it runs (Finder, Spotlight) shows the menu; there is no window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MenuBarPanel.open()
        return false
    }
}

/// `MenuBarExtra` has no API to show its window, so this presents it the way a click on the
/// status item does.
@MainActor
enum MenuBarPanel {
    /// A URL that launches the app arrives before the status item exists, so look again briefly.
    static func open(attempts: Int = 5) {
        guard let item = statusItem() else {
            if attempts > 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { open(attempts: attempts - 1) }
            }
            return
        }
        // Presenting it again would close it.
        guard !isPresented(item) else { return }
        NSApp.activate(ignoringOtherApps: true)
        if !beginExpandedInterfaceSession(item) {
            item.button?.performClick(nil)
        }
    }

    // From macOS 27 a window-style MenuBarExtra is shown through the status item's expanded
    // interface session, and its button has no target or action, so a simulated click does
    // nothing. These selectors are what the system calls on a real click.
    private static let beginSession = NSSelectorFromString("_beginExpandedInterfaceSession:")
    private static let session = NSSelectorFromString("expandedInterfaceSession")
    private static let sessionDelegate = NSSelectorFromString("expandedInterfaceDelegate")

    private static func usesExpandedInterfaceSession(_ item: NSStatusItem) -> Bool {
        item.responds(to: beginSession) && item.responds(to: sessionDelegate)
            && item.perform(sessionDelegate)?.takeUnretainedValue() != nil
    }

    private static func isPresented(_ item: NSStatusItem) -> Bool {
        if usesExpandedInterfaceSession(item) {
            return item.responds(to: session) && item.perform(session)?.takeUnretainedValue() != nil
        }
        return item.button?.state == .on
    }

    /// The begin call takes the triggering event's timestamp and drops any that predate the end
    /// of the previous session, so a click that closes the window cannot reopen it. There is no
    /// triggering event here, so pass the largest timestamp to always get through.
    private static func beginExpandedInterfaceSession(_ item: NSStatusItem) -> Bool {
        guard usesExpandedInterfaceSession(item), let method = item.method(for: beginSession) else { return false }
        typealias Begin = @convention(c) (NSStatusItem, Selector, TimeInterval) -> Void
        unsafeBitCast(method, to: Begin.self)(item, beginSession, .greatestFiniteMagnitude)
        return true
    }

    /// The app has one status item: MenuBarExtra's, held by its status bar window.
    private static func statusItem() -> NSStatusItem? {
        NSApp.windows.lazy
            .filter { $0.className.contains("StatusBar") }
            .compactMap { $0.value(forKey: "statusItem") as? NSStatusItem }
            .first
    }
}
