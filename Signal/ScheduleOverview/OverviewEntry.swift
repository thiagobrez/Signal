import SwiftUI
import SwiftData

/// A single thing shown on a day in the overview: either an upcoming schedule
/// or one of that day's actual to-dos.
enum OverviewEntry: Identifiable {
    case scheduled(ScheduledTask)
    case todo(TodoItem)

    var id: PersistentIdentifier {
        switch self {
        case .scheduled(let task): return task.persistentModelID
        case .todo(let item): return item.persistentModelID
        }
    }
}

/// A read-only row for one of a day's real to-dos, showing its completion
/// state. Editing happens in the main Signal panel — here it's just history.
struct DayTaskRow: View {
    let item: TodoItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(item.isCompleted ? Color.green : Color.white.opacity(0.35))

            Text(item.text)
                .font(.system(size: 13, weight: .medium))
                .strikethrough(item.isCompleted, color: .white.opacity(0.5))
                .foregroundStyle(item.isCompleted ? .white.opacity(0.5) : .white)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }
}
