import SwiftUI

/// A read-only row for one of a *past* day's to-dos, showing its completion
/// state. History is never edited — today and the days ahead get the panel's
/// own editable row instead.
///
/// Styled to the panel's row metrics so a day of history lines up with the
/// editable days above it.
struct DayTaskRow: View {
    let item: TodoItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundStyle(item.isCompleted ? Color.green : Color.white.opacity(0.35))
                .frame(width: 20, height: 20)

            Text(item.text)
                .font(.system(size: 15, weight: .medium))
                .strikethrough(item.isCompleted, color: .white.opacity(0.5))
                .foregroundStyle(item.isCompleted ? .white.opacity(0.5) : .white)
                .multilineTextAlignment(.leading)
                .lineLimit(RowTextLayout.maxLines)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: TodoRow.textRowHeight, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.vertical, (TodoRow.rowHeight - TodoRow.textRowHeight) / 2)
        .frame(minHeight: TodoRow.rowHeight)
    }
}
