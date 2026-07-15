#if DEBUG
import AppKit
import Foundation

/// Debug-only demo database for screen recordings. The flag is read once at
/// launch by SignalServices to pick the store; flipping it wipes the demo
/// store (on OFF→ON only) and relaunches the app.
@MainActor
enum DemoMode {
    private static let key = "demoModeEnabled"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: key) }

    /// Lives next to SwiftData's default.store in the sandbox container.
    static var storeURL: URL {
        URL.applicationSupportDirectory.appending(path: "demo.store")
    }

    static func setEnabled(_ enabled: Bool) {
        if enabled { wipeDemoStore() }  // safe: this process has default.store open, demo.store is cold
        UserDefaults.standard.set(enabled, forKey: key)
        relaunch()
    }

    private static func wipeDemoStore() {
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
        }
    }

    private static func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        // Without a new instance, launching an already-running app only sends
        // a reopen event to this process.
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
#endif
