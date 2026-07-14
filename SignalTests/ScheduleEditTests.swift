import XCTest

/// dueDate recompute rules for the overview's structured edit controls,
/// pinned to fixed dates in January 2026 (Jan 7 is a Wednesday, Jan 12 a
/// Monday) — same convention as RecurrenceTests.
final class ScheduleEditTests: XCTestCase {
    private let calendar = Calendar.current

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testOneTimeFloorsToStartOfDay() {
        let edit = ScheduleEdit.oneTime(date: date(2026, 1, 20, hour: 17))
        XCTAssertEqual(edit.dueDate(now: date(2026, 1, 7), calendar: calendar), date(2026, 1, 20))
    }

    func testDailyStartsTomorrow() {
        let due = ScheduleEdit.daily.dueDate(now: date(2026, 1, 7, hour: 15), calendar: calendar)
        XCTAssertEqual(due, date(2026, 1, 8))
    }

    func testDailyFromMidnightIsStrictlyFuture() {
        let due = ScheduleEdit.daily.dueDate(now: date(2026, 1, 8), calendar: calendar)
        XCTAssertEqual(due, date(2026, 1, 9))
    }

    func testWeeklyLaterSameWeek() {
        // Wednesday afternoon → Friday (weekday 6) two days later.
        let due = ScheduleEdit.weekly(weekday: 6).dueDate(now: date(2026, 1, 7, hour: 15), calendar: calendar)
        XCTAssertEqual(due, date(2026, 1, 9))
    }

    func testWeeklySameWeekdayAdvancesAFullWeek() {
        // Monday, switching to "every Monday" → next Monday, not today.
        let due = ScheduleEdit.weekly(weekday: 2).dueDate(now: date(2026, 1, 12), calendar: calendar)
        XCTAssertEqual(due, date(2026, 1, 19))
    }

    func testWeeklyAcrossMonthBoundary() {
        // Friday Jan 30 → Friday Feb 6.
        let due = ScheduleEdit.weekly(weekday: 6).dueDate(now: date(2026, 1, 30), calendar: calendar)
        XCTAssertEqual(due, date(2026, 2, 6))
    }

    func testRecurrenceMapping() {
        XCTAssertNil(ScheduleEdit.oneTime(date: Date()).recurrence)
        XCTAssertEqual(ScheduleEdit.daily.recurrence, .daily)
        XCTAssertEqual(ScheduleEdit.weekly(weekday: 4).recurrence, .weekly(weekday: 4))
    }
}
