import Foundation

/// Calendar math for the schedule overview grid. The overview is hardcoded
/// Monday-first regardless of locale (Calendar's own `firstWeekday` is
/// deliberately ignored — note its weekday numbering keeps 1 = Sunday).
enum ScheduleGrid {
    /// Where a day sits relative to today, which is what decides whether the
    /// overview lets it be edited: history is read-only, today is the live
    /// list, and every day after it is the schedule.
    enum DayKind {
        case past, today, future

        /// Whether tasks can be added to, edited on, or removed from the day.
        var isEditable: Bool { self != .past }
    }

    static func kind(of day: Date, today: Date, calendar: Calendar = .current) -> DayKind {
        let start = calendar.startOfDay(for: day)
        let reference = calendar.startOfDay(for: today)
        if start == reference { return .today }
        return start < reference ? .past : .future
    }

    /// Monday 00:00 of the week containing `date`.
    static func weekStart(containing date: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: date)
        // Days since Monday: weekday 2 (Mon) → 0 … weekday 1 (Sun) → 6.
        let offset = (calendar.component(.weekday, from: day) + 5) % 7
        return calendar.date(byAdding: .day, value: -offset, to: day) ?? day
    }

    /// The seven days Monday…Sunday starting at `weekStart`.
    static func weekDays(from weekStart: Date, calendar: Calendar = .current) -> [Date] {
        (0 ..< 7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    /// Whether a schedule occurs on `day` (a start-of-day date).
    ///
    /// `dueDate` on a recurring task always points at the *next* occurrence and
    /// advances as occurrences materialize, so recurring tasks occur on every
    /// matching day from `dueDate` onward — past weeks stay clean, and today
    /// disappears once today's occurrence has already been delivered. Delivered
    /// one-time tasks never occur; pending ones occur only on their due day
    /// (which may be in the past when the app hasn't been opened since).
    static func occurs(
        dueDate: Date,
        recurrence: Recurrence?,
        deliveredAt: Date?,
        on day: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard deliveredAt == nil else { return false }
        switch recurrence {
        case nil:
            return calendar.startOfDay(for: dueDate) == day
        case .daily:
            return day >= dueDate
        case .weekly(let weekday):
            return day >= dueDate && calendar.component(.weekday, from: day) == weekday
        }
    }
}
