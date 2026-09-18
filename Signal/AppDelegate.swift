import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Agent app: no Dock icon, no default window.
        NSApp.setActivationPolicy(.accessory)
        Analytics.start()
        SignalServices.shared.start()
        SettingsOpener.shared.prepare()
        #if !APPSTORE
        // Kick off Sparkle's scheduled background update checks.
        _ = UpdaterManager.shared
        #endif
    }

    /// Signal is an agent: it has to outlive its windows *and* its menu bar
    /// item, which the user can now hide (#17).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Re-launching an already-running agent app (Spotlight, Finder, `open -a`)
    /// sends a reopen event instead of starting a second instance. With no Dock
    /// icon and a possibly-hidden menu bar item, this is the user's escape hatch
    /// to the UI — so always bring up the panel, and when the icon is hidden also
    /// open Preferences, which is otherwise unreachable (#17).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let actions = ReopenPolicy.actions(menuBarIconVisible: SettingsStore.showMenuBarIcon)
        if actions.presentPanel {
            SignalServices.shared.controller.presentInteractive(source: .reopen)
        }
        if actions.openPreferences, !SettingsOpener.shared.open() {
            // Never leave the user locked out: no way to show Preferences, so
            // bring the icon back.
            SettingsStore.showMenuBarIcon = true
        }
        return true
    }
}
