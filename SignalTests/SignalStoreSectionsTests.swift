import XCTest
import SwiftData

/// The two sections `SignalStore` keeps today's list in: the regular tasks the
/// user types, then the ones the schedule delivered. Covers where an arrival
/// lands, where a new task is inserted, which moves and deletes are allowed,
/// and that the split survives carry-over and a store written before the flag
/// existed.
@MainActor
final class SignalStoreSectionsTests: XCTestCase {
    private let calendar = Calendar.current
    private var container: ModelContainer!

    override func setUp() async throws {
        container = try ModelContainer(
            for: DayLog.self, TodoItem.self, ScheduledTask.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        // The store reads this directly; pin it so the machine's own
        // preference can't decide whether carry-over runs.
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

    @discardableResult
    private func schedule(_ text: String, due: Date, recurrence: Recurrence? = nil) -> ScheduledTask {
        let task = ScheduledTask(text: text, dueDate: due, recurrence: recurrence)
        container.mainContext.insert(task)
        try? container.mainContext.save()
        return task
    }

    /// A log written straight to the context, bypassing the store — the shape a
    /// prior day (or a pre-migration store) leaves behind.
    @discardableResult
    private func log(on date: Date, items: [(text: String, completed: Bool, scheduled: Bool)]) -> DayLog {
        let log = DayLog(date: date)
        container.mainContext.insert(log)
        for (index, spec) in items.enumerated() {
            let item = TodoItem(
                text: spec.text,
                isCompleted: spec.completed,
                order: index,
                isScheduled: spec.scheduled
            )
            item.day = log
            container.mainContext.insert(item)
        }
        try? container.mainContext.save()
        return log
    }

    private func makeStore() -> SignalStore {
        SignalStore(context: container.mainContext)
    }

    // MARK: - materialize

    func testMaterializedTaskAppendsToScheduledSectionAndLeavesBlanksAlone() {
        schedule("water plants", due: today)

        let store = makeStore()

        // The three Signal slots stay the user's, empty and unscheduled; the
        // arrival is a fourth row in its own section.
        XCTAssertEqual(store.items.count, 4)
        XCTAssertEqual(store.regularItems.map(\.text), ["", "", ""])
        XCTAssertEqual(store.scheduledItems.map(\.text), ["water plants"])
        XCTAssertEqual(store.scheduledSectionStart, 3)
        XCTAssertEqual(store.items.map(\.order), [0, 1, 2, 3])
        XCTAssertTrue(store.items[3].isScheduled)
    }

    func testRecurringTaskMaterializesAsScheduledAndAdvancesDueDate() {
        let task = schedule("stand-up", due: today, recurrence: .daily)

        let store = makeStore()

        XCTAssertEqual(store.scheduledItems.map(\.text), ["stand-up"])
        // A recurring task never delivers — it just points at the next day.
        XCTAssertNil(task.deliveredAt)
        XCTAssertEqual(task.dueDate, day(1))
    }

    func testMaterializedTaskIsNotDuplicatedByCarryOver() {
        // An "every day" task that went unfinished yesterday is carried over,
        // so today's delivery must not add a second copy of it.
        log(on: day(-1), items: [("stand-up", false, true)])
        schedule("stand-up", due: today, recurrence: .daily)

        let store = makeStore()

        XCTAssertEqual(store.scheduledItems.map(\.text), ["stand-up"])
    }

    // MARK: - addTask

    func testAddTaskInsertsBeforeScheduledSection() {
        schedule("water plants", due: today)
        let store = makeStore()

        let index = store.addTask()

        XCTAssertEqual(index, 3)
        XCTAssertEqual(store.items.count, 5)
        XCTAssertFalse(store.items[3].isScheduled)
        XCTAssertEqual(store.items[4].text, "water plants")
        XCTAssertTrue(store.items[4].isScheduled)
        XCTAssertEqual(store.items.map(\.order), [0, 1, 2, 3, 4])
        XCTAssertEqual(store.scheduledSectionStart, 4)
    }

    // MARK: - moveTask

    func testMoveTaskRefusesToCrossSectionBoundary() {
        schedule("water plants", due: today)
        let store = makeStore()
        store.items[0].text = "first"

        // Up out of the scheduled section, and down into it: both refused.
        XCTAssertFalse(store.canMove(from: 3, to: 2))
        XCTAssertFalse(store.canMove(from: 0, to: 3))
        store.moveTask(from: 3, to: 2)
        store.moveTask(from: 0, to: 3)
        XCTAssertEqual(store.items.map(\.text), ["first", "", "", "water plants"])
        XCTAssertEqual(store.items.map(\.isScheduled), [false, false, false, true])
    }

    func testKeyboardReorderStopsAtSectionBoundary() {
        schedule("water plants", due: today)
        let store = makeStore()
        store.items[2].text = "last regular"

        // ⌥↓ on the last regular row and ⌥↑ on the first scheduled row: both
        // refused, focus stays where it is (nil), nothing moves.
        XCTAssertNil(store.moveTaskDown(at: 2))
        XCTAssertNil(store.moveTaskUp(at: 3))
        XCTAssertEqual(store.items.map(\.text), ["", "", "last regular", "water plants"])

        // Within the regular section the keyboard still reorders.
        XCTAssertEqual(store.moveTaskUp(at: 2), 1)
        XCTAssertEqual(store.items.map(\.text), ["", "last regular", "", "water plants"])
    }

    func testMoveTaskWithinRegularSectionStillWorks() {
        schedule("water plants", due: today)
        let store = makeStore()
        store.items[0].text = "first"

        XCTAssertTrue(store.canMove(from: 0, to: 2))
        store.moveTask(from: 0, to: 2)

        XCTAssertEqual(store.items.map(\.text), ["", "", "first", "water plants"])
        XCTAssertEqual(store.items.map(\.order), [0, 1, 2, 3])
    }

    // MARK: - canDelete

    func testCanDeleteScheduledRowEvenAtFloor() {
        schedule("water plants", due: today)
        let store = makeStore()

        // Trim the regular section down to its floor of one.
        store.deleteTask(store.items[2])
        store.deleteTask(store.items[1])

        XCTAssertEqual(store.regularItems.count, 1)
        XCTAssertFalse(store.canDelete(store.items[0]))
        XCTAssertTrue(store.canDelete(store.items[1]))

        store.deleteTask(store.items[1])
        XCTAssertEqual(store.items.map(\.text), [""])
        XCTAssertEqual(store.scheduledSectionStart, 1)
    }

    // MARK: - carry-over

    func testCarryOverKeepsScheduledFlagAndSection() {
        log(on: day(-1), items: [
            ("typed one", false, false),
            ("done", true, false),
            ("from the schedule", false, true),
        ])

        let store = makeStore()

        // The completed row is dropped; the two unfinished ones come across on
        // the side of the header they were on.
        XCTAssertEqual(store.regularItems.map(\.text), ["typed one", "", ""])
        XCTAssertEqual(store.scheduledItems.map(\.text), ["from the schedule"])
        XCTAssertEqual(store.scheduledSectionStart, 3)
        XCTAssertEqual(store.items.map(\.order), [0, 1, 2, 3])
    }

    // MARK: - normalizeOrder

    func testNormalizeOrderMovesStrayScheduledItemsToTail() {
        // What a store written before the section existed can look like once
        // the flag is set: a scheduled row sitting in a Signal slot.
        log(on: today, items: [
            ("from the schedule", false, true),
            ("typed one", false, false),
            ("typed two", false, false),
        ])

        let store = makeStore()

        XCTAssertEqual(store.items.map(\.text), ["typed one", "typed two", "from the schedule"])
        XCTAssertEqual(store.items.map(\.order), [0, 1, 2])
        XCTAssertEqual(store.scheduledSectionStart, 2)
    }

    func testNormalizeOrderKeepsRelativeOrderWithinEachSection() {
        log(on: today, items: [
            ("a", false, false),
            ("s1", false, true),
            ("b", false, false),
            ("s2", false, true),
            ("c", false, false),
        ])

        let store = makeStore()

        XCTAssertEqual(store.items.map(\.text), ["a", "b", "c", "s1", "s2"])
        XCTAssertEqual(store.items.map(\.order), [0, 1, 2, 3, 4])
    }
}
