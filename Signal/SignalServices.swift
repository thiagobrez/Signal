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

    private init() {
        SettingsStore.registerDefaults()

        do {
            container = try ModelContainer(for: DayLog.self, TodoItem.self)
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }

        store = SignalStore(context: container.mainContext)
        controller = NotchController(store: store)
        scheduler = Scheduler(controller: controller)
        onboarding = OnboardingWindowController()
    }

    /// Wires up the hotkey, scheduler, and the launch-time prompt. Called from the AppDelegate.
    func start() {
        if KeyboardShortcuts.getShortcut(for: .toggleSignal) == nil {
            KeyboardShortcuts.setShortcut(.init(.s, modifiers: [.control, .option]), for: .toggleSignal)
        }
        KeyboardShortcuts.onKeyUp(for: .toggleSignal) { [controller] in
            controller.toggle()
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
}
