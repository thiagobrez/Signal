import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Agent app: no Dock icon, no default window.
        NSApp.setActivationPolicy(.accessory)
        SignalServices.shared.start()
    }
}
