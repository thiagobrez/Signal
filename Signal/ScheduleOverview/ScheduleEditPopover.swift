import SwiftUI

/// Structured schedule editor: One-time (date picker), Daily, or Weekly
/// (weekday picker) — the same shapes the natural-language parser can produce.
struct ScheduleEditPopover: View {
    private enum Kind: String, CaseIterable {
        case oneTime = "One-time"
        case daily = "Daily"
        case weekly = "Weekly"
    }

    let task: ScheduledTask
    let onSave: (ScheduleEdit) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var kind: Kind
    @State private var date: Date
    @State private var weekday: Int

    /// Display order Monday-first; tags stay Calendar values (1 = Sunday).
    private static let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]

    init(task: ScheduledTask, onSave: @escaping (ScheduleEdit) -> Void) {
        self.task = task
        self.onSave = onSave
        switch task.recurrence {
        case .daily:
            _kind = State(initialValue: .daily)
            _weekday = State(initialValue: 2)
        case .weekly(let day):
            _kind = State(initialValue: .weekly)
            _weekday = State(initialValue: day)
        case nil:
            _kind = State(initialValue: .oneTime)
            _weekday = State(initialValue: 2)
        }
        // Seed the date picker with the task's next appearance either way.
        _date = State(initialValue: max(task.dueDate, Calendar.current.startOfDay(for: Date())))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(task.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Picker("", selection: $kind) {
                ForEach(Kind.allCases, id: \.self) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch kind {
            case .oneTime:
                DatePicker(
                    "On",
                    selection: $date,
                    in: Calendar.current.startOfDay(for: Date())...,
                    displayedComponents: .date
                )
                .datePickerStyle(.field)
            case .daily:
                Text("Repeats every day, starting tomorrow")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .weekly:
                Picker("On", selection: $weekday) {
                    ForEach(Self.weekdayOrder, id: \.self) { day in
                        Text(Calendar.current.standaloneWeekdaySymbols[day - 1]).tag(day)
                    }
                }
                .pickerStyle(.menu)
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") {
                    onSave(edit)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 260)
    }

    private var edit: ScheduleEdit {
        switch kind {
        case .oneTime: return .oneTime(date: date)
        case .daily: return .daily
        case .weekly: return .weekly(weekday: weekday)
        }
    }
}
