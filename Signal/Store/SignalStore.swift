import Foundation
import SwiftData

/// Owns "today's" to-dos and the day-transition logic (carry-over + history).
///
/// Today is one flat list split into two sections: the regular tasks the user
/// types in, then the tasks the schedule delivered (`isScheduled`). `order`
/// stays a single contiguous 0-based sequence across both, with the invariant
/// that every regular item precedes every scheduled one — so the view can keep
/// indexing one array while rendering a `SCHEDULED` header at the seam.
@MainActor
@Observable
final class SignalStore {
    private let context: ModelContext

    /// The number of slots a fresh day starts with — the "three things" at the
    /// heart of Signal. A day can grow beyond this when the user adds tasks.
    static let defaultTaskCount = 3
    /// Floor a day can be trimmed to via deletion — there's always one task.
    /// Counts regular tasks only: a scheduled row is never the last thing
    /// standing between the user and an empty day.
    static let minTaskCount = 1

    /// Today's log and its tasks: at least `defaultTaskCount`, more if the user
    /// added some (or that many incomplete tasks carried over from a prior day).
    private(set) var today: DayLog?
    private(set) var items: [TodoItem] = []

    /// Bumped the moment every task becomes complete, so the view can fire
    /// the celebration (grass + sound). Only fires on the transition
    /// *into* a fully-done day, not on every toggle.
    private(set) var celebrationTrigger = 0

    init(context: ModelContext) {
        self.context = context
        refreshForToday()
    }

    /// Resolves the current day, creating it (with carry-over) on a new day.
    /// Safe to call on every open — it's a no-op once today's log exists.
    func refreshForToday() {
        let startOfToday = Calendar.current.startOfDay(for: Date())

        if let existing = fetchDayLog(for: startOfToday) {
            today = existing
            ensureMinimumSlots(existing)
        } else {
            today = createDayLog(for: startOfToday)
        }

        if let today {
            materializePending(into: today, on: startOfToday)
        }

        items = today.map { normalizeOrder($0) } ?? []
    }

    // MARK: - Sections

    /// The tasks the user owns: everything above the `SCHEDULED` header.
    var regularItems: [TodoItem] {
        items.filter { !$0.isScheduled }
    }

    /// The tasks the schedule delivered, in the order they arrived.
    var scheduledItems: [TodoItem] {
        items.filter(\.isScheduled)
    }

    /// Index of the first scheduled row — equivalently, how many regular rows
    /// there are, and where a newly added task is inserted. `items.count` when
    /// nothing is scheduled today.
    var scheduledSectionStart: Int {
        items.firstIndex(where: \.isScheduled) ?? items.count
    }

    var completedCount: Int {
        items.filter(\.isCompleted).count
    }

    /// Whether the day is fully done: every task complete. An empty slot can't be
    /// completed, so this also requires every slot to be filled.
    var isDayComplete: Bool {
        !items.isEmpty && completedCount == items.count
    }

    /// A regular task can be removed as long as it wouldn't drop the day below
    /// its floor. A scheduled one always can — it isn't the user's to keep, and
    /// removing it only empties the section the schedule fills back up.
    func canDelete(_ item: TodoItem) -> Bool {
        item.isScheduled || regularItems.count > Self.minTaskCount
    }

    /// Whether a reorder is legal: real slots, an actual move, and both ends in
    /// the same section — a row can't be dragged across the `SCHEDULED` header
    /// in either direction.
    func canMove(from source: Int, to destination: Int) -> Bool {
        guard source != destination,
              items.indices.contains(source), items.indices.contains(destination) else { return false }
        return items[source].isScheduled == items[destination].isScheduled
    }

    func toggleComplete(_ item: TodoItem) {
        // An empty to-do can't be completed.
        if !item.isCompleted, item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }
        item.isCompleted.toggle()
        item.completedAt = item.isCompleted ? Date() : nil
        if item.isCompleted {
            // Completing the final task is the big moment: celebrate instead of
            // the ordinary per-task chime so the two sounds don't pile up.
            if isDayComplete {
                celebrationTrigger &+= 1
                Analytics.dayCompleted()
                SoundPlayer.play(SettingsStore.celebrationSound)
            } else {
                SoundPlayer.play(SettingsStore.completionSound)
            }
        }
        save()
    }

    /// Adds a fresh empty slot at the end of the *regular* section — above the
    /// scheduled rows, not below them — and returns its index so the caller can
    /// move focus to it.
    @discardableResult
    func addTask() -> Int? {
        guard let today else { return nil }
        let insertionPoint = scheduledSectionStart
        let item = TodoItem(text: "", isCompleted: false, order: insertionPoint)
        item.day = today
        context.insert(item)

        var reordered = items
        reordered.insert(item, at: insertionPoint)
        repack(reordered)
        save()
        items = reordered
        return insertionPoint
    }

    /// Removes a task and re-packs the remaining slots so `order` stays a
    /// contiguous 0-based sequence (which keeps `addTask`'s ordering correct).
    /// No-op when `canDelete(_:)` is false.
    func deleteTask(_ item: TodoItem) {
        guard canDelete(item), today != nil else { return }
        let remaining = items.filter { $0.persistentModelID != item.persistentModelID }
        context.delete(item)
        repack(remaining)
        save()
        items = remaining
    }

    /// Moves a task to a new slot and re-packs `order` so it stays a
    /// contiguous 0-based sequence (the invariant `addTask` relies on). Moves
    /// that would cross the section boundary are refused — see `canMove`.
    func moveTask(from source: Int, to destination: Int) {
        guard canMove(from: source, to: destination) else { return }
        var reordered = items
        reordered.insert(reordered.remove(at: source), at: destination)
        repack(reordered)
        save()
        items = reordered
    }

    func save() {
        try? context.save()
    }

    // MARK: - Scheduling

    /// Moves a row out of today and into the future: stores a `ScheduledTask`
    /// built from the parsed phrase, then removes the source slot (or just
    /// clears it when the day is already at its floor).
    func schedule(_ item: TodoItem, parse: ScheduleParse) {
        let task = ScheduledTask(text: parse.cleanText, dueDate: parse.dueDate, recurrence: parse.recurrence)
        context.insert(task)

        if canDelete(item) {
            deleteTask(item)
        } else {
            item.text = ""
            save()
        }
    }

    /// Fills today with any scheduled tasks that have come due. Idempotent —
    /// delivered one-time tasks fail the `deliveredAt == nil` predicate and
    /// recurring tasks advance `dueDate` past today — so it's safe on every
    /// open. Arrivals are appended to the scheduled section at the bottom and
    /// never claim a blank regular slot: the three Signal slots stay the
    /// user's to fill.
    private func materializePending(into log: DayLog, on date: Date) {
        let descriptor = FetchDescriptor<ScheduledTask>(
            predicate: #Predicate { $0.dueDate <= date && $0.deliveredAt == nil },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        guard let due = try? context.fetch(descriptor), !due.isEmpty else { return }

        var changed = false
        for task in due {
            let text = task.text.trimmingCharacters(in: .whitespacesAndNewlines)

            // Carry-over may already have brought the same unfinished task
            // into today (e.g. an incomplete "every day" task) — don't double up.
            let alreadyPresent = log.items.contains {
                !$0.isCompleted && $0.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(text) == .orderedSame
            }

            if !alreadyPresent {
                let item = TodoItem(
                    text: task.text,
                    isCompleted: false,
                    order: log.items.count,
                    isScheduled: true
                )
                item.day = log
                context.insert(item)
            }

            if task.isRecurring {
                task.dueDate = task.nextOccurrence(after: date)
            } else {
                task.deliveredAt = Date()
            }
            changed = true
        }

        if changed { save() }
    }

    // MARK: - Day transition

    private func createDayLog(for date: Date) -> DayLog {
        let log = DayLog(date: date)
        context.insert(log)

        // Carry-over keeps each task on the side of the header it was on, so a
        // recurring task that went unfinished doesn't get promoted into the
        // Signal slots overnight.
        var carriedRegular: [String] = []
        var carriedScheduled: [String] = []
        if SettingsStore.carryOverIncomplete, let prior = mostRecentPriorLog(before: date) {
            let carried = prior.orderedItems
                .filter { !$0.isCompleted && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            carriedRegular = carried.filter { !$0.isScheduled }.map(\.text)
            carriedScheduled = carried.filter(\.isScheduled).map(\.text)
        }

        // Start with the default number of slots, but grow to fit every carried
        // task so nothing is dropped when a prior day had more than three.
        let slotCount = max(Self.defaultTaskCount, carriedRegular.count)
        for index in 0 ..< slotCount {
            let text = index < carriedRegular.count ? carriedRegular[index] : ""
            let item = TodoItem(text: text, isCompleted: false, order: index)
            item.day = log
            context.insert(item)
        }
        for (offset, text) in carriedScheduled.enumerated() {
            let item = TodoItem(
                text: text,
                isCompleted: false,
                order: slotCount + offset,
                isScheduled: true
            )
            item.day = log
            context.insert(item)
        }

        save()
        return log
    }

    /// Defensive: make sure a loaded day is never empty of regular slots. A
    /// fresh day starts at `defaultTaskCount` (see `createDayLog`); days the
    /// user has grown or trimmed are left as-is, down to the `minTaskCount`
    /// floor. `normalizeOrder` does the renumbering afterwards.
    private func ensureMinimumSlots(_ log: DayLog) {
        let count = log.items.filter { !$0.isScheduled }.count
        guard count < Self.minTaskCount else { return }
        for _ in count ..< Self.minTaskCount {
            let item = TodoItem(text: "", isCompleted: false, order: log.items.count)
            item.day = log
            context.insert(item)
        }
        save()
    }

    // MARK: - Ordering

    /// The day's items in list order, with `order` re-packed to a contiguous
    /// 0-based sequence that puts every regular task before every scheduled
    /// one. Sorting is stable within each section, so relative order — the
    /// user's own arrangement — is preserved; it only ever pushes a stray
    /// scheduled row (one written before the flag existed, or left behind by a
    /// deletion) down to the tail.
    private func normalizeOrder(_ log: DayLog) -> [TodoItem] {
        let sorted = log.orderedItems
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.isScheduled != rhs.element.isScheduled {
                    return !lhs.element.isScheduled
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)

        if repack(sorted) { save() }
        return sorted
    }

    /// Renumbers `order` to match list position. Returns whether anything moved.
    @discardableResult
    private func repack(_ ordered: [TodoItem]) -> Bool {
        var changed = false
        for (index, todo) in ordered.enumerated() where todo.order != index {
            todo.order = index
            changed = true
        }
        return changed
    }

    // MARK: - Fetches

    private func fetchDayLog(for date: Date) -> DayLog? {
        var descriptor = FetchDescriptor<DayLog>(predicate: #Predicate { $0.date == date })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func mostRecentPriorLog(before date: Date) -> DayLog? {
        var descriptor = FetchDescriptor<DayLog>(
            predicate: #Predicate { $0.date < date },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
