import XCTest
import SwiftData

/// SignalStore reordering against an in-memory container. A fresh store creates
/// today's log with three empty slots; the tests label them a/b/c so the order
/// is observable.
@MainActor
final class SignalStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var store: SignalStore!

    override func setUp() async throws {
        container = try ModelContainer(
            for: DayLog.self, TodoItem.self, ScheduledTask.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        store = SignalStore(context: container.mainContext)
        for (item, text) in zip(store.items, ["a", "b", "c"]) { item.text = text }
        store.save()
    }

    private var texts: [String] { store.items.map(\.text) }
    private var orders: [Int] { store.items.map(\.order) }

    // MARK: - moving

    func testMoveTaskDownSwapsWithNextRow() {
        XCTAssertEqual(store.moveTaskDown(at: 0), 1)
        XCTAssertEqual(texts, ["b", "a", "c"])
        // `order` stays a contiguous 0-based sequence, which is what `addTask`
        // and the day's own sort rely on.
        XCTAssertEqual(orders, [0, 1, 2])
        XCTAssertEqual(store.today?.orderedItems.map(\.text), ["b", "a", "c"])
    }

    func testMoveTaskUpSwapsWithPreviousRow() {
        XCTAssertEqual(store.moveTaskUp(at: 2), 1)
        XCTAssertEqual(texts, ["a", "c", "b"])
        XCTAssertEqual(orders, [0, 1, 2])
    }

    // MARK: - boundaries

    func testMoveTaskUpOnFirstRowIsANoOp() {
        XCTAssertNil(store.moveTaskUp(at: 0))
        XCTAssertEqual(texts, ["a", "b", "c"])
    }

    func testMoveTaskDownOnLastRowIsANoOp() {
        XCTAssertNil(store.moveTaskDown(at: store.items.count - 1))
        XCTAssertEqual(texts, ["a", "b", "c"])
    }

    func testMoveOutOfRangeIsANoOp() {
        XCTAssertNil(store.moveTaskUp(at: -1))
        XCTAssertNil(store.moveTaskUp(at: 99))
        XCTAssertNil(store.moveTaskDown(at: -1))
        XCTAssertNil(store.moveTaskDown(at: 99))
        XCTAssertEqual(texts, ["a", "b", "c"])
    }

    // MARK: - persistence

    func testMovePersistsAcrossReload() {
        store.moveTaskDown(at: 0)

        store.refreshForToday()
        XCTAssertEqual(texts, ["b", "a", "c"])

        // A store built fresh from the same context reads the saved order back.
        let reloaded = SignalStore(context: container.mainContext)
        XCTAssertEqual(reloaded.items.map(\.text), ["b", "a", "c"])
    }

    func testMoveKeepsCompletionState() {
        store.toggleComplete(store.items[0])
        XCTAssertEqual(store.moveTaskDown(at: 0), 1)
        XCTAssertEqual(texts, ["b", "a", "c"])
        XCTAssertEqual(store.items.map(\.isCompleted), [false, true, false])
        XCTAssertEqual(store.completedCount, 1)
    }
}
