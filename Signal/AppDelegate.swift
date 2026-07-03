import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Agent app: no Dock icon, no default window.
        NSApp.setActivationPolicy(.accessory)
        Analytics.start()
        SignalServices.shared.start()
        #if !APPSTORE
        // Kick off Sparkle's scheduled background update checks.
        _ = UpdaterManager.shared
        #endif
    }

    /// Re-launching an already-running agent app (Spotlight, Finder, `open -a`)
    /// sends a reopen event instead of starting a second instance. With no Dock
    /// icon and a possibly-hidden menu bar item, this is the user's escape hatch
    /// to the UI — so always bring up the panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SignalServices.shared.controller.presentInteractive(source: .reopen)
        return true
    }
}
