import Foundation

/// The structured re-schedule choices offered by the overview's edit popover.
/// Lives beside `Recurrence` (persistence-free) so the edit rules stay
/// unit-testable without SwiftData.
enum ScheduleEdit: Equatable {
    /// A single future appearance on the given day.
    case oneTime(date: Date)
    case daily
    /// `weekday` uses Calendar's numbering: 1 (Sunday) – 7 (Saturday).
    case weekly(weekday: Int)

    /// nil for a one-time schedule.
    var recurrence: Recurrence? {
        switch self {
        case .oneTime: return nil
        case .daily: return .daily
        case .weekly(let weekday): return .weekly(weekday: weekday)
        }
    }

    /// The `dueDate` a task should carry after applying this edit at `now`.
    /// Recurring edits use the same strictly-future semantics as the parser —
    /// switching to "every Monday" on a Monday first fires the *next* Monday.
    func dueDate(now: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .oneTime(let date):
            return calendar.startOfDay(for: date)
        case .daily, .weekly:
            // recurrence is non-nil for both cases by construction.
            return recurrence!.nextOccurrence(after: now, calendar: calendar)
        }
    }
}
