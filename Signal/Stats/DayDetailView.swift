import SwiftUI

/// A single day's tasks with their completion state.
struct DayDetailView: View {
    let day: DayLog
    let isToday: Bool

    var body: some View {
        let tasks = StatsCalculator.nonEmptyItems(of: day)
        let completed = tasks.filter(\.isCompleted).count

        VStack(alignment: .leading, spacing: 0) {
            header(completed: completed, total: tasks.count)

            Divider()

            if tasks.isEmpty {
                ContentUnavailableView(
                    "No tasks",
                    systemImage: "circle.dashed",
                    description: Text(isToday ? "Nothing added yet today." : "No tasks were added on this day.")
                )
            } else {
                List(tasks, id: \.persistentModelID) { item in
                    taskRow(item)
                }
            }
        }
    }

    private func header(completed: Int, total: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(day.date.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                    .font(.title2.weight(.semibold))
                Text("\(completed) of \(total) completed")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if total > 0, completed == total {
                Label("Full day", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.green)
            }
        }
        .padding(20)
    }

    private func taskRow(_ item: TodoItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(item.isCompleted ? Color.green : Color.secondary)

            Text(item.text)

            Spacer()

            trailingLabel(item)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func trailingLabel(_ item: TodoItem) -> some View {
        if item.isCompleted {
            if let completedAt = item.completedAt {
                Text(completedAt.formatted(date: .omitted, time: .shortened))
            }
        } else {
            Text(isToday ? "In progress" : "Not completed")
        }
    }
}
