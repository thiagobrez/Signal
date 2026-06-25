import SwiftUI
import AppKit

/// The entire primary UI: three fixed to-do slots shown inside the notch.
struct SignalNotchView: View {
    let store: SignalStore
    let controller: NotchController

    @State private var focused: Int?
    @State private var placeholders: [String] = SignalNotchView.randomPlaceholders()

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

    private static func randomPlaceholders() -> [String] {
        Array(placeholderPool.shuffled().prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            ForEach(Array(store.items.enumerated()), id: \.element.persistentModelID) { pair in
                TodoRow(
                    item: pair.element,
                    index: pair.offset,
                    store: store,
                    placeholder: placeholders[pair.offset % placeholders.count],
                    focused: $focused,
                    onSubmit: { advanceOrDismiss(from: pair.offset) },
                    onEscape: { controller.hide() }
                )
            }
        }
        .padding(16)
        .frame(width: 340)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.black)
        )
        .onKeyPress(.escape) {
            controller.hide()
            return .handled
        }
        .onChange(of: controller.presentationRequest) { _, _ in
            placeholders = SignalNotchView.randomPlaceholders()
        }
        .onChange(of: controller.focusRequest) { _, _ in focusInitial() }
        .onAppear { focusInitial() }
    }

    private var header: some View {
        HStack {
            Text(todayLabel)
                .font(.system(size: 10, weight: .bold))
                .tracking(2.5)
            Spacer()
            Text("\(store.completedCount)/3")
                .font(.system(size: 10, weight: .semibold))
                .tracking(2.5)
                .monospacedDigit()
        }
        .foregroundStyle(.white.opacity(0.4))
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

    private func advanceOrDismiss(from index: Int) {
        if index < store.items.count - 1 {
            focused = index + 1
        } else {
            store.save()
            controller.hide()
        }
    }
}

private struct TodoRow: View {
    @Bindable var item: TodoItem
    let index: Int
    let store: SignalStore
    let placeholder: String
    @Binding var focused: Int?
    let onSubmit: () -> Void
    let onEscape: () -> Void

    /// Fixed height for the text area so the row never shifts vertically when the
    /// field is swapped for a `Text` on completion. The vertical jump *within*
    /// the field on focus is handled by `VerticallyCenteredTextFieldCell`.
    private static let textRowHeight: CGFloat = 20

    private var isEmpty: Bool {
        item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                store.toggleComplete(item)
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(item.isCompleted ? Color.green : Color.white.opacity(isEmpty ? 0.2 : 0.45))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .disabled(!item.isCompleted && isEmpty)

            // A live TextField doesn't render `.strikethrough` on macOS, so once an
            // item is completed (and no longer editable) we show a Text instead.
            Group {
                if item.isCompleted {
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
                        onEscape: onEscape
                    )
                }
            }
            .frame(height: Self.textRowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(.snappy(duration: 0.2), value: item.isCompleted)
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
    let onSubmit: () -> Void
    let onEscape: () -> Void

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
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PlainTextField
        init(_ parent: PlainTextField) { self.parent = parent }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidBeginEditing(_ note: Notification) {
            if parent.focusedIndex != parent.index { parent.focusedIndex = parent.index }
        }

        @objc func didSubmit(_ sender: NSTextField) { parent.onSubmit() }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onEscape()
                return true
            }
            return false
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
