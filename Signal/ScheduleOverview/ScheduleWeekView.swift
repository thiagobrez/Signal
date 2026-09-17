import SwiftUI
import SwiftData

/// Week mode: a dedicated "Every day" section for daily tasks, then one
/// vertical row per day, Monday through Sunday.
///
/// Today and every day after it are editable — the same rows, the same editor
/// and the same keys as the panel — and days already past stay history. The
/// keyboard walks the whole week as one list, so this view owns the focus
/// choreography: what Tab does at the end of a day, where the caret lands after
/// a delete, and the beat a row holds while it is being scheduled away.
struct ScheduleWeekView: View {
    let model: ScheduleOverviewModel

    /// Which edge of a row the caret is arriving at — see `RowEntry`.
    @State private var rowEntry: RowEntry = .fromBelow
    /// Rows mid-scheduling: the "Every Monday" / "Scheduled for…" label shown
    /// during the brief confirmation beat before the row moves.
    @State private var confirmations: [PersistentIdentifier: String] = [:]

    private let calendar = Calendar.current

    /// The rows' own `index` / `focusedIndex` API, adapted onto the ID the
    /// model tracks: rows come and go under the caret, and an index-based focus
    /// would land on whichever task happened to shift into that slot.
    private var focusBinding: Binding<Int?> {
        Binding(
            get: { model.focusIndex(of: model.focusedID) },
            set: { model.focusedID = model.id(atFocusIndex: $0) }
        )
    }

    var body: some View {
        let rows = model.focusRows
        let indexByID = Dictionary(
            rows.enumerated().map { ($0.element.id, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )

        Group {
            if model.weekIsEmpty {
                emptyState
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        if !model.dailyTasks.isEmpty {
                            everydaySection(indexByID)
                            Divider().overlay(.white.opacity(0.1))
                        }

                        ForEach(model.weekDays, id: \.self) { day in
                            dayRow(day, indexByID)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private func everydaySection(_ indexByID: [PersistentIdentifier: Int]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: "repeat")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.green)
                Text("EVERY DAY")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(.green.opacity(0.8))
            }
            .frame(width: 64, alignment: .leading)
            .padding(.top, 6)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(model.dailyTasks, id: \.persistentModelID) { task in
                    // A daily routine belongs to no single day, so its text is
                    // parsed against now, exactly as in the panel.
                    scheduledRow(task, on: nil, indexByID)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.green.opacity(0.06))
        )
        .padding(.bottom, 4)
    }

    private func dayRow(_ day: Date, _ indexByID: [PersistentIdentifier: Int]) -> some View {
        let kind = model.kind(of: day)
        let isToday = kind == .today
        let isHighlighted = model.highlightedDay == day
        let entries = model.entries(on: day)

        return HStack(alignment: .top, spacing: 12) {
            // The weekday label is fixed-width so the day numbers line up in a
            // column regardless of "WED" being wider than "TUE".
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(weekdayLabel(day))
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .frame(width: 30, alignment: .leading)
                Text(dayNumber(day))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(isToday ? .green : .white.opacity(kind == .past ? 0.25 : 0.5))
            .frame(width: 64, alignment: .leading)
            .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                switch kind {
                case .past:
                    if entries.isEmpty {
                        Text("—")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.15))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 3)
                    } else {
                        ForEach(entries) { entry in
                            switch entry {
                            case .scheduled(let task):
                                // A pending schedule the app never opened to
                                // collect: shown, but not edited from history.
                                ScheduledTaskHistoryRow(task: task)
                            case .todo(let item):
                                DayTaskRow(item: item)
                            }
                        }
                    }
                case .today:
                    todayRows(day, indexByID)
                case .future:
                    ForEach(model.tasks(on: day), id: \.persistentModelID) { task in
                        scheduledRow(task, on: day, indexByID)
                    }
                    addButton(on: day)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.06))
            }
        }
    }

    /// Today's row mirrors the panel: the regular tasks, the add button, then —
    /// when the schedule delivered something — a SCHEDULED caption and its rows.
    @ViewBuilder
    private func todayRows(_ day: Date, _ indexByID: [PersistentIdentifier: Int]) -> some View {
        let items = Array(model.store.items.enumerated())
        let sectionStart = model.store.scheduledSectionStart

        ForEach(items.prefix(sectionStart), id: \.element.persistentModelID) { pair in
            todoRow(pair.element, slot: pair.offset, on: day, indexByID)
        }

        addButton(on: day)

        if sectionStart < items.count {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 9, weight: .semibold))
                Text("SCHEDULED")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
            }
            .foregroundStyle(.white.opacity(0.4))
            .padding(.top, 2)

            ForEach(items.suffix(from: sectionStart), id: \.element.persistentModelID) { pair in
                todoRow(pair.element, slot: pair.offset, on: day, indexByID)
            }
        }
    }

    // MARK: - Rows

    private func todoRow(
        _ item: TodoItem,
        slot: Int,
        on day: Date,
        _ indexByID: [PersistentIdentifier: Int]
    ) -> some View {
        let id = item.persistentModelID
        let index = indexByID[id] ?? -1
        return TodoRow(
            item: item,
            index: index,
            store: model.store,
            placeholder: "Something that matters…",
            confirmationLabel: confirmations[id],
            focused: focusBinding,
            isDragging: false,
            onSubmit: { parse in submit(at: index, parse: parse) },
            onToggle: { toggleComplete(item, at: index) },
            onEscape: model.endEditing,
            onDelete: { deleteFromButton(.todo(item)) },
            onTab: { advanceOrAdd(from: index) },
            onBacktab: { focusPrevious(from: index) },
            onMoveDown: {
                rowEntry = .fromAbove
                advanceOrAdd(from: index)
            },
            onMoveUp: {
                rowEntry = .fromBelow
                focusPrevious(from: index)
            },
            rowEntry: rowEntry,
            onFocusLanded: { if rowEntry != .fromBelow { rowEntry = .fromBelow } },
            onEmptyBackspace: { backspaceDelete(at: index) },
            onReorderUp: { reorderToday(at: slot, by: -1) },
            onReorderDown: { reorderToday(at: slot, by: 1) },
            showsDragHandle: false,
            podiumIndex: slot,
            // Today's rows keep the panel's strictly-future keyword semantics.
            parseAnchor: nil,
            metrics: .compact
        )
    }

    private func scheduledRow(
        _ task: ScheduledTask,
        on day: Date?,
        _ indexByID: [PersistentIdentifier: Int]
    ) -> some View {
        let id = task.persistentModelID
        let index = indexByID[id] ?? -1
        return ScheduledTaskRow(
            task: task,
            index: index,
            parseAnchor: day,
            focused: focusBinding,
            onSubmit: { parse in submit(at: index, parse: parse) },
            onEscape: model.endEditing,
            onDelete: { deleteFromButton(.scheduled(task)) },
            onTab: { advanceOrAdd(from: index) },
            onBacktab: { focusPrevious(from: index) },
            onMoveDown: {
                rowEntry = .fromAbove
                advanceOrAdd(from: index)
            },
            onMoveUp: {
                rowEntry = .fromBelow
                focusPrevious(from: index)
            },
            rowEntry: rowEntry,
            onFocusLanded: { if rowEntry != .fromBelow { rowEntry = .fromBelow } },
            onEmptyBackspace: { backspaceDelete(at: index) },
            confirmationLabel: confirmations[id]
        )
    }

    private func addButton(on day: Date) -> some View {
        Button { addTask(on: day) } label: {
            HStack(spacing: TaskRowMetrics.compact.spacing) {
                Image(systemName: "plus.circle")
                    .font(TaskRowMetrics.compact.iconFont)
                    .frame(width: TaskRowMetrics.compact.iconBox, height: TaskRowMetrics.compact.textRowHeight)
                Text("Add a task")
                    .font(TaskRowMetrics.compact.textFont)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white.opacity(0.3))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minHeight: TaskRowMetrics.compact.textRowHeight)
        .padding(.vertical, TaskRowMetrics.compact.verticalPadding)
    }

    // MARK: - Focus choreography

    private func addTask(on day: Date) {
        guard let id = model.addTask(on: day) else { return }
        // Deferred so the caret lands after the new row has been rendered.
        DispatchQueue.main.async { model.focusedID = id }
    }

    /// Tab: the next row, or — off the end of a day whose last row is filled —
    /// a fresh row on that same day, so capturing never pauses.
    private func advanceOrAdd(from index: Int) {
        let rows = model.focusRows
        guard rows.indices.contains(index) else { return }
        let row = rows[index]
        let endsGroup = index == rows.count - 1 || rows[index + 1].group != row.group

        if endsGroup, !row.entry.isBlank, let day = row.addDay {
            addTask(on: day)
        } else if index < rows.count - 1 {
            model.focusedID = rows[index + 1].id
        }
    }

    private func focusPrevious(from index: Int) {
        let rows = model.focusRows
        guard index > 0, rows.indices.contains(index - 1) else { return }
        model.focusedID = rows[index - 1].id
    }

    /// Enter: schedule the row away when its text ends in a date phrase,
    /// otherwise complete it (today) or simply move on (a future day, which has
    /// nothing to complete).
    private func submit(at index: Int, parse: ScheduleParse?) {
        let rows = model.focusRows
        guard rows.indices.contains(index) else { return }
        switch rows[index].entry {
        case .todo(let item):
            if let parse {
                scheduleAway(item, at: index, parse: parse)
            } else {
                toggleComplete(item, at: index)
            }
        case .scheduled(let task):
            if let parse {
                reschedule(task, parse: parse)
            } else {
                advanceOrAdd(from: index)
            }
        }
    }

    private func toggleComplete(_ item: TodoItem, at index: Int) {
        let wasCompleted = item.isCompleted
        model.toggle(item)
        // An empty slot refuses to complete — leave the caret alone.
        guard item.isCompleted != wasCompleted else { return }
        // Defer so focus lands after the row swaps between field and `Text`.
        DispatchQueue.main.async {
            let rows = model.focusRows
            guard rows.indices.contains(index) else { return }
            if item.isCompleted, index < rows.count - 1 {
                model.focusedID = rows[index + 1].id
            } else {
                model.focusedID = rows[index].id
            }
        }
    }

    /// One of today's rows ending in a date phrase: hold it for a beat showing
    /// where it went, then move it out of today.
    private func scheduleAway(_ item: TodoItem, at index: Int, parse: ScheduleParse) {
        let id = item.persistentModelID
        model.focusedID = nil
        confirmations[id] = parse.confirmationLabel
        Task {
            try? await Task.sleep(for: .seconds(0.9))
            confirmations[id] = nil
            model.schedule(item, parse: parse)
            DispatchQueue.main.async {
                let rows = model.focusRows
                guard !rows.isEmpty else { return }
                model.focusedID = rows[min(index, rows.count - 1)].id
            }
        }
    }

    /// A future row ending in a date phrase: the schedule itself moves, which
    /// is how a one-off becomes a routine. The caret is dropped rather than
    /// chased — the row has left the day it was typed on.
    private func reschedule(_ task: ScheduledTask, parse: ScheduleParse) {
        let id = task.persistentModelID
        model.focusedID = nil
        confirmations[id] = parse.confirmationLabel
        Task {
            try? await Task.sleep(for: .seconds(0.9))
            confirmations[id] = nil
            model.reschedule(task, parse: parse)
        }
    }

    /// Backspace on an already-empty row: remove it and put the caret at the
    /// end of the row above. Deferred a tick because this fires from inside the
    /// editor's own key handling, and a second tick so the rows re-render
    /// before focus is written.
    private func backspaceDelete(at index: Int) {
        let rows = model.focusRows
        guard rows.indices.contains(index) else { return }
        let entry = rows[index].entry
        if case .todo(let item) = entry, !model.store.canDelete(item) { return }

        model.focusedID = nil
        DispatchQueue.main.async {
            delete(entry)
            DispatchQueue.main.async {
                let updated = model.focusRows
                let target = min(max(index - 1, 0), updated.count - 1)
                if updated.indices.contains(target) { model.focusedID = updated[target].id }
            }
        }
    }

    /// The hover × button. Focus is dropped first: the row is about to go, and
    /// reading a deleted model to work out where the caret should land is how
    /// SwiftData crashes.
    private func deleteFromButton(_ entry: OverviewEntry) {
        model.focusedID = nil
        DispatchQueue.main.async { delete(entry) }
    }

    private func delete(_ entry: OverviewEntry) {
        switch entry {
        case .todo(let item): model.delete(item)
        case .scheduled(let task): model.delete(task)
        }
    }

    /// ⌥↑ / ⌥↓ on one of today's rows, which is the only place the overview has
    /// an order to change. `slot` is the row's index in `store.items`.
    private func reorderToday(at slot: Int, by offset: Int) {
        withAnimation(.snappy(duration: 0.2)) {
            _ = offset < 0 ? model.store.moveTaskUp(at: slot) : model.store.moveTaskDown(at: slot)
        }
    }

    // MARK: - Chrome

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.25))
            Text("No tasks this week")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
            Text("Press T to jump back to today, where tasks can be added")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func weekdayLabel(_ day: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: day).uppercased()
    }

    private func dayNumber(_ day: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: day)
    }
}

/// A schedule sitting on a day already past: one that came due while the app
/// was closed. Read-only like the rest of history.
private struct ScheduledTaskHistoryRow: View {
    let task: ScheduledTask

    var body: some View {
        HStack(alignment: .top, spacing: TaskRowMetrics.compact.spacing) {
            Image(systemName: task.isRecurring ? "repeat" : "calendar")
                .font(TaskRowMetrics.compact.iconFont)
                .foregroundStyle(task.isRecurring ? Color.green : Color.white.opacity(0.4))
                .frame(width: TaskRowMetrics.compact.iconBox, height: TaskRowMetrics.compact.textRowHeight)

            Text(task.text)
                .font(TaskRowMetrics.compact.textFont)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(RowTextLayout.maxLines)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: TaskRowMetrics.compact.textRowHeight, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.vertical, TaskRowMetrics.compact.verticalPadding)
        .frame(minHeight: TaskRowMetrics.compact.rowHeight)
    }
}
