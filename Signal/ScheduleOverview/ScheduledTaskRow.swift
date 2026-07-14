import SwiftUI

/// One schedule entry: recurring badge, task text, and hover-revealed
/// edit/delete controls. Shared by the "Every day" section and the day rows.
struct ScheduledTaskRow: View {
    let task: ScheduledTask
    let model: ScheduleOverviewModel

    @State private var hovering = false
    @State private var editing = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: task.isRecurring ? "repeat" : "calendar")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(task.isRecurring ? Color.green : Color.white.opacity(0.4))

            Text(task.text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)

            if let label = recurrenceLabel {
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.green.opacity(0.15)))
            }

            Spacer(minLength: 0)

            // Reserved so the text width never jumps when the buttons appear.
            HStack(spacing: 6) {
                if hovering {
                    Button {
                        editing = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .help("Edit schedule")

                    Button {
                        model.delete(task)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .help("Delete schedule")
                }
            }
            .buttonStyle(.plain)
            .frame(width: 38, height: 16, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: hovering)
        .contextMenu {
            Button("Edit Schedule…") { editing = true }
            Divider()
            Button("Delete", role: .destructive) { model.delete(task) }
        }
        .popover(isPresented: $editing, arrowEdge: .bottom) {
            ScheduleEditPopover(task: task) { edit in
                model.apply(edit, to: task)
            }
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
