import SwiftUI

/// A read-only row for one of a *past* day's to-dos, showing its completion
/// state. History is never edited — today and the days ahead get the panel's
/// own editable row instead.
///
/// Drawn at the overview's compact metrics, like the editable rows of today
/// and the days ahead, so every day of the week lines up.
struct DayTaskRow: View {
    let item: TodoItem

    var body: some View {
        HStack(alignment: .top, spacing: TaskRowMetrics.compact.spacing) {
            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(TaskRowMetrics.compact.iconFont)
                .foregroundStyle(item.isCompleted ? Color.green : Color.white.opacity(0.35))
                .frame(width: TaskRowMetrics.compact.iconBox, height: TaskRowMetrics.compact.textRowHeight)

            Text(item.text)
                .font(TaskRowMetrics.compact.textFont)
                .strikethrough(item.isCompleted, color: .white.opacity(0.5))
                .foregroundStyle(item.isCompleted ? .white.opacity(0.5) : .white)
                .multilineTextAlignment(.leading)
                .lineLimit(RowTextLayout.maxLines)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: TaskRowMetrics.compact.textRowHeight, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.vertical, TaskRowMetrics.compact.verticalPadding)
        .frame(minHeight: TaskRowMetrics.compact.rowHeight)
    }
}
