import SwiftUI

/// The entire primary UI: three fixed to-do slots shown inside the notch.
struct SignalNotchView: View {
    let store: SignalStore
    let controller: NotchController

    @FocusState private var focused: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            ForEach(Array(store.items.enumerated()), id: \.element.persistentModelID) { pair in
                TodoRow(
                    item: pair.element,
                    index: pair.offset,
                    store: store,
                    focused: $focused,
                    onSubmit: { advanceOrDismiss(from: pair.offset) }
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
        .onChange(of: controller.focusRequest) { _, _ in focusInitial() }
        .onAppear { focusInitial() }
    }

    private var header: some View {
        HStack {
            Text("TODAY")
                .font(.system(size: 10, weight: .bold))
                .tracking(2.5)
            Spacer()
            Text("\(store.completedCount)/3")
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(.white.opacity(0.4))
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
    @FocusState.Binding var focused: Int?
    let onSubmit: () -> Void

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
                } else {
                    TextField("Something that matters…", text: $item.text)
                        .textFieldStyle(.plain)
                        .foregroundStyle(.white)
                        .focused($focused, equals: index)
                        .submitLabel(index < 2 ? .next : .done)
                        .onSubmit(onSubmit)
                }
            }
            .font(.system(size: 15, weight: .medium))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(.snappy(duration: 0.2), value: item.isCompleted)
    }
}
