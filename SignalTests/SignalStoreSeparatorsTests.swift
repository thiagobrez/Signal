import XCTest
import SwiftData

/// Separators in `SignalStore`: rows of today's list that are lines rather than
/// tasks. Covers where one may be added, that it never counts as a task, how
/// the keyboard walks and reorders around it, when a stranded one is pruned,
/// and what carry-over brings into the next day.
@MainActor
final class SignalStoreSeparatorsTests: XCTestCase {
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

    /// A store whose three opening slots read a / b / c.
    private func makeStore() -> SignalStore {
        let store = SignalStore(context: container.mainContext)
        for (item, text) in zip(store.items, ["a", "b", "c"]) { item.text = text }
        store.save()
        return store
    }

    /// Today's rows at a glance: a task's text, or "|" for a separator.
    private func shape(_ store: SignalStore) -> [String] {
        store.items.map { $0.isSeparator ? "|" : $0.text }
    }

    /// A recurring schedule due today — the one arrival that lands in the
    /// bottom section whatever that section is called.
    private func deliverRoutine(_ text: String) {
        container.mainContext.insert(ScheduledTask(text: text, dueDate: today, recurrence: .daily))
        try? container.mainContext.save()
    }

    /// Yesterday, written straight to the context. "|" is a separator; a
    /// trailing "✓" marks a task done.
    private func logYesterday(_ rows: [String]) {
        let log = DayLog(date: calendar.date(byAdding: .day, value: -1, to: today)!)
        container.mainContext.insert(log)
        for (index, row) in rows.enumerated() {
            let done = row.hasSuffix("✓")
            let item = TodoItem(
                text: row == "|" ? "" : row.replacingOccurrences(of: "✓", with: ""),
                isCompleted: done,
                order: index
            )
            item.isSeparator = row == "|"
            item.day = log
            container.mainContext.insert(item)
        }
        try? container.mainContext.save()
    }

    // MARK: - inserting

    func testInsertSeparatorBetweenTwoTasks() {
        let store = makeStore()

        XCTAssertTrue(store.insertSeparator(at: 1))

        XCTAssertEqual(shape(store), ["a", "|", "b", "c"])
        XCTAssertEqual(store.items.map(\.order), [0, 1, 2, 3])
        XCTAssertEqual(store.today?.orderedItems.map(\.isSeparator), [false, true, false, false])
    }

    func testSeparatorPersistsAcrossReload() {
        let store = makeStore()
        store.insertSeparator(at: 2)

        store.refreshForToday()
        XCTAssertEqual(shape(store), ["a", "b", "|", "c"])

        let reloaded = SignalStore(context: container.mainContext)
        XCTAssertEqual(shape(reloaded), ["a", "b", "|", "c"])
    }

    func testCannotInsertSeparatorAtEitherEnd() {
        let store = makeStore()

        XCTAssertFalse(store.insertSeparator(at: 0))
        XCTAssertFalse(store.insertSeparator(at: 3))
        XCTAssertFalse(store.insertSeparator(at: -1))
        XCTAssertFalse(store.insertSeparator(at: 99))
        XCTAssertEqual(shape(store), ["a", "b", "c"])
    }

    func testCannotInsertSeparatorNextToAnother() {
        let store = makeStore()
        store.insertSeparator(at: 1)

        // Directly above and directly below the one already there.
        XCTAssertFalse(store.canInsertSeparator(at: 1))
        XCTAssertFalse(store.canInsertSeparator(at: 2))
        XCTAssertTrue(store.canInsertSeparator(at: 3))
    }

    func testCannotInsertSeparatorInOrAgainstTheBottomSection() {
        deliverRoutine("stand-up")
        deliverRoutine("stretch")
        let store = makeStore()
        XCTAssertEqual(shape(store), ["a", "b", "c", "stand-up", "stretch"])

        // Between the last regular row and the header, and between two routines.
        XCTAssertFalse(store.insertSeparator(at: 3))
        XCTAssertFalse(store.insertSeparator(at: 4))
        XCTAssertTrue(store.insertSeparator(at: 2))
        XCTAssertEqual(shape(store), ["a", "b", "|", "c", "stand-up", "stretch"])
    }

    // MARK: - not a task

    func testSeparatorIsNotCountedAsATask() {
        let store = makeStore()
        store.insertSeparator(at: 1)

        XCTAssertEqual(store.items.count, 4)
        XCTAssertEqual(store.taskCount, 3)
        XCTAssertEqual(store.taskOrdinal(at: 0), 0)
        XCTAssertEqual(store.taskOrdinal(at: 2), 1)
        XCTAssertEqual(store.taskOrdinal(at: 3), 2)
    }

    func testDayCompletesWithASeparatorInIt() {
        let store = makeStore()
        store.insertSeparator(at: 1)
        let before = store.celebrationTrigger

        for item in store.items where !item.isSeparator { store.toggleComplete(item) }

        XCTAssertEqual(store.completedCount, 3)
        XCTAssertTrue(store.isDayComplete)
        XCTAssertEqual(store.celebrationTrigger, before + 1)
    }

    func testSeparatorCannotBeCompleted() {
        let store = makeStore()
        store.insertSeparator(at: 1)

        store.toggleComplete(store.items[1])

        XCTAssertFalse(store.items[1].isCompleted)
        XCTAssertEqual(store.completedCount, 0)
    }

    // MARK: - deleting

    func testSeparatorCanAlwaysBeDeleted() {
        let store = makeStore()
        store.insertSeparator(at: 1)

        XCTAssertTrue(store.canDelete(store.items[1]))
        store.deleteTask(store.items[1])

        XCTAssertEqual(shape(store), ["a", "b", "c"])
        XCTAssertEqual(store.items.map(\.order), [0, 1, 2])
    }

    func testDeletingDownToOneTaskLeavesNoSeparatorAndKeepsTheFloor() {
        let store = makeStore()
        store.insertSeparator(at: 1)

        store.deleteTask(store.items[3])  // c
        XCTAssertEqual(shape(store), ["a", "|", "b"])
        store.deleteTask(store.items[2])  // b — strands the separator

        XCTAssertEqual(shape(store), ["a"])
        XCTAssertFalse(store.canDelete(store.items[0]))
    }

    func testDeletingTheTaskBetweenTwoSeparatorsKeepsOne() {
        let store = makeStore()
        store.insertSeparator(at: 1)
        store.insertSeparator(at: 3)
        XCTAssertEqual(shape(store), ["a", "|", "b", "|", "c"])

        store.deleteTask(store.items[2])

        XCTAssertEqual(shape(store), ["a", "|", "c"])
        XCTAssertEqual(store.items.map(\.order), [0, 1, 2])
    }

    // MARK: - keyboard

    func testFocusNavigationSkipsSeparators() {
        let store = makeStore()
        store.insertSeparator(at: 1)

        XCTAssertEqual(store.nextTaskIndex(after: 0), 2)
        XCTAssertEqual(store.previousTaskIndex(before: 2), 0)
        XCTAssertNil(store.nextTaskIndex(after: 3))
        XCTAssertNil(store.previousTaskIndex(before: 0))
        XCTAssertEqual(store.taskIndex(nearest: 1), 2)
        XCTAssertEqual(store.taskIndex(nearest: 99), 3)
    }

    func testKeyboardMoveStepsOverASeparator() {
        let store = makeStore()
        store.insertSeparator(at: 1)

        // b joins the group above: one press, one step.
        XCTAssertEqual(store.moveTaskUp(at: 2), 1)
        XCTAssertEqual(shape(store), ["a", "b", "|", "c"])

        XCTAssertEqual(store.moveTaskDown(at: 1), 2)
        XCTAssertEqual(shape(store), ["a", "|", "b", "c"])
    }

    func testKeyboardMoveThatEmptiesAGroupPrunesItsSeparator() {
        let store = makeStore()
        store.insertSeparator(at: 1)

        // a was alone above the line; stepping below it leaves the line on top.
        XCTAssertEqual(store.moveTaskDown(at: 0), 0)
        XCTAssertEqual(shape(store), ["a", "b", "c"])
        XCTAssertEqual(store.items.map(\.order), [0, 1, 2])
    }

    func testKeyboardNeverMovesASeparator() {
        let store = makeStore()
        store.insertSeparator(at: 1)

        XCTAssertNil(store.moveTaskUp(at: 1))
        XCTAssertNil(store.moveTaskDown(at: 1))
        XCTAssertEqual(shape(store), ["a", "|", "b", "c"])
    }

    // MARK: - dragging

    func testSeparatorDragsBetweenTasksButNotOntoAnEnd() {
        let store = makeStore()
        store.insertSeparator(at: 1)

        XCTAssertFalse(store.canDrag(from: 1, to: 0))
        XCTAssertTrue(store.canDrag(from: 1, to: 2))
        store.moveTask(from: 1, to: 2)
        XCTAssertEqual(shape(store), ["a", "b", "|", "c"])
        XCTAssertFalse(store.canDrag(from: 2, to: 3))

        // Tasks drag exactly as before, past a separator included.
        XCTAssertTrue(store.canDrag(from: 3, to: 2))
        XCTAssertTrue(store.canDrag(from: 0, to: 3))
    }

    func testSeparatorCannotBeDraggedIntoTheBottomSection() {
        deliverRoutine("stand-up")
        deliverRoutine("stretch")
        let store = makeStore()
        store.insertSeparator(at: 2)
        XCTAssertEqual(shape(store), ["a", "b", "|", "c", "stand-up", "stretch"])

        XCTAssertFalse(store.canDrag(from: 2, to: 3))
        XCTAssertFalse(store.canDrag(from: 2, to: 4))
    }

    func testPruneAfterADragStrandsASeparator() {
        let store = makeStore()
        store.insertSeparator(at: 1)

        // The drag's live moves aren't pruned; the drop is.
        store.moveTask(from: 0, to: 1)
        XCTAssertEqual(shape(store), ["|", "a", "b", "c"])

        XCTAssertTrue(store.pruneSeparators())
        XCTAssertEqual(shape(store), ["a", "b", "c"])
        XCTAssertFalse(store.pruneSeparators())
    }

    func testPruneCollapsesSeparatorsLeftSideBySide() {
        let store = makeStore()
        store.insertSeparator(at: 1)
        store.insertSeparator(at: 3)
        store.moveTask(from: 2, to: 4)
        XCTAssertEqual(shape(store), ["a", "|", "|", "c", "b"])

        store.pruneSeparators()

        XCTAssertEqual(shape(store), ["a", "|", "c", "b"])
        XCTAssertEqual(store.today?.items.count, 4)
    }

    func testSeparatorThatAcquiredTextBecomesATask() {
        let store = makeStore()
        store.insertSeparator(at: 1)
        store.items[1].text = "call dentist"
        store.save()

        store.refreshForToday()

        XCTAssertEqual(shape(store), ["a", "call dentist", "b", "c"])
        XCTAssertEqual(store.taskCount, 4)
    }

    // MARK: - carry-over

    func testCarryOverKeepsASeparatorBetweenUnfinishedTasks() {
        logYesterday(["a", "|", "b✓", "c"])

        let store = SignalStore(context: container.mainContext)

        XCTAssertEqual(shape(store), ["a", "|", "c", ""])
        XCTAssertEqual(store.items.map(\.order), [0, 1, 2, 3])
    }

    func testCarryOverDropsASeparatorWithNothingUnfinishedOnOneSide() {
        logYesterday(["a✓", "|", "b", "|", "c✓"])

        let store = SignalStore(context: container.mainContext)

        XCTAssertEqual(shape(store), ["b", "", ""])
    }

    func testCarryOverCollapsesSeparatorsThatEndUpSideBySide() {
        logYesterday(["a", "|", "b✓", "|", "c", "d"])

        let store = SignalStore(context: container.mainContext)

        XCTAssertEqual(shape(store), ["a", "|", "c", "d"])
    }

    func testCarryOverLeavesYesterdayUntouched() {
        logYesterday(["a", "|", "b"])

        let store = SignalStore(context: container.mainContext)
        XCTAssertEqual(shape(store), ["a", "|", "b", ""])

        let logs = try? container.mainContext.fetch(FetchDescriptor<DayLog>(sortBy: [SortDescriptor(\.date)]))
        XCTAssertEqual(logs?.first?.orderedItems.map(\.isSeparator), [false, true, false])
    }

    func testNoSeparatorsCarryOverWhenCarryOverIsOff() {
        UserDefaults.standard.set(false, forKey: SettingsStore.Key.carryOverIncomplete)
        logYesterday(["a", "|", "b"])

        let store = SignalStore(context: container.mainContext)

        XCTAssertEqual(shape(store), ["", "", ""])
    }

    func testCarryOverKeepsSeparatorsAboveTheBottomSection() {
        logYesterday(["a", "|", "b", "c"])
        deliverRoutine("stand-up")

        let store = SignalStore(context: container.mainContext)

        XCTAssertEqual(shape(store), ["a", "|", "b", "c", "stand-up"])
    }

    // MARK: - outside the panel

    func testOverviewKeyboardOrderSkipsSeparators() {
        let store = makeStore()
        store.insertSeparator(at: 1)
        let model = ScheduleOverviewModel(
            repository: ScheduleRepository(context: container.mainContext), store: store
        )
        model.refresh()

        XCTAssertEqual(model.focusRows.map(\.entry.text), ["a", "b", "c"])
        XCTAssertEqual(model.entries(on: today).map(\.text), ["a", "b", "c"])
    }

    func testHistoryNeverListsSeparators() {
        logYesterday(["a", "|", "b"])

        let history = ScheduleRepository(context: container.mainContext).dayTasksByDay()

        XCTAssertEqual(history.values.first?.map(\.text), ["a", "b"])
    }

    func testSchedulingATaskAwayPrunesTheSeparatorItStranded() {
        let store = makeStore()
        store.insertSeparator(at: 2)
        XCTAssertEqual(shape(store), ["a", "b", "|", "c"])
        let parse = NaturalDateParser.parse("c tomorrow")!

        store.schedule(store.items[3], parse: parse)

        XCTAssertEqual(shape(store), ["a", "b"])
    }
}
