import Foundation
import SwiftData
import KeyboardShortcuts

/// App-wide object graph. Created once and shared by the SwiftUI scenes and the AppDelegate.
@MainActor
final class SignalServices {
    static let shared = SignalServices()

    let container: ModelContainer
    let store: SignalStore
    let controller: NotchController
    let scheduler: Scheduler
    let onboarding: OnboardingWindowController
    let stats: StatsWindowController

    private init() {
        SettingsStore.registerDefaults()

        do {
            container = try ModelContainer(for: DayLog.self, TodoItem.self, ScheduledTask.self)
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }

        store = SignalStore(context: container.mainContext)
        controller = NotchController(store: store)
        scheduler = Scheduler(controller: controller)
        onboarding = OnboardingWindowController()
        stats = StatsWindowController(container: container)
    }

    /// Wires up the hotkeys, scheduler, and the launch-time prompt. Called from the AppDelegate.
    func start() {
        migrateToggleSignalShortcutIfNeeded()

        KeyboardShortcuts.onKeyUp(for: .toggleSignal) { [controller] in
            controller.toggle()
        }

        // Opening stats first thing on a new day must still create today's
        // log (with carry-over) before the window shows it.
        stats.willPresent = { [store] in
            store.refreshForToday()
        }
        KeyboardShortcuts.onKeyUp(for: .toggleStats) { [stats] in
            stats.toggle()
        }

        scheduler.start()

        // First launch: show onboarding instead of the notch so the two don't
        // collide. When it finishes, drop the user into the app just like a
        // normal open-on-launch. Afterwards, resume that behavior directly.
        if !SettingsStore.hasSeenOnboarding {
            onboarding.present { [controller, scheduler] in
                scheduler.markPromptedToday()
                SoundPlayer.play(SettingsStore.openSound)
                controller.presentInteractive(source: .launch)
            }
        } else if SettingsStore.openOnLaunch {
            scheduler.markPromptedToday()
            SoundPlayer.play(SettingsStore.openSound)
            controller.presentInteractive(source: .launch)
        }
    }

    /// The default toggle chord changed from ⌃⌥S to ⌘⇧T. Earlier launch code
    /// wrote the old default into UserDefaults as if the user had chosen it,
    /// so installs still on it are moved to the new default once; a custom
    /// chord is left alone. The flag keeps a later deliberate choice of ⌃⌥S
    /// from being reset again.
    private func migrateToggleSignalShortcutIfNeeded() {
        guard !SettingsStore.didMigrateToggleSignalShortcut else { return }
        SettingsStore.didMigrateToggleSignalShortcut = true

        if KeyboardShortcuts.getShortcut(for: .toggleSignal) == .init(.s, modifiers: [.control, .option]) {
            KeyboardShortcuts.reset(.toggleSignal)
        }
    }
}
