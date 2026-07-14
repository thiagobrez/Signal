import AppKit
import SwiftUI
import DynamicNotchKit

/// Owns the DynamicNotch lifecycle and the two ways the UI is shown:
/// `presentInteractive` (focusable, stays open) and `presentGlance` (peek,
/// auto-closes) — plus the bigger schedule-overview surface opened by
/// long-pressing the toggle hotkey. The small panel and the overview are
/// mutually exclusive: presenting either hides the other first.
@MainActor
@Observable
final class NotchController {
    enum Mode: Equatable { case interactive, glance }

    private(set) var mode: Mode = .interactive
    private(set) var isVisible = false
    private(set) var isOverviewVisible = false
    /// Bumped after the panel becomes key so the view can grab text focus.
    private(set) var focusRequest = 0
    /// Bumped synchronously before the open animation so the view can refresh
    /// transient content (e.g. placeholders) in the same frame it expands.
    private(set) var presentationRequest = 0
    /// Bumped before each overview open so the view can reset to this week in
    /// Week mode and re-fetch — DynamicNotch builds its content only once.
    private(set) var overviewPresentationRequest = 0

    private let store: SignalStore
    private let scheduleRepository: ScheduleRepository
    private var notch: DynamicNotch<SignalNotchView, EmptyView, EmptyView>?
    private var overviewNotch: DynamicNotch<ScheduleOverviewView, EmptyView, EmptyView>?
    private var glanceHideTask: Task<Void, Never>?
    private var clickMonitor: Any?

    init(store: SignalStore, scheduleRepository: ScheduleRepository) {
        self.store = store
        self.scheduleRepository = scheduleRepository
    }

    // MARK: - Public API

    func toggle() {
        if isOverviewVisible {
            // A plain press closes the overview too, rather than swapping to the
            // small panel — either press dismisses whatever is up.
            hideOverview()
        } else if isVisible {
            hide()
        } else {
            presentInteractive()
        }
    }

    func presentInteractive(source: Analytics.OpenSource = .manual) {
        glanceHideTask?.cancel()
        store.refreshForToday()
        Analytics.signalOpened(source: source)
        mode = .interactive
        presentationRequest &+= 1

        let notch = ensureNotch()
        let screen = presentationScreen
        isVisible = true
        Task {
            await hideOverviewAsync()
            await notch.expand(on: screen)
            activateForInput(self.notch?.windowController?.window)
            installClickMonitor()
        }
    }

    func presentGlance(duration: TimeInterval) {
        store.refreshForToday()
        mode = .glance
        presentationRequest &+= 1

        let notch = ensureNotch()
        let screen = presentationScreen
        isVisible = true
        Task {
            await hideOverviewAsync()
            await notch.expand(on: screen)
        }

        glanceHideTask?.cancel()
        glanceHideTask = Task {
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            await hideAsync()
        }
    }

    func hide() {
        Task { await hideAsync() }
    }

    // MARK: - Schedule overview

    func toggleOverview() {
        if isOverviewVisible {
            hideOverview()
        } else {
            presentOverview()
        }
    }

    func presentOverview() {
        glanceHideTask?.cancel()
        overviewPresentationRequest &+= 1

        let overview = ensureOverviewNotch()
        let screen = presentationScreen
        isOverviewVisible = true
        Task {
            // Let the small panel finish shrinking before the big card expands.
            await hideAsync()
            await overview.expand(on: screen)
            activateForInput(overviewNotch?.windowController?.window)
            installClickMonitor()
        }
    }

    func hideOverview() {
        Task { await hideOverviewAsync() }
    }

    // MARK: - Internals

    /// The screen to present on: the one containing the pointer, so the panel
    /// follows the user to whichever display they're working on (and the
    /// notch/floating style is then resolved for *that* screen). Falls back to the
    /// main screen, then the primary — matching DynamicNotchKit's own default.
    private var presentationScreen: NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func ensureNotch() -> DynamicNotch<SignalNotchView, EmptyView, EmptyView> {
        if let notch { return notch }
        // `.auto` renders the notch shape on notched screens and the floating pill
        // on notchless ones. The floating pill's hardcoded margins are patched to 0
        // in our vendored DynamicNotchKit (LocalPackages/DynamicNotchKit) so the
        // panel reaches the window edges instead of floating with a gap.
        let created = DynamicNotch(hoverBehavior: [.keepVisible], style: .auto) { [unowned self] in
            SignalNotchView(store: self.store, controller: self)
        }
        notch = created
        return created
    }

    private func ensureOverviewNotch() -> DynamicNotch<ScheduleOverviewView, EmptyView, EmptyView> {
        if let overviewNotch { return overviewNotch }
        let created = DynamicNotch(hoverBehavior: [.keepVisible], style: .auto) { [unowned self] in
            ScheduleOverviewView(repository: self.scheduleRepository, controller: self)
        }
        overviewNotch = created
        return created
    }

    private func activateForInput(_ window: NSWindow?) {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        focusRequest &+= 1
    }

    private func hideAsync() async {
        glanceHideTask?.cancel()
        guard isVisible else { return }
        if !isOverviewVisible { removeClickMonitor() }
        store.save()
        isVisible = false
        await notch?.hide()
    }

    private func hideOverviewAsync() async {
        guard isOverviewVisible else { return }
        if !isVisible { removeClickMonitor() }
        isOverviewVisible = false
        await overviewNotch?.hide()
    }

    /// Dismiss whichever surface is up when the user clicks anywhere outside it.
    private func installClickMonitor() {
        removeClickMonitor()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.hide()
                self?.hideOverview()
            }
        }
    }

    private func removeClickMonitor() {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
    }
}
