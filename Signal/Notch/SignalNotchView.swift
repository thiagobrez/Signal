import SwiftUI
import AppKit
import SwiftData
#if APPSTORE
import StoreKit
#endif

/// The entire primary UI: the day's to-do slots shown inside the notch. Starts
/// at three but grows as the user adds tasks.
///
/// The list is drawn in two pieces from one flat array: the regular rows, the
/// "Add a task" button, then — when the schedule has delivered something — a
/// `SCHEDULED` header and the rows beneath it. Indices stay flat throughout, so
/// focus, measured row heights and the drag geometry are unchanged by the
/// split; the section block between the two pieces is carried as extra space in
/// `NotchRowLayout`, and reorders are clamped at it exactly as at the list ends.
struct SignalNotchView: View {
    let store: SignalStore
    let controller: NotchController

    @State private var focused: Int?
    @State private var placeholders: [String] = SignalNotchView.randomPlaceholders()
    @State private var celebrating = false
    @State private var blurred = false
    /// Rows mid-scheduling: the "Scheduled for…" label shown during the brief
    /// confirmation beat before the row leaves today.
    @State private var scheduledConfirmation: [PersistentIdentifier: String] = [:]
    /// The task currently being dragged to a new slot: it follows the cursor
    /// while the rows it passes shuffle out of its way.
    @State private var draggingID: PersistentIdentifier?
    /// How far the dragged row sits from the slot it currently occupies.
    @State private var dragTranslation: CGFloat = 0
    /// How far the dragged row has already been moved by the swaps it earned,
    /// so the live offset is measured against its new home rather than where
    /// the drag started. In points rather than slots: rows wrap, so no two
    /// slots are necessarily the same height.
    @State private var dragShift: CGFloat = 0
    /// Each row's measured height, keyed by task. Rows grow with their text
    /// (see `TaskTextEditor`), so the list's arithmetic — its height, what's
    /// on screen, how far a drag has to travel — is driven by what the rows
    /// actually measured rather than by one fixed row height.
    @State private var rowHeights: [PersistentIdentifier: CGFloat] = [:]
    /// Which edge of a row the keyboard is arriving at, so focus lands at the
    /// end of the line it entered on: the last line when it came up from the
    /// row below, the first when it came down from the row above. On a
    /// single-line row the two are the same character — the end of the text —
    /// so short rows keep landing exactly where they always did.
    @State private var rowEntry: RowEntry = .fromBelow
    /// How much scroll content hangs below the viewport — drives the chevron
    /// hinting at tasks hidden past the fold.
    @State private var bottomOverflow: CGFloat = 0

    #if APPSTORE
    @Environment(\.requestReview) private var requestReview
    #endif

    /// A pool of suggestions spanning software development, project management,
    /// design, and everyday chores. One is shown per empty slot, refreshed each
    /// time the notch opens.
    private static let placeholderPool: [String] = [
        // Software development
        "Fix that flaky test…",
        "Review the open pull request…",
        "Refactor the messy module…",
        "Write tests for the new feature…",
        "Squash a lingering bug…",
        "Update the dependencies…",
        // Project management
        "Unblock a teammate…",
        "Tidy up the backlog…",
        "Prep for standup…",
        "Follow up on that thread…",
        "Scope the next milestone…",
        // Design
        "Polish a rough UI…",
        "Sketch a new flow…",
        "Pick a better color…",
        "Refine the icon set…",
        // Day to day
        "Reply to that email…",
        "Drink some water…",
        "Take a short walk…",
        "Tidy your desk…",
        "Plan tomorrow…",
        "Something that matters…",
    ]

    // The whole pool, shuffled — enough distinct suggestions to cover every slot
    // (rows index into this modulo its length, so adding tasks never crashes).
    private static func randomPlaceholders() -> [String] {
        placeholderPool.shuffled()
    }

    /// How many rows the card shows before the list starts scrolling.
    private static let maxVisibleRows = 10
    private static let rowSpacing: CGFloat = 10

    /// Pinned so the list's natural height can be computed exactly rather than
    /// measured — the list is one container at all sizes, and its height is
    /// what grows, so the arithmetic has to match the layout to the point.
    private static let footerHeight: CGFloat = TodoRow.rowHeight
    /// The `SCHEDULED` label that opens the bottom section.
    private static let sectionHeaderHeight: CGFloat = 18

    /// Index of the first scheduled row — where the section header goes, and
    /// the end of the regular rows.
    private var sectionStart: Int { store.scheduledSectionStart }

    /// Whether the schedule delivered anything into today.
    private var hasScheduled: Bool { sectionStart < store.items.count }

    /// The block that separates the two sections: the add button (interactive
    /// mode only) and the `SCHEDULED` header, each with the gap above it. It
    /// isn't a row, so the list geometry carries it as extra space above the
    /// first scheduled row.
    private var sectionGap: CGFloat {
        let footer = controller.mode == .interactive ? Self.footerHeight + Self.rowSpacing : 0
        return footer + Self.sectionHeaderHeight + Self.rowSpacing
    }

    /// The rows as the list sees them: every row's measured height in order,
    /// falling back to the single-line height for a row that hasn't reported
    /// one yet (the frame before it's first laid out), plus the section block
    /// when there is one.
    private var rowLayout: NotchRowLayout {
        NotchRowLayout(
            heights: store.items.map { rowHeights[$0.persistentModelID] ?? TodoRow.rowHeight },
            spacing: Self.rowSpacing,
            extras: hasScheduled ? [sectionStart: sectionGap] : [:]
        )
    }

    /// The list's natural height: every row, the section block when the
    /// schedule delivered something, plus the add button. The button is only
    /// counted here when it's still the last thing in the list — once there's
    /// a scheduled section it has moved up into `sectionGap`.
    private var listContentHeight: CGFloat {
        guard !store.items.isEmpty else { return 0 }
        var height = rowLayout.contentHeight
        if controller.mode == .interactive, !hasScheduled {
            height += Self.rowSpacing + Self.footerHeight
        }
        return height
    }

    /// Where growth stops and scrolling takes over: ten single-line rows' worth
    /// of list, the gaps between them, and the add button under the last one.
    /// A wrapped row spends more of that budget than a short one does.
    private var listCapHeight: CGFloat {
        var height = CGFloat(Self.maxVisibleRows) * TodoRow.rowHeight
            + CGFloat(Self.maxVisibleRows - 1) * Self.rowSpacing
        if controller.mode == .interactive {
            height += Self.rowSpacing + Self.footerHeight
        }
        return height
    }

    private var listHeight: CGFloat { min(listContentHeight, listCapHeight) }

    /// Whether the list is tall enough to actually scroll. When it isn't,
    /// scrolling is disabled and never touched — a stray `scrollTo` on a list
    /// that fits leaves the clip view at a fractional offset (~0.1pt), which
    /// pushes every hosted text view to a fractional window Y. SwiftUI snaps
    /// its own views (the checkboxes) to the pixel grid but not the hosted
    /// ones, so the text then sits a fraction of a pixel off its checkbox —
    /// the shimmer that showed up when arrowing through a short list.
    private var listOverflows: Bool { listContentHeight > listCapHeight + 0.5 }

    /// Scroll target for keeping the add button in view on the last row.
    private static let footerID = "add-task-footer"

    /// The scroll offset, derived from the tracked overflow and the pinned
    /// geometry rather than measured (coordinate-space queries don't work in
    /// this panel — see ScrollOverflowReporter).
    private var scrollOrigin: CGFloat {
        listContentHeight - listHeight - bottomOverflow
    }

    /// Whether a row sits fully inside the viewport right now.
    private func rowIsVisible(_ index: Int) -> Bool {
        rowLayout.isVisible(index, scrollOrigin: scrollOrigin, viewportHeight: listHeight)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            header

            // One container at every size. The list is always a ScrollView and
            // only its *height* changes — growing with the rows until it hits
            // the cap, then scrolling. Branching on the row count instead would
            // swap one container for another as the tenth task is added, which
            // tears the rows down and rebuilds them: a visible fade, and the
            // field being typed into loses first responder mid-edit.
            //
            // Scrolling stays entirely on SwiftUI's side: the ScrollView
            // re-asserts its own remembered offset on every render, so any
            // offset written from AppKit is reverted (or worse, fought
            // frame-by-frame). The AppKit tracker below only *reads*.
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Self.rowSpacing) {
                        rows(0 ..< sectionStart)

                        // The add button lives in the flow, after the last
                        // regular row — adding a task always continues the
                        // user's own list, never the schedule's.
                        if controller.mode == .interactive {
                            footer
                                // The scroll content is shifted left to cover
                                // the grip gutter; the footer has no grip, so
                                // push it back into alignment.
                                .padding(.leading, TodoRow.handleGutterWidth)
                                .frame(height: Self.footerHeight)
                                .id(Self.footerID)
                        }

                        // Whatever the schedule delivered, under its own
                        // heading at the bottom of the panel.
                        if hasScheduled {
                            sectionHeader
                            rows(sectionStart ..< store.items.count)
                        }
                    }
                    .background(ScrollOverflowReporter { bottomOverflow = $0 })
                }
                .frame(height: listHeight)
                // The viewport has to cover the grip gutter too, otherwise
                // it clips the grips away.
                .padding(.leading, -TodoRow.handleGutterWidth)
                // A list that fits never scrolls — see `listOverflows`. This
                // pins the clip view at offset 0 so hosted fields stay on the
                // pixel grid.
                .scrollDisabled(!listOverflows)
                .overlay(alignment: .bottom) { overflowChevron }
                // Keep the focused row visible — covers both adding a row
                // beyond the fold (focus lands on the new row) and
                // reopening with the caret on a row that's scrolled away.
                // Only ever scroll when the list actually overflows and the
                // target isn't already visible: any scrollTo on a fitting or
                // already-visible row nudges the offset by a fraction of a
                // point, which shows up as the list twitching on every
                // keypress and knocks the text off the pixel grid.
                .onChange(of: focused) { _, newValue in
                    guard listOverflows,
                          let newValue, store.items.indices.contains(newValue) else { return }
                    if !hasScheduled, newValue == store.items.count - 1 {
                        // On the last row, go all the way down so the add
                        // button below it stays in reach. Re-fire after the
                        // layout settles: on open the panel's slide-in is
                        // still moving the offset, and on add the new row
                        // hasn't grown the content yet when this runs.
                        // scrollTo is idempotent, so the repeats are no-ops
                        // whenever the earlier ones already landed.
                        for delay: TimeInterval in [0, 0.15, 0.45, 0.8] {
                            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                withAnimation(.snappy(duration: 0.2)) {
                                    proxy.scrollTo(Self.footerID, anchor: .bottom)
                                }
                            }
                        }
                    } else if !rowIsVisible(newValue) {
                        let target = store.items[newValue].persistentModelID
                        withAnimation(.snappy(duration: 0.2)) {
                            proxy.scrollTo(target)
                        }
                        // The last regular row has the add button and the
                        // section header hanging below it, so it gets the same
                        // settle-and-re-fire ladder the footer used to: on add
                        // the new row hasn't grown the content yet when this
                        // first runs. scrollTo is idempotent, so the repeats
                        // are no-ops once an earlier one has landed.
                        if hasScheduled, newValue == sectionStart - 1 {
                            for delay: TimeInterval in [0.15, 0.45, 0.8] {
                                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                    withAnimation(.snappy(duration: 0.2)) {
                                        proxy.scrollTo(target)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 340)
        // Grow/shrink the card smoothly as tasks are added.
        .animation(.snappy(duration: 0.25), value: store.items.count)
        // Depth-of-field: while the day is done the tasks recede out of focus so
        // the sharp grass in front is the subject; the blur lifts as the grass
        // parts, bringing the tasks back into focus.
        .blur(radius: blurred ? 7 : 0)
        .animation(.easeInOut(duration: 0.6), value: blurred)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.black)
        )
        .overlay {
            if celebrating {
                CelebrationGrass()
                    .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(.easeInOut(duration: 0.4), value: celebrating)
        .onChange(of: store.celebrationTrigger) { _, _ in celebrate() }
        .onKeyPress(.escape) {
            controller.hide()
            return .handled
        }
        .onChange(of: controller.presentationRequest) { _, _ in
            placeholders = SignalNotchView.randomPlaceholders()
            endDrag()
        }
        .onChange(of: controller.focusRequest) { _, _ in focusInitial() }
        .onAppear { focusInitial() }
    }

    /// One row per task over a slice of the list. `pair.offset` stays the flat
    /// index into `store.items`, so every index-based mechanism — focus, row
    /// heights, drag geometry — is unaffected by the list being drawn in two
    /// pieces.
    private func rows(_ range: Range<Int>) -> some View {
        ForEach(Array(store.items.enumerated())[range], id: \.element.persistentModelID) { pair in
            let isDragging = draggingID == pair.element.persistentModelID
            TodoRow(
                item: pair.element,
                index: pair.offset,
                store: store,
                placeholder: placeholders[pair.offset % placeholders.count],
                confirmationLabel: scheduledConfirmation[pair.element.persistentModelID],
                focused: $focused,
                isDragging: isDragging,
                onSubmit: idle { parse in submit(pair.element, at: pair.offset, parse: parse) },
                onToggle: idle { toggleComplete(pair.element, at: pair.offset) },
                // Escape isn't a row interaction — dismissing has to stay
                // available even mid-celebration.
                onEscape: { controller.hide() },
                onDelete: idle { deleteTask(pair.element) },
                onTab: idle { advanceOrAdd(from: pair.offset) },
                onBacktab: idle { focusPrevious(from: pair.offset) },
                // Same moves as Tab and Shift-Tab, but the arrows say which
                // edge of the next row the caret should land on — they're
                // walking through the text, not jumping between fields.
                onMoveDown: idle {
                    rowEntry = .fromAbove
                    advanceOrAdd(from: pair.offset)
                },
                onMoveUp: idle {
                    rowEntry = .fromBelow
                    focusPrevious(from: pair.offset)
                },
                rowEntry: rowEntry,
                // The arrows' choice of edge is spent the moment it's used, so
                // the next click, Tab or new task lands at the end as always.
                onFocusLanded: { if rowEntry != .fromBelow { rowEntry = .fromBelow } },
                onEmptyBackspace: idle { backspaceDelete(pair.element, at: pair.offset) },
                onReorderUp: idle { moveTaskUp(at: pair.offset) },
                onReorderDown: idle { moveTaskDown(at: pair.offset) },
                onDragChanged: { translation in drag(pair.element, by: translation) },
                onDragEnded: endDrag
            )
            // Rows grow with their text, so the list learns each one's height
            // from the row itself. Measured before the drag offset is applied,
            // so a row in flight still reports the height of its slot.
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                rowHeights[pair.element.persistentModelID] = height
            }
            // The dragged row follows the cursor and rides above its
            // neighbours as they shuffle out of the way.
            .offset(y: isDragging ? dragTranslation : 0)
            .zIndex(isDragging ? 1 : 0)
        }
    }

    /// Wraps a row interaction so it does nothing while the celebration is on
    /// screen. The grass overlay already swallows the mouse; the rows behind it
    /// keep first responder though, so the keyboard has to be held back too —
    /// otherwise arrows, Tab and Enter go on editing the blurred list nobody
    /// can see.
    private func idle(_ action: @escaping () -> Void) -> () -> Void {
        { if !celebrating { action() } }
    }

    private func idle<T>(_ action: @escaping (T) -> Void) -> (T) -> Void {
        { value in if !celebrating { action(value) } }
    }

    /// Tracks the cursor during a reorder: the row is offset to follow the
    /// drag, and each time it has travelled more than half of the neighbour
    /// it's passing, the two swap — so the list reorders live under the
    /// cursor. Each swap is measured against that neighbour's own height: a
    /// wrapped row takes further to pass than a single-line one.
    private func drag(_ item: TodoItem, by translation: CGFloat) {
        if draggingID != item.persistentModelID {
            draggingID = item.persistentModelID
            dragShift = 0
            // Indices are about to shift, so the focused index no longer maps
            // cleanly — same reasoning as delete.
            focused = nil
        }

        var offset = translation - dragShift
        while let from = store.items.firstIndex(where: { $0.persistentModelID == item.persistentModelID }) {
            guard let step = rowLayout.swapStep(from: from, offset: offset),
                  store.canMove(from: from, to: step.to) else {
                let neighbour = offset > 0 ? from + 1 : from - 1
                if !store.canMove(from: from, to: neighbour) {
                    // Already at an end — or at the section header, which a row
                    // may no more cross than it may leave the list: hold the
                    // row at the boundary rather than letting it drift past.
                    let limit = rowLayout.boundaryLimit(at: from)
                    offset = max(-limit, min(limit, offset))
                }
                break
            }
            withAnimation(.snappy(duration: 0.2)) {
                store.moveTask(from: from, to: step.to)
            }
            // The row now sits a whole neighbour further along, so the offset
            // that's left is what it overshot that new home by.
            let travelled = offset > 0 ? step.distance : -step.distance
            dragShift += travelled
            offset -= travelled
        }
        dragTranslation = offset
    }

    /// Drops the row into the slot it's hovering: the moves already happened
    /// live, so this only has to settle the row back onto the grid.
    private func endDrag() {
        withAnimation(.snappy(duration: 0.2)) {
            dragTranslation = 0
        }
        draggingID = nil
        dragShift = 0
    }

    private var header: some View {
        HStack {
            Text(todayLabel)
                .font(.system(size: 10, weight: .bold))
                .tracking(2.5)
            Spacer()
            Text("\(store.completedCount)/\(store.items.count)")
                .font(.system(size: 10, weight: .semibold))
                .tracking(2.5)
                .monospacedDigit()
        }
        .foregroundStyle(.white.opacity(0.4))
    }

    /// Opens the bottom section: everything below it came from the schedule
    /// rather than from today's typing.
    private var sectionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 10, weight: .semibold))
            Text("SCHEDULED")
                .font(.system(size: 10, weight: .bold))
                .tracking(2.5)
        }
        .foregroundStyle(.white.opacity(0.4))
        // The scroll content is shifted left to cover the grip gutter; the
        // header has no grip, so push it back into alignment with the rows.
        .padding(.leading, TodoRow.handleGutterWidth)
        .frame(height: Self.sectionHeaderHeight, alignment: .bottomLeading)
    }

    /// The "add a task" affordance.
    private var footer: some View {
        Button(action: addTask) {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 18))
                Text("Add a task")
                    .font(.system(size: 15, weight: .medium))
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.3))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Subtle hint that more tasks are hidden below; fades out at the bottom.
    private var overflowChevron: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.3))
            // Re-center within the visible card: the viewport is widened
            // leftwards by the grip gutter, which would skew the midpoint.
            .padding(.leading, TodoRow.handleGutterWidth / 2)
            .padding(.bottom, 2)
            // Small dead-zone so the hint doesn't flicker while resting
            // within a hair of the bottom.
            .opacity(bottomOverflow > 4 ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: bottomOverflow > 4)
            .allowsHitTesting(false)
    }

    private var todayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: Date())
    }

    /// Opening drops the caret on the last *regular* slot — that's where
    /// capturing the next thing continues, and it brings the add button into
    /// view with it. The scheduled rows below are somewhere the caret is sent,
    /// never somewhere it starts.
    private func focusInitial() {
        guard controller.mode == .interactive else {
            focused = nil
            return
        }
        // Defer so focus lands after the panel becomes key.
        DispatchQueue.main.async {
            guard !store.items.isEmpty else { return }
            let lastRegular = hasScheduled ? sectionStart - 1 : store.items.count - 1
            focused = max(lastRegular, 0)
        }
    }

    /// Grow the grass (and blur the tasks), hold, then part the grass to the
    /// sides — lifting the blur in sync so the tasks slide back into focus —
    /// before tearing the overlay down once the blades have cleared.
    private func celebrate() {
        celebrating = true
        blurred = true
        Task {
            try? await Task.sleep(for: .seconds(GrassBlade.exitStart))
            blurred = false
            try? await Task.sleep(for: .seconds(GrassBlade.exitStagger + GrassBlade.exitSlide + 0.1))
            celebrating = false

            #if APPSTORE
            // First completed day: ask for a rating once ever, and only after
            // the grass has fully cleared so the ask never steps on the moment.
            if !SettingsStore.hasRequestedReview {
                SettingsStore.hasRequestedReview = true
                // Let the card settle for a beat before the system dialog.
                try? await Task.sleep(for: .seconds(0.5))
                requestReview()
            }
            #endif
        }
    }

    /// Append a slot and drop the caret straight into it so the user can keep
    /// typing without reaching for the mouse.
    private func addTask() {
        guard let newIndex = store.addTask() else { return }
        DispatchQueue.main.async { focused = newIndex }
    }

    /// Remove a slot. Focus is dropped rather than guessed at — the remaining
    /// rows have just shifted, so the old focused index no longer maps cleanly.
    private func deleteTask(_ item: TodoItem) {
        focused = nil
        store.deleteTask(item)
    }

    /// Backspace in an empty field: remove the row and put the caret at the
    /// end of the row above (or the new first row when it was on top). Deferred
    /// a tick because this fires from inside the field's own key handling —
    /// deleting the row would tear the NSTextField down mid-event — and a
    /// second tick so the rows re-render with shifted indices before the
    /// index-based focus binding fires.
    private func backspaceDelete(_ item: TodoItem, at index: Int) {
        guard store.canDelete(item) else { return }
        focused = nil
        DispatchQueue.main.async {
            store.deleteTask(item)
            DispatchQueue.main.async { focused = max(index - 1, 0) }
        }
    }

    /// Enter: when the task ends in a date phrase, schedule it away; otherwise
    /// check the focused task off, exactly as clicking its circle would.
    private func submit(_ item: TodoItem, at index: Int, parse: ScheduleParse?) {
        if let parse {
            scheduleTask(item, at: index, parse: parse)
        } else {
            toggleComplete(item, at: index)
        }
    }

    /// Hold the row for a beat showing where the task went, then move it out of
    /// today and put the caret back to work — into the row that slid up, or the
    /// new last row when the scheduled one was at the bottom. The UI stays open.
    private func scheduleTask(_ item: TodoItem, at index: Int, parse: ScheduleParse) {
        focused = nil
        scheduledConfirmation[item.persistentModelID] = parse.confirmationLabel
        Task {
            try? await Task.sleep(for: .seconds(0.9))
            scheduledConfirmation[item.persistentModelID] = nil
            store.schedule(item, parse: parse)
            let last = store.items.count - 1
            guard last >= 0 else { return }
            // Defer so focus lands after the rows re-render.
            DispatchQueue.main.async { focused = min(index, last) }
        }
    }

    /// Tab moves to the next slot. On the last *regular* slot, if it's filled,
    /// spill into a fresh task and focus it so the user can keep capturing
    /// without a pause; if it's empty there's nothing to spill, so step into
    /// the scheduled section instead of stranding the caret. Tab on the very
    /// last row does nothing, as it always has.
    private func advanceOrAdd(from index: Int) {
        let isLastRegular = index == sectionStart - 1
        let filled = !store.items[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if isLastRegular, filled {
            addTask()
        } else if index < store.items.count - 1 {
            focused = index + 1
        }
    }

    /// Shift-Tab steps back to the previous slot (no-op on the first).
    private func focusPrevious(from index: Int) {
        if index > 0 { focused = index - 1 }
    }

    /// ⌥↑: the keyboard twin of dragging the grip up one slot. Focus follows
    /// the row — its new index is written in the same transaction as the
    /// reorder, so no other row ever sees its own index match `focused` and
    /// steals first responder. The row keeps its identity (the ForEach keys on
    /// the model ID), so the hosted editor, and the caret inside it, survive
    /// the move. On the first row nothing happens. Ignored mid-drag so the
    /// mouse and the keyboard never reorder the same list at once.
    private func moveTaskUp(at index: Int) {
        guard draggingID == nil else { return }
        withAnimation(.snappy(duration: 0.2)) {
            if let newIndex = store.moveTaskUp(at: index) { focused = newIndex }
        }
    }

    /// ⌥↓: same as `moveTaskUp(at:)`, one slot the other way. No-op on the last row.
    private func moveTaskDown(at index: Int) {
        guard draggingID == nil else { return }
        withAnimation(.snappy(duration: 0.2)) {
            if let newIndex = store.moveTaskDown(at: index) { focused = newIndex }
        }
    }

    /// The single toggle path, shared by Enter and the row's circle so both move
    /// focus the same way. Checking a task off steps down one row — completed
    /// rows are focusable too (they show a highlight instead of a caret), so
    /// nothing is skipped and nothing wraps. Checking off the last row, or
    /// un-checking any row, keeps focus where it is: Enter there undoes what was
    /// just done, and an un-checked row gets its caret straight back.
    private func toggleComplete(_ item: TodoItem, at index: Int) {
        let wasCompleted = item.isCompleted
        store.toggleComplete(item)
        // An empty slot refuses to complete — leave the caret alone.
        guard item.isCompleted != wasCompleted else { return }
        // Defer so focus lands after the row swaps between field and `Text` and
        // the old one has resigned first responder.
        DispatchQueue.main.async {
            if item.isCompleted, index < store.items.count - 1 {
                focused = index + 1
            } else {
                focused = index
            }
        }
    }
}

/// The "all three done" celebration. Sharp blades of grass sprout from the
/// bottom edge in a staggered wave and then sway gently, while the tasks behind
/// sit out of focus (see the `.blur` on the content). A centered message invites
/// the user to go outside. Every blade's growth and sway are computed
/// analytically from elapsed time, so one `TimelineView` drives the whole field
/// with no per-frame mutable state.
private struct CelebrationGrass: View {
    @State private var start = Date()
    @State private var blades: [GrassBlade] = []
    @State private var messageIn = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // A soft darkening at the base grounds the grass and keeps the
                // message legible against whatever's blurred behind it.
                LinearGradient(
                    colors: [.clear, .black.opacity(0.35)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        let t = timeline.date.timeIntervalSince(start)
                        for blade in blades {
                            blade.draw(in: context, at: t, canvas: size)
                        }
                    }
                }

                Text("You completed everything for today!\nGo touch some grass.")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.7), radius: 5, y: 1)
                    .padding(.horizontal, 22)
                    .offset(y: -14)
                    .opacity(messageIn ? 1 : 0)
                    .scaleEffect(messageIn ? 1 : 0.94)
            }
            // While the celebration is on screen it sits in front of the tasks
            // and swallows every click, so nothing underneath can be focused or
            // edited until the grass has cleared.
            .contentShape(Rectangle())
            .onAppear {
                start = Date()
                blades = GrassBlade.field(in: geo.size)
                withAnimation(.easeOut(duration: 0.5).delay(0.15)) {
                    messageIn = true
                }
                // Fade the message just as the grass begins to part.
                Task {
                    try? await Task.sleep(for: .seconds(GrassBlade.exitStart))
                    withAnimation(.easeIn(duration: 0.35)) { messageIn = false }
                }
            }
        }
    }
}

/// One blade of grass, drawn as a tapered curve rooted at the bottom edge.
/// `growth` eases the blade up from nothing over its lifetime (offset by a small
/// per-blade `delay` so the field sprouts as a wave); once grown it sways with a
/// gentle sine. `depth` fakes a shallow field — nearer blades are taller,
/// wider, and brighter, and are drawn last so they sit in front.
private struct GrassBlade {
    let baseX: CGFloat        // fraction of width, 0...1
    let height: CGFloat       // full height in points
    let width: CGFloat        // base width in points
    let bend: CGFloat         // resting horizontal tip offset
    let tint: Color
    let delay: Double
    let swayAmplitude: CGFloat
    let swaySpeed: Double
    let swayPhase: Double

    private static let growDuration = 1.2
    private static let bladeCount = 110
    static let maxEntryDelay = 0.6
    /// Seconds into the celebration when the blades begin parting to the sides.
    static let exitStart = 3.7
    /// Spread of the parting wave across the field, and each blade's slide time.
    static let exitStagger = 0.3
    static let exitSlide = 0.55

    private static let palette: [Color] = [
        Color(red: 0.16, green: 0.46, blue: 0.18),
        Color(red: 0.22, green: 0.55, blue: 0.22),
        Color(red: 0.30, green: 0.64, blue: 0.26),
        Color(red: 0.40, green: 0.72, blue: 0.30),
        Color(red: 0.50, green: 0.80, blue: 0.36),
    ]

    static func field(in canvas: CGSize) -> [GrassBlade] {
        guard canvas.width > 0, canvas.height > 0 else { return [] }

        var blades: [GrassBlade] = (0 ..< bladeCount).map { _ in
            // Nearer blades (depth → 1) are taller, fuller, and lit brighter.
            let depth = Double.random(in: 0 ... 1)
            let height = canvas.height * (0.20 + 0.42 * depth) * .random(in: 0.85 ... 1.15)
            let shade = palette[min(palette.count - 1, Int(depth * Double(palette.count)))]
            return GrassBlade(
                baseX: .random(in: -0.02 ... 1.02),
                height: height,
                width: 5 + 7 * depth,
                bend: .random(in: -26 ... 26) * (0.5 + 0.5 * depth),
                tint: shade,
                delay: .random(in: 0 ... maxEntryDelay),
                swayAmplitude: .random(in: 4 ... 11),
                swaySpeed: .random(in: 0.7 ... 1.4),
                swayPhase: .random(in: 0 ... 2 * .pi)
            )
        }
        // Draw far blades first so the brighter, taller foreground overlaps them.
        blades.sort { $0.height < $1.height }
        return blades
    }

    func draw(in context: GraphicsContext, at t: TimeInterval, canvas: CGSize) {
        let local = max(0, t - delay)
        let raw = min(local / Self.growDuration, 1)
        // Ease-out cubic: shoots up, then settles.
        let growth = 1 - pow(1 - raw, 3)
        guard growth > 0 else { return }

        let baseY = canvas.height
        let bx = baseX * canvas.width
        let h = height * growth
        let half = width / 2

        // Sway scales with how grown (and therefore how tall) the blade is.
        let sway = CGFloat(sin(t * swaySpeed + swayPhase)) * swayAmplitude * growth
        let tipX = bx + bend * growth + sway
        let tipY = baseY - h

        var path = Path()
        path.move(to: CGPoint(x: bx - half, y: baseY))
        path.addQuadCurve(
            to: CGPoint(x: tipX, y: tipY),
            control: CGPoint(x: bx - half + (tipX - bx) * 0.5, y: baseY - h * 0.6)
        )
        path.addQuadCurve(
            to: CGPoint(x: bx + half, y: baseY),
            control: CGPoint(x: bx + half + (tipX - bx) * 0.5, y: baseY - h * 0.5)
        )
        path.closeSubpath()

        // Darker at the root, blade tint toward the tip, for a touch of volume.
        let shading = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [tint.opacity(0.65), tint]),
            startPoint: CGPoint(x: bx, y: baseY),
            endPoint: CGPoint(x: tipX, y: tipY)
        )

        // Exit: each blade parts toward its nearest side and accelerates clean
        // off-screen. The wave runs in reverse of the entry — blades that
        // sprouted last (longest entry delay) are the first to leave.
        let exitDelay = (1 - delay / Self.maxEntryDelay) * Self.exitStagger
        let exitT = t - Self.exitStart - exitDelay
        guard exitT > 0 else {
            context.fill(path, with: shading)
            return
        }
        let p = min(exitT / Self.exitSlide, 1)
        let eased = p * p
        let direction: CGFloat = bx < canvas.width / 2 ? -1 : 1
        let clearance = (direction < 0 ? bx : canvas.width - bx) + width
        var c = context
        c.translateBy(x: direction * clearance * 1.1 * eased, y: 0)
        c.fill(path, with: shading)
    }
}

private struct TodoRow: View {
    @Bindable var item: TodoItem
    let index: Int
    let store: SignalStore
    let placeholder: String
    /// Non-nil while the post-Enter "Scheduled for…" beat is showing; the row
    /// is frozen (no field, no checkbox) until it leaves today.
    let confirmationLabel: String?
    @Binding var focused: Int?
    /// Whether this row is the one being dragged to a new slot.
    let isDragging: Bool
    let onSubmit: (ScheduleParse?) -> Void
    /// Check the task off, or un-check it — the parent owns both the store
    /// mutation and where focus lands afterwards.
    let onToggle: () -> Void
    let onEscape: () -> Void
    let onDelete: () -> Void
    let onTab: () -> Void
    let onBacktab: () -> Void
    /// The arrow-key versions of the two above: same move, but they tell the
    /// list which edge of the next row the caret should land on.
    let onMoveDown: () -> Void
    let onMoveUp: () -> Void
    /// Which edge of this row focus is arriving at.
    let rowEntry: RowEntry
    /// Called once this row has taken focus, so the entry edge resets.
    let onFocusLanded: () -> Void
    /// Backspace pressed while the field is already empty.
    let onEmptyBackspace: () -> Void
    /// ⌥↑ / ⌥↓: move this row one slot up or down (VS Code's "Move Line").
    let onReorderUp: () -> Void
    let onReorderDown: () -> Void
    /// Cumulative vertical distance dragged from where the grip was grabbed.
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: () -> Void

    @State private var hovering = false
    /// Live parse of the field's trailing date phrase — tints the ↵ hint green
    /// when Enter would schedule instead of just advancing.
    @State private var parse: ScheduleParse?

    /// Minimum height for the text area, so a one-line row never shifts
    /// vertically when the field is swapped for a `Text` on completion. Long
    /// text wraps and the area grows past this, up to `RowTextLayout.maxLines`,
    /// beyond which it scrolls inside the row instead.
    static let textRowHeight: CGFloat = 20
    /// Minimum height for the whole row — what a single-line row measures, and
    /// the unit the scroll cap is expressed in (`maxVisibleRows` of these plus
    /// spacing). A row with wrapped text is taller — at most three lines' worth
    /// — and reports its real height back to the list.
    static let rowHeight: CGFloat = 22
    /// Shared box for every completion control, medal or plain, so the task
    /// text starts at the same x on all rows — the bare symbol's natural width
    /// differs from the medal's composed one.
    private static let checkboxSize: CGFloat = 20
    /// Width of the strip on the row's leading edge that hosts the drag grip.
    /// It's real layout — the list is shifted left by the same amount so the
    /// task text still lines up with the header — because an overlay hanging
    /// outside the row would be clipped away by the scrolling viewport.
    static let handleGutterWidth: CGFloat = 16

    private var isEmpty: Bool {
        item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether this row wears the focus wash — only completed rows, which have
    /// no caret of their own to show where the keyboard is.
    private var isHighlighted: Bool {
        focused == index && item.isCompleted && confirmationLabel == nil
    }

    /// The top three slots are the "signal" — they wear a podium medal. Rows
    /// the schedule delivered sit in their own section below and never do:
    /// the medals belong to what the user chose for today.
    private var isSignalSlot: Bool {
        !item.isScheduled && index < SignalStore.defaultTaskCount
    }

    /// Completing a row reveals what it earned, exactly as the plain rows
    /// reveal their check: the top three show their podium number instead.
    private var completionSymbol: String {
        guard item.isCompleted else { return "circle" }
        return isSignalSlot ? "\(index + 1).circle.fill" : "checkmark.circle.fill"
    }

    private var completionColor: Color {
        if isSignalSlot {
            return item.isCompleted ? medalColor : medalColor.opacity(medalRestOpacity)
        }
        return item.isCompleted ? .green : .white.opacity(isEmpty ? 0.2 : 0.45)
    }

    var body: some View {
        // Top-aligned: a wrapped row grows downwards, so the checkbox, the ↵
        // hint and the grip stay level with the task's *first* line rather
        // than drifting to the middle of the block of text.
        HStack(alignment: .top, spacing: 0) {
            dragHandle

            HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: completionSymbol)
                    .font(.system(size: 18))
                    .foregroundStyle(completionColor)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: Self.checkboxSize, height: Self.checkboxSize)
                    // Also covers a reorder moving the row onto, off, or along
                    // the podium — the symbol swaps rather than snapping.
                    .animation(.snappy(duration: 0.2), value: completionSymbol)
            }
            .buttonStyle(.plain)
            .disabled(confirmationLabel != nil || (!item.isCompleted && isEmpty))

            // A live TextField doesn't render `.strikethrough` on macOS, so once an
            // item is completed (and no longer editable) we show a Text instead.
            Group {
                if let confirmationLabel {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 12, weight: .semibold))
                        Text(confirmationLabel)
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundStyle(Color.green)
                } else if item.isCompleted {
                    Text(item.text.isEmpty ? " " : item.text)
                        .strikethrough(true, color: .white.opacity(0.6))
                        .foregroundStyle(.white.opacity(0.5))
                        .font(.system(size: 15, weight: .medium))
                        // Completed rows wrap — and stop wrapping — exactly as
                        // editable ones do, so checking a long task off doesn't
                        // reflow the list.
                        .multilineTextAlignment(.leading)
                        .lineLimit(RowTextLayout.maxLines)
                        .fixedSize(horizontal: false, vertical: true)
                        // A completed row has no field to hold first responder,
                        // so this invisible responder stands in for it — the
                        // row stays part of keyboard navigation and Enter can
                        // un-complete it.
                        .background {
                            RowKeyCatcher(
                                index: index,
                                focusedIndex: $focused,
                                onSubmit: { onSubmit(nil) },
                                onEscape: onEscape,
                                onTab: onTab,
                                onBacktab: onBacktab,
                                onReorderUp: onReorderUp,
                                onReorderDown: onReorderDown
                            )
                        }
                } else {
                    TaskTextEditor(
                        text: $item.text,
                        placeholder: placeholder,
                        index: index,
                        focusedIndex: $focused,
                        onSubmit: onSubmit,
                        onParseChange: { parse = $0 },
                        onEscape: onEscape,
                        onTab: onTab,
                        onBacktab: onBacktab,
                        onMoveDown: onMoveDown,
                        onMoveUp: onMoveUp,
                        rowEntry: rowEntry,
                        onFocusLanded: onFocusLanded,
                        onEmptyBackspace: onEmptyBackspace,
                        onReorderUp: onReorderUp,
                        onReorderDown: onReorderDown
                    )
                }
            }
            .frame(minHeight: Self.textRowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Trailing gutter, always reserved so the text width never jumps:
            // delete on hover, otherwise the ↵ confirm hint while editing —
            // green when Enter would schedule the task to another day.
            ZStack {
                if hovering, store.canDelete(item), confirmationLabel == nil {
                    Button(action: onDelete) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Delete task")
                } else if focused == index, confirmationLabel == nil {
                    Image(systemName: "return")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(parse != nil ? Color.green : Color.white.opacity(0.35))
                }
            }
            // As tall as one line of text, so the hint sits beside the first
            // line of a wrapped row rather than centred against the block.
            .frame(width: 16, height: Self.textRowHeight)
            }
            // A completed row shows no caret, so focus is carried by a faint
            // wash behind the row instead. The negative padding lets it breathe
            // past the content without taking any layout of its own.
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.white.opacity(isHighlighted ? 0.06 : 0))
                    .padding(.horizontal, -6)
            }
            .animation(.snappy(duration: 0.15), value: isHighlighted)
            // Makes the content as tall as the grip beside it, so top-aligning
            // the two leaves a single-line row looking exactly as centred as
            // it did when every row was pinned to `rowHeight`.
            .padding(.vertical, (Self.rowHeight - Self.textRowHeight) / 2)
        }
        .frame(minHeight: Self.rowHeight)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.2), value: item.isCompleted)
        .animation(.snappy(duration: 0.2), value: confirmationLabel)
        // Hover deliberately has no animation: the grip and the delete button
        // are pointer affordances, so they have to land the instant the row is
        // under the cursor rather than fading in behind it.
    }

    /// Grip in the leading gutter, shown on hover; dragging it reorders the
    /// list. The view itself is always mounted and hit-testable — only its
    /// colour changes — so neither the pointer leaving the row nor the state
    /// change can tear down an in-flight gesture.
    private var dragHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(handleOpacity))
            .frame(width: Self.handleGutterWidth, height: Self.rowHeight)
            .contentShape(Rectangle())
            // Global space: the row moves as it's dragged, so a translation
            // measured locally would feed back into its own measurement.
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { onDragChanged($0.translation.height) }
                    .onEnded { _ in onDragEnded() }
            )
            .disabled(confirmationLabel != nil)
            .help("Drag to reorder (⌥↑ / ⌥↓)")
    }

    private var handleOpacity: Double {
        if isDragging { return 0.7 }
        return hovering && confirmationLabel == nil ? 0.35 : 0
    }

    /// Podium colours for the top three slots. Saturated enough to carry the
    /// medal read against the plain white rows on a black card.
    private static let medalColors: [Color] = [
        Color(red: 1.00, green: 0.80, blue: 0.22),  // gold
        // Cool enough to read as silver rather than as the plain white ring
        // the untiered rows already use.
        Color(red: 0.76, green: 0.86, blue: 1.00),  // silver
        Color(red: 0.96, green: 0.56, blue: 0.24),  // bronze
    ]

    private var medalColor: Color {
        Self.medalColors[min(index, Self.medalColors.count - 1)]
    }

    /// Held back at rest so the podium reads as "these three matter" without
    /// competing with the task text; an unfilled slot dims further still.
    private var medalRestOpacity: Double {
        isEmpty ? 0.45 : 0.85
    }

}

/// Reports how much of the enclosing ScrollView's content hangs below its
/// viewport. Sits invisibly in the scroll content and watches the backing
/// `NSClipView` directly — the notch panel's hosting setup makes SwiftUI
/// coordinate-space queries (`.global`, `.named`) report zero frames, so
/// GeometryReader-based offset tracking doesn't work here.
///
/// Strictly read-only. Writing scroll offsets from this side loses: the
/// SwiftUI ScrollView re-asserts its own remembered offset on every render,
/// and the clip view additionally quantizes origins to device pixels, so an
/// AppKit-set offset either gets reverted or starts a set/realign loop.
private struct ScrollOverflowReporter: NSViewRepresentable {
    let onChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> TrackerView {
        let view = TrackerView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: TrackerView, context: Context) {
        view.onChange = onChange
        // Row count changes resize the document view without moving the clip
        // view's bounds, so re-report on every SwiftUI update as well — and
        // defer, because the new row isn't laid out yet at this point.
        DispatchQueue.main.async { view.report() }
    }

    final class TrackerView: NSView {
        var onChange: ((CGFloat) -> Void)?
        private var observers: [NSObjectProtocol] = []
        private weak var clipView: NSClipView?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attach()
        }

        private func attach() {
            var candidate: NSView? = superview
            while candidate != nil, !(candidate is NSClipView) { candidate = candidate?.superview }
            guard let clip = candidate as? NSClipView, clip !== clipView else { return }
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers.removeAll()
            clipView = clip
            clip.postsBoundsChangedNotifications = true
            observers.append(NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
            ) { [weak self] _ in self?.report() })
            if let doc = clip.documentView {
                doc.postsFrameChangedNotifications = true
                observers.append(NotificationCenter.default.addObserver(
                    forName: NSView.frameDidChangeNotification, object: doc, queue: .main
                ) { [weak self] _ in self?.report() })
            }
            DispatchQueue.main.async { self.report() }
        }

        func report() {
            guard let clip = clipView, let doc = clip.documentView else { return }
            let overflow = doc.isFlipped
                ? doc.frame.height - clip.bounds.maxY
                : clip.bounds.minY
            onChange?(overflow)
        }

        deinit {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
        }
    }
}

/// An invisible responder that stands in for the text field on a completed row.
/// Completing a task swaps its field for a `Text` (a live NSTextField can't draw
/// the strikethrough), which would otherwise drop the row out of the responder
/// chain: focus couldn't land on it, so arrows and Tab skipped it and Enter had
/// no way to un-complete it. This takes first responder on exactly the same
/// terms the field does and maps the same keys onto the same callbacks.
private extension NSEvent {
    /// Option held on its own. Arrow keys always carry `.function` and
    /// `.numericPad`, so only the four real modifiers are compared — and
    /// ⇧⌥↑ (extend selection) is deliberately left to AppKit.
    var isOptionOnly: Bool {
        modifierFlags.intersection([.command, .control, .option, .shift]) == .option
    }
}

private struct RowKeyCatcher: NSViewRepresentable {
    let index: Int
    @Binding var focusedIndex: Int?
    let onSubmit: () -> Void
    let onEscape: () -> Void
    let onTab: () -> Void
    let onBacktab: () -> Void
    let onReorderUp: () -> Void
    let onReorderDown: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        apply(to: view)
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        apply(to: view)
        view.focusIfWanted()
    }

    private func apply(to view: CatcherView) {
        view.wantsFocus = focusedIndex == index
        view.onSubmit = onSubmit
        view.onEscape = onEscape
        view.onTab = onTab
        view.onBacktab = onBacktab
        view.onReorderUp = onReorderUp
        view.onReorderDown = onReorderDown
    }

    final class CatcherView: NSView {
        var wantsFocus = false
        var onSubmit: (() -> Void)?
        var onEscape: (() -> Void)?
        var onTab: (() -> Void)?
        var onBacktab: (() -> Void)?
        var onReorderUp: (() -> Void)?
        var onReorderDown: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        // The row is built the moment the task is completed, before it's in a
        // window — so claim focus here too, not only from `updateNSView`.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            focusIfWanted()
        }

        func focusIfWanted() {
            guard wantsFocus, let window, window.firstResponder !== self else { return }
            window.makeFirstResponder(self)
        }

        override func keyDown(with event: NSEvent) {
            switch Int(event.keyCode) {
            case 36, 76:  // Return, keypad Enter
                onSubmit?()
            case 53:  // Escape
                onEscape?()
            case 48:  // Tab
                event.modifierFlags.contains(.shift) ? onBacktab?() : onTab?()
            // ⌥↓ / ⌥↑ reorder instead of navigating — matched first so the
            // plain-arrow cases below stay Option-free.
            case 125 where event.isOptionOnly:
                onReorderDown?()
            case 126 where event.isOptionOnly:
                onReorderUp?()
            case 125:  // Down
                onTab?()
            case 126:  // Up
                onBacktab?()
            default:
                // Swallowed rather than passed up: a completed row has nothing
                // to type into, and forwarding would just beep. Backspace
                // included — deleting a finished task stays on its × button.
                break
            }
        }
    }
}

/// A borderless, word-wrapping task editor backed by AppKit: an `NSTextView`
/// inside a short `NSScrollView`.
///
/// It wraps rather than scrolling sideways. A scrollable single-line field
/// slides its content horizontally to keep the caret in view, which on focus
/// (the caret lands at the end) dragged the leading edge of a long task out of
/// alignment with the rows above and below it — issue #9. Wrapping keeps every
/// row's text starting at the same x and lets the row grow downwards instead.
///
/// It only grows so far: at `RowTextLayout.maxLines` the row stops and the text
/// scrolls *vertically* inside it, so one rambling task can't take the panel
/// over. That's what the scroll view is for, and it's why the arrow keys walk
/// the row's own lines before they hand focus to another task.
///
/// This used to be an `NSTextField`, which draws its text two ways: the cell
/// draws it when the row is idle, and a shared field editor draws it while the
/// row is being typed into. The two don't agree — measured on this font, the
/// cell lays lines out 19pt apart and starts the first one 3pt higher than the
/// editor does, and the editor's clip view carries a 3pt horizontal offset of
/// its own — so a focused row's text sat a few points up and to the right of
/// where the same row drew it unfocused. A single centering fudge could hide
/// that on a one-line row; across three lines, where the 1pt-per-line drift
/// compounds, nothing can. A text view draws both states itself, so the two
/// can't disagree. Its container inset matches the inset the cell used to draw
/// at, so no row's text moved sideways in the swap.
///
/// `TodoItem.text` stays one logical line: the extra lines are layout only, and
/// the Coordinator swallows every key and paste that would insert a real break.
private struct TaskTextEditor: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let index: Int
    @Binding var focusedIndex: Int?
    /// Called with the trailing date phrase parsed at Enter time — non-nil
    /// means "schedule this task" rather than the plain confirm-and-advance.
    let onSubmit: (ScheduleParse?) -> Void
    /// Fires whenever the live parse of the text changes, so the row can tint
    /// its ↵ hint while the phrase itself is highlighted in the text.
    let onParseChange: (ScheduleParse?) -> Void
    let onEscape: () -> Void
    let onTab: () -> Void
    let onBacktab: () -> Void
    /// The arrow-key versions of the two above, used once the caret has run out
    /// of lines to walk in this row.
    let onMoveDown: () -> Void
    let onMoveUp: () -> Void
    /// Which edge of the row focus is arriving at, and the acknowledgement that
    /// it has been used.
    let rowEntry: RowEntry
    let onFocusLanded: () -> Void
    /// Backspace pressed while the row is already empty.
    let onEmptyBackspace: () -> Void
    /// ⌥↑ / ⌥↓: move this row one slot up or down.
    let onReorderUp: () -> Void
    let onReorderDown: () -> Void

    fileprivate static let font = NSFont.systemFont(ofSize: 15, weight: .medium)
    /// The inset `NSTextFieldCell` used to draw its text at. Matching it kept
    /// every row's text at the same x through the swap to a text view, and in
    /// line with the header above the list.
    fileprivate static let textInset = NSSize(width: 2, height: 0)

    func makeNSView(context: Context) -> RowScrollView {
        let textView = RowTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.allowsUndo = true
        textView.focusRingType = .none
        textView.font = Self.font
        textView.textColor = .white
        textView.insertionPointColor = .white
        // A task is plain text: nothing here may quietly rewrite what's typed.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        // Free to grow taller than the viewport; the scroll view takes care of
        // the rest. The padding goes on the inset instead, where it also
        // positions the placeholder.
        textView.textContainerInset = Self.textInset
        textView.textContainer?.lineFragmentPadding = 0
        // The container's width is set explicitly from the viewport (see
        // `RowScrollView.layout`) rather than tracked off the text view. A
        // tracked container is zero-width until SwiftUI first lays the row
        // out, and a zero-width container doesn't wrap: anything that forces
        // layout before then — placing the caret, scrolling to it — strings the
        // whole task onto one endless line, and nothing brings the wrap back.
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]

        textView.onFocusChange = { [weak textView] focused in
            guard let textView else { return }
            context.coordinator.focusChanged(to: focused, in: textView)
        }

        let scroll = RowScrollView(frame: .zero)
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ scroll: RowScrollView, context: Context) {
        context.coordinator.parent = self
        let textView = scroll.rowTextView
        if textView.string != text {
            // Replacing the string drops the attributes with it, so the row has
            // to be painted again — with its date phrase highlighted if the
            // keyboard is here, plain white if it isn't.
            textView.string = text
            context.coordinator.restyle(textView)
        }
        textView.placeholder = placeholder
        // Drive AppKit's first responder from SwiftUI's focus state.
        textView.wantsFocus = focusedIndex == index
        textView.entersOnFirstLine = rowEntry == .fromAbove
        if textView.focusIfWanted() {
            // Deferred: this runs inside a SwiftUI view update.
            let onFocusLanded = self.onFocusLanded
            DispatchQueue.main.async(execute: onFocusLanded)
        }
    }

    /// Measures wrapped text the way the row draws it — same font, same
    /// container, no padding — so the height SwiftUI is given is the height the
    /// text actually takes.
    private static let measuring: (storage: NSTextStorage, layout: NSLayoutManager, container: NSTextContainer) = {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        return (storage, layout, container)
    }()

    private static func measuredHeight(of string: String, width: CGFloat) -> CGFloat {
        let (storage, layout, container) = measuring
        container.size = NSSize(width: max(width, 0), height: .greatestFiniteMagnitude)
        storage.setAttributedString(
            NSAttributedString(string: string.isEmpty ? " " : string, attributes: [.font: font])
        )
        layout.ensureLayout(for: container)
        return layout.usedRect(for: container).height
    }

    /// One line of the row's text, so the three-line cap lands exactly on a
    /// line boundary instead of slicing a fourth line in half.
    static let lineHeight: CGFloat = measuredHeight(of: "Ag", width: .greatestFiniteMagnitude)

    /// The height the text needs once wrapped into `width`, never more than
    /// `RowTextLayout.maxLines` lines' worth — past that the row holds still and
    /// the text scrolls inside it.
    ///
    /// Rounded up so the row height lands on whole points: a fractional height
    /// puts the hosted view at a fractional window Y, where the text shimmers
    /// off the pixel grid (same reasoning as `listOverflows`).
    static func wrappedHeight(of string: String, width: CGFloat) -> CGFloat {
        let measured = measuredHeight(of: string, width: width - textInset.width * 2)
        return ceil(RowTextLayout.cappedHeight(measured: measured, lineHeight: lineHeight))
    }

    /// Report the wrapped height to SwiftUI so the row — and the card behind
    /// it — grow with the text, up to the cap. The placeholder is measured when
    /// the row is empty so an empty row is never shorter than the text it's
    /// inviting.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: RowScrollView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        let content = text.isEmpty ? placeholder : text
        let height = Self.wrappedHeight(of: content, width: width)
        return CGSize(width: width, height: max(height, TodoRow.textRowHeight))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// The row's viewport: at most `RowTextLayout.maxLines` tall, with the text
    /// view free to be taller inside it.
    final class RowScrollView: NSScrollView {
        var rowTextView: RowTextView { documentView as! RowTextView }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            drawsBackground = false
            contentView.drawsBackground = false
            borderType = .noBorder
            focusRingType = .none
            hasVerticalScroller = false
            hasHorizontalScroller = false
            // No rubber-banding: a row is two or three lines tall, and a bounce
            // inside something that small reads as a glitch.
            verticalScrollElasticity = .none
            horizontalScrollElasticity = .none
            automaticallyAdjustsContentInsets = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layout() {
            super.layout()
            let viewport = contentView.bounds.size
            // The text wraps into the width the row actually got. Set before
            // anything can ask the layout manager a question, and only once the
            // row has a width — a zero-width container doesn't wrap at all.
            if viewport.width > 0 {
                let inset = rowTextView.textContainerInset.width
                let width = max(viewport.width - inset * 2, 1)
                if rowTextView.textContainer?.containerSize.width != width {
                    rowTextView.textContainer?.containerSize =
                        NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
                }
            }
            // The text view fills the viewport even when the task is one short
            // line, so a click anywhere in the row lands in the text rather
            // than falling through to the card behind it.
            rowTextView.minSize = NSSize(width: 0, height: viewport.height)
            if rowTextView.frame.width != viewport.width || rowTextView.frame.height < viewport.height {
                rowTextView.setFrameSize(
                    NSSize(width: viewport.width, height: max(rowTextView.frame.height, viewport.height))
                )
            }
        }

        /// A row only claims the wheel when it actually has lines hidden past
        /// its cap; otherwise the gesture belongs to the task list behind it.
        override func scrollWheel(with event: NSEvent) {
            guard let documentView, documentView.frame.height > contentView.bounds.height else {
                nextResponder?.scrollWheel(with: event)
                return
            }
            super.scrollWheel(with: event)
        }
    }

    /// Claims first responder whenever SwiftUI says this row has focus, and
    /// draws the placeholder itself — a text view has none of its own.
    final class RowTextView: NSTextView {
        var wantsFocus = false
        /// Whether focus is arriving from the row above, in which case the
        /// caret lands on this row's first line rather than after all of it.
        var entersOnFirstLine = false
        /// Told when the keyboard arrives or leaves, so the row can take the
        /// focused index and drop its date highlight on the way out.
        var onFocusChange: ((Bool) -> Void)?

        var placeholder = "" {
            didSet { if placeholder != oldValue, string.isEmpty { needsDisplay = true } }
        }

        /// Matters when the view is *created* already focused — which is what
        /// un-completing a task does, replacing the row's `Text` with a fresh
        /// editor: at `updateNSView` time it isn't in a window yet, so without
        /// this the row would render focused while nothing held the keyboard.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            focusIfWanted()
        }

        /// Returns whether it actually claimed the keyboard just now.
        @discardableResult
        func focusIfWanted() -> Bool {
            guard wantsFocus, let window, window.firstResponder !== self else { return false }
            window.makeFirstResponder(self)
            // Focusing drops the caret at the end of the line it arrived on
            // rather than teeing the task up to be overwritten, and scrolls a
            // row that's hit its cap to wherever that landed.
            setSelectedRange(NSRange(location: caretLocationOnEntry(), length: 0))
            scrollRangeToVisible(selectedRange())
            return true
        }

        /// The end of the text, or — when the caret came down from the row
        /// above — the end of the row's first visual line. On a single-line row
        /// those are the same character.
        private func caretLocationOnEntry() -> Int {
            let end = (string as NSString).length
            guard entersOnFirstLine, end > 0,
                  let layout = layoutManager, let container = textContainer,
                  // Never ask the layout manager anything before the row has a
                  // width to wrap into — see `makeNSView`.
                  container.containerSize.width > 1 else { return end }
            layout.ensureLayout(for: container)
            guard layout.numberOfGlyphs > 0 else { return end }
            var fragment = NSRange(location: 0, length: 0)
            _ = layout.lineFragmentRect(forGlyphAt: 0, effectiveRange: &fragment)
            let characters = layout.characterRange(forGlyphRange: fragment, actualGlyphRange: nil)
            var location = min(NSMaxRange(characters), end)
            // A caret sitting exactly on a soft wrap can belong to either side
            // of it; step back one character so it's unambiguously on the line
            // it was meant to land on.
            if location > 0, location < end {
                let glyph = layout.glyphIndexForCharacter(at: location)
                let landed = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
                let first = layout.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil).minY
                if landed > first + RowTextLayout.CaretLine.tolerance { location -= 1 }
            }
            return location
        }

        override func becomeFirstResponder() -> Bool {
            let became = super.becomeFirstResponder()
            if became { onFocusChange?(true) }
            return became
        }

        override func resignFirstResponder() -> Bool {
            let resigned = super.resignFirstResponder()
            if resigned {
                updateInsertionPointStateAndRestartTimer(false)
                needsDisplay = true
                onFocusChange?(false)
            }
            return resigned
        }

        /// Only the row that actually holds the keyboard shows a caret.
        ///
        /// Each row owns a text view of its own, and a text view that has been
        /// asked to give up the keyboard still repaints its last insertion
        /// point whenever it redraws — which left every idle task in the list
        /// wearing a caret. (A text field never had this: its editor is one
        /// shared view that simply leaves the row it came from.) Gated on the
        /// draw itself, since that's the path a redraw takes.
        override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
            guard window?.firstResponder === self else { return }
            super.drawInsertionPoint(in: rect, color: color, turnedOn: flag)
        }

        override func updateInsertionPointStateAndRestartTimer(_ restartFlag: Bool) {
            super.updateInsertionPointStateAndRestartTimer(
                restartFlag && window?.firstResponder === self
            )
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            guard string.isEmpty, !placeholder.isEmpty else { return }
            // Drawn at the text's own origin, so the prompt and the first thing
            // typed over it start at exactly the same pixel.
            NSAttributedString(
                string: placeholder,
                attributes: [
                    .foregroundColor: NSColor.white.withAlphaComponent(0.25),
                    .font: TaskTextEditor.font,
                ]
            ).draw(at: NSPoint(x: textContainerInset.width, y: textContainerInset.height))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TaskTextEditor
        private var lastParse: ScheduleParse?
        init(_ parent: TaskTextEditor) { self.parent = parent }

        func textDidChange(_ note: Notification) {
            guard let textView = note.object as? RowTextView else { return }
            // A task is one logical line even though it may be drawn on
            // several: a pasted paragraph collapses to spaces rather than
            // smuggling real breaks into the model.
            let flattened = Self.flattened(textView.string)
            if flattened != textView.string {
                textView.string = flattened
                textView.setSelectedRange(NSRange(location: (flattened as NSString).length, length: 0))
            }
            parent.text = flattened
            // The placeholder appears and disappears with the text.
            textView.needsDisplay = true
            refreshParse(for: textView)
            // The row may have just gained a line; if it's already at the cap,
            // follow the caret rather than typing off the bottom edge.
            textView.scrollRangeToVisible(textView.selectedRange())
        }

        /// Every kind of line break — CRLF, CR, LF, and the Unicode line and
        /// paragraph separators — folded into single spaces.
        private static func flattened(_ string: String) -> String {
            guard string.contains(where: \.isNewline) else { return string }
            let joined = string.replacingOccurrences(of: "\r\n", with: " ")
            return String(joined.map { $0.isNewline ? " " : $0 })
        }

        /// Called by the text view as the keyboard arrives and leaves.
        func focusChanged(to focused: Bool, in textView: RowTextView) {
            if focused {
                if parent.focusedIndex != parent.index { parent.focusedIndex = parent.index }
                // Re-highlight a phrase typed earlier but never confirmed.
                refreshParse(for: textView)
            } else {
                // The highlight is an editing affordance: an unfocused row goes
                // back to plain white, exactly as it read before it was touched.
                clearHighlight(in: textView)
                // And a row that was scrolled to follow the caret rewinds to
                // the top, so an idle list reads as every task's opening words
                // rather than wherever each was last being edited.
                textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
            }
        }

        /// Re-parse the trailing date phrase and paint it. Nothing leaks into
        /// the model — the attributes live on the view's storage — and resetting
        /// the full range every keystroke is also what clears the highlight once
        /// the phrase stops matching.
        func refreshParse(for textView: NSTextView) {
            let parse = NaturalDateParser.parse(textView.string)
            if parse != lastParse {
                lastParse = parse
                // Defer: focus can change inside a SwiftUI view update.
                let onParseChange = parent.onParseChange
                DispatchQueue.main.async { onParseChange(parse) }
            }

            guard let storage = textView.textStorage else { return }
            let full = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.removeAttribute(.backgroundColor, range: full)
            storage.addAttribute(.foregroundColor, value: NSColor.white, range: full)
            storage.addAttribute(.font, value: TaskTextEditor.font, range: full)
            if let parse, NSMaxRange(parse.matchedRange) <= storage.length {
                storage.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: parse.matchedRange)
                storage.addAttribute(
                    .backgroundColor,
                    value: NSColor.systemGreen.withAlphaComponent(0.22),
                    range: parse.matchedRange
                )
            }
            storage.endEditing()
            // Don't let fresh keystrokes inherit the highlight's attributes.
            textView.typingAttributes = [.font: TaskTextEditor.font, .foregroundColor: NSColor.white]
        }

        /// Paints the row for the state it's in: the date phrase highlighted
        /// while the keyboard is here, plain white once it leaves.
        func restyle(_ textView: RowTextView) {
            if textView.window?.firstResponder === textView {
                refreshParse(for: textView)
            } else {
                clearHighlight(in: textView)
            }
        }

        private func clearHighlight(in textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let full = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.removeAttribute(.backgroundColor, range: full)
            storage.addAttribute(.foregroundColor, value: NSColor.white, range: full)
            storage.addAttribute(.font, value: TaskTextEditor.font, range: full)
            storage.endEditing()
            lastParse = nil
        }

        /// Which of the row's wrapped lines the caret is on, read off the text
        /// view's own layout. Nil when there's nothing laid out to be on — an
        /// empty row — where the caret is trivially on the first line and the
        /// last at once.
        private func caretLine(in textView: NSTextView) -> RowTextLayout.CaretLine? {
            guard let layout = textView.layoutManager, let container = textView.textContainer else { return nil }
            layout.ensureLayout(for: container)
            let glyphs = layout.numberOfGlyphs
            guard glyphs > 0 else { return nil }
            // A caret past the last character belongs to the line that
            // character is on: the text holds no real breaks, so there is never
            // an empty line below it for the caret to have fallen onto.
            let length = (textView.string as NSString).length
            let character = min(max(textView.selectedRange().location, 0), max(length - 1, 0))
            let glyph = min(layout.glyphIndexForCharacter(at: character), glyphs - 1)
            func top(ofGlyphAt index: Int) -> CGFloat {
                layout.lineFragmentRect(forGlyphAt: index, effectiveRange: nil).minY
            }
            return RowTextLayout.CaretLine(
                top: top(ofGlyphAt: glyph),
                firstLineTop: top(ofGlyphAt: 0),
                lastLineTop: top(ofGlyphAt: glyphs - 1)
            )
        }

        /// Key code of the event currently being interpreted when it's ⌥↑ (126)
        /// or ⌥↓ (125) with Option alone; nil for anything else. The selectors
        /// below are also reachable without Option (⌃B/⌃F, and ⌥arrow variants
        /// with other modifiers), so the event itself is the only reliable
        /// way to tell the reorder chord apart from ordinary caret motion.
        private var optionArrowKeyCode: UInt16? {
            guard let event = NSApp.currentEvent, event.type == .keyDown, event.isOptionOnly,
                  event.keyCode == 125 || event.keyCode == 126 else { return nil }
            return event.keyCode
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            // ⌥↑ / ⌥↓ arrive as a two-selector sequence per key press —
            // `moveBackward:` then `moveToBeginningOfParagraph:` for up, and
            // the forward pair for down (see StandardKeyBinding.dict). Act on
            // the second and swallow the first, otherwise the caret steps
            // sideways before the row moves.
            case #selector(NSResponder.moveBackward(_:)), #selector(NSResponder.moveForward(_:)):
                return optionArrowKeyCode != nil
            case #selector(NSResponder.moveToBeginningOfParagraph(_:)):
                guard optionArrowKeyCode == 126 else { return false }
                parent.onReorderUp()
                // Consumed even on the first row: a boundary is a silent
                // no-op, not a beep and not a caret jump.
                return true
            case #selector(NSResponder.moveToEndOfParagraph(_:)):
                guard optionArrowKeyCode == 125 else { return false }
                parent.onReorderDown()
                return true
            // Parsed fresh at submit time so Enter always acts on what's
            // visible.
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit(NaturalDateParser.parse(textView.string))
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onEscape()
                return true
            case #selector(NSResponder.insertTab(_:)):
                parent.onTab()
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                parent.onBacktab()
                return true
            // Option-Return, Control-Return and the line-break key all ask for
            // a hard break. The row wraps on its own and the task is one
            // logical line, so these do nothing at all.
            case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)),
                 #selector(NSResponder.insertLineBreak(_:)),
                 #selector(NSResponder.insertParagraphSeparator(_:)):
                return true
            // Arrows walk the list like Tab/Shift-Tab — Down on the last
            // filled row spills into a fresh task. A row whose text wrapped is
            // walked line by line first, though: only from its top line does Up
            // leave for the task above, and only from its bottom line does Down
            // leave for the one below. Returning false hands the move back to
            // the text view, which walks the caret and scrolls the row to it.
            case #selector(NSResponder.moveUp(_:)):
                guard caretLine(in: textView)?.isOnFirstLine ?? true else { return false }
                parent.onMoveUp()
                return true
            case #selector(NSResponder.moveDown(_:)):
                guard caretLine(in: textView)?.isOnLastLine ?? true else { return false }
                parent.onMoveDown()
                return true
            case #selector(NSResponder.deleteBackward(_:)):
                // Backspace on an already-empty task deletes the slot; with
                // text present (even at caret 0) AppKit handles it normally.
                if textView.string.isEmpty {
                    parent.onEmptyBackspace()
                    return true
                }
                return false
            default:
                return false
            }
        }
    }
}
