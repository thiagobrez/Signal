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

    /// Rewrites the recurrence columns and recomputes `dueDate` per
    /// `ScheduleEdit.dueDate(now:)`. An edit matching the task's current shape
    /// is a no-op, so opening the popover and hitting Save never silently
    /// pushes a recurring task's next occurrence a week out.
    func update(_ task: ScheduledTask, to edit: ScheduleEdit, now: Date = Date(), calendar: Calendar = .current) {
        let sameShape: Bool
        switch edit {
        case .oneTime(let date):
            sameShape = task.recurrence == nil && task.dueDate == calendar.startOfDay(for: date)
        case .daily, .weekly:
            sameShape = task.recurrence == edit.recurrence
        }
        guard !sameShape else { return }

        switch edit.recurrence {
        case .daily:
            task.recurrenceUnit = "day"
            task.recurrenceWeekday = nil
        case .weekly(let weekday):
            task.recurrenceUnit = "week"
            task.recurrenceWeekday = weekday
        case nil:
            task.recurrenceUnit = nil
            task.recurrenceWeekday = nil
        }
        task.dueDate = edit.dueDate(now: now, calendar: calendar)
        save()
    }

    private func save() {
        try? context.save()
    }
}
