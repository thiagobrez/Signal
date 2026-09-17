import SwiftUI
import AppKit

extension NSEvent {
    /// Option held on its own. Arrow keys always carry `.function` and
    /// `.numericPad`, so only the four real modifiers are compared — and
    /// ⇧⌥↑ (extend selection) is deliberately left to AppKit.
    var isOptionOnly: Bool {
        modifierFlags.intersection([.command, .control, .option, .shift]) == .option
    }
}

/// An invisible responder that stands in for the text field on a completed row.
/// Completing a task swaps its field for a `Text` (a live NSTextField can't draw
/// the strikethrough), which would otherwise drop the row out of the responder
/// chain: focus couldn't land on it, so arrows and Tab skipped it and Enter had
/// no way to un-complete it. This takes first responder on exactly the same
/// terms the field does and maps the same keys onto the same callbacks.
struct RowKeyCatcher: NSViewRepresentable {
    let index: Int
    @Binding var focusedIndex: Int?
    let onSubmit: () -> Void
    let onEscape: () -> Void
    let onTab: () -> Void
    let onBacktab: () -> Void
    let onReorderUp: () -> Void
    let onReorderDown: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        apply(to: view)
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        apply(to: view)
        view.focusIfWanted()
    }

    private func apply(to view: CatcherView) {
        view.wantsFocus = focusedIndex == index
        view.onSubmit = onSubmit
        view.onEscape = onEscape
        view.onTab = onTab
        view.onBacktab = onBacktab
        view.onReorderUp = onReorderUp
        view.onReorderDown = onReorderDown
    }

    final class CatcherView: NSView {
        var wantsFocus = false
        var onSubmit: (() -> Void)?
        var onEscape: (() -> Void)?
        var onTab: (() -> Void)?
        var onBacktab: (() -> Void)?
        var onReorderUp: (() -> Void)?
        var onReorderDown: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        // The row is built the moment the task is completed, before it's in a
        // window — so claim focus here too, not only from `updateNSView`.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            focusIfWanted()
        }

        func focusIfWanted() {
            guard wantsFocus, let window, window.firstResponder !== self else { return }
            window.makeFirstResponder(self)
        }

        override func keyDown(with event: NSEvent) {
            switch Int(event.keyCode) {
            case 36, 76:  // Return, keypad Enter
                onSubmit?()
            case 53:  // Escape
                onEscape?()
            case 48:  // Tab
                event.modifierFlags.contains(.shift) ? onBacktab?() : onTab?()
            // ⌥↓ / ⌥↑ reorder instead of navigating — matched first so the
            // plain-arrow cases below stay Option-free.
            case 125 where event.isOptionOnly:
                onReorderDown?()
            case 126 where event.isOptionOnly:
                onReorderUp?()
            case 125:  // Down
                onTab?()
            case 126:  // Up
                onBacktab?()
            default:
                // Swallowed rather than passed up: a completed row has nothing
                // to type into, and forwarding would just beep. Backspace
                // included — deleting a finished task stays on its × button.
                break
            }
        }
    }
}

/// A borderless, word-wrapping task editor backed by AppKit: an `NSTextView`
/// inside a short `NSScrollView`.
///
/// It wraps rather than scrolling sideways. A scrollable single-line field
/// slides its content horizontally to keep the caret in view, which on focus
/// (the caret lands at the end) dragged the leading edge of a long task out of
/// alignment with the rows above and below it — issue #9. Wrapping keeps every
/// row's text starting at the same x and lets the row grow downwards instead.
///
/// It only grows so far: at `RowTextLayout.maxLines` the row stops and the text
/// scrolls *vertically* inside it, so one rambling task can't take the panel
/// over. That's what the scroll view is for, and it's why the arrow keys walk
/// the row's own lines before they hand focus to another task.
///
/// This used to be an `NSTextField`, which draws its text two ways: the cell
/// draws it when the row is idle, and a shared field editor draws it while the
/// row is being typed into. The two don't agree — measured on this font, the
/// cell lays lines out 19pt apart and starts the first one 3pt higher than the
/// editor does, and the editor's clip view carries a 3pt horizontal offset of
/// its own — so a focused row's text sat a few points up and to the right of
/// where the same row drew it unfocused. A single centering fudge could hide
/// that on a one-line row; across three lines, where the 1pt-per-line drift
/// compounds, nothing can. A text view draws both states itself, so the two
/// can't disagree. Its container inset matches the inset the cell used to draw
/// at, so no row's text moved sideways in the swap.
///
/// `TodoItem.text` stays one logical line: the extra lines are layout only, and
/// the Coordinator swallows every key and paste that would insert a real break.
struct TaskTextEditor: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let index: Int
    @Binding var focusedIndex: Int?
    /// Called with the trailing date phrase parsed at Enter time — non-nil
    /// means "schedule this task" rather than the plain confirm-and-advance.
    let onSubmit: (ScheduleParse?) -> Void
    /// Fires whenever the live parse of the text changes, so the row can tint
    /// its ↵ hint while the phrase itself is highlighted in the text.
    let onParseChange: (ScheduleParse?) -> Void
    /// The day this row sits on, when it isn't today: date phrases then resolve
    /// against that day rather than against now. Nil in the panel.
    var parseAnchor: Date?
    let onEscape: () -> Void
    let onTab: () -> Void
    let onBacktab: () -> Void
    /// The arrow-key versions of the two above, used once the caret has run out
    /// of lines to walk in this row.
    let onMoveDown: () -> Void
    let onMoveUp: () -> Void
    /// Which edge of the row focus is arriving at, and the acknowledgement that
    /// it has been used.
    let rowEntry: RowEntry
    let onFocusLanded: () -> Void
    /// Backspace pressed while the row is already empty.
    let onEmptyBackspace: () -> Void
    /// ⌥↑ / ⌥↓: move this row one slot up or down.
    let onReorderUp: () -> Void
    let onReorderDown: () -> Void

    static let font = NSFont.systemFont(ofSize: 15, weight: .medium)
    /// The inset `NSTextFieldCell` used to draw its text at. Matching it kept
    /// every row's text at the same x through the swap to a text view, and in
    /// line with the header above the list.
    static let textInset = NSSize(width: 2, height: 0)

    func makeNSView(context: Context) -> RowScrollView {
        let textView = RowTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.allowsUndo = true
        textView.focusRingType = .none
        textView.font = Self.font
        textView.textColor = .white
        textView.insertionPointColor = .white
        // A task is plain text: nothing here may quietly rewrite what's typed.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        // Free to grow taller than the viewport; the scroll view takes care of
        // the rest. The padding goes on the inset instead, where it also
        // positions the placeholder.
        textView.textContainerInset = Self.textInset
        textView.textContainer?.lineFragmentPadding = 0
        // The container's width is set explicitly from the viewport (see
        // `RowScrollView.layout`) rather than tracked off the text view. A
        // tracked container is zero-width until SwiftUI first lays the row
        // out, and a zero-width container doesn't wrap: anything that forces
        // layout before then — placing the caret, scrolling to it — strings the
        // whole task onto one endless line, and nothing brings the wrap back.
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]

        textView.onFocusChange = { [weak textView] focused in
            guard let textView else { return }
            context.coordinator.focusChanged(to: focused, in: textView)
        }

        let scroll = RowScrollView(frame: .zero)
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ scroll: RowScrollView, context: Context) {
        context.coordinator.parent = self
        let textView = scroll.rowTextView
        if textView.string != text {
            // Replacing the string drops the attributes with it, so the row has
            // to be painted again — with its date phrase highlighted if the
            // keyboard is here, plain white if it isn't.
            textView.string = text
            context.coordinator.restyle(textView)
        }
        textView.placeholder = placeholder
        // Drive AppKit's first responder from SwiftUI's focus state.
        textView.wantsFocus = focusedIndex == index
        textView.entersOnFirstLine = rowEntry == .fromAbove
        if textView.focusIfWanted() {
            // Deferred: this runs inside a SwiftUI view update.
            let onFocusLanded = self.onFocusLanded
            DispatchQueue.main.async(execute: onFocusLanded)
        }
    }

    /// Measures wrapped text the way the row draws it — same font, same
    /// container, no padding — so the height SwiftUI is given is the height the
    /// text actually takes.
    private static let measuring: (storage: NSTextStorage, layout: NSLayoutManager, container: NSTextContainer) = {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        return (storage, layout, container)
    }()

    private static func measuredHeight(of string: String, width: CGFloat) -> CGFloat {
        let (storage, layout, container) = measuring
        container.size = NSSize(width: max(width, 0), height: .greatestFiniteMagnitude)
        storage.setAttributedString(
            NSAttributedString(string: string.isEmpty ? " " : string, attributes: [.font: font])
        )
        layout.ensureLayout(for: container)
        return layout.usedRect(for: container).height
    }

    /// One line of the row's text, so the three-line cap lands exactly on a
    /// line boundary instead of slicing a fourth line in half.
    static let lineHeight: CGFloat = measuredHeight(of: "Ag", width: .greatestFiniteMagnitude)

    /// The height the text needs once wrapped into `width`, never more than
    /// `RowTextLayout.maxLines` lines' worth — past that the row holds still and
    /// the text scrolls inside it.
    ///
    /// Rounded up so the row height lands on whole points: a fractional height
    /// puts the hosted view at a fractional window Y, where the text shimmers
    /// off the pixel grid (same reasoning as `listOverflows`).
    static func wrappedHeight(of string: String, width: CGFloat) -> CGFloat {
        let measured = measuredHeight(of: string, width: width - textInset.width * 2)
        return ceil(RowTextLayout.cappedHeight(measured: measured, lineHeight: lineHeight))
    }

    /// Report the wrapped height to SwiftUI so the row — and the card behind
    /// it — grow with the text, up to the cap. The placeholder is measured when
    /// the row is empty so an empty row is never shorter than the text it's
    /// inviting.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: RowScrollView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        let content = text.isEmpty ? placeholder : text
        let height = Self.wrappedHeight(of: content, width: width)
        return CGSize(width: width, height: max(height, TodoRow.textRowHeight))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// The row's viewport: at most `RowTextLayout.maxLines` tall, with the text
    /// view free to be taller inside it.
    final class RowScrollView: NSScrollView {
        var rowTextView: RowTextView { documentView as! RowTextView }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            drawsBackground = false
            contentView.drawsBackground = false
            borderType = .noBorder
            focusRingType = .none
            hasVerticalScroller = false
            hasHorizontalScroller = false
            // No rubber-banding: a row is two or three lines tall, and a bounce
            // inside something that small reads as a glitch.
            verticalScrollElasticity = .none
            horizontalScrollElasticity = .none
            automaticallyAdjustsContentInsets = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layout() {
            super.layout()
            let viewport = contentView.bounds.size
            // The text wraps into the width the row actually got. Set before
            // anything can ask the layout manager a question, and only once the
            // row has a width — a zero-width container doesn't wrap at all.
            if viewport.width > 0 {
                let inset = rowTextView.textContainerInset.width
                let width = max(viewport.width - inset * 2, 1)
                if rowTextView.textContainer?.containerSize.width != width {
                    rowTextView.textContainer?.containerSize =
                        NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
                }
            }
            // The text view fills the viewport even when the task is one short
            // line, so a click anywhere in the row lands in the text rather
            // than falling through to the card behind it.
            rowTextView.minSize = NSSize(width: 0, height: viewport.height)
            if rowTextView.frame.width != viewport.width || rowTextView.frame.height < viewport.height {
                rowTextView.setFrameSize(
                    NSSize(width: viewport.width, height: max(rowTextView.frame.height, viewport.height))
                )
            }
        }

        /// A row only claims the wheel when it actually has lines hidden past
        /// its cap; otherwise the gesture belongs to the task list behind it.
        override func scrollWheel(with event: NSEvent) {
            guard let documentView, documentView.frame.height > contentView.bounds.height else {
                nextResponder?.scrollWheel(with: event)
                return
            }
            super.scrollWheel(with: event)
        }
    }

    /// Claims first responder whenever SwiftUI says this row has focus, and
    /// draws the placeholder itself — a text view has none of its own.
    final class RowTextView: NSTextView {
        var wantsFocus = false
        /// Whether focus is arriving from the row above, in which case the
        /// caret lands on this row's first line rather than after all of it.
        var entersOnFirstLine = false
        /// Told when the keyboard arrives or leaves, so the row can take the
        /// focused index and drop its date highlight on the way out.
        var onFocusChange: ((Bool) -> Void)?

        var placeholder = "" {
            didSet { if placeholder != oldValue, string.isEmpty { needsDisplay = true } }
        }

        /// Matters when the view is *created* already focused — which is what
        /// un-completing a task does, replacing the row's `Text` with a fresh
        /// editor: at `updateNSView` time it isn't in a window yet, so without
        /// this the row would render focused while nothing held the keyboard.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            focusIfWanted()
        }

        /// Returns whether it actually claimed the keyboard just now.
        @discardableResult
        func focusIfWanted() -> Bool {
            guard wantsFocus, let window, window.firstResponder !== self else { return false }
            window.makeFirstResponder(self)
            // Focusing drops the caret at the end of the line it arrived on
            // rather than teeing the task up to be overwritten, and scrolls a
            // row that's hit its cap to wherever that landed.
            setSelectedRange(NSRange(location: caretLocationOnEntry(), length: 0))
            scrollRangeToVisible(selectedRange())
            return true
        }

        /// The end of the text, or — when the caret came down from the row
        /// above — the end of the row's first visual line. On a single-line row
        /// those are the same character.
        private func caretLocationOnEntry() -> Int {
            let end = (string as NSString).length
            guard entersOnFirstLine, end > 0,
                  let layout = layoutManager, let container = textContainer,
                  // Never ask the layout manager anything before the row has a
                  // width to wrap into — see `makeNSView`.
                  container.containerSize.width > 1 else { return end }
            layout.ensureLayout(for: container)
            guard layout.numberOfGlyphs > 0 else { return end }
            var fragment = NSRange(location: 0, length: 0)
            _ = layout.lineFragmentRect(forGlyphAt: 0, effectiveRange: &fragment)
            let characters = layout.characterRange(forGlyphRange: fragment, actualGlyphRange: nil)
            var location = min(NSMaxRange(characters), end)
            // A caret sitting exactly on a soft wrap can belong to either side
            // of it; step back one character so it's unambiguously on the line
            // it was meant to land on.
            if location > 0, location < end {
                let glyph = layout.glyphIndexForCharacter(at: location)
                let landed = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
                let first = layout.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil).minY
                if landed > first + RowTextLayout.CaretLine.tolerance { location -= 1 }
            }
            return location
        }

        override func becomeFirstResponder() -> Bool {
            let became = super.becomeFirstResponder()
            if became { onFocusChange?(true) }
            return became
        }

        override func resignFirstResponder() -> Bool {
            let resigned = super.resignFirstResponder()
            if resigned {
                updateInsertionPointStateAndRestartTimer(false)
                needsDisplay = true
                onFocusChange?(false)
            }
            return resigned
        }

        /// Only the row that actually holds the keyboard shows a caret.
        ///
        /// Each row owns a text view of its own, and a text view that has been
        /// asked to give up the keyboard still repaints its last insertion
        /// point whenever it redraws — which left every idle task in the list
        /// wearing a caret. (A text field never had this: its editor is one
        /// shared view that simply leaves the row it came from.) Gated on the
        /// draw itself, since that's the path a redraw takes.
        override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
            guard window?.firstResponder === self else { return }
            super.drawInsertionPoint(in: rect, color: color, turnedOn: flag)
        }

        override func updateInsertionPointStateAndRestartTimer(_ restartFlag: Bool) {
            super.updateInsertionPointStateAndRestartTimer(
                restartFlag && window?.firstResponder === self
            )
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            guard string.isEmpty, !placeholder.isEmpty else { return }
            // Drawn at the text's own origin, so the prompt and the first thing
            // typed over it start at exactly the same pixel.
            NSAttributedString(
                string: placeholder,
                attributes: [
                    .foregroundColor: NSColor.white.withAlphaComponent(0.25),
                    .font: TaskTextEditor.font,
                ]
            ).draw(at: NSPoint(x: textContainerInset.width, y: textContainerInset.height))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TaskTextEditor
        private var lastParse: ScheduleParse?
        init(_ parent: TaskTextEditor) { self.parent = parent }

        func textDidChange(_ note: Notification) {
            guard let textView = note.object as? RowTextView else { return }
            // A task is one logical line even though it may be drawn on
            // several: a pasted paragraph collapses to spaces rather than
            // smuggling real breaks into the model.
            let flattened = Self.flattened(textView.string)
            if flattened != textView.string {
                textView.string = flattened
                textView.setSelectedRange(NSRange(location: (flattened as NSString).length, length: 0))
            }
            parent.text = flattened
            // The placeholder appears and disappears with the text.
            textView.needsDisplay = true
            refreshParse(for: textView)
            // The row may have just gained a line; if it's already at the cap,
            // follow the caret rather than typing off the bottom edge.
            textView.scrollRangeToVisible(textView.selectedRange())
        }

        /// Every kind of line break — CRLF, CR, LF, and the Unicode line and
        /// paragraph separators — folded into single spaces.
        private static func flattened(_ string: String) -> String {
            guard string.contains(where: \.isNewline) else { return string }
            let joined = string.replacingOccurrences(of: "\r\n", with: " ")
            return String(joined.map { $0.isNewline ? " " : $0 })
        }

        /// Called by the text view as the keyboard arrives and leaves.
        func focusChanged(to focused: Bool, in textView: RowTextView) {
            if focused {
                if parent.focusedIndex != parent.index { parent.focusedIndex = parent.index }
                // Re-highlight a phrase typed earlier but never confirmed.
                refreshParse(for: textView)
            } else {
                // The highlight is an editing affordance: an unfocused row goes
                // back to plain white, exactly as it read before it was touched.
                clearHighlight(in: textView)
                // And a row that was scrolled to follow the caret rewinds to
                // the top, so an idle list reads as every task's opening words
                // rather than wherever each was last being edited.
                textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
            }
        }

        /// Re-parse the trailing date phrase and paint it. Nothing leaks into
        /// the model — the attributes live on the view's storage — and resetting
        /// the full range every keystroke is also what clears the highlight once
        /// the phrase stops matching.
        func refreshParse(for textView: NSTextView) {
            let parse = NaturalDateParser.parse(textView.string, anchor: parent.parseAnchor)
            if parse != lastParse {
                lastParse = parse
                // Defer: focus can change inside a SwiftUI view update.
                let onParseChange = parent.onParseChange
                DispatchQueue.main.async { onParseChange(parse) }
            }

            guard let storage = textView.textStorage else { return }
            let full = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.removeAttribute(.backgroundColor, range: full)
            storage.addAttribute(.foregroundColor, value: NSColor.white, range: full)
            storage.addAttribute(.font, value: TaskTextEditor.font, range: full)
            if let parse, NSMaxRange(parse.matchedRange) <= storage.length {
                storage.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: parse.matchedRange)
                storage.addAttribute(
                    .backgroundColor,
                    value: NSColor.systemGreen.withAlphaComponent(0.22),
                    range: parse.matchedRange
                )
            }
            storage.endEditing()
            // Don't let fresh keystrokes inherit the highlight's attributes.
            textView.typingAttributes = [.font: TaskTextEditor.font, .foregroundColor: NSColor.white]
        }

        /// Paints the row for the state it's in: the date phrase highlighted
        /// while the keyboard is here, plain white once it leaves.
        func restyle(_ textView: RowTextView) {
            if textView.window?.firstResponder === textView {
                refreshParse(for: textView)
            } else {
                clearHighlight(in: textView)
            }
        }

        private func clearHighlight(in textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let full = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.removeAttribute(.backgroundColor, range: full)
            storage.addAttribute(.foregroundColor, value: NSColor.white, range: full)
            storage.addAttribute(.font, value: TaskTextEditor.font, range: full)
            storage.endEditing()
            lastParse = nil
        }

        /// Which of the row's wrapped lines the caret is on, read off the text
        /// view's own layout. Nil when there's nothing laid out to be on — an
        /// empty row — where the caret is trivially on the first line and the
        /// last at once.
        private func caretLine(in textView: NSTextView) -> RowTextLayout.CaretLine? {
            guard let layout = textView.layoutManager, let container = textView.textContainer else { return nil }
            layout.ensureLayout(for: container)
            let glyphs = layout.numberOfGlyphs
            guard glyphs > 0 else { return nil }
            // A caret past the last character belongs to the line that
            // character is on: the text holds no real breaks, so there is never
            // an empty line below it for the caret to have fallen onto.
            let length = (textView.string as NSString).length
            let character = min(max(textView.selectedRange().location, 0), max(length - 1, 0))
            let glyph = min(layout.glyphIndexForCharacter(at: character), glyphs - 1)
            func top(ofGlyphAt index: Int) -> CGFloat {
                layout.lineFragmentRect(forGlyphAt: index, effectiveRange: nil).minY
            }
            return RowTextLayout.CaretLine(
                top: top(ofGlyphAt: glyph),
                firstLineTop: top(ofGlyphAt: 0),
                lastLineTop: top(ofGlyphAt: glyphs - 1)
            )
        }

        /// Key code of the event currently being interpreted when it's ⌥↑ (126)
        /// or ⌥↓ (125) with Option alone; nil for anything else. The selectors
        /// below are also reachable without Option (⌃B/⌃F, and ⌥arrow variants
        /// with other modifiers), so the event itself is the only reliable
        /// way to tell the reorder chord apart from ordinary caret motion.
        private var optionArrowKeyCode: UInt16? {
            guard let event = NSApp.currentEvent, event.type == .keyDown, event.isOptionOnly,
                  event.keyCode == 125 || event.keyCode == 126 else { return nil }
            return event.keyCode
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            // ⌥↑ / ⌥↓ arrive as a two-selector sequence per key press —
            // `moveBackward:` then `moveToBeginningOfParagraph:` for up, and
            // the forward pair for down (see StandardKeyBinding.dict). Act on
            // the second and swallow the first, otherwise the caret steps
            // sideways before the row moves.
            case #selector(NSResponder.moveBackward(_:)), #selector(NSResponder.moveForward(_:)):
                return optionArrowKeyCode != nil
            case #selector(NSResponder.moveToBeginningOfParagraph(_:)):
                guard optionArrowKeyCode == 126 else { return false }
                parent.onReorderUp()
                // Consumed even on the first row: a boundary is a silent
                // no-op, not a beep and not a caret jump.
                return true
            case #selector(NSResponder.moveToEndOfParagraph(_:)):
                guard optionArrowKeyCode == 125 else { return false }
                parent.onReorderDown()
                return true
            // Parsed fresh at submit time so Enter always acts on what's
            // visible.
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit(NaturalDateParser.parse(textView.string, anchor: parent.parseAnchor))
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onEscape()
                return true
            case #selector(NSResponder.insertTab(_:)):
                parent.onTab()
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                parent.onBacktab()
                return true
            // Option-Return, Control-Return and the line-break key all ask for
            // a hard break. The row wraps on its own and the task is one
            // logical line, so these do nothing at all.
            case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)),
                 #selector(NSResponder.insertLineBreak(_:)),
                 #selector(NSResponder.insertParagraphSeparator(_:)):
                return true
            // Arrows walk the list like Tab/Shift-Tab — Down on the last
            // filled row spills into a fresh task. A row whose text wrapped is
            // walked line by line first, though: only from its top line does Up
            // leave for the task above, and only from its bottom line does Down
            // leave for the one below. Returning false hands the move back to
            // the text view, which walks the caret and scrolls the row to it.
            case #selector(NSResponder.moveUp(_:)):
                guard caretLine(in: textView)?.isOnFirstLine ?? true else { return false }
                parent.onMoveUp()
                return true
            case #selector(NSResponder.moveDown(_:)):
                guard caretLine(in: textView)?.isOnLastLine ?? true else { return false }
                parent.onMoveDown()
                return true
            case #selector(NSResponder.deleteBackward(_:)):
                // Backspace on an already-empty task deletes the slot; with
                // text present (even at caret 0) AppKit handles it normally.
                if textView.string.isEmpty {
                    parent.onEmptyBackspace()
                    return true
                }
                return false
            default:
                return false
            }
        }
    }
}
