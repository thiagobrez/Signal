import Foundation
import SwiftData

/// Owns "today's" three to-dos and the day-transition logic (carry-over + history).
@MainActor
@Observable
final class SignalStore {
    private let context: ModelContext

    /// Today's log and its three items, always exactly three.
    private(set) var today: DayLog?
    private(set) var items: [TodoItem] = []

    /// Bumped the moment all three to-dos become complete, so the view can fire
    /// the celebration (grass + sound). Only fires on the transition
    /// *into* a fully-done day, not on every toggle.
    private(set) var celebrationTrigger = 0

    init(context: ModelContext) {
        self.context = context
        refreshForToday()
    }

    /// Resolves the current day, creating it (with carry-over) on a new day.
    /// Safe to call on every open — it's a no-op once today's log exists.
    func refreshForToday() {
        let startOfToday = Calendar.current.startOfDay(for: Date())

        if let existing = fetchDayLog(for: startOfToday) {
            today = existing
            ensureThreeSlots(existing)
        } else {
            today = createDayLog(for: startOfToday)
        }

        items = today?.orderedItems ?? []
    }

    var completedCount: Int {
        items.filter(\.isCompleted).count
    }

    func toggleComplete(_ item: TodoItem) {
        // An empty to-do can't be completed.
        if !item.isCompleted, item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }
        item.isCompleted.toggle()
        item.completedAt = item.isCompleted ? Date() : nil
        if item.isCompleted {
            // Reaching all three is the big moment: celebrate instead of the
            // ordinary per-task chime so the two sounds don't pile up.
            if completedCount == 3 {
                celebrationTrigger &+= 1
                SoundPlayer.play(SettingsStore.celebrationSound)
            } else {
                SoundPlayer.play(SettingsStore.completionSound)
            }
        }
        save()
    }

    func save() {
        try? context.save()
    }

    // MARK: - Day transition

    private func createDayLog(for date: Date) -> DayLog {
        let log = DayLog(date: date)
        context.insert(log)

        var carried: [String] = []
        if SettingsStore.carryOverIncomplete, let prior = mostRecentPriorLog(before: date) {
            carried = prior.orderedItems
                .filter { !$0.isCompleted && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
                .map(\.text)
        }

        for index in 0 ..< 3 {
            let text = index < carried.count ? carried[index] : ""
            let item = TodoItem(text: text, isCompleted: false, order: index)
            item.day = log
            context.insert(item)
        }

        save()
        return log
    }

    /// Defensive: make sure a loaded day always exposes three slots.
    private func ensureThreeSlots(_ log: DayLog) {
        let count = log.items.count
        guard count < 3 else { return }
        for index in count ..< 3 {
            let item = TodoItem(text: "", isCompleted: false, order: index)
            item.day = log
            context.insert(item)
        }
        save()
    }

    // MARK: - Fetches

    private func fetchDayLog(for date: Date) -> DayLog? {
        var descriptor = FetchDescriptor<DayLog>(predicate: #Predicate { $0.date == date })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func mostRecentPriorLog(before date: Date) -> DayLog? {
        var descriptor = FetchDescriptor<DayLog>(
            predicate: #Predicate { $0.date < date },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
