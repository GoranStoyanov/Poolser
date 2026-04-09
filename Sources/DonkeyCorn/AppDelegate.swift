import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide the dock icon; the app lives only in the menu bar
        NSApp.setActivationPolicy(.accessory)
    }
}
