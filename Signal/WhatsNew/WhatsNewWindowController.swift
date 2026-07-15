import AppKit
import SwiftUI

/// Owns the "What's New" window shown once after an update (and on demand from
/// the menu bar). Like `OnboardingWindowController`, Signal is an `.accessory`
/// app with no normal windows, so this creates and activates an AppKit window
/// directly rather than relying on a SwiftUI scene.
@MainActor
final class WhatsNewWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    /// Run once when the window is closed — used to resume the normal
    /// open-on-launch flow after the post-update presentation.
    private var onComplete: (() -> Void)?

    /// How many releases the manual "What's New…" menu item shows.
    private static let manualReleaseCap = 3

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Releases newer than `storedVersion` from the bundled CHANGELOG.md, or
    /// nil if the changelog is missing/unreadable — callers treat nil as "skip
    /// the window", so a broken resource never blocks launch.
    static func releasesSince(_ storedVersion: String) -> [ChangelogRelease]? {
        guard let all = bundledReleases() else { return nil }
        return ChangelogParser.releases(after: storedVersion, in: all)
    }

    private static func bundledReleases() -> [ChangelogRelease]? {
        guard
            let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
            let markdown = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return ChangelogParser.parse(markdown)
    }

    /// Auto-show after an update. Closing the window (button or red close)
    /// marks the current version as seen and fires `onComplete` once.
    func present(releases: [ChangelogRelease], onComplete: (() -> Void)? = nil) {
        self.onComplete = onComplete
        show(releases: releases)
    }

    /// Manual open from the menu bar: the newest few releases, regardless of
    /// what the user has already seen. No-op if the changelog is unreadable.
    func presentLatest() {
        guard let all = Self.bundledReleases(), !all.isEmpty else { return }
        show(releases: Array(all.prefix(Self.manualReleaseCap)))
    }

    private func show(releases: [ChangelogRelease]) {
        // Rebuild the window each time: the release list differs per call.
        if let window {
            self.window = nil
            window.delegate = nil
            window.close()
        }
        let window = makeWindow(releases: releases)
        self.window = window

        // A real window, so show a Dock icon while it's open (the app is
        // otherwise a menu-bar `.accessory`). Reverted in `finish()`.
        NSApp.setActivationPolicy(.regular)
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(releases: [ChangelogRelease]) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 520),
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
        window.contentView = NSHostingView(rootView: WhatsNewView(releases: releases, onFinish: { [weak self] in
            self?.finish()
        }))
        return window
    }

    /// Marks the current version as seen and tears down the window. Safe to
    /// call more than once (the button and the resulting close both route here).
    private func finish() {
        SettingsStore.lastSeenWhatsNewVersion = Self.currentVersion
        // Back to a menu-bar-only agent: drop the Dock icon.
        NSApp.setActivationPolicy(.accessory)

        if let window {
            self.window = nil
            window.delegate = nil
            window.close()
        }

        let completion = onComplete
        onComplete = nil
        completion?()
    }

    // MARK: - NSWindowDelegate

    /// Closing the window via the red button also counts as having seen it.
    func windowWillClose(_ notification: Notification) {
        finish()
    }
}
