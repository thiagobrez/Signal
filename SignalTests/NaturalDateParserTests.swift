import XCTest

/// Grammar tests pinned to a fixed "now": Wednesday, January 7, 2026, 15:00
/// local time, so weekday resolution is deterministic.
final class NaturalDateParserTests: XCTestCase {
    private let calendar = Calendar.current

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 1, day: 7, hour: 15))!
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func parse(_ text: String) -> ScheduleParse? {
        NaturalDateParser.parse(text, now: now, calendar: calendar)
    }

    // MARK: - One-time phrases

    func testTomorrow() throws {
        let parse = try XCTUnwrap(parse("Do the dishes tomorrow"))
        XCTAssertEqual(parse.cleanText, "Do the dishes")
        XCTAssertEqual(parse.dueDate, day(2026, 1, 8))
        XCTAssertNil(parse.recurrence)
        XCTAssertEqual(parse.matchedRange, NSRange(location: 14, length: 8))
        XCTAssertEqual(parse.confirmationLabel, "Scheduled for tomorrow")
    }

    func testBareWeekdayLaterThisWeek() throws {
        let parse = try XCTUnwrap(parse("call mom friday"))
        XCTAssertEqual(parse.cleanText, "call mom")
        XCTAssertEqual(parse.dueDate, day(2026, 1, 9))
        XCTAssertNil(parse.recurrence)
    }

    func testSameWeekdayMeansNextWeek() throws {
        // "now" is a Wednesday, so "wednesday" is strictly future: next week.
        let parse = try XCTUnwrap(parse("review wednesday"))
        XCTAssertEqual(parse.dueDate, day(2026, 1, 14))
    }

    func testInNDays() throws {
        let parse = try XCTUnwrap(parse("pay rent in 3 days"))
        XCTAssertEqual(parse.cleanText, "pay rent")
        XCTAssertEqual(parse.dueDate, day(2026, 1, 10))
        XCTAssertNil(parse.recurrence)
    }

    func testInNWeeks() throws {
        let parse = try XCTUnwrap(parse("dentist in 2 weeks"))
        XCTAssertEqual(parse.dueDate, day(2026, 1, 21))
    }

    func testInOneDayIsTomorrow() throws {
        let parse = try XCTUnwrap(parse("follow up in 1 day"))
        XCTAssertEqual(parse.dueDate, day(2026, 1, 8))
        XCTAssertEqual(parse.confirmationLabel, "Scheduled for tomorrow")
    }

    func testLiberalPluralization() {
        XCTAssertNotNil(parse("ship it in 1 days"))
        XCTAssertNotNil(parse("ship it in 2 week"))
    }

    func testZeroDaysRejected() {
        XCTAssertNil(parse("do it in 0 days"))
    }

    // MARK: - Recurring phrases

    func testEveryWeekday() throws {
        let parse = try XCTUnwrap(parse("gym every monday"))
        XCTAssertEqual(parse.cleanText, "gym")
        XCTAssertEqual(parse.recurrence, .weekly(weekday: 2))
        XCTAssertEqual(parse.dueDate, day(2026, 1, 12))
        XCTAssertEqual(parse.confirmationLabel, "Every Monday")
    }

    func testEveryDay() throws {
        let parse = try XCTUnwrap(parse("standup every day"))
        XCTAssertEqual(parse.recurrence, .daily)
        XCTAssertEqual(parse.dueDate, day(2026, 1, 8))
        XCTAssertEqual(parse.confirmationLabel, "Every day")
    }

    func testEverydayOneWord() throws {
        let parse = try XCTUnwrap(parse("journal everyday"))
        XCTAssertEqual(parse.recurrence, .daily)
        XCTAssertEqual(parse.cleanText, "journal")
    }

    func testEveryWeek() throws {
        // "now" is a Wednesday → weekly on Wednesdays, starting next week.
        let parse = try XCTUnwrap(parse("groceries every week"))
        XCTAssertEqual(parse.recurrence, .weekly(weekday: 4))
        XCTAssertEqual(parse.dueDate, day(2026, 1, 14))
        XCTAssertEqual(parse.confirmationLabel, "Every week")
    }

    // MARK: - Non-matches

    func testPhraseAloneIsJustText() {
        XCTAssertNil(parse("tomorrow"))
        XCTAssertNil(parse("every monday"))
        XCTAssertNil(parse("  tomorrow  "))
    }

    func testIntraWordKeywordsDontMatch() {
        XCTAssertNil(parse("Prepare for doomsday"))
        XCTAssertNil(parse("Read Tomorrowland"))
    }

    func testPhraseMustBeAtEnd() {
        XCTAssertNil(parse("tomorrow do the dishes"))
        XCTAssertNil(parse("the monday meeting notes"))
    }

    func testTrailingPunctuationDefeatsParse() {
        // The escape hatch for tasks that literally end in a keyword.
        XCTAssertNil(parse("Plan tomorrow."))
        XCTAssertNil(parse("gym every monday!"))
    }

    func testEmptyText() {
        XCTAssertNil(parse(""))
    }

    // MARK: - Mechanics

    func testCaseInsensitive() throws {
        let parse = try XCTUnwrap(parse("Call Mom TOMORROW"))
        XCTAssertEqual(parse.cleanText, "Call Mom")
        XCTAssertEqual(try XCTUnwrap(self.parse("gym Every Friday")).confirmationLabel, "Every Friday")
    }

    func testTrailingWhitespaceTolerated() throws {
        let parse = try XCTUnwrap(parse("water plants tomorrow  "))
        XCTAssertEqual(parse.cleanText, "water plants")
    }

    func testMatchedRangeIsUTF16() throws {
        // The pizza emoji is two UTF-16 units; the range must account for it
        // since it feeds NSTextStorage highlighting.
        let text = "🍕 order pizza tomorrow"
        let parse = try XCTUnwrap(NaturalDateParser.parse(text, now: now, calendar: calendar))
        XCTAssertEqual(parse.cleanText, "🍕 order pizza")
        let ns = text as NSString
        XCTAssertEqual(parse.matchedRange, NSRange(location: ns.length - 8, length: 8))
        XCTAssertEqual(ns.substring(with: parse.matchedRange), "tomorrow")
    }
}
