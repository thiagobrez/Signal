#if !APPSTORE
import AppKit
import Combine
import Sparkle

/// Observable wrapper around Sparkle's standard updater, shared by the About
/// tab controls and the menu bar's "update available" item. Direct-download
/// builds only — the App Store variant compiles this file out entirely
/// (updates there belong to the App Store).
///
/// Sparkle persists the automatic-check/download switches in UserDefaults
/// itself (seeded by SUEnableAutomaticChecks / SUAutomaticallyUpdate in
/// Info.plist), so there is no SettingsStore key for them.
final class UpdaterManager: NSObject, ObservableObject {
    static let shared = UpdaterManager()

    /// False while a check is already in flight; drives button enablement.
    @Published private(set) var canCheckForUpdates = false

    /// Display version of an update Sparkle has found (and, once downloaded,
    /// staged to install on quit). Non-nil drives the menu bar item — the
    /// escape hatch for users who never quit the app.
    @Published private(set) var pendingUpdateVersion: String?

    /// Sparkle hands us this when an update is staged for install-on-quit;
    /// invoking it installs and relaunches immediately.
    private var immediateInstallBlock: (() -> Void)?

    private var controller: SPUStandardUpdaterController!

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)
    }

    /// The About tab checkbox. One switch controls the whole behavior:
    /// scheduled checks plus background download + install-on-quit.
    var automaticUpdatesEnabled: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set {
            objectWillChange.send()
            controller.updater.automaticallyChecksForUpdates = newValue
            controller.updater.automaticallyDownloadsUpdates = newValue
        }
    }

    /// User-initiated check with Sparkle's UI. If an update is already
    /// downloaded this resumes it with Install & Relaunch.
    func checkForUpdates() {
        // Accessory app: without activation Sparkle's window opens behind
        // whatever app is frontmost.
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    /// The menu bar item's action: install the staged update and relaunch
    /// now. Falls back to a normal check if nothing is staged yet (e.g. the
    /// download hasn't finished), letting Sparkle's UI drive the install.
    func applyPendingUpdate() {
        if let install = immediateInstallBlock {
            install()
        } else {
            checkForUpdates()
        }
    }
}

extension UpdaterManager: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        DispatchQueue.main.async {
            self.pendingUpdateVersion = item.displayVersionString
        }
    }

    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        DispatchQueue.main.async {
            self.pendingUpdateVersion = item.displayVersionString
            self.immediateInstallBlock = immediateInstallHandler
        }
        // Returning true keeps the handler so the menu bar item can install
        // with no extra UI. Per Sparkle's docs this pauses further update
        // cycles until this update is installed (menu item click or quit) —
        // acceptable: a newer version published meanwhile is picked up on
        // the first cycle after relaunch.
        return true
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        // Any error (including SUNoUpdateError) means nothing is pending.
        guard error != nil else { return }
        DispatchQueue.main.async {
            self.pendingUpdateVersion = nil
            self.immediateInstallBlock = nil
        }
    }
}
#endif
