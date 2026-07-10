import Foundation
import SwiftData

/// A task captured for a future day ("Do the dishes tomorrow"). One-time tasks
/// keep their `deliveredAt` stamp after materializing into a `DayLog`, so a
/// future upcoming/overview UI can query both pending and past schedules.
/// Recurring tasks are templates that never deliver — `dueDate` always points
/// at the next occurrence and advances after each one materializes.
@Model
final class ScheduledTask {
    var text: String
    /// Start of day (midnight, local) of the next appearance.
    var dueDate: Date
    var createdAt: Date
    /// One-time tasks only: set once materialized into a day.
    var deliveredAt: Date?
    /// "day" | "week"; nil for a one-time task. Stored as discrete columns
    /// (not a Codable blob) so `#Predicate` can filter on them.
    var recurrenceUnit: String?
    /// Calendar weekday 1 (Sunday) – 7 (Saturday), when `recurrenceUnit` is "week".
    var recurrenceWeekday: Int?
    /// Always 1 for now; stored so "every 2 weeks" later won't need a migration.
    var recurrenceInterval: Int

    init(text: String, dueDate: Date, recurrence: Recurrence?, createdAt: Date = Date()) {
        self.text = text
        self.dueDate = dueDate
        self.createdAt = createdAt
        self.deliveredAt = nil
        self.recurrenceInterval = 1
        switch recurrence {
        case .daily:
            recurrenceUnit = "day"
            recurrenceWeekday = nil
        case .weekly(let weekday):
            recurrenceUnit = "week"
            recurrenceWeekday = weekday
        case nil:
            recurrenceUnit = nil
            recurrenceWeekday = nil
        }
    }

    var isRecurring: Bool { recurrenceUnit != nil }

    /// Typed view over the discrete recurrence columns.
    var recurrence: Recurrence? {
        switch recurrenceUnit {
        case "day": return .daily
        case "week": return recurrenceWeekday.map { .weekly(weekday: $0) }
        default: return nil
        }
    }

    /// Start of day of the next occurrence strictly after `date`. Falls back to
    /// the next day should the recurrence columns ever be malformed.
    func nextOccurrence(after date: Date, calendar: Calendar = .current) -> Date {
        (recurrence ?? .daily).nextOccurrence(after: date, calendar: calendar)
    }
}
