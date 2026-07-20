import SwiftUI
import AppKit
import SwiftData
#if APPSTORE
import StoreKit
#endif

/// The entire primary UI: the day's to-do slots shown inside the notch. Starts
/// at three but grows as the user adds tasks.
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
    /// Slots the dragged row has already been moved by, so the live offset can
    /// be measured against its new home rather than where the drag started.
    @State private var dragSlotShift = 0

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

    /// Fixed height of the scrolling viewport: ten rows plus the gaps between.
    private var listCapHeight: CGFloat {
        CGFloat(Self.maxVisibleRows) * TodoRow.rowHeight
            + CGFloat(Self.maxVisibleRows - 1) * Self.rowSpacing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            header

            // The card stays intrinsically sized (and grows smoothly) while the
            // list is short; past `maxVisibleRows` the rows scroll inside a
            // fixed viewport so the card never outgrows the screen.
            if store.items.count > Self.maxVisibleRows {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: Self.rowSpacing) {
                            taskRows
                        }
                    }
                    .frame(height: listCapHeight)
                    // The viewport has to cover the grip gutter too, otherwise
                    // it clips the grips away.
                    .padding(.leading, -TodoRow.handleGutterWidth)
                    // Keep the focused row visible — covers both adding a row
                    // beyond the fold (focus lands on the new row) and
                    // reopening with the caret on a row that's scrolled away.
                    .onChange(of: focused) { _, newValue in
                        guard let newValue, store.items.indices.contains(newValue) else { return }
                        withAnimation(.snappy(duration: 0.2)) {
                            proxy.scrollTo(store.items[newValue].persistentModelID)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: Self.rowSpacing) {
                    taskRows
                }
                .padding(.leading, -TodoRow.handleGutterWidth)
            }

            if controller.mode == .interactive {
                footer
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

    /// One row per task. Rendered directly in the card while the list is
    /// short, or inside the capped ScrollView once it grows past
    /// `maxVisibleRows`.
    private var taskRows: some View {
        ForEach(Array(store.items.enumerated()), id: \.element.persistentModelID) { pair in
            let isDragging = draggingID == pair.element.persistentModelID
            TodoRow(
                item: pair.element,
                index: pair.offset,
                store: store,
                placeholder: placeholders[pair.offset % placeholders.count],
                confirmationLabel: scheduledConfirmation[pair.element.persistentModelID],
                focused: $focused,
                isDragging: isDragging,
                onSubmit: { parse in submit(pair.element, at: pair.offset, parse: parse) },
                onComplete: { focusNextEditable(after: pair.offset) },
                onEscape: { controller.hide() },
                onDelete: { deleteTask(pair.element) },
                onTab: { advanceOrAdd(from: pair.offset) },
                onBacktab: { focusPrevious(from: pair.offset) },
                onDragChanged: { translation in drag(pair.element, by: translation) },
                onDragEnded: endDrag
            )
            // The dragged row follows the cursor and rides above its
            // neighbours as they shuffle out of the way.
            .offset(y: isDragging ? dragTranslation : 0)
            .zIndex(isDragging ? 1 : 0)
        }
    }

    /// Vertical distance from one row to the next.
    private static var rowStride: CGFloat { TodoRow.rowHeight + rowSpacing }

    /// Tracks the cursor during a reorder: the row is offset to follow the
    /// drag, and each time it has travelled half a slot it swaps with the
    /// neighbour it's passing, so the list reorders live under the cursor.
    private func drag(_ item: TodoItem, by translation: CGFloat) {
        if draggingID != item.persistentModelID {
            draggingID = item.persistentModelID
            dragSlotShift = 0
            // Indices are about to shift, so the focused index no longer maps
            // cleanly — same reasoning as delete.
            focused = nil
        }

        var offset = translation - CGFloat(dragSlotShift) * Self.rowStride
        while abs(offset) > Self.rowStride / 2 {
            guard let from = store.items.firstIndex(where: { $0.persistentModelID == item.persistentModelID })
            else { break }
            let to = offset > 0 ? from + 1 : from - 1
            guard store.items.indices.contains(to) else {
                // Already at an end: hold the row at the boundary rather than
                // letting it drift off the list.
                offset = offset > 0 ? Self.rowStride / 2 : -Self.rowStride / 2
                break
            }
            withAnimation(.snappy(duration: 0.2)) {
                store.moveTask(from: from, to: to)
            }
            dragSlotShift += offset > 0 ? 1 : -1
            offset = translation - CGFloat(dragSlotShift) * Self.rowStride
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
        dragSlotShift = 0
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

    /// The "add a task" affordance.
    @ViewBuilder
    private var footer: some View {
        if store.canAddTask {
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
    }

    private var todayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: Date())
    }

    private func focusInitial() {
        guard controller.mode == .interactive else {
            focused = nil
            return
        }
        // Defer so focus lands after the panel becomes key.
        DispatchQueue.main.async {
            let firstEmpty = store.items.firstIndex {
                $0.text.trimmingCharacters(in: .whitespaces).isEmpty
            }
            focused = firstEmpty ?? 0
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

    private func advanceOrDismiss(from index: Int) {
        if index < store.items.count - 1 {
            focused = index + 1
        } else {
            store.save()
            controller.hide()
        }
    }

    /// Enter: when the task ends in a date phrase, schedule it away; otherwise
    /// confirm it and advance exactly as before.
    private func submit(_ item: TodoItem, at index: Int, parse: ScheduleParse?) {
        if let parse {
            scheduleTask(item, at: index, parse: parse)
        } else {
            advanceOrDismiss(from: index)
        }
    }

    /// Hold the row for a beat showing where the task went, then move it out of
    /// today and put the caret back to work — into the row that slid up, or
    /// dismiss when the scheduled row was the last one (mirroring Enter).
    private func scheduleTask(_ item: TodoItem, at index: Int, parse: ScheduleParse) {
        focused = nil
        scheduledConfirmation[item.persistentModelID] = parse.confirmationLabel
        Task {
            try? await Task.sleep(for: .seconds(0.9))
            scheduledConfirmation[item.persistentModelID] = nil
            store.schedule(item, parse: parse)
            if index < store.items.count {
                // Defer so focus lands after the rows re-render.
                DispatchQueue.main.async { focused = index }
            } else {
                controller.hide()
            }
        }
    }

    /// Tab moves to the next slot. On the last slot, if it's filled, spill into a
    /// fresh task and focus it so the user can keep capturing without a pause.
    private func advanceOrAdd(from index: Int) {
        if index < store.items.count - 1 {
            focused = index + 1
        } else if !store.items[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            addTask()
        }
    }

    /// Shift-Tab steps back to the previous slot (no-op on the first).
    private func focusPrevious(from index: Int) {
        if index > 0 { focused = index - 1 }
    }

    /// After a task is checked off, move focus to the next still-editable slot —
    /// searching forward and wrapping — so the user can keep capturing the next
    /// thing without reaching for the mouse. If every slot is done (the day is
    /// complete) focus is dropped so nothing fights the celebration.
    private func focusNextEditable(after index: Int) {
        // Defer so focus lands after the checked row collapses to a `Text` and
        // resigns first responder.
        DispatchQueue.main.async {
            let count = store.items.count
            guard count > 0 else { return }
            for offset in 1 ... count {
                let i = (index + offset) % count
                if !store.items[i].isCompleted {
                    focused = i
                    return
                }
            }
            focused = nil
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
    let onComplete: () -> Void
    let onEscape: () -> Void
    let onDelete: () -> Void
    let onTab: () -> Void
    let onBacktab: () -> Void
    /// Cumulative vertical distance dragged from where the grip was grabbed.
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: () -> Void

    @State private var hovering = false
    /// Live parse of the field's trailing date phrase — tints the ↵ hint green
    /// when Enter would schedule instead of just advancing.
    @State private var parse: ScheduleParse?

    /// Fixed height for the text area so the row never shifts vertically when the
    /// field is swapped for a `Text` on completion. The vertical jump *within*
    /// the field on focus is handled by `VerticallyCenteredTextFieldCell`.
    private static let textRowHeight: CGFloat = 20
    /// Fixed height for the whole row, so the capped scroll viewport can be
    /// sized exactly (`maxVisibleRows` rows plus spacing).
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

    /// The top three slots are the "signal" — they wear a podium medal.
    private var isSignalSlot: Bool {
        index < SignalStore.defaultTaskCount
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
        HStack(spacing: 0) {
            dragHandle

            HStack(spacing: 12) {
            Button {
                let wasCompleted = item.isCompleted
                store.toggleComplete(item)
                // Only advance on the actual completion transition — not when
                // un-checking, and not when an empty slot refuses to complete.
                if !wasCompleted, item.isCompleted { onComplete() }
            } label: {
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
                } else {
                    PlainTextField(
                        text: $item.text,
                        placeholder: placeholder,
                        index: index,
                        focusedIndex: $focused,
                        onSubmit: onSubmit,
                        onParseChange: { parse = $0 },
                        onEscape: onEscape,
                        onTab: onTab,
                        onBacktab: onBacktab
                    )
                }
            }
            .frame(height: Self.textRowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Trailing gutter, always reserved so the text width never jumps:
            // delete on hover, otherwise the ↵ confirm hint while editing —
            // green when Enter would schedule the task to another day.
            ZStack {
                if hovering, store.canDeleteTask, confirmationLabel == nil {
                    Button(action: onDelete) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Delete task")
                } else if focused == index, !item.isCompleted, confirmationLabel == nil {
                    Image(systemName: "return")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(parse != nil ? Color.green : Color.white.opacity(0.35))
                }
            }
            .frame(width: 16, height: 16)
            }
        }
        .frame(height: Self.rowHeight)
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
            .help("Drag to reorder")
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

/// A borderless single-line text field backed by AppKit. SwiftUI's `TextField`
/// nudges its text up a pixel when it becomes first responder because the cell
/// vertically centers text in display mode but the field editor draws it from a
/// different origin while editing. `VerticallyCenteredTextFieldCell` forces both
/// modes to center identically, so the text stays put on focus.
private struct PlainTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let index: Int
    @Binding var focusedIndex: Int?
    /// Called with the trailing date phrase parsed at Enter time — non-nil
    /// means "schedule this task" rather than the plain confirm-and-advance.
    let onSubmit: (ScheduleParse?) -> Void
    /// Fires whenever the live parse of the text changes, so the row can tint
    /// its ↵ hint while the phrase itself is highlighted in the field.
    let onParseChange: (ScheduleParse?) -> Void
    let onEscape: () -> Void
    let onTab: () -> Void
    let onBacktab: () -> Void

    private static let font = NSFont.systemFont(ofSize: 15, weight: .medium)

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        let cell = VerticallyCenteredTextFieldCell(textCell: "")
        cell.isEditable = true
        cell.isSelectable = true
        cell.isBordered = false
        cell.drawsBackground = false
        cell.usesSingleLineMode = true
        cell.lineBreakMode = .byTruncatingTail
        cell.wraps = false
        cell.isScrollable = true
        field.cell = cell
        field.focusRingType = .none
        field.font = Self.font
        field.textColor = .white
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.didSubmit(_:))
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.25),
                .font: Self.font,
            ]
        )
        // Drive AppKit's first responder from SwiftUI's focus state.
        if focusedIndex == index, field.window != nil, field.currentEditor() == nil {
            field.window?.makeFirstResponder(field)
            // Taking first responder selects the whole string by default; collapse
            // the selection to the end so focusing just drops the caret after the
            // existing text instead of teeing it up to be overwritten.
            if let editor = field.currentEditor() {
                let end = (field.stringValue as NSString).length
                editor.selectedRange = NSRange(location: end, length: 0)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PlainTextField
        private var lastParse: ScheduleParse?
        init(_ parent: PlainTextField) { self.parent = parent }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            parent.text = field.stringValue
            refreshParse(for: field)
        }

        func controlTextDidBeginEditing(_ note: Notification) {
            if parent.focusedIndex != parent.index { parent.focusedIndex = parent.index }
            // Re-highlight a phrase that was typed earlier but never confirmed.
            if let field = note.object as? NSTextField { refreshParse(for: field) }
        }

        // Parse fresh at submit time so Enter always acts on what's visible.
        @objc func didSubmit(_ sender: NSTextField) {
            parent.onSubmit(NaturalDateParser.parse(sender.stringValue))
        }

        /// Re-parse the trailing date phrase and paint it in the field editor.
        /// The attributes live only in the editor, so an unfocused field
        /// re-renders plain white from `stringValue` — nothing leaks into the
        /// model, and resetting the full range every keystroke is also what
        /// clears the highlight once the phrase stops matching.
        private func refreshParse(for field: NSTextField) {
            let parse = NaturalDateParser.parse(field.stringValue)
            if parse != lastParse {
                lastParse = parse
                // Defer: begin-editing can fire inside a SwiftUI view update.
                let onParseChange = parent.onParseChange
                DispatchQueue.main.async { onParseChange(parse) }
            }

            guard let editor = field.currentEditor() as? NSTextView,
                  let storage = editor.textStorage else { return }
            let full = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.removeAttribute(.backgroundColor, range: full)
            storage.addAttribute(.foregroundColor, value: NSColor.white, range: full)
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
            editor.typingAttributes = [.font: PlainTextField.font, .foregroundColor: NSColor.white]
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onEscape()
                return true
            case #selector(NSResponder.insertTab(_:)):
                parent.onTab()
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                parent.onBacktab()
                return true
            default:
                return false
            }
        }
    }
}

/// `NSTextFieldCell` that keeps text vertically centered in both display and
/// editing modes so the text doesn't shift when the field gains focus.
private final class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    private func centered(_ rect: NSRect) -> NSRect {
        let textHeight = cellSize(forBounds: rect).height
        guard textHeight < rect.height else { return rect }
        var r = rect
        r.origin.y += (rect.height - textHeight) / 2
        r.size.height = textHeight
        return r
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        super.drawingRect(forBounds: centered(rect))
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: centered(rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: centered(rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}
