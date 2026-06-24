import AppKit
import Foundation

/// Arms timers for the daily prompt and the quick glances, and re-arms on
/// settings change, system wake, and at midnight.
@MainActor
final class Scheduler {
    private let controller: NotchController
    private var timers: [Timer] = []
    private var debounceTimer: Timer?

    private let lastPromptedKey = "lastPromptedDay"

    init(controller: NotchController) {
        self.controller = controller
    }

    func start() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsChanged),
            name: UserDefaults.didChangeNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(rebuild),
            name: NSWorkspace.didWakeNotification, object: nil
        )
        rebuild()
    }

    // MARK: - Prompt bookkeeping

    var promptedToday: Bool {
        guard let last = UserDefaults.standard.object(forKey: lastPromptedKey) as? Date else { return false }
        return Calendar.current.isDateInToday(last)
    }

    func markPromptedToday() {
        UserDefaults.standard.set(Date(), forKey: lastPromptedKey)
    }

    // MARK: - Scheduling

    @objc private func settingsChanged() {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.rebuild() }
        }
    }

    @objc func rebuild() {
        timers.forEach { $0.invalidate() }
        timers.removeAll()

        let cal = Calendar.current
        let now = Date()

        // Daily prompt.
        if SettingsStore.dailyPromptEnabled,
           let fire = cal.date(bySettingHour: SettingsStore.dailyPromptHour,
                               minute: SettingsStore.dailyPromptMinute,
                               second: 0, of: now) {
            if fire > now {
                schedule(at: fire) { [weak self] in self?.fireDailyPrompt() }
            } else if !promptedToday {
                fireDailyPrompt()
            }
        }

        // Quick glances.
        if SettingsStore.glancesEnabled {
            for fire in glanceTimes(on: now) where fire > now {
                schedule(at: fire) { [weak self] in self?.fireGlance() }
            }
        }

        // Re-arm for the new day.
        if let nextMidnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) {
            schedule(at: nextMidnight) { [weak self] in self?.rebuild() }
        }
    }

    /// Evenly distributes `glanceCount` times across the [start, end] hour window.
    private func glanceTimes(on date: Date) -> [Date] {
        let cal = Calendar.current
        let count = max(0, SettingsStore.glanceCount)
        guard count > 0,
              let start = cal.date(bySettingHour: SettingsStore.glanceWindowStartHour, minute: 0, second: 0, of: date),
              let end = cal.date(bySettingHour: SettingsStore.glanceWindowEndHour, minute: 0, second: 0, of: date),
              end > start else { return [] }

        let span = end.timeIntervalSince(start)
        if count == 1 {
            return [start.addingTimeInterval(span / 2)]
        }
        return (0 ..< count).map { start.addingTimeInterval(span * Double($0) / Double(count - 1)) }
    }

    private func schedule(at date: Date, action: @escaping () -> Void) {
        let timer = Timer(fire: date, interval: 0, repeats: false) { _ in
            Task { @MainActor in action() }
        }
        RunLoop.main.add(timer, forMode: .common)
        timers.append(timer)
    }

    private func fireDailyPrompt() {
        guard SettingsStore.dailyPromptEnabled else { return }
        markPromptedToday()
        controller.presentInteractive()
    }

    private func fireGlance() {
        guard SettingsStore.glancesEnabled, !controller.isVisible else { return }
        controller.presentGlance(duration: SettingsStore.glanceDurationSeconds)
    }
}
