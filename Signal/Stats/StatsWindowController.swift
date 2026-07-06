import AppKit
import SwiftData
import SwiftUI

/// A tap relay from the titlebar accessory (its own hosting view) to
/// `StatsView`. The accessory bumps `toggleCount`; `StatsView` watches it and
/// animates the sidebar *within its own* hierarchy, so the detail pane reflows
/// in lockstep. Letting AppKit animate the split view instead leaves the
/// SwiftUI detail laid out at the old width until the animation ends — the
/// jump the user sees.
@MainActor
@Observable
final class StatsWindowState {
    var toggleCount = 0
}

/// Owns the standalone "Task Stats" window. Like onboarding, the app is an
/// `.accessory` agent with no SwiftUI window scenes, so this creates and
/// activates an AppKit window directly. Unlike onboarding it's re-openable:
/// the window is kept alive and toggled by the global hotkey.
@MainActor
final class StatsWindowController: NSObject, NSWindowDelegate {
    private let container: ModelContainer
    private let windowState = StatsWindowState()
    private var window: NSWindow?

    /// Run just before the window is shown — `SignalServices` points this at
    /// `store.refreshForToday()` so opening stats first thing on a new day
    /// still creates today's log (with carry-over) before it's displayed.
    var willPresent: (() -> Void)?

    init(container: ModelContainer) {
        self.container = container
        super.init()
    }

    /// Hotkey behavior: hide when visible, show otherwise (mirrors
    /// `NotchController.toggle()`).
    func toggle() {
        if let window, window.isVisible {
            window.close()
        } else {
            present()
        }
    }

    /// Builds (if needed) and brings the window to the front. Stats is a real
    /// window, so show a Dock icon while it's open — reverted in
    /// `windowWillClose` (mirrors `OnboardingWindowController`).
    func present() {
        willPresent?()
        let window = window ?? makeWindow()
        self.window = window

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private static let frameName = "TaskStatsWindow"

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        // The system title text is hidden; the titlebar accessory below draws
        // the toggle + title pinned beside the traffic lights instead, so the
        // toggle never moves with the sidebar. The title string stays for
        // accessibility and Mission Control.
        window.title = "Task Stats"
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        // The controller retains and reuses the window across toggles.
        window.isReleasedWhenClosed = false
        window.delegate = self

        // Restore the user's last size/position; center only on the very first open.
        if !window.setFrameUsingName(Self.frameName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.frameName)

        let accessory = NSTitlebarAccessoryViewController()
        let accessoryView = NSHostingView(rootView: StatsTitlebarAccessory(state: windowState))
        accessoryView.setFrameSize(accessoryView.fittingSize)
        accessory.view = accessoryView
        accessory.layoutAttribute = .leading
        window.addTitlebarAccessoryViewController(accessory)

        // `.modelContainer` is what lets `@Query` inside `StatsView` see the
        // app's shared store — without it the query crashes at runtime.
        // The minimum size lives on the SwiftUI content: NSHostingView derives
        // the window's minSize from it (a plain `window.minSize` would be
        // overridden by the hosting view's sizing).
        window.contentView = NSHostingView(
            rootView: StatsView(windowState: windowState)
                .frame(minWidth: 640, minHeight: 420)
                .modelContainer(container)
        )
        return window
    }

    // MARK: - NSWindowDelegate

    /// Red-button close and `toggle()` both land here: back to a
    /// menu-bar-only agent, dropping the Dock icon.
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

/// The titlebar row next to the traffic lights: sidebar toggle + window
/// title. Living in the real titlebar (not the content) keeps it clickable,
/// opaque, and fixed in place no matter what the sidebar does.
private struct StatsTitlebarAccessory: View {
    let state: StatsWindowState

    var body: some View {
        HStack(spacing: 8) {
            Button {
                // Just signal StatsView; it owns the animation so the detail
                // pane animates with the sidebar (see StatsWindowState).
                state.toggleCount += 1
            } label: {
                Image(systemName: "sidebar.leading")
            }
            .buttonStyle(.borderless)
            .help("Toggle Sidebar")
            .accessibilityLabel("Toggle Sidebar")

            Text("Task Stats")
                .font(.system(size: 13, weight: .semibold))
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .frame(height: 28)
    }
}
