import Foundation
import SwiftData

/// CRUD over `ScheduledTask` for the schedule overview. Kept separate from
/// `SignalStore` (and free of its sound/analytics/settings dependencies) so it
/// compiles into the host-less test bundle alongside the model.
@MainActor
final class ScheduleRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// Every undelivered schedule: pending one-time tasks plus all recurring
    /// templates (which never deliver).
    func pending() -> [ScheduledTask] {
        let descriptor = FetchDescriptor<ScheduledTask>(
            predicate: #Predicate { $0.deliveredAt == nil },
            sortBy: [SortDescriptor(\.dueDate), SortDescriptor(\.createdAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// The actual (non-scheduled) to-dos of every day that has any, keyed by
    /// start-of-day — today's live tasks plus past days' history, so the
    /// overview shows real tasks alongside upcoming schedules. Empty slots are
    /// dropped.
    func dayTasksByDay(calendar: Calendar = .current) -> [Date: [TodoItem]] {
        let descriptor = FetchDescriptor<DayLog>(sortBy: [SortDescriptor(\.date)])
        guard let logs = try? context.fetch(descriptor) else { return [:] }

        var map: [Date: [TodoItem]] = [:]
        for log in logs {
            let items = log.orderedItems.filter {
                !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            if !items.isEmpty {
                map[calendar.startOfDay(for: log.date)] = items
            }
        }
        return map
    }

    /// Creates a schedule on `day`, which is how the overview adds a task to a
    /// future day: a day in the future *is* a schedule. Refused for a day
    /// already past — history is read-only. Inserted *and saved* before
    /// returning, because a SwiftData `persistentModelID` is only permanent
    /// once saved and the overview keys both its `ForEach` and its focus on it.
    @discardableResult
    func add(
        text: String = "",
        on day: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ScheduledTask? {
        let due = calendar.startOfDay(for: day)
        guard due >= calendar.startOfDay(for: now) else { return nil }
        let task = ScheduledTask(text: text, dueDate: due, recurrence: nil)
        context.insert(task)
        save()
        return task
    }

    /// Applies a freshly typed date phrase to an existing schedule: the text
    /// loses the phrase and the task moves to the day (or the routine) it names.
    func reschedule(_ task: ScheduledTask, parse: ScheduleParse) {
        task.text = parse.cleanText
        task.dueDate = parse.dueDate
        task.setRecurrence(parse.recurrence)
        save()
    }

    /// Drops undelivered schedules with no text — the blank rows the overview
    /// leaves behind when a draft is abandoned. `except` spares the one row the
    /// user is still typing into.
    func purgeEmpty(except kept: PersistentIdentifier? = nil) {
        let blanks = pending().filter {
            $0.persistentModelID != kept
                && $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !blanks.isEmpty else { return }
        blanks.forEach { context.delete($0) }
        save()
    }

    func delete(_ task: ScheduledTask) {
        context.delete(task)
        save()
    }

    func rename(_ task: ScheduledTask, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != task.text else { return }
        task.text = trimmed
        save()
    }

    private func save() {
        try? context.save()
    }
}
