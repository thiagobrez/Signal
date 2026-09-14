import CoreGraphics

/// The geometry of the text *inside* a task row: how tall the row is allowed to
/// grow, and where the caret sits among the lines the text wrapped onto.
///
/// A row grows with its text, but only so far — past `maxLines` it holds its
/// height and the text scrolls inside it instead, so one rambling task can't
/// push the rest of the list off the panel. That makes every row a little
/// viewport, which gives the arrow keys two jobs: walk the lines *within* the
/// row, and hand focus to another task only from the row's first or last line.
///
/// Both rules are arithmetic over numbers AppKit hands us, so they live here —
/// no AppKit, no SwiftUI — where they can be unit-tested.
/// Which edge of a row the keyboard arrives at. Focus lands at the end of the
/// line it entered on, so the arrows walk a wrapped row's lines in both
/// directions instead of skipping past them on the way down. A single-line row
/// has only one line, so both cases land at the end of its text — exactly where
/// focus has always landed.
enum RowEntry {
    /// Arrived from the row above (Down): land on this row's first line.
    case fromAbove
    /// Arrived from the row below, or from nothing in particular — a click, a
    /// new task, Tab: land at the end of the text.
    case fromBelow
}

enum RowTextLayout {
    /// How many wrapped lines a row shows before it stops growing and starts
    /// scrolling. Three is enough to read a long task at a glance without a
    /// single row owning the panel.
    static let maxLines = 3

    /// The height the row's text area gets: what the text measured, capped at
    /// `maxLines` lines' worth. `measured` and `lineHeight` come from the same
    /// text system, so the cap lands exactly on a line boundary rather than
    /// slicing a line in half.
    static func cappedHeight(
        measured: CGFloat,
        lineHeight: CGFloat,
        maxLines: Int = RowTextLayout.maxLines
    ) -> CGFloat {
        guard lineHeight > 0, maxLines > 0 else { return measured }
        return min(measured, lineHeight * CGFloat(maxLines))
    }

    /// Which of a wrapped row's visual lines the caret is on, in the line-
    /// fragment coordinates the field editor's layout manager reports.
    ///
    /// Only the two edges matter: Up on the first line and Down on the last
    /// leave the row for the neighbouring task, and anywhere else the text view
    /// moves the caret itself (scrolling the row's content if it has to).
    struct CaretLine: Equatable {
        /// Top of the line fragment the caret sits on.
        let top: CGFloat
        /// Top of the text's first line fragment.
        let firstLineTop: CGFloat
        /// Top of the text's last line fragment.
        let lastLineTop: CGFloat

        /// Line fragments are laid out in fractional coordinates, so "the same
        /// line" has to be a near-comparison rather than an equality.
        static let tolerance: CGFloat = 0.5

        /// True for a single-line row, where both edges are the same line.
        var isOnFirstLine: Bool { top <= firstLineTop + Self.tolerance }
        var isOnLastLine: Bool { top >= lastLineTop - Self.tolerance }
    }
}
