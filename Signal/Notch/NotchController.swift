import AppKit
import SwiftUI
import DynamicNotchKit

/// Owns the DynamicNotch lifecycle and the two ways the UI is shown:
/// `presentInteractive` (focusable, stays open) and `presentGlance` (peek, auto-closes).
@MainActor
@Observable
final class NotchController {
    enum Mode: Equatable { case interactive, glance }

    private(set) var mode: Mode = .interactive
    private(set) var isVisible = false
    /// Bumped after the panel becomes key so the view can grab text focus.
    private(set) var focusRequest = 0
    /// Bumped synchronously before the open animation so the view can refresh
    /// transient content (e.g. placeholders) in the same frame it expands.
    private(set) var presentationRequest = 0

    private let store: SignalStore
    private var notch: DynamicNotch<SignalNotchView, EmptyView, EmptyView>?
    private var glanceHideTask: Task<Void, Never>?
    private var clickMonitor: Any?

    init(store: SignalStore) {
        self.store = store
    }

    // MARK: - Public API

    func toggle() {
        if isVisible {
            hide()
        } else {
            presentInteractive()
        }
    }

    func presentInteractive() {
        glanceHideTask?.cancel()
        store.refreshForToday()
        mode = .interactive
        presentationRequest &+= 1

        let notch = ensureNotch()
        isVisible = true
        Task {
            await notch.expand()
            activateForInput()
            installClickMonitor()
        }
    }

    func presentGlance(duration: TimeInterval) {
        store.refreshForToday()
        mode = .glance
        presentationRequest &+= 1

        let notch = ensureNotch()
        isVisible = true
        Task { await notch.expand() }

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

    // MARK: - Internals

    private func ensureNotch() -> DynamicNotch<SignalNotchView, EmptyView, EmptyView> {
        if let notch { return notch }
        let created = DynamicNotch(hoverBehavior: [.keepVisible], style: .auto) { [unowned self] in
            SignalNotchView(store: self.store, controller: self)
        }
        notch = created
        return created
    }

    private func activateForInput() {
        guard let window = notch?.windowController?.window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        focusRequest &+= 1
    }

    private func hideAsync() async {
        glanceHideTask?.cancel()
        removeClickMonitor()
        store.save()
        isVisible = false
        await notch?.hide()
    }

    /// Dismiss interactive mode when the user clicks anywhere outside the notch.
    private func installClickMonitor() {
        removeClickMonitor()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    private func removeClickMonitor() {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
    }
}
