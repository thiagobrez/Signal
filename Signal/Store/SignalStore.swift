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

        var isNewDay = false
        if let existing = fetchDayLog(for: startOfToday) {
            today = existing
            ensureMinimumSlots(existing)
        } else {
            today = createDayLog(for: startOfToday)
            isNewDay = true
        }

        if let today {
            materializePending(into: today, on: startOfToday)
        }

        items = today.map { normalizeOrder($0) } ?? []

        if isNewDay { carryOverSeparators(before: startOfToday) }
        pruneSeparators()
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
        taskCount > 0 && completedCount == taskCount
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
                SoundPlayer.play(
                    SettingsStore.celebrationSound, on: SettingsStore.celebrationSoundDevice
                )
            } else {
                SoundPlayer.play(
                    SettingsStore.completionSound, on: SettingsStore.completionSoundDevice
                )
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
        pruneSeparators()
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

    /// Swaps a task with the one above it — the keyboard's half of the reorder
    /// the drag grip does. Returns the row's new index, or nil when it's
    /// already on top, `index` is out of range, or the move would cross the
    /// `SCHEDULED` header: nothing moves.
    @discardableResult
    func moveTaskUp(at index: Int) -> Int? {
        guard canMove(from: index, to: index - 1) else { return nil }
        return moveByKeyboard(from: index, to: index - 1)
    }

    /// Swaps a task with the one below it. Returns the row's new index, or nil
    /// when it's already at the bottom (or `index` is out of range).
    @discardableResult
    func moveTaskDown(at index: Int) -> Int? {
        guard canMove(from: index, to: index + 1) else { return nil }
        return moveByKeyboard(from: index, to: index + 1)
    }

    // MARK: - Separators

    /// How many of today's rows are tasks — everything but the separators.
    var taskCount: Int {
        items.filter { !$0.isSeparator }.count
    }

    /// How many rows sit above the section header, tasks and separators alike.
    /// Separators are always regular rows, so they only ever live in here.
    private var regularRowCount: Int { regularItems.count }

    /// The row's place among the tasks alone: how many tasks sit above it. This
    /// is what the podium counts, so a separator never costs a task its medal.
    func taskOrdinal(at index: Int) -> Int {
        items.prefix(max(index, 0)).filter { !$0.isSeparator }.count
    }

    /// The nearest task below `index`, skipping separators — where the keyboard
    /// goes next. Nil when nothing but separators (or nothing at all) follows.
    func nextTaskIndex(after index: Int) -> Int? {
        items.indices.first { $0 > index && !items[$0].isSeparator }
    }

    /// The nearest task above `index`, skipping separators.
    func previousTaskIndex(before index: Int) -> Int? {
        items.indices.last { $0 < index && !items[$0].isSeparator }
    }

    /// The task now standing at `index`, or failing that the closest one: the
    /// first below it, else the last above. Where focus lands once the row that
    /// was at `index` has left the list.
    func taskIndex(nearest index: Int) -> Int? {
        nextTaskIndex(after: index - 1) ?? previousTaskIndex(before: index)
    }

    /// Whether a separator may be added above the row at `index`: only between
    /// two tasks of the regular section, so never at either end of it, never
    /// next to another separator and never among the scheduled rows.
    func canInsertSeparator(at index: Int) -> Bool {
        guard today != nil, index > 0, index < regularRowCount else { return false }
        return !items[index - 1].isSeparator && !items[index].isSeparator
    }

    /// Adds a separator above the row at `index`. Returns whether it was added
    /// — see `canInsertSeparator(at:)`.
    @discardableResult
    func insertSeparator(at index: Int) -> Bool {
        guard canInsertSeparator(at: index), let today else { return false }
        var reordered = items
        reordered.insert(makeSeparator(in: today, order: index), at: index)
        repack(reordered)
        save()
        items = reordered
        return true
    }

    /// The drag's version of `canMove`: a separator may additionally not be
    /// dragged onto either end of its section, where it would separate nothing.
    func canDrag(from source: Int, to destination: Int) -> Bool {
        guard canMove(from: source, to: destination) else { return false }
        guard items[source].isSeparator else { return true }
        return destination > 0 && destination < regularRowCount - 1
    }

    /// Removes every separator that no longer separates anything: one at the
    /// top or bottom of the regular section, or directly under another. Run
    /// after anything that can strand one — a delete, a keyboard move, the end
    /// of a drag, a new day — so a separator always has a task on both sides.
    /// That is also what keeps `canDelete` honest without it knowing about
    /// separators: a day down to its last task has no separator left to count.
    ///
    /// A separator holding text is turned back into a task first. Nothing can
    /// type into one, so it was mistaken for a blank slot by something that
    /// fills those — and the text is the part worth keeping.
    ///
    /// Returns whether anything changed.
    @discardableResult
    func pruneSeparators() -> Bool {
        var changed = false
        for item in items where item.isSeparator
            && !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            item.isSeparator = false
            changed = true
        }

        let regularCount = regularRowCount
        var kept: [TodoItem] = []
        var stranded: [TodoItem] = []
        for item in items.prefix(regularCount) {
            if item.isSeparator, kept.last?.isSeparator ?? true {
                stranded.append(item)
            } else {
                kept.append(item)
            }
        }
        if let last = kept.last, last.isSeparator {
            stranded.append(kept.removeLast())
        }

        if !stranded.isEmpty {
            let remaining = kept + items.dropFirst(regularCount)
            stranded.forEach { context.delete($0) }
            repack(remaining)
            items = remaining
            changed = true
        }
        if changed { save() }
        return changed
    }

    /// The keyboard's move, shared by `moveTaskUp` and `moveTaskDown`. A task
    /// steps over a separator exactly as it steps over a task; a separator
    /// itself never moves this way. Returns where the row ended up, which is
    /// not always `destination`: stepping out of a group can strand the
    /// separator that bounded it, and pruning that shifts the rows below.
    private func moveByKeyboard(from source: Int, to destination: Int) -> Int? {
        let item = items[source]
        guard !item.isSeparator else { return nil }
        moveTask(from: source, to: destination)
        pruneSeparators()
        return items.firstIndex { $0 === item }
    }

    /// Brings yesterday's separators along with the tasks they sat between. A
    /// separator comes across only if unfinished tasks were carried over on
    /// both sides of it; `createDayLog` has already laid those out in order at
    /// the top of the day, so a separator's slot is simply the number of
    /// carried tasks that were above it.
    private func carryOverSeparators(before date: Date) {
        guard SettingsStore.carryOverIncomplete, let today,
              let prior = mostRecentPriorLog(before: date) else { return }

        var carriedAbove = 0
        var slots: [Int] = []
        for item in prior.orderedItems {
            if item.isSeparator {
                if carriedAbove > 0, slots.last != carriedAbove { slots.append(carriedAbove) }
            } else if !item.isCompleted, !item.text.trimmingCharacters(in: .whitespaces).isEmpty {
                carriedAbove += 1
            }
        }

        let regularCount = regularRowCount
        var reordered = items
        // Back to front, so an insertion never shifts a slot still to come.
        for slot in slots.reversed() where slot < regularCount
            && !items[slot].text.trimmingCharacters(in: .whitespaces).isEmpty {
            reordered.insert(makeSeparator(in: today, order: slot), at: slot)
        }
        guard reordered.count != items.count else { return }
        repack(reordered)
        save()
        items = reordered
    }

    private func makeSeparator(in log: DayLog, order: Int) -> TodoItem {
        let separator = TodoItem(order: order)
        separator.isSeparator = true
        separator.day = log
        context.insert(separator)
        return separator
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

            // A schedule with no text is an abandoned draft from the overview,
            // not something to deliver — the overview prunes its own blanks,
            // and this is the net under that.
            if text.isEmpty {
                context.delete(task)
                changed = true
                continue
            }

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
