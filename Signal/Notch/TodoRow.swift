import SwiftUI
import SwiftData

struct TodoRow: View {
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
    var onDragChanged: (CGFloat) -> Void = { _ in }
    var onDragEnded: () -> Void = {}
    /// Whether the leading gutter hosts a drag grip. The schedule overview
    /// doesn't reorder, so its rows drop the gutter entirely.
    var showsDragHandle = true
    /// Which podium slot this row occupies, when that isn't its own index —
    /// the overview renders today's list inside a day row, so the medal has to
    /// follow the task's place in `store.items` rather than its place on screen.
    var podiumIndex: Int?
    /// The day this row sits on, when it isn't today — forwarded to the editor
    /// so date phrases resolve against that day.
    var parseAnchor: Date?

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

    /// Where the row sits in today's list, which is what the podium is drawn
    /// from. `index` stays the row's place in the focus order.
    private var slot: Int { podiumIndex ?? index }

    /// The top three slots are the "signal" — they wear a podium medal. Rows
    /// the schedule delivered sit in their own section below and never do:
    /// the medals belong to what the user chose for today.
    private var isSignalSlot: Bool {
        !item.isScheduled && slot < SignalStore.defaultTaskCount
    }

    /// Completing a row reveals what it earned, exactly as the plain rows
    /// reveal their check: the top three show their podium number instead.
    private var completionSymbol: String {
        guard item.isCompleted else { return "circle" }
        return isSignalSlot ? "\(slot + 1).circle.fill" : "checkmark.circle.fill"
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
            if showsDragHandle { dragHandle }

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
                    ScheduleConfirmationLabel(text: confirmationLabel)
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
                        parseAnchor: parseAnchor,
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

            TaskRowTrailingGutter(
                showsDelete: hovering && store.canDelete(item) && confirmationLabel == nil,
                isFocused: focused == index && confirmationLabel == nil,
                willSchedule: parse != nil,
                onDelete: onDelete
            )
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
        Self.medalColors[min(max(slot, 0), Self.medalColors.count - 1)]
    }

    /// Held back at rest so the podium reads as "these three matter" without
    /// competing with the task text; an unfilled slot dims further still.
    private var medalRestOpacity: Double {
        isEmpty ? 0.45 : 0.85
    }

}

/// The strip at the trailing edge of an editable task row. Always the same
/// width so the text beside it never reflows: the delete button while the
/// pointer is on the row, otherwise the ↵ hint while the keyboard is — green
/// when Enter would schedule the task rather than confirm it.
struct TaskRowTrailingGutter: View {
    let showsDelete: Bool
    let isFocused: Bool
    let willSchedule: Bool
    var deleteHelp = "Delete task"
    let onDelete: () -> Void

    var body: some View {
        ZStack {
            if showsDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(deleteHelp)
            } else if isFocused {
                Image(systemName: "return")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(willSchedule ? Color.green : Color.white.opacity(0.35))
            }
        }
        // As tall as one line of text, so the hint sits beside the first
        // line of a wrapped row rather than centred against the block.
        .frame(width: 16, height: TodoRow.textRowHeight)
    }
}

/// The brief "Scheduled for…" beat a row shows after Enter, before it leaves
/// for the day it was scheduled to.
struct ScheduleConfirmationLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(.system(size: 15, weight: .medium))
        }
        .foregroundStyle(Color.green)
    }
}
