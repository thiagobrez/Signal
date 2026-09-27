import XCTest
import SwiftData

/// The overview's own rules now that it manages tasks rather than only showing
/// them: which days accept an add, where the new row goes, what the keyboard
/// walks, and which blanks get cleaned up.
///
/// Weekday-independent — every date is relative to the real today, so the suite
/// passes whichever day it runs on.
@MainActor
final class ScheduleOverviewModelTests: XCTestCase {
    private let calendar = Calendar.current
    private var container: ModelContainer!

    override func setUp() async throws {
        container = try ModelContainer(
            for: DayLog.self, TodoItem.self, ScheduledTask.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        UserDefaults.standard.set(true, forKey: SettingsStore.Key.carryOverIncomplete)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: SettingsStore.Key.carryOverIncomplete)
        container = nil
    }

    private var today: Date { calendar.startOfDay(for: Date()) }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today)!
    }

    private func makeModel() -> ScheduleOverviewModel {
        let store = SignalStore(context: container.mainContext)
        let repository = ScheduleRepository(context: container.mainContext)
        let model = ScheduleOverviewModel(repository: repository, store: store)
        model.refresh()
        return model
    }

    private func scheduledTasks() -> [ScheduledTask] {
        (try? container.mainContext.fetch(FetchDescriptor<ScheduledTask>())) ?? []
    }

    /// A day inside the visible week that is strictly after today. The week is
    /// Monday-first, so Sunday has no later day in its own week — jump the
    /// anchor forward a week in that case so the test always has one.
    private func futureDayInWeek(_ model: ScheduleOverviewModel) -> Date {
        if let day = model.weekDays.first(where: { model.kind(of: $0) == .future }) {
            return day
        }
        model.goNext()
        return model.weekDays[0]
    }

    // MARK: - addTask

    func testAddOnAPastDayIsRefused() {
        let model = makeModel()
        XCTAssertNil(model.addTask(on: day(-1)))
        XCTAssertTrue(scheduledTasks().isEmpty)
    }

    func testAddOnAFutureDayCreatesAOneTimeScheduleOnThatDay() throws {
        let model = makeModel()
        let target = day(3)

        let id = try XCTUnwrap(model.addTask(on: target))

        let created = try XCTUnwrap(scheduledTasks().first { $0.persistentModelID == id })
        XCTAssertEqual(created.dueDate, target)
        XCTAssertNil(created.recurrence)
        XCTAssertEqual(created.text, "")
        // No DayLog is written ahead of time — a future day *is* the schedule.
        let logs = try container.mainContext.fetch(FetchDescriptor<DayLog>())
        XCTAssertEqual(logs.map(\.date), [today])
    }

    func testAddOnAFutureDayReusesAnExistingBlankDraft() throws {
        let model = makeModel()
        let target = day(3)

        let first = try XCTUnwrap(model.addTask(on: target))
        let second = try XCTUnwrap(model.addTask(on: target))

        XCTAssertEqual(first, second)
        XCTAssertEqual(scheduledTasks().count, 1)
    }

    func testAddOnTodayGoesThroughTheStore() throws {
        let model = makeModel()
        let before = model.store.items.count

        let id = try XCTUnwrap(model.addTask(on: today))

        XCTAssertEqual(model.store.items.count, before + 1)
        XCTAssertEqual(model.store.items.last?.persistentModelID, id)
        // Today is a real day, not a schedule.
        XCTAssertTrue(scheduledTasks().isEmpty)
    }

    // MARK: - focus order

    func testFocusOrderSkipsPastDaysAndCoversTodayAndAhead() throws {
        let model = makeModel()
        let target = futureDayInWeek(model)
        // A task on a day already gone, which must never be walked to.
        let stale = ScheduledTask(text: "old", dueDate: day(-2), recurrence: nil)
        container.mainContext.insert(stale)
        try container.mainContext.save()

        let id = try XCTUnwrap(model.addTask(on: target))
        model.refresh()

        let order = model.focusOrder
        XCTAssertFalse(order.contains(stale.persistentModelID))
        // Today's live rows come first, then the day ahead.
        XCTAssertEqual(Array(order.prefix(model.store.items.count)), model.store.items.map(\.persistentModelID))
        XCTAssertEqual(order.last, id)
        XCTAssertEqual(model.focusIndex(of: id), order.count - 1)
        XCTAssertEqual(model.id(atFocusIndex: order.count - 1), id)
    }

    func testFocusRowsGroupTodaysOwnTasksApartFromItsSchedule() throws {
        let delivered = ScheduledTask(text: "stand-up", dueDate: today, recurrence: nil)
        container.mainContext.insert(delivered)
        try container.mainContext.save()

        let model = makeModel()
        let groups = model.focusRows.compactMap { row -> OverviewFocusRow.Group? in
            row.day == model.today ? row.group : nil
        }
        XCTAssertEqual(groups.filter { $0 == .todayScheduled }.count, 1)
        XCTAssertEqual(groups.last, .todayScheduled)
        // Only today's own tasks have an add point; the delivered row does not.
        let scheduledRow = try XCTUnwrap(model.focusRows.last)
        XCTAssertNil(scheduledRow.addDay)
    }

    // MARK: - pruning

    func testPruneSparesTheFocusedDraftAndDropsTheOneLeftBehind() throws {
        let model = makeModel()
        let target = day(3)
        let first = try XCTUnwrap(model.addTask(on: target))
        // A second blank draft on another day, so there are two to choose from.
        let second = try XCTUnwrap(model.addTask(on: day(4)))

        model.focusedID = second
        model.pruneEmptyDraft(second)
        XCTAssertEqual(scheduledTasks().count, 2, "the focused draft is left alone")

        model.pruneEmptyDraft(first)
        XCTAssertEqual(scheduledTasks().map(\.persistentModelID), [second])
    }

    func testPruneKeepsADraftThatWasGivenAName() throws {
        let model = makeModel()
        let id = try XCTUnwrap(model.addTask(on: day(3)))
        let task = try XCTUnwrap(scheduledTasks().first)
        task.text = "buy milk"

        model.pruneEmptyDraft(id)

        XCTAssertEqual(scheduledTasks().map(\.text), ["buy milk"])
    }

    func testEndEditingClearsFocusAndSweepsBlankDrafts() throws {
        let model = makeModel()
        _ = model.addTask(on: day(3))
        model.focusedID = model.focusOrder.last

        model.endEditing()

        XCTAssertNil(model.focusedID)
        XCTAssertTrue(scheduledTasks().isEmpty)
    }

    // MARK: - deleting today's rows

    func testTodayDeleteHonoursTheStoreFloor() {
        let model = makeModel()
        model.store.items.forEach { $0.text = "something" }

        while model.store.items.count > SignalStore.minTaskCount {
            model.delete(model.store.items[0])
        }
        XCTAssertEqual(model.store.items.count, SignalStore.minTaskCount)

        // The last row refuses to go.
        model.delete(model.store.items[0])
        XCTAssertEqual(model.store.items.count, SignalStore.minTaskCount)
    }

    // MARK: - week emptiness

    func testAWeekWithTodayInItIsNeverEmpty() {
        let model = makeModel()
        XCTAssertFalse(model.weekIsEmpty)
    }

    func testAPastWeekWithNothingInItIsEmpty() {
        let model = makeModel()
        model.goPrevious()
        model.goPrevious()
        XCTAssertTrue(model.weekIsEmpty)
    }
}
