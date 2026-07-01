import AppKit
import SwiftUI

/// Owns the one-time first-launch onboarding window. Signal is an `.accessory`
/// app with no normal windows, so — like `NotchController` — this creates and
/// activates an AppKit window directly rather than relying on a SwiftUI scene.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    /// Run once when onboarding is finished or dismissed — used to drop the user
    /// straight into the app (the notch) afterwards.
    private var onComplete: (() -> Void)?

    /// Builds (if needed), centers, and brings the onboarding window to the
    /// front. Because the app is `.accessory`, we activate it explicitly so the
    /// window takes focus above other apps (mirrors `NotchController`).
    /// `onComplete` fires once the window is finished/closed.
    func present(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        let window = window ?? makeWindow()
        self.window = window

        // Onboarding is a real window, so show a Dock icon while it's open (the
        // app is otherwise a menu-bar `.accessory`). Reverted in `finish()`.
        NSApp.setActivationPolicy(.regular)
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: OnboardingView(onFinish: { [weak self] in
            self?.finish()
        }))
        return window
    }

    /// Marks onboarding as seen and tears down the window. Safe to call more
    /// than once (finishing then the resulting close both route here).
    private func finish() {
        SettingsStore.hasSeenOnboarding = true
        // Back to a menu-bar-only agent: drop the Dock icon.
        NSApp.setActivationPolicy(.accessory)

        if let window {
            self.window = nil
            window.delegate = nil
            window.close()
        }

        // Fire (and clear) the completion exactly once so the user lands in the
        // app afterwards, whether they finished, skipped, or closed the window.
        let completion = onComplete
        onComplete = nil
        completion?()
    }

    // MARK: - NSWindowDelegate

    /// Closing the window early (red button) also counts as having seen it.
    func windowWillClose(_ notification: Notification) {
        finish()
    }
}
