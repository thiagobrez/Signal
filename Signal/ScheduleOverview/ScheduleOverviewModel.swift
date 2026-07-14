import Foundation
import SwiftData

/// State for the schedule overview: which period is visible, in which mode,
/// and the pending schedules that fall inside it. All occurrence math is
/// delegated to `ScheduleGrid` so the rules stay unit-tested in one place.
@MainActor
@Observable
final class ScheduleOverviewModel {
    enum ViewMode: String, CaseIterable {
        case week = "Week"
        case month = "Month"
        case year = "Year"
    }

    private let repository: ScheduleRepository
    private let calendar = Calendar.current

    var mode: ViewMode = .week
    /// Any day inside the visible week / month / year.
    private(set) var anchor: Date
    /// Day emphasized after a month → week drill-down; cleared on navigation.
    private(set) var highlightedDay: Date?
    private(set) var tasks: [ScheduledTask] = []
    /// Each day's actual to-dos (today's live list + past history), keyed by
    /// start-of-day, shown alongside the upcoming schedules.
    private(set) var dayTasks: [Date: [TodoItem]] = [:]

    init(repository: ScheduleRepository) {
        self.repository = repository
        anchor = Calendar.current.startOfDay(for: Date())
    }

    /// Fresh state for a new presentation: this week, Week mode, current data.
    func reset() {
        mode = .week
        anchor = calendar.startOfDay(for: Date())
        highlightedDay = nil
        refresh()
    }

    func refresh() {
        tasks = repository.pending()
        dayTasks = repository.dayTasksByDay(calendar: calendar)
    }

    // MARK: - Navigation

    func goPrevious() { step(-1) }
    func goNext() { step(1) }

    private func step(_ direction: Int) {
        let component: Calendar.Component
        switch mode {
        case .week: component = .weekOfYear
        case .month: component = .month
        case .year: component = .year
        }
        anchor = calendar.date(byAdding: component, value: direction, to: anchor) ?? anchor
        highlightedDay = nil
    }

    func goToToday() {
        anchor = calendar.startOfDay(for: Date())
        highlightedDay = nil
    }

    /// Month cell tap: zoom into the week containing that day.
    func drillDown(to day: Date) {
        anchor = day
        highlightedDay = day
        mode = .week
    }

    /// Year cell tap: zoom into that month.
    func drillDown(toMonth month: Date) {
        anchor = month
        highlightedDay = nil
        mode = .month
    }

    /// iOS-Calendar-style back-out: week → month → year.
    func zoomOut() {
        switch mode {
        case .week: mode = .month
        case .month: mode = .year
        case .year: break
        }
        highlightedDay = nil
    }

    // MARK: - Week mode

    /// Monday…Sunday of the visible week.
    var weekDays: [Date] {
        ScheduleGrid.weekDays(from: ScheduleGrid.weekStart(containing: anchor, calendar: calendar), calendar: calendar)
    }

    /// Daily recurring tasks that occur at all in the visible week — shown once
    /// in the "Every day" section rather than repeated on all seven rows.
    var dailyTasks: [ScheduledTask] {
        guard let lastDay = weekDays.last else { return [] }
        return tasks.filter {
            $0.recurrence == .daily && occurs($0, on: lastDay)
        }
    }

    /// One-time and weekly schedules that fall on `day` (daily ones live in the
    /// "Every day" section).
    func tasks(on day: Date) -> [ScheduledTask] {
        tasks.filter { $0.recurrence != .daily && occurs($0, on: day) }
    }

    /// Everything shown on `day`'s row: its upcoming schedules first, then the
    /// day's real to-dos.
    func entries(on day: Date) -> [OverviewEntry] {
        tasks(on: day).map(OverviewEntry.scheduled)
            + (dayTasks[day] ?? []).map(OverviewEntry.todo)
    }

    var weekIsEmpty: Bool {
        dailyTasks.isEmpty && weekDays.allSatisfy { entries(on: $0).isEmpty }
    }

    // MARK: - Month mode

    /// Six Monday-first rows (42 days) covering the anchor month, including the
    /// dimmed leading/trailing days of the neighboring months.
    var monthCells: [Date] {
        guard let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: anchor)) else {
            return []
        }
        let gridStart = ScheduleGrid.weekStart(containing: firstOfMonth, calendar: calendar)
        return (0 ..< 42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    func isInAnchorMonth(_ day: Date) -> Bool {
        calendar.isDate(day, equalTo: anchor, toGranularity: .month)
    }

    /// Dot count for a month cell — daily schedules and the day's real to-dos
    /// count too.
    func taskCount(on day: Date) -> Int {
        tasks.filter { occurs($0, on: day) }.count + (dayTasks[day]?.count ?? 0)
    }

    // MARK: - Year mode

    /// The first day of each month of the anchor year.
    var yearMonths: [Date] {
        let year = calendar.component(.year, from: anchor)
        return (1 ... 12).compactMap {
            calendar.date(from: DateComponents(year: year, month: $0, day: 1))
        }
    }

    /// Every day of the anchor year with at least one occurrence — precomputed
    /// as a set so the year grid renders in a single pass over the tasks.
    func taskDaysInYear() -> Set<Date> {
        let year = calendar.component(.year, from: anchor)
        guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))
        else { return [] }

        var days: Set<Date> = []
        var day = start
        while day < end {
            if dayTasks[day] != nil || tasks.contains(where: { occurs($0, on: day) }) {
                days.insert(day)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    // MARK: - Header

    var periodTitle: String {
        switch mode {
        case .week:
            guard let start = weekDays.first, let end = weekDays.last else { return "" }
            let sameMonth = calendar.isDate(start, equalTo: end, toGranularity: .month)
            let sameYear = calendar.isDate(start, equalTo: end, toGranularity: .year)
            if sameMonth {
                return "\(format(start, "MMM d")) – \(format(end, "d, yyyy"))"
            } else if sameYear {
                return "\(format(start, "MMM d")) – \(format(end, "MMM d, yyyy"))"
            }
            return "\(format(start, "MMM d, yyyy")) – \(format(end, "MMM d, yyyy"))"
        case .month:
            return format(anchor, "MMMM yyyy")
        case .year:
            return format(anchor, "yyyy")
        }
    }

    private func format(_ date: Date, _ template: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = template
        return formatter.string(from: date)
    }

    // MARK: - Mutations

    func delete(_ task: ScheduledTask) {
        repository.delete(task)
        refresh()
    }

    func apply(_ edit: ScheduleEdit, to task: ScheduledTask) {
        repository.update(task, to: edit)
        refresh()
    }

    // MARK: - Helpers

    private func occurs(_ task: ScheduledTask, on day: Date) -> Bool {
        ScheduleGrid.occurs(
            dueDate: task.dueDate,
            recurrence: task.recurrence,
            deliveredAt: task.deliveredAt,
            on: day,
            calendar: calendar
        )
    }
}
