import SwiftUI
import SwiftData

/// One schedule, edited in place. Structurally the panel's `TodoRow` with the
/// completion circle swapped for the repeat/calendar icon: the same
/// `TaskTextEditor`, the same keys, the same trailing gutter.
///
/// There is no frequency popover any more. A row that already sits on the day
/// the user navigated to *is* scheduled for it, and typing a keyword at the end
/// of the text ("every monday") re-schedules it — which is the whole of what
/// the popover used to offer.
struct ScheduledTaskRow: View {
    @Bindable var task: ScheduledTask
    let index: Int
    /// The day this row is drawn on, so date phrases resolve against it. Nil in
    /// the EVERY DAY section, which belongs to no single day.
    let parseAnchor: Date?
    @Binding var focused: Int?
    let onSubmit: (ScheduleParse?) -> Void
    let onEscape: () -> Void
    let onDelete: () -> Void
    let onTab: () -> Void
    let onBacktab: () -> Void
    let onMoveDown: () -> Void
    let onMoveUp: () -> Void
    let rowEntry: RowEntry
    let onFocusLanded: () -> Void
    let onEmptyBackspace: () -> Void
    /// Non-nil while the post-Enter "Every Monday" / "Scheduled for…" beat is
    /// showing, before the row moves to where it was just sent.
    var confirmationLabel: String?
    var placeholder = "New task…"

    @State private var hovering = false
    @State private var parse: ScheduleParse?

    /// Matches the completion circle's box in `TodoRow` so the text of a
    /// schedule starts at exactly the same x as the text of a to-do.
    private static let iconSize: CGFloat = 20

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: task.isRecurring ? "repeat" : "calendar")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(task.isRecurring ? Color.green : Color.white.opacity(0.4))
                .frame(width: Self.iconSize, height: Self.iconSize)

            Group {
                if let confirmationLabel {
                    ScheduleConfirmationLabel(text: confirmationLabel)
                } else {
                    TaskTextEditor(
                        text: $task.text,
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
                        // The overview doesn't reorder.
                        onReorderUp: {},
                        onReorderDown: {}
                    )
                }
            }
            .frame(minHeight: TodoRow.textRowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)

            if let label = recurrenceLabel, confirmationLabel == nil {
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.green.opacity(0.15)))
                    .frame(height: TodoRow.textRowHeight)
                    .fixedSize()
            }

            TaskRowTrailingGutter(
                showsDelete: hovering && confirmationLabel == nil,
                isFocused: focused == index && confirmationLabel == nil,
                willSchedule: parse != nil,
                deleteHelp: task.isRecurring ? "Delete routine" : "Delete task",
                onDelete: onDelete
            )
        }
        .padding(.vertical, (TodoRow.rowHeight - TodoRow.textRowHeight) / 2)
        .frame(minHeight: TodoRow.rowHeight)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.2), value: confirmationLabel)
        .contextMenu {
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    /// "Every day" / "Every Monday" for recurring tasks; nil for one-time
    /// (their date is implied by the row they sit in).
    private var recurrenceLabel: String? {
        switch task.recurrence {
        case .daily:
            return "Every day"
        case .weekly(let weekday):
            let symbols = Calendar.current.standaloneWeekdaySymbols
            guard (1 ... symbols.count).contains(weekday) else { return "Weekly" }
            return "Every \(symbols[weekday - 1])"
        case nil:
            return nil
        }
    }
}
