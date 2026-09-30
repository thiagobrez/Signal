import XCTest
import SwiftData

/// The two sections `SignalStore` keeps today's list in: the regular tasks
/// (typed, or delivered by a one-time schedule), then the routines a recurring
/// schedule delivered. Covers where an arrival lands, where a new task is
/// inserted, which moves and deletes are allowed, and that the split survives
/// carry-over and a store written before the Routines section existed.
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
    private func log(on date: Date, items: [(text: String, completed: Bool, routine: Bool)]) -> DayLog {
        let log = DayLog(date: date)
        container.mainContext.insert(log)
        for (index, spec) in items.enumerated() {
            let item = TodoItem(
                text: spec.text,
                isCompleted: spec.completed,
                order: index,
                isRoutine: spec.routine
            )
            item.day = log
            container.mainContext.insert(item)
        }
        try? container.mainContext.save()
        return log
    }

    /// Appends a row the way builds before the Routines section wrote anything
    /// the schedule delivered: `isScheduled` set, `isRoutine` not yet decided.
    @discardableResult
    private func legacyRow(_ text: String, in log: DayLog, completed: Bool = false) -> TodoItem {
        let item = TodoItem(text: text, isCompleted: completed, order: log.items.count)
        item.isScheduled = true
        item.day = log
        container.mainContext.insert(item)
        try? container.mainContext.save()
        return item
    }

    private func makeStore() -> SignalStore {
        SignalStore(context: container.mainContext)
    }

    // MARK: - materialize

    func testOneTimeTaskClaimsFirstBlankRegularSlot() {
        let task = schedule("water plants", due: today)

        let store = makeStore()

        // Planned ahead, but still the user's own task: it takes the first
        // empty Signal slot rather than growing the day.
        XCTAssertEqual(store.items.count, 3)
        XCTAssertEqual(store.items.map(\.text), ["water plants", "", ""])
        XCTAssertTrue(store.routineItems.isEmpty)
        XCTAssertEqual(store.routinesSectionStart, 3)
        XCTAssertNotNil(task.deliveredAt)
    }

    func testOneTimeTaskAppendsToRegularSectionWhenNoSlotIsBlank() {
        log(on: today, items: [
            ("a", false, false),
            ("b", false, false),
            ("c", false, false),
            ("stand-up", false, true),
        ])
        schedule("call dentist", due: today)

        let store = makeStore()

        // No blank to claim: the day grows, above the ROUTINES header.
        XCTAssertEqual(store.items.map(\.text), ["a", "b", "c", "call dentist", "stand-up"])
        XCTAssertEqual(store.routinesSectionStart, 4)
        XCTAssertEqual(store.items.map(\.order), [0, 1, 2, 3, 4])
    }

    func testRecurringTaskAppendsToRoutinesSectionAndLeavesBlanksAlone() {
        schedule("stand-up", due: today, recurrence: .daily)

        let store = makeStore()

        // The three Signal slots stay the user's, empty; the routine is a
        // fourth row in its own section.
        XCTAssertEqual(store.items.count, 4)
        XCTAssertEqual(store.regularItems.map(\.text), ["", "", ""])
        XCTAssertEqual(store.routineItems.map(\.text), ["stand-up"])
        XCTAssertEqual(store.routinesSectionStart, 3)
        XCTAssertEqual(store.items.map(\.order), [0, 1, 2, 3])
        XCTAssertTrue(store.items[3].isRoutine)
    }

    func testWeeklyTaskMaterializesAsRoutine() {
        let weekday = calendar.component(.weekday, from: today)
        schedule("review week", due: today, recurrence: .weekly(weekday: weekday))

        let store = makeStore()

        XCTAssertEqual(store.regularItems.map(\.text), ["", "", ""])
        XCTAssertEqual(store.routineItems.map(\.text), ["review week"])
    }

    func testMixedArrivalsSplitAcrossSections() {
        schedule("call dentist", due: today)
        schedule("stand-up", due: today, recurrence: .daily)

        let store = makeStore()

        XCTAssertEqual(store.regularItems.map(\.text), ["call dentist", "", ""])
        XCTAssertEqual(store.routineItems.map(\.text), ["stand-up"])
        XCTAssertEqual(store.items.map(\.order), [0, 1, 2, 3])
    }

    func testRecurringTaskMaterializesAsRoutineAndAdvancesDueDate() {
        let task = schedule("stand-up", due: today, recurrence: .daily)

        let store = makeStore()

        XCTAssertEqual(store.routineItems.map(\.text), ["stand-up"])
        // A recurring task never delivers — it just points at the next day.
        XCTAssertNil(task.deliveredAt)
        XCTAssertEqual(task.dueDate, day(1))
    }

    func testBlankScheduleIsDeletedRatherThanDelivered() {
        // An abandoned draft from the overview: it must never become a row.
        schedule("   ", due: today)

        let store = makeStore()

        XCTAssertTrue(store.routineItems.isEmpty)
        XCTAssertEqual(store.items.map(\.text), ["", "", ""])
        XCTAssertEqual(store.items.count, SignalStore.defaultTaskCount)
        let remaining = try? container.mainContext.fetch(FetchDescriptor<ScheduledTask>())
        XCTAssertEqual(remaining?.count, 0)
    }

    func testMaterializedTaskIsNotDuplicatedByCarryOver() {
        // An "every day" task that went unfinished yesterday is carried over,
        // so today's delivery must not add a second copy of it.
        log(on: day(-1), items: [("stand-up", false, true)])
        schedule("stand-up", due: today, recurrence: .daily)

        let store = makeStore()

        XCTAssertEqual(store.routineItems.map(\.text), ["stand-up"])
    }

    func testOneTimeTaskIsNotDuplicatedByCarryOver() {
        log(on: day(-1), items: [("call dentist", false, false)])
        let task = schedule("Call Dentist", due: today)

        let store = makeStore()

        XCTAssertEqual(store.items.filter { $0.text.lowercased() == "call dentist" }.count, 1)
        XCTAssertEqual(store.regularItems.map(\.text), ["call dentist", "", ""])
        XCTAssertNotNil(task.deliveredAt)
    }

    // MARK: - one-time arrivals are regular tasks

    func testOneTimeArrivalReordersWithRegularTasks() {
        schedule("call dentist", due: today)
        let store = makeStore()

        XCTAssertTrue(store.canMove(from: 0, to: 2))
        XCTAssertEqual(store.moveTaskDown(at: 0), 1)
        XCTAssertEqual(store.items.map(\.text), ["", "call dentist", ""])
    }

    func testOneTimeArrivalCountsTowardsTheRegularFloor() {
        schedule("call dentist", due: today)
        let store = makeStore()

        store.deleteTask(store.items[2])
        store.deleteTask(store.items[1])

        XCTAssertEqual(store.items.map(\.text), ["call dentist"])
        XCTAssertFalse(store.canDelete(store.items[0]))
    }

    // MARK: - addTask

    func testAddTaskInsertsBeforeRoutinesSection() {
        schedule("water plants", due: today, recurrence: .daily)
        let store = makeStore()

        let index = store.addTask()

        XCTAssertEqual(index, 3)
        XCTAssertEqual(store.items.count, 5)
        XCTAssertFalse(store.items[3].isRoutine)
        XCTAssertEqual(store.items[4].text, "water plants")
        XCTAssertTrue(store.items[4].isRoutine)
        XCTAssertEqual(store.items.map(\.order), [0, 1, 2, 3, 4])
        XCTAssertEqual(store.routinesSectionStart, 4)
    }

    // MARK: - moveTask

    func testMoveTaskRefusesToCrossSectionBoundary() {
        schedule("water plants", due: today, recurrence: .daily)
        let store = makeStore()
        store.items[0].text = "first"

        // Up out of the routines section, and down into it: both refused.
        XCTAssertFalse(store.canMove(from: 3, to: 2))
        XCTAssertFalse(store.canMove(from: 0, to: 3))
        store.moveTask(from: 3, to: 2)
        store.moveTask(from: 0, to: 3)
        XCTAssertEqual(store.items.map(\.text), ["first", "", "", "water plants"])
        XCTAssertEqual(store.items.map(\.isRoutine), [false, false, false, true])
    }

    func testKeyboardReorderStopsAtSectionBoundary() {
        schedule("water plants", due: today, recurrence: .daily)
        let store = makeStore()
        store.items[2].text = "last regular"

        // ⌥↓ on the last regular row and ⌥↑ on the first routine: both
        // refused, focus stays where it is (nil), nothing moves.
        XCTAssertNil(store.moveTaskDown(at: 2))
        XCTAssertNil(store.moveTaskUp(at: 3))
        XCTAssertEqual(store.items.map(\.text), ["", "", "last regular", "water plants"])

        // Within the regular section the keyboard still reorders.
        XCTAssertEqual(store.moveTaskUp(at: 2), 1)
        XCTAssertEqual(store.items.map(\.text), ["", "last regular", "", "water plants"])
    }

    func testMoveTaskWithinRegularSectionStillWorks() {
        schedule("water plants", due: today, recurrence: .daily)
        let store = makeStore()
        store.items[0].text = "first"

        XCTAssertTrue(store.canMove(from: 0, to: 2))
        store.moveTask(from: 0, to: 2)

        XCTAssertEqual(store.items.map(\.text), ["", "", "first", "water plants"])
        XCTAssertEqual(store.items.map(\.order), [0, 1, 2, 3])
    }

    // MARK: - canDelete

    func testCanDeleteRoutineEvenAtFloor() {
        schedule("water plants", due: today, recurrence: .daily)
        let store = makeStore()

        // Trim the regular section down to its floor of one.
        store.deleteTask(store.items[2])
        store.deleteTask(store.items[1])

        XCTAssertEqual(store.regularItems.count, 1)
        XCTAssertFalse(store.canDelete(store.items[0]))
        XCTAssertTrue(store.canDelete(store.items[1]))

        store.deleteTask(store.items[1])
        XCTAssertEqual(store.items.map(\.text), [""])
        XCTAssertEqual(store.routinesSectionStart, 1)
    }

    // MARK: - carry-over

    func testCarryOverKeepsRoutineFlagAndSection() {
        log(on: day(-1), items: [
            ("typed one", false, false),
            ("done", true, false),
            ("from the schedule", false, true),
        ])

        let store = makeStore()

        // The completed row is dropped; the two unfinished ones come across on
        // the side of the header they were on.
        XCTAssertEqual(store.regularItems.map(\.text), ["typed one", "", ""])
        XCTAssertEqual(store.routineItems.map(\.text), ["from the schedule"])
        XCTAssertEqual(store.routinesSectionStart, 3)
        XCTAssertEqual(store.items.map(\.order), [0, 1, 2, 3])
    }

    // MARK: - upgrading rows from before the Routines section

    func testLegacyScheduledRowMatchingARoutineJoinsRoutines() {
        let todayLog = log(on: today, items: [("typed", false, false)])
        let legacy = legacyRow("stand-up", in: todayLog)
        // Matched trimmed and case-insensitively, and whenever it's next due.
        schedule(" Stand-up", due: day(1), recurrence: .daily)

        let store = makeStore()

        XCTAssertEqual(store.regularItems.map(\.text), ["typed"])
        XCTAssertEqual(store.routineItems.map(\.text), ["stand-up"])
        XCTAssertTrue(legacy.isRoutine)
        XCTAssertFalse(legacy.isScheduled)
    }

    func testLegacyScheduledRowFromAOneTimeScheduleJoinsRegularSection() {
        let todayLog = log(on: today, items: [("typed", false, false)])
        let legacy = legacyRow("call dentist", in: todayLog)

        let store = makeStore()

        XCTAssertEqual(store.regularItems.map(\.text), ["typed", "call dentist"])
        XCTAssertTrue(store.routineItems.isEmpty)
        XCTAssertFalse(legacy.isRoutine)
        XCTAssertFalse(legacy.isScheduled)
    }

    func testLegacyFlagsAreUpgradedBeforeCarryOver() {
        let yesterday = log(on: day(-1), items: [])
        legacyRow("stand-up", in: yesterday)
        legacyRow("call dentist", in: yesterday)
        schedule("stand-up", due: today, recurrence: .daily)

        let store = makeStore()

        // Carry-over already sees the upgraded flags: the one-time delivery
        // comes across as a regular task, the routine stays a routine, and
        // today's delivery of it doesn't add a second copy.
        XCTAssertEqual(store.regularItems.map(\.text), ["call dentist", "", ""])
        XCTAssertEqual(store.routineItems.map(\.text), ["stand-up"])
    }

    func testRoutineRowStaysARoutineWithoutATemplate() {
        // A routine whose schedule was since removed: it is never re-examined.
        log(on: today, items: [
            ("typed", false, false),
            ("stretch", false, true),
        ])

        let store = makeStore()

        XCTAssertEqual(store.routineItems.map(\.text), ["stretch"])
    }

    // MARK: - normalizeOrder

    func testNormalizeOrderMovesStrayRoutinesToTail() {
        // A routine sitting in a Signal slot — e.g. left behind by a deletion —
        // is pushed down below the regular rows.
        log(on: today, items: [
            ("from the schedule", false, true),
            ("typed one", false, false),
            ("typed two", false, false),
        ])

        let store = makeStore()

        XCTAssertEqual(store.items.map(\.text), ["typed one", "typed two", "from the schedule"])
        XCTAssertEqual(store.items.map(\.order), [0, 1, 2])
        XCTAssertEqual(store.routinesSectionStart, 2)
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
