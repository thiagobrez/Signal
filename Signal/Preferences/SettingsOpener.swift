import SwiftUI

/// Opens the Settings scene from non-SwiftUI code (the reopen handler in
/// `AppDelegate`).
///
/// `NSApp.sendAction(Selector(("showSettingsWindow:")), …)` — the usual trick —
/// stopped working in macOS 14, and its SwiftUI replacement, `openSettings`, is
/// an environment value that only exists inside a view. The menu's own view is
/// the one place the app reads it today, and that view doesn't exist while the
/// menu bar icon is hidden (#17) — which is exactly when reopen needs to open
/// Preferences. So we host a 1×1 offscreen SwiftUI view whose only job is to
/// hand the action back to us, and keep it alive for the life of the app.
@MainActor
final class SettingsOpener {
    static let shared = SettingsOpener()

    private var host: NSHostingView<SettingsActionProbe>?
    private var action: OpenSettingsAction?

    private init() {}

    /// Creates the offscreen host (once) so the action is captured before it is
    /// first needed. Safe to call repeatedly.
    func prepare() {
        guard host == nil else { return }

        let host = NSHostingView(rootView: SettingsActionProbe { [weak self] action in
            self?.action = action
        })
        host.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        host.layoutSubtreeIfNeeded()
        self.host = host
    }

    /// Brings Preferences to the front. Returns `false` when the action was
    /// never captured, so the caller can fall back rather than silently doing
    /// nothing.
    @discardableResult
    func open() -> Bool {
        prepare()
        guard let action else { return false }

        // As an accessory (`LSUIElement`) app we're never frontmost, so the
        // window would otherwise open *behind* whatever the user is using.
        NSApp.activate(ignoringOtherApps: true)
        action()
        return true
    }
}

/// A view that exists only to read `\.openSettings` out of the environment.
private struct SettingsActionProbe: View {
    @Environment(\.openSettings) private var openSettings

    let capture: (OpenSettingsAction) -> Void

    var body: some View {
        let _ = capture(openSettings)
        Color.clear.frame(width: 1, height: 1)
    }
}
