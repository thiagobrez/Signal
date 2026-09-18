import XCTest
import SwiftData

/// ScheduleRepository CRUD against an in-memory SwiftData container. Dates are
/// pinned to January 2026 (Jan 12 is a Monday, Jan 14 a Wednesday).
@MainActor
final class ScheduleRepositoryTests: XCTestCase {
    private let calendar = Calendar.current
    private var container: ModelContainer!
    private var repository: ScheduleRepository!

    override func setUp() async throws {
        container = try ModelContainer(
            for: ScheduledTask.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        repository = ScheduleRepository(context: container.mainContext)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @discardableResult
    private func insert(
        _ text: String,
        due: Date,
        recurrence: Recurrence? = nil,
        deliveredAt: Date? = nil
    ) -> ScheduledTask {
        let task = ScheduledTask(text: text, dueDate: due, recurrence: recurrence)
        task.deliveredAt = deliveredAt
        container.mainContext.insert(task)
        try? container.mainContext.save()
        return task
    }

    // MARK: - pending

    func testPendingExcludesDeliveredAndSortsByDueDate() {
        insert("later", due: date(2026, 1, 20))
        insert("sooner", due: date(2026, 1, 14))
        insert("done", due: date(2026, 1, 10), deliveredAt: Date())

        let pending = repository.pending()
        XCTAssertEqual(pending.map(\.text), ["sooner", "later"])
    }

    // MARK: - delete / rename

    func testDeleteRemovesTask() {
        let task = insert("water plants", due: date(2026, 1, 14), recurrence: .daily)
        repository.delete(task)
        XCTAssertTrue(repository.pending().isEmpty)
    }

    func testRenameTrimsAndIgnoresEmpty() {
        let task = insert("water plants", due: date(2026, 1, 14))
        repository.rename(task, text: "  water the plants  ")
        XCTAssertEqual(task.text, "water the plants")
        repository.rename(task, text: "   ")
        XCTAssertEqual(task.text, "water the plants")
    }

    // MARK: - add

    func testAddRefusesADayAlreadyPast() {
        XCTAssertNil(
            repository.add(on: date(2026, 1, 11), now: date(2026, 1, 12, hour: 9), calendar: calendar)
        )
        XCTAssertTrue(repository.pending().isEmpty)
    }

    func testAddOnTodayAndOnAFutureDayLandsAtStartOfDay() {
        let today = repository.add(
            text: "dentist", on: date(2026, 1, 12, hour: 23),
            now: date(2026, 1, 12, hour: 9), calendar: calendar
        )
        XCTAssertEqual(today?.dueDate, date(2026, 1, 12))

        let future = repository.add(
            on: date(2026, 1, 20, hour: 17), now: date(2026, 1, 12, hour: 9), calendar: calendar
        )
        XCTAssertEqual(future?.dueDate, date(2026, 1, 20))
        XCTAssertNil(future?.recurrence)
        XCTAssertEqual(future?.text, "")
    }

    // MARK: - reschedule

    func testRescheduleAppliesTextDateAndRecurrence() throws {
        let task = insert("gym every monday", due: date(2026, 1, 20))
        let parse = try XCTUnwrap(
            NaturalDateParser.parse(
                "gym every monday", now: date(2026, 1, 12, hour: 9),
                anchor: date(2026, 1, 19), calendar: calendar
            )
        )
        repository.reschedule(task, parse: parse)

        XCTAssertEqual(task.text, "gym")
        XCTAssertEqual(task.recurrence, .weekly(weekday: 2))
        // Jan 19 is itself a Monday, so the routine starts there.
        XCTAssertEqual(task.dueDate, date(2026, 1, 19))
    }

    func testRescheduleBackToOneTimeClearsRecurrenceColumns() throws {
        let task = insert("report", due: date(2026, 1, 14), recurrence: .weekly(weekday: 4))
        let parse = try XCTUnwrap(
            NaturalDateParser.parse(
                "report tomorrow", now: date(2026, 1, 12, hour: 9), calendar: calendar
            )
        )
        repository.reschedule(task, parse: parse)

        XCTAssertEqual(task.text, "report")
        XCTAssertNil(task.recurrence)
        XCTAssertNil(task.recurrenceUnit)
        XCTAssertNil(task.recurrenceWeekday)
        XCTAssertEqual(task.dueDate, date(2026, 1, 13))
    }

    // MARK: - purgeEmpty

    func testPurgeEmptyDropsBlanksAndSparesTheExceptedOne() {
        let named = insert("dentist", due: date(2026, 1, 20))
        let blank = insert("", due: date(2026, 1, 20))
        let whitespace = insert("   ", due: date(2026, 1, 21))
        let kept = insert("", due: date(2026, 1, 22))

        repository.purgeEmpty(except: kept.persistentModelID)

        let remaining = repository.pending()
        XCTAssertEqual(remaining.count, 2)
        XCTAssertTrue(remaining.contains { $0.persistentModelID == named.persistentModelID })
        XCTAssertTrue(remaining.contains { $0.persistentModelID == kept.persistentModelID })
        XCTAssertFalse(remaining.contains { $0.persistentModelID == blank.persistentModelID })
        XCTAssertFalse(remaining.contains { $0.persistentModelID == whitespace.persistentModelID })
    }

    func testPurgeEmptyWithNoExceptionDropsEveryBlank() {
        insert("dentist", due: date(2026, 1, 20))
        insert("", due: date(2026, 1, 20))

        repository.purgeEmpty()

        XCTAssertEqual(repository.pending().map(\.text), ["dentist"])
    }
}
