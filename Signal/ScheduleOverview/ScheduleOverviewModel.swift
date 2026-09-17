import Foundation
import SwiftData

/// State for the schedule overview: which period is visible, in which mode,
/// the pending schedules that fall inside it, and — since the overview became
/// a place to *manage* tasks rather than only look at them — where the keyboard
/// is and what adding, editing and removing do on each day. All occurrence math
/// is delegated to `ScheduleGrid` so the rules stay unit-tested in one place.
///
/// Days divide three ways (`ScheduleGrid.DayKind`):
/// - **past**: history, read-only.
/// - **today**: the live list, owned by `SignalStore` — the very same rows the
///   panel shows, edited through the very same store.
/// - **future**: `ScheduledTask`s. Adding a task to a future day *is* creating
///   a schedule for that day, which is why no `DayLog` is ever written ahead of
///   time.
@MainActor
@Observable
final class ScheduleOverviewModel {
    enum ViewMode: String, CaseIterable {
        case week = "Week"
        case month = "Month"
        case year = "Year"
    }

    private let repository: ScheduleRepository
    let store: SignalStore
    private let calendar = Calendar.current

    var mode: ViewMode = .week {
        didSet { if mode != oldValue { endEditing() } }
    }
    /// Any day inside the visible week / month / year.
    private(set) var anchor: Date
    /// Day emphasized after a month → week drill-down; cleared on navigation.
    private(set) var highlightedDay: Date?
    private(set) var tasks: [ScheduledTask] = []
    /// Each day's actual to-dos, keyed by start-of-day, for the days whose rows
    /// are history. Today's row is not read from here — it comes live off the
    /// store — but the month and year dot counts still are.
    private(set) var dayTasks: [Date: [TodoItem]] = [:]

    /// Which row holds the keyboard, by model ID rather than by position: rows
    /// are added, deleted and re-dated under the caret, and every one of those
    /// shifts an index-based focus onto the wrong task.
    var focusedID: PersistentIdentifier?

    /// Whether a row is being typed into, which suspends the plain-key
    /// navigation shortcuts so "t" and the arrows reach the text.
    var isEditing: Bool { focusedID != nil }

    init(repository: ScheduleRepository, store: SignalStore) {
        self.repository = repository
        self.store = store
        anchor = Calendar.current.startOfDay(for: Date())
    }

    /// Fresh state for a new presentation: this week, Week mode, current data,
    /// no caret, and none of the previous session's abandoned drafts.
    func reset() {
        mode = .week
        anchor = calendar.startOfDay(for: Date())
        highlightedDay = nil
        focusedID = nil
        repository.purgeEmpty()
        refresh()
    }

    func refresh() {
        tasks = repository.pending()
        dayTasks = repository.dayTasksByDay(calendar: calendar)
    }

    var today: Date { calendar.startOfDay(for: Date()) }

    func kind(of day: Date) -> ScheduleGrid.DayKind {
        ScheduleGrid.kind(of: day, today: today, calendar: calendar)
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
        endEditing()
        anchor = calendar.date(byAdding: component, value: direction, to: anchor) ?? anchor
        highlightedDay = nil
    }

    func goToToday() {
        endEditing()
        anchor = calendar.startOfDay(for: Date())
        highlightedDay = nil
    }

    /// Month cell tap: zoom into the week containing that day.
    func drillDown(to day: Date) {
        endEditing()
        anchor = day
        highlightedDay = day
        mode = .week
    }

    /// Year cell tap: zoom into that month.
    func drillDown(toMonth month: Date) {
        endEditing()
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

    /// Everything shown on `day`'s row, in display order.
    ///
    /// Today is the live list straight off the store — the same rows as the
    /// panel, blank slots included, so a slot can be typed into here too. Every
    /// other day is its schedules, and a past day also carries the to-dos it
    /// actually held.
    func entries(on day: Date) -> [OverviewEntry] {
        switch kind(of: day) {
        case .today:
            return store.items.map(OverviewEntry.todo)
        case .future:
            return tasks(on: day).map(OverviewEntry.scheduled)
        case .past:
            return tasks(on: day).map(OverviewEntry.scheduled)
                + (dayTasks[day] ?? []).map(OverviewEntry.todo)
        }
    }

    /// True only when there is nothing to show *and* nothing can be added:
    /// a week containing today or a future day always has its add buttons, so
    /// it is never replaced by the empty state.
    var weekIsEmpty: Bool {
        guard dailyTasks.isEmpty, weekDays.allSatisfy({ entries(on: $0).isEmpty }) else { return false }
        return weekDays.allSatisfy { kind(of: $0) == .past }
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

    // MARK: - Focus

    /// Every editable row in the week, in the order the keyboard walks them:
    /// the EVERY DAY section, then each day from today onward. Past days are
    /// read-only, so they are not in the order at all.
    var focusRows: [OverviewFocusRow] {
        var rows = dailyTasks.map {
            OverviewFocusRow(entry: .scheduled($0), day: nil, group: .daily)
        }
        for day in weekDays {
            switch kind(of: day) {
            case .past:
                continue
            case .today:
                rows += store.items.map {
                    OverviewFocusRow(
                        entry: .todo($0),
                        day: day,
                        group: $0.isScheduled ? .todayScheduled : .todayRegular
                    )
                }
            case .future:
                rows += tasks(on: day).map {
                    OverviewFocusRow(entry: .scheduled($0), day: day, group: .future(day))
                }
            }
        }
        return rows
    }

    var focusOrder: [PersistentIdentifier] { focusRows.map(\.id) }

    func focusIndex(of id: PersistentIdentifier?) -> Int? {
        guard let id else { return nil }
        return focusOrder.firstIndex(of: id)
    }

    func id(atFocusIndex index: Int?) -> PersistentIdentifier? {
        guard let index, focusOrder.indices.contains(index) else { return nil }
        return focusOrder[index]
    }

    /// Focus leaves the overview: commit what was typed, drop the caret, and
    /// clear away any draft row that was never given a name.
    func endEditing() {
        focusedID = nil
        store.save()
        repository.purgeEmpty()
        refresh()
    }

    /// Deletes a blank future draft the caret has just left. Only blanks, and
    /// never the row that now holds the keyboard.
    func pruneEmptyDraft(_ id: PersistentIdentifier?) {
        guard let id, id != focusedID,
              let task = tasks.first(where: { $0.persistentModelID == id }),
              task.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        repository.delete(task)
        refresh()
    }

    // MARK: - Mutations

    /// Adds a row to `day` and returns it so the caller can focus it.
    ///
    /// Today goes through the store — it's the same list the panel adds to.
    /// A future day gets a blank schedule, reusing one that's already there so
    /// hammering the button can't litter the day with empty rows. Past days
    /// refuse.
    @discardableResult
    func addTask(on day: Date) -> PersistentIdentifier? {
        switch kind(of: day) {
        case .past:
            return nil
        case .today:
            guard let index = store.addTask() else { return nil }
            return store.items[index].persistentModelID
        case .future:
            if let blank = tasks(on: day).first(where: {
                $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }) {
                return blank.persistentModelID
            }
            guard let task = repository.add(on: day) else { return nil }
            refresh()
            return task.persistentModelID
        }
    }

    func delete(_ task: ScheduledTask) {
        repository.delete(task)
        refresh()
    }

    /// Removes one of today's rows, honouring the store's floor of one.
    func delete(_ item: TodoItem) {
        guard store.canDelete(item) else { return }
        store.deleteTask(item)
    }

    func toggle(_ item: TodoItem) {
        store.toggleComplete(item)
    }

    /// Enter on one of today's rows that ends in a date phrase: the task leaves
    /// today for the day it names, exactly as it would in the panel.
    func schedule(_ item: TodoItem, parse: ScheduleParse) {
        store.schedule(item, parse: parse)
        refresh()
    }

    /// Enter on a future row that ends in a date phrase: the schedule itself
    /// moves, which is how a row becomes a routine without any popover.
    func reschedule(_ task: ScheduledTask, parse: ScheduleParse) {
        repository.reschedule(task, parse: parse)
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
