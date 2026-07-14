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

    // MARK: - update

    func testUpdateOneTimeToWeeklyRecomputesDueDate() {
        let task = insert("report", due: date(2026, 1, 20))
        // Monday Jan 12 → next Wednesday (weekday 4) is Jan 14.
        repository.update(task, to: .weekly(weekday: 4), now: date(2026, 1, 12, hour: 9), calendar: calendar)
        XCTAssertEqual(task.recurrence, .weekly(weekday: 4))
        XCTAssertEqual(task.dueDate, date(2026, 1, 14))
    }

    func testUpdateWeeklyToOneTimeClearsRecurrenceColumns() {
        let task = insert("report", due: date(2026, 1, 14), recurrence: .weekly(weekday: 4))
        repository.update(task, to: .oneTime(date: date(2026, 1, 22, hour: 17)), now: date(2026, 1, 12), calendar: calendar)
        XCTAssertNil(task.recurrence)
        XCTAssertNil(task.recurrenceUnit)
        XCTAssertNil(task.recurrenceWeekday)
        XCTAssertEqual(task.dueDate, date(2026, 1, 22))
    }

    func testUpdateDailyToWeeklyOnTodaysWeekdayLandsNextWeek() {
        let task = insert("standup", due: date(2026, 1, 13), recurrence: .daily)
        // Monday Jan 12, switching to "every Monday" → Jan 19, not today.
        repository.update(task, to: .weekly(weekday: 2), now: date(2026, 1, 12, hour: 9), calendar: calendar)
        XCTAssertEqual(task.dueDate, date(2026, 1, 19))
    }

    func testUpdateWithSameShapeIsANoOp() {
        // Recurring: dueDate must not be pushed out by a no-change Save.
        let weekly = insert("report", due: date(2026, 1, 14), recurrence: .weekly(weekday: 4))
        repository.update(weekly, to: .weekly(weekday: 4), now: date(2026, 1, 12), calendar: calendar)
        XCTAssertEqual(weekly.dueDate, date(2026, 1, 14))

        let daily = insert("standup", due: date(2026, 1, 13), recurrence: .daily)
        repository.update(daily, to: .daily, now: date(2026, 1, 14), calendar: calendar)
        XCTAssertEqual(daily.dueDate, date(2026, 1, 13))

        // One-time to the same day keeps everything as-is.
        let once = insert("dentist", due: date(2026, 1, 20))
        repository.update(once, to: .oneTime(date: date(2026, 1, 20, hour: 8)), now: date(2026, 1, 12), calendar: calendar)
        XCTAssertEqual(once.dueDate, date(2026, 1, 20))
        XCTAssertNil(once.recurrence)
    }
}
