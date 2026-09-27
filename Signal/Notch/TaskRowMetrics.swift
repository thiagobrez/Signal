import AppKit
import SwiftUI

/// The sizes a task row is drawn at. The behaviour of a row — its editor, its
/// keys, its delete button — is the same wherever it appears; only its scale
/// differs. The panel is the app's main surface and draws rows large; the
/// schedule overview fits a whole week on one card and draws them compact.
struct TaskRowMetrics: Equatable {
    /// Point size of the task text (always medium weight).
    let textSize: CGFloat
    /// Point size and weight of the leading symbol — the completion control on
    /// a to-do, the calendar / repeat glyph on a schedule. One value for every
    /// kind of row, so the symbols down a column match.
    let iconSize: CGFloat
    let iconWeight: Font.Weight
    /// The box every leading symbol is centred in, so the text beside it starts
    /// at the same x on all rows whatever the glyph's natural width.
    let iconBox: CGFloat
    /// Gap between the leading symbol, the text and the trailing gutter.
    let spacing: CGFloat
    /// Minimum height of the text area: one line of `textSize` text.
    let textRowHeight: CGFloat
    /// Minimum height of the whole row.
    let rowHeight: CGFloat

    var verticalPadding: CGFloat { (rowHeight - textRowHeight) / 2 }
    var textFont: Font { .system(size: textSize, weight: .medium) }
    var iconFont: Font { .system(size: iconSize, weight: iconWeight) }
    var nsTextFont: NSFont { .systemFont(ofSize: textSize, weight: .medium) }

    /// The main Signal panel.
    static let panel = TaskRowMetrics(
        textSize: 15, iconSize: 18, iconWeight: .regular, iconBox: 20,
        spacing: 12, textRowHeight: 20, rowHeight: 22
    )

    /// The schedule overview — the sizes its read-only rows have always had.
    static let compact = TaskRowMetrics(
        textSize: 13, iconSize: 11, iconWeight: .semibold, iconBox: 16,
        spacing: 8, textRowHeight: 16, rowHeight: 22
    )
}
