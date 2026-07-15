import Foundation
import SwiftData
import KeyboardShortcuts

/// App-wide object graph. Created once and shared by the SwiftUI scenes and the AppDelegate.
@MainActor
final class SignalServices {
    static let shared = SignalServices()

    let container: ModelContainer
    let store: SignalStore
    let scheduleRepository: ScheduleRepository
    let controller: NotchController
    let scheduler: Scheduler
    let onboarding: OnboardingWindowController
    let whatsNew: WhatsNewWindowController
    let stats: StatsWindowController

    /// Pending long-press timer for the toggle hotkey; nil once it fires or
    /// the key is released.
    private var holdWorkItem: DispatchWorkItem?
    /// True between the long-press firing and the key release, so the
    /// trailing key-up doesn't also toggle the small panel.
    private var longPressFired = false
    /// How long ⌘⇧T must be held to open the schedule overview instead.
    private static let longPressThreshold: TimeInterval = 0.45

    private init() {
        SettingsStore.registerDefaults()

        do {
            container = try ModelContainer(for: DayLog.self, TodoItem.self, ScheduledTask.self)
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }

        store = SignalStore(context: container.mainContext)
        scheduleRepository = ScheduleRepository(context: container.mainContext)
        controller = NotchController(store: store, scheduleRepository: scheduleRepository)
        scheduler = Scheduler(controller: controller)
        onboarding = OnboardingWindowController()
        whatsNew = WhatsNewWindowController()
        stats = StatsWindowController(container: container)
    }

    /// Wires up the hotkeys, scheduler, and the launch-time prompt. Called from the AppDelegate.
    func start() {
        migrateToggleSignalShortcutIfNeeded()

        // The toggle hotkey does double duty: a short press toggles the task
        // panel (on release, as before), while holding it past the threshold
        // opens the schedule overview immediately — the release is then
        // swallowed so it doesn't also toggle the panel.
        KeyboardShortcuts.onKeyDown(for: .toggleSignal) { [weak self] in
            guard let self else { return }
            // Carbon can deliver repeated key-down events while held; only the
            // first one arms the timer.
            guard holdWorkItem == nil, !longPressFired else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                holdWorkItem = nil
                longPressFired = true
                controller.toggleOverview()
            }
            holdWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.longPressThreshold, execute: work)
        }
        KeyboardShortcuts.onKeyUp(for: .toggleSignal) { [weak self] in
            guard let self else { return }
            if let work = holdWorkItem {
                work.cancel()
                holdWorkItem = nil
                controller.toggle()
            } else {
                longPressFired = false
            }
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
        // normal open-on-launch. First launch after an update: show What's New
        // instead, then resume the open-on-launch behavior when it closes.
        let currentVersion = WhatsNewWindowController.currentVersion
        if !SettingsStore.hasSeenOnboarding {
            onboarding.present { [controller, scheduler] in
                // Finishing onboarding credits the user with the current
                // version, so a fresh install never sees old release notes.
                SettingsStore.lastSeenWhatsNewVersion = currentVersion
                scheduler.markPromptedToday()
                SoundPlayer.play(SettingsStore.openSound)
                controller.presentInteractive(source: .launch)
            }
        } else if SettingsStore.showWhatsNewAfterUpdates,
                  let lastSeen = SettingsStore.lastSeenWhatsNewVersion,
                  lastSeen != currentVersion,
                  let releases = WhatsNewWindowController.releasesSince(lastSeen),
                  !releases.isEmpty {
            whatsNew.present(releases: releases) { [controller, scheduler] in
                guard SettingsStore.openOnLaunch else { return }
                scheduler.markPromptedToday()
                SoundPlayer.play(SettingsStore.openSound)
                controller.presentInteractive(source: .launch)
            }
        } else {
            // Covers: up to date; a pre-What's-New install with no marker yet
            // (seed silently rather than showing a wall of old notes); a
            // downgrade; or a missing/unparseable bundled changelog.
            SettingsStore.lastSeenWhatsNewVersion = currentVersion
            if SettingsStore.openOnLaunch {
                scheduler.markPromptedToday()
                SoundPlayer.play(SettingsStore.openSound)
                controller.presentInteractive(source: .launch)
            }
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
