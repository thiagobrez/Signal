import AppKit
import SwiftUI

/// Shows the one-time "Signal lives here!" hint under the menu bar icon.
///
/// Signal is an `.accessory` app whose entire UI hangs off a menu bar item, so
/// the first thing a new user needs to know is which of the icons up there is
/// ours. Right after onboarding we point at it with a small `NSPopover` whose
/// arrow lands on the status item, then take it away again after a few seconds
/// or on the first click anywhere — it's a signpost, not something to dismiss.
///
/// The anchor is SwiftUI's own `MenuBarExtra` button, which has no public
/// handle, so we find it by walking `NSApp.windows` for the status bar window
/// and its view tree for the `NSStatusBarButton`.
@MainActor
final class MenuBarHintController {
    private var popover: NSPopover?
    private var dismissWorkItem: DispatchWorkItem?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var attemptsRemaining = MenuBarHintPolicy.anchorRetryLimit

    private static let hintWindowLevel = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)

    /// Shows the hint once, ever. Called from the onboarding completion, which
    /// fires whether the user finished, skipped, or closed the window.
    func presentIfNeeded() {
        guard !SettingsStore.hasSeenMenuBarHint, popover == nil else { return }
        schedule(after: MenuBarHintPolicy.presentationDelay)
    }

    private func schedule(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.attemptPresentation()
        }
    }

    /// One attempt at finding a visible status item to anchor to. The item may
    /// not exist yet (SwiftUI creates it lazily) or may be off-screen behind a
    /// menu bar manager, so we retry a few times and then give up without
    /// burning the flag — the hint is worth nothing if nobody can see it.
    private func attemptPresentation() {
        guard !SettingsStore.hasSeenMenuBarHint, popover == nil else { return }

        if let anchor = Self.visibleStatusItemButton() {
            show(anchoredTo: anchor)
            return
        }

        attemptsRemaining -= 1
        guard attemptsRemaining > 0 else { return }
        schedule(after: MenuBarHintPolicy.anchorRetryInterval)
    }

    private func show(anchoredTo anchor: NSView) {
        let popover = NSPopover()
        // `.applicationDefined`: we own the dismissal, so the hint survives the
        // activation churn of the onboarding window closing behind it.
        popover.behavior = .applicationDefined
        popover.animates = true
        let content = NSHostingController(rootView: MenuBarHintView())
        // Pin the size before showing. A hosting controller only reports the
        // size its SwiftUI content really wants after a layout pass, and the
        // popover would otherwise aim its arrow using the provisional one —
        // leaving the hint pointing at empty menu bar next to our icon.
        content.view.layoutSubtreeIfNeeded()
        content.preferredContentSize = content.view.fittingSize
        popover.contentViewController = content
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        // The notch panel opens at the same moment (onboarding hands the user
        // straight to it) and floats at `.screenSaver`, which would swallow a
        // popover sitting at the status bar level. Put the hint above it: it is
        // pointing at the icon the panel came out of.
        popover.contentViewController?.view.window?.level = Self.hintWindowLevel
        self.popover = popover

        // Only a hint the user actually saw counts as seen.
        SettingsStore.hasSeenMenuBarHint = true
        installDismissal()
    }

    /// Auto-dismiss after a few seconds, or on the first click anywhere — in
    /// this app or any other.
    private func installDismissal() {
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + MenuBarHintPolicy.autoDismissDelay, execute: work)

        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self] event in
            self?.dismiss()
            // Must hand the event back, or the hint eats the user's click.
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
    }

    /// Idempotent: the timer and either monitor can all race to get here.
    private func dismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil

        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }

        popover?.performClose(nil)
        popover = nil
    }

    // MARK: - Finding the status item

    /// The `NSStatusBarButton` behind `MenuBarExtra`, if it's on screen right
    /// now. Public AppKit only — the window carrying a status item is the one
    /// whose class is `NSStatusBarWindow`.
    private static func visibleStatusItemButton() -> NSView? {
        let statusWindows = NSApp.windows.filter { $0.className.contains("NSStatusBarWindow") }
        // With several screens each gets its own status bar window; prefer the
        // one the user is looking at.
        let window = statusWindows.first { $0.screen == NSScreen.main } ?? statusWindows.first

        guard
            let window,
            window.isVisible,
            window.occlusionState.contains(.visible),
            let contentView = window.contentView
        else { return nil }

        let anchor = statusButton(in: contentView) ?? contentView
        let frameInWindow = anchor.convert(anchor.bounds, to: nil)
        let frameOnScreen = window.convertToScreen(frameInWindow)

        guard MenuBarHintPolicy.isAnchorOnScreen(
            anchorFrame: frameOnScreen,
            screenFrames: NSScreen.screens.map(\.frame)
        ) else { return nil }

        return anchor
    }

    private static func statusButton(in view: NSView) -> NSStatusBarButton? {
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews {
            if let button = statusButton(in: subview) { return button }
        }
        return nil
    }
}

/// The hint itself: one line, sized to its text.
private struct MenuBarHintView: View {
    var body: some View {
        Text(MenuBarHintPolicy.text)
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .fixedSize()
            .accessibilityIdentifier("menuBarHint")
    }
}
