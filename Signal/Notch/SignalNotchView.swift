import SwiftUI
import AppKit

/// The entire primary UI: three fixed to-do slots shown inside the notch.
struct SignalNotchView: View {
    let store: SignalStore
    let controller: NotchController

    @State private var focused: Int?
    @State private var placeholders: [String] = SignalNotchView.randomPlaceholders()
    @State private var celebrating = false

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
        // Depth-of-field: when the day is done, the tasks recede out of focus so
        // the sharp grass in front becomes the subject.
        .blur(radius: celebrating ? 7 : 0)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.black)
        )
        .overlay {
            if celebrating {
                CelebrationGrass()
                    .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(.easeInOut(duration: 0.6), value: celebrating)
        .onChange(of: store.celebrationTrigger) { _, _ in celebrate() }
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

    /// Grow the grass (and blur the tasks) for a few seconds, then let it fade out.
    private func celebrate() {
        celebrating = true
        Task {
            try? await Task.sleep(for: .seconds(4.5))
            celebrating = false
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

/// The "all three done" celebration. Sharp blades of grass sprout from the
/// bottom edge in a staggered wave and then sway gently, while the tasks behind
/// sit out of focus (see the `.blur` on the content). A centered message invites
/// the user to go outside. Every blade's growth and sway are computed
/// analytically from elapsed time, so one `TimelineView` drives the whole field
/// with no per-frame mutable state.
private struct CelebrationGrass: View {
    @State private var start = Date()
    @State private var blades: [GrassBlade] = []
    @State private var messageIn = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // A soft darkening at the base grounds the grass and keeps the
                // message legible against whatever's blurred behind it.
                LinearGradient(
                    colors: [.clear, .black.opacity(0.35)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        let t = timeline.date.timeIntervalSince(start)
                        for blade in blades {
                            blade.draw(in: context, at: t, canvas: size)
                        }
                    }
                }

                Text("You completed everything for today!\nGo touch some grass.")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.7), radius: 5, y: 1)
                    .padding(.horizontal, 22)
                    .offset(y: -14)
                    .opacity(messageIn ? 1 : 0)
                    .scaleEffect(messageIn ? 1 : 0.94)
            }
            .onAppear {
                start = Date()
                blades = GrassBlade.field(in: geo.size)
                withAnimation(.easeOut(duration: 0.5).delay(0.15)) {
                    messageIn = true
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// One blade of grass, drawn as a tapered curve rooted at the bottom edge.
/// `growth` eases the blade up from nothing over its lifetime (offset by a small
/// per-blade `delay` so the field sprouts as a wave); once grown it sways with a
/// gentle sine. `depth` fakes a shallow field — nearer blades are taller,
/// wider, and brighter, and are drawn last so they sit in front.
private struct GrassBlade {
    let baseX: CGFloat        // fraction of width, 0...1
    let height: CGFloat       // full height in points
    let width: CGFloat        // base width in points
    let bend: CGFloat         // resting horizontal tip offset
    let tint: Color
    let delay: Double
    let swayAmplitude: CGFloat
    let swaySpeed: Double
    let swayPhase: Double

    private static let growDuration = 1.2
    private static let bladeCount = 110

    private static let palette: [Color] = [
        Color(red: 0.16, green: 0.46, blue: 0.18),
        Color(red: 0.22, green: 0.55, blue: 0.22),
        Color(red: 0.30, green: 0.64, blue: 0.26),
        Color(red: 0.40, green: 0.72, blue: 0.30),
        Color(red: 0.50, green: 0.80, blue: 0.36),
    ]

    static func field(in canvas: CGSize) -> [GrassBlade] {
        guard canvas.width > 0, canvas.height > 0 else { return [] }

        var blades: [GrassBlade] = (0 ..< bladeCount).map { _ in
            // Nearer blades (depth → 1) are taller, fuller, and lit brighter.
            let depth = Double.random(in: 0 ... 1)
            let height = canvas.height * (0.20 + 0.42 * depth) * .random(in: 0.85 ... 1.15)
            let shade = palette[min(palette.count - 1, Int(depth * Double(palette.count)))]
            return GrassBlade(
                baseX: .random(in: -0.02 ... 1.02),
                height: height,
                width: 5 + 7 * depth,
                bend: .random(in: -26 ... 26) * (0.5 + 0.5 * depth),
                tint: shade,
                delay: .random(in: 0 ... 0.6),
                swayAmplitude: .random(in: 4 ... 11),
                swaySpeed: .random(in: 0.7 ... 1.4),
                swayPhase: .random(in: 0 ... 2 * .pi)
            )
        }
        // Draw far blades first so the brighter, taller foreground overlaps them.
        blades.sort { $0.height < $1.height }
        return blades
    }

    func draw(in context: GraphicsContext, at t: TimeInterval, canvas: CGSize) {
        let local = max(0, t - delay)
        let raw = min(local / Self.growDuration, 1)
        // Ease-out cubic: shoots up, then settles.
        let growth = 1 - pow(1 - raw, 3)
        guard growth > 0 else { return }

        let baseY = canvas.height
        let bx = baseX * canvas.width
        let h = height * growth
        let half = width / 2

        // Sway scales with how grown (and therefore how tall) the blade is.
        let sway = CGFloat(sin(t * swaySpeed + swayPhase)) * swayAmplitude * growth
        let tipX = bx + bend * growth + sway
        let tipY = baseY - h

        var path = Path()
        path.move(to: CGPoint(x: bx - half, y: baseY))
        path.addQuadCurve(
            to: CGPoint(x: tipX, y: tipY),
            control: CGPoint(x: bx - half + (tipX - bx) * 0.5, y: baseY - h * 0.6)
        )
        path.addQuadCurve(
            to: CGPoint(x: bx + half, y: baseY),
            control: CGPoint(x: bx + half + (tipX - bx) * 0.5, y: baseY - h * 0.5)
        )
        path.closeSubpath()

        // Darker at the root, blade tint toward the tip, for a touch of volume.
        let shading = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [tint.opacity(0.65), tint]),
            startPoint: CGPoint(x: bx, y: baseY),
            endPoint: CGPoint(x: tipX, y: tipY)
        )
        context.fill(path, with: shading)
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
