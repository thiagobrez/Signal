import XCTest

/// Monday-first week math and the occurrence rule behind the schedule
/// overview. Pinned to January 2026: Jan 12 is a Monday, Jan 18 a Sunday.
final class ScheduleGridTests: XCTestCase {
    private let calendar = Calendar.current

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    // MARK: - weekStart

    func testWeekStartForEveryDayOfTheWeek() {
        let monday = date(2026, 1, 12)
        // Jan 12 (Mon) … Jan 18 (Sun) all belong to the same Monday-first week.
        for offset in 0 ..< 7 {
            let day = calendar.date(byAdding: .day, value: offset, to: monday)!
            XCTAssertEqual(
                ScheduleGrid.weekStart(containing: day, calendar: calendar), monday,
                "offset \(offset)"
            )
        }
    }

    func testWeekStartIgnoresLocaleFirstWeekday() {
        // A US-style calendar (weeks start Sunday) must not shift the grid.
        var us = Calendar(identifier: .gregorian)
        us.firstWeekday = 1
        us.timeZone = calendar.timeZone
        let sunday = us.date(from: DateComponents(year: 2026, month: 1, day: 18))!
        let monday = us.date(from: DateComponents(year: 2026, month: 1, day: 12))!
        XCTAssertEqual(ScheduleGrid.weekStart(containing: sunday, calendar: us), monday)
    }

    func testWeekDaysReturnsMondayThroughSunday() {
        let days = ScheduleGrid.weekDays(from: date(2026, 1, 12), calendar: calendar)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.first, date(2026, 1, 12))
        XCTAssertEqual(days.last, date(2026, 1, 18))
    }

    // MARK: - occurs

    func testOneTimeOccursOnlyOnItsDay() {
        let due = date(2026, 1, 14)
        XCTAssertTrue(ScheduleGrid.occurs(dueDate: due, recurrence: nil, deliveredAt: nil, on: due, calendar: calendar))
        XCTAssertFalse(ScheduleGrid.occurs(dueDate: due, recurrence: nil, deliveredAt: nil, on: date(2026, 1, 15), calendar: calendar))
        XCTAssertFalse(ScheduleGrid.occurs(dueDate: due, recurrence: nil, deliveredAt: nil, on: date(2026, 1, 13), calendar: calendar))
    }

    func testDeliveredOneTimeNeverOccurs() {
        let due = date(2026, 1, 14)
        XCTAssertFalse(ScheduleGrid.occurs(dueDate: due, recurrence: nil, deliveredAt: Date(), on: due, calendar: calendar))
    }

    func testOverduePendingOneTimeStillOccursOnItsDay() {
        // App not opened since the due day: the task should still show there.
        let due = date(2026, 1, 5)
        XCTAssertTrue(ScheduleGrid.occurs(dueDate: due, recurrence: nil, deliveredAt: nil, on: due, calendar: calendar))
    }

    func testDailyOccursFromDueDateOnward() {
        let due = date(2026, 1, 14)
        XCTAssertFalse(ScheduleGrid.occurs(dueDate: due, recurrence: .daily, deliveredAt: nil, on: date(2026, 1, 13), calendar: calendar))
        XCTAssertTrue(ScheduleGrid.occurs(dueDate: due, recurrence: .daily, deliveredAt: nil, on: due, calendar: calendar))
        XCTAssertTrue(ScheduleGrid.occurs(dueDate: due, recurrence: .daily, deliveredAt: nil, on: date(2026, 3, 2), calendar: calendar))
    }

    func testWeeklyOccursOnlyOnItsWeekdayFromDueDateOnward() {
        // Due next Wednesday Jan 14, repeats Wednesdays (weekday 4).
        let due = date(2026, 1, 14)
        let rule = Recurrence.weekly(weekday: 4)
        XCTAssertTrue(ScheduleGrid.occurs(dueDate: due, recurrence: rule, deliveredAt: nil, on: due, calendar: calendar))
        // The Wednesday before dueDate — occurrence already materialized.
        XCTAssertFalse(ScheduleGrid.occurs(dueDate: due, recurrence: rule, deliveredAt: nil, on: date(2026, 1, 7), calendar: calendar))
        // Other weekdays never match.
        XCTAssertFalse(ScheduleGrid.occurs(dueDate: due, recurrence: rule, deliveredAt: nil, on: date(2026, 1, 15), calendar: calendar))
        // Far-future Wednesdays keep occurring.
        XCTAssertTrue(ScheduleGrid.occurs(dueDate: due, recurrence: rule, deliveredAt: nil, on: date(2026, 6, 3), calendar: calendar))
    }
}
