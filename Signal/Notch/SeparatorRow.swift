import SwiftUI

/// A separator in the task list: a hairline dropped between two tasks to group
/// them. To the list it is a row like any other — it has a slot, a measured
/// height, and it drags to a new one — but it holds no text, never takes the
/// keyboard and answers no keys: it is added, moved and removed with the mouse
/// alone.
struct SeparatorRow: View {
    /// Whether this row is the one being dragged to a new slot.
    let isDragging: Bool
    let onDelete: () -> Void
    /// Cumulative vertical distance dragged from where the row was grabbed.
    var onDragChanged: (CGFloat) -> Void = { _ in }
    var onDragEnded: () -> Void = {}

    @State private var hovering = false

    /// The row's whole height. Odd, so the 1pt line sits on whole points.
    static let height: CGFloat = 11

    var body: some View {
        HStack(spacing: TaskRowMetrics.panel.spacing) {
            HStack(spacing: 0) {
                // The same grip a task shows, in the same gutter.
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(handleOpacity))
                    .frame(width: TodoRow.handleGutterWidth, height: Self.height)

                Rectangle()
                    .fill(.white.opacity(isDragging ? 0.45 : hovering ? 0.3 : 0.18))
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)
            }

            // Always mounted, like the grip: only its colour changes, so the
            // line beside it never changes length under the pointer.
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(hovering && !isDragging ? 0.5 : 0))
                    .frame(width: 16, height: Self.height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("Remove separator")
            .accessibilityLabel("Remove separator")
        }
        .frame(height: Self.height)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        // The whole row is the handle — there is nothing else on it to click.
        // Global space for the same reason as a task's grip: the row moves as
        // it's dragged, so a local translation would feed back into itself.
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { onDragChanged($0.translation.height) }
                .onEnded { _ in onDragEnded() }
        )
        .help("Drag to move the separator")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Separator")
    }

    private var handleOpacity: Double {
        if isDragging { return 0.7 }
        return hovering ? 0.35 : 0
    }
}

/// The gap between two tasks, as a hover target: under the pointer it previews
/// the line a click would leave there. Always mounted and hit-testable — only
/// its colour changes — so it answers the instant the pointer arrives.
struct SeparatorInsertionGap: View {
    let height: CGFloat
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Image(systemName: "plus")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: TodoRow.handleGutterWidth)

                Line()
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)
            }
            .foregroundStyle(.white.opacity(hovering ? 0.35 : 0))
            .frame(height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
        .help("Add a separator")
        .accessibilityLabel("Add separator")
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }
}
