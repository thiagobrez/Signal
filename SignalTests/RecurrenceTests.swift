import XCTest

/// Date math for recurring tasks, pinned to fixed dates in January 2026
/// (Jan 7 is a Wednesday, Jan 12 a Monday, Jan 30 a Friday).
final class RecurrenceTests: XCTestCase {
    private let calendar = Calendar.current

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testDailyFromMidAfternoon() {
        let next = Recurrence.daily.nextOccurrence(after: date(2026, 1, 7, hour: 15), calendar: calendar)
        XCTAssertEqual(next, date(2026, 1, 8))
    }

    func testDailyFromMidnightIsStrictlyFuture() {
        let next = Recurrence.daily.nextOccurrence(after: date(2026, 1, 8), calendar: calendar)
        XCTAssertEqual(next, date(2026, 1, 9))
    }

    func testWeeklyLaterSameWeek() {
        // From Wednesday afternoon to Friday (weekday 6).
        let next = Recurrence.weekly(weekday: 6).nextOccurrence(after: date(2026, 1, 7, hour: 15), calendar: calendar)
        XCTAssertEqual(next, date(2026, 1, 9))
    }

    func testWeeklySameWeekdayAdvancesAFullWeek() {
        // Monday midnight, rule fires Mondays (weekday 2) → strictly the next one.
        let next = Recurrence.weekly(weekday: 2).nextOccurrence(after: date(2026, 1, 12), calendar: calendar)
        XCTAssertEqual(next, date(2026, 1, 19))
    }

    func testWeeklyAcrossMonthBoundary() {
        // Friday Jan 30, rule fires Fridays → Friday Feb 6.
        let next = Recurrence.weekly(weekday: 6).nextOccurrence(after: date(2026, 1, 30), calendar: calendar)
        XCTAssertEqual(next, date(2026, 2, 6))
    }
}
