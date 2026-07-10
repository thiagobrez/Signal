import Foundation
import SwiftData

/// Owns "today's" to-dos and the day-transition logic (carry-over + history).
@MainActor
@Observable
final class SignalStore {
    private let context: ModelContext

    /// The number of slots a fresh day starts with — the "three things" at the
    /// heart of Signal. A day can grow beyond this when the user adds tasks.
    static let defaultTaskCount = 3
    /// Floor a day can be trimmed to via deletion — there's always one task.
    static let minTaskCount = 1
    /// Upper bound on tasks per day, so the list can't outgrow the notch panel.
    static let maxTaskCount = 6

    /// Today's log and its tasks: at least `defaultTaskCount`, more if the user
    /// added some (or that many incomplete tasks carried over from a prior day).
    private(set) var today: DayLog?
    private(set) var items: [TodoItem] = []

    /// Bumped the moment every task becomes complete, so the view can fire
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
            ensureMinimumSlots(existing)
        } else {
            today = createDayLog(for: startOfToday)
        }

        if let today {
            materializePending(into: today, on: startOfToday)
        }

        items = today?.orderedItems ?? []
    }

    var completedCount: Int {
        items.filter(\.isCompleted).count
    }

    /// Whether the day is fully done: every task complete. An empty slot can't be
    /// completed, so this also requires every slot to be filled.
    var isDayComplete: Bool {
        !items.isEmpty && completedCount == items.count
    }

    /// A new empty task can be added while there's room and no slot is still
    /// blank — so the user fills what they have before stacking on more.
    var canAddTask: Bool {
        items.count < Self.maxTaskCount && items.allSatisfy { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// A task can be removed as long as it wouldn't drop the day below its floor.
    var canDeleteTask: Bool {
        items.count > Self.minTaskCount
    }

    func toggleComplete(_ item: TodoItem) {
        // An empty to-do can't be completed.
        if !item.isCompleted, item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }
        item.isCompleted.toggle()
        item.completedAt = item.isCompleted ? Date() : nil
        if item.isCompleted {
            // Completing the final task is the big moment: celebrate instead of
            // the ordinary per-task chime so the two sounds don't pile up.
            if isDayComplete {
                celebrationTrigger &+= 1
                Analytics.dayCompleted()
                SoundPlayer.play(SettingsStore.celebrationSound)
            } else {
                SoundPlayer.play(SettingsStore.completionSound)
            }
        }
        save()
    }

    /// Appends a fresh empty slot to today and returns its index, so the caller
    /// can move focus to it. No-op (returns nil) when `canAddTask` is false.
    @discardableResult
    func addTask() -> Int? {
        guard canAddTask, let today else { return nil }
        let item = TodoItem(text: "", isCompleted: false, order: items.count)
        item.day = today
        context.insert(item)
        save()
        items = today.orderedItems
        return items.count - 1
    }

    /// Removes a task and re-packs the remaining slots so `order` stays a
    /// contiguous 0-based sequence (which keeps `addTask`'s ordering correct).
    /// No-op when `canDeleteTask` is false.
    func deleteTask(_ item: TodoItem) {
        guard canDeleteTask, let today else { return }
        context.delete(item)
        let remaining = today.orderedItems.filter { $0.persistentModelID != item.persistentModelID }
        for (index, todo) in remaining.enumerated() {
            todo.order = index
        }
        save()
        items = remaining
    }

    func save() {
        try? context.save()
    }

    // MARK: - Scheduling

    /// Moves a row out of today and into the future: stores a `ScheduledTask`
    /// built from the parsed phrase, then removes the source slot (or just
    /// clears it when the day is already at its floor).
    func schedule(_ item: TodoItem, parse: ScheduleParse) {
        let task = ScheduledTask(text: parse.cleanText, dueDate: parse.dueDate, recurrence: parse.recurrence)
        context.insert(task)

        if canDeleteTask {
            deleteTask(item)
        } else {
            item.text = ""
            save()
        }
    }

    /// Fills today with any scheduled tasks that have come due. Idempotent —
    /// delivered one-time tasks fail the `deliveredAt == nil` predicate and
    /// recurring tasks advance `dueDate` past today — so it's safe on every
    /// open. Blank slots are claimed first, then the day grows up to its cap;
    /// when full, one-time tasks stay pending for the next open and recurring
    /// tasks skip the occurrence.
    private func materializePending(into log: DayLog, on date: Date) {
        let descriptor = FetchDescriptor<ScheduledTask>(
            predicate: #Predicate { $0.dueDate <= date && $0.deliveredAt == nil },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        guard let due = try? context.fetch(descriptor), !due.isEmpty else { return }

        var changed = false
        for task in due {
            let text = task.text.trimmingCharacters(in: .whitespacesAndNewlines)

            // Carry-over may already have brought the same unfinished task
            // into today (e.g. an incomplete "every day" task) — don't double up.
            let alreadyPresent = log.items.contains {
                !$0.isCompleted && $0.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(text) == .orderedSame
            }

            if !alreadyPresent {
                if let blank = log.orderedItems.first(where: {
                    !$0.isCompleted && $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }) {
                    blank.text = task.text
                } else if log.items.count < Self.maxTaskCount {
                    let item = TodoItem(text: task.text, isCompleted: false, order: log.items.count)
                    item.day = log
                    context.insert(item)
                } else {
                    // Day is full: recurring skips this occurrence; one-time
                    // stays pending and is retried on the next open.
                    if task.isRecurring {
                        task.dueDate = task.nextOccurrence(after: date)
                        changed = true
                    }
                    continue
                }
            }

            if task.isRecurring {
                task.dueDate = task.nextOccurrence(after: date)
            } else {
                task.deliveredAt = Date()
            }
            changed = true
        }

        if changed { save() }
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

        // Start with the default number of slots, but grow to fit every carried
        // task so nothing is dropped when a prior day had more than three.
        let slotCount = min(Self.maxTaskCount, max(Self.defaultTaskCount, carried.count))
        for index in 0 ..< slotCount {
            let text = index < carried.count ? carried[index] : ""
            let item = TodoItem(text: text, isCompleted: false, order: index)
            item.day = log
            context.insert(item)
        }

        save()
        return log
    }

    /// Defensive: make sure a loaded day is never empty. A fresh day starts at
    /// `defaultTaskCount` (see `createDayLog`); days the user has grown or
    /// trimmed are left as-is, down to the `minTaskCount` floor.
    private func ensureMinimumSlots(_ log: DayLog) {
        let count = log.items.count
        guard count < Self.minTaskCount else { return }
        for index in count ..< Self.minTaskCount {
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
