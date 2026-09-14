import XCTest
import CoreGraphics

/// The rules a task row's own text follows: it grows with the text but stops at
/// three lines, and once it has more than one line the arrow keys walk those
/// lines before they hand focus to another task.
final class RowTextLayoutTests: XCTestCase {
    /// Roughly what the row's 15pt font measures; the exact value doesn't
    /// matter, only that the cap is a whole number of these.
    private let lineHeight: CGFloat = 20

    // MARK: - cappedHeight

    func testShortTextKeepsItsMeasuredHeight() {
        XCTAssertEqual(RowTextLayout.cappedHeight(measured: 20, lineHeight: lineHeight), 20)
        XCTAssertEqual(RowTextLayout.cappedHeight(measured: 40, lineHeight: lineHeight), 40)
    }

    func testTextAtTheCapIsUntouched() {
        XCTAssertEqual(RowTextLayout.cappedHeight(measured: 60, lineHeight: lineHeight), 60)
    }

    func testLongerTextIsCappedAtAWholeNumberOfLines() {
        // Five lines' worth of text still only takes three lines of row; the
        // rest is scrolled inside it.
        XCTAssertEqual(RowTextLayout.cappedHeight(measured: 100, lineHeight: lineHeight), 60)
    }

    func testCapFollowsTheLineLimitItIsGiven() {
        XCTAssertEqual(RowTextLayout.cappedHeight(measured: 100, lineHeight: lineHeight, maxLines: 1), 20)
        XCTAssertEqual(RowTextLayout.cappedHeight(measured: 100, lineHeight: lineHeight, maxLines: 10), 100)
    }

    func testUnmeasurableLineHeightLeavesTheTextAlone() {
        // Better a tall row than a row collapsed to nothing if the font ever
        // fails to measure.
        XCTAssertEqual(RowTextLayout.cappedHeight(measured: 100, lineHeight: 0), 100)
        XCTAssertEqual(RowTextLayout.cappedHeight(measured: 100, lineHeight: lineHeight, maxLines: 0), 100)
    }

    // MARK: - CaretLine

    private func caretLine(top: CGFloat, first: CGFloat = 0, last: CGFloat = 40) -> RowTextLayout.CaretLine {
        RowTextLayout.CaretLine(top: top, firstLineTop: first, lastLineTop: last)
    }

    func testSingleLineRowIsBothItsFirstLineAndItsLast() {
        // The one line is the top line and the bottom line, so Up and Down both
        // leave the row immediately — exactly as they did before rows wrapped.
        let line = caretLine(top: 0, first: 0, last: 0)
        XCTAssertTrue(line.isOnFirstLine)
        XCTAssertTrue(line.isOnLastLine)
    }

    func testCaretOnTheTopLineOfAWrappedRowOnlyLeavesUpwards() {
        let line = caretLine(top: 0)
        XCTAssertTrue(line.isOnFirstLine)
        XCTAssertFalse(line.isOnLastLine)
    }

    func testCaretOnTheBottomLineOfAWrappedRowOnlyLeavesDownwards() {
        let line = caretLine(top: 40)
        XCTAssertFalse(line.isOnFirstLine)
        XCTAssertTrue(line.isOnLastLine)
    }

    func testCaretOnAMiddleLineStaysInTheRow() {
        let line = caretLine(top: 20)
        XCTAssertFalse(line.isOnFirstLine)
        XCTAssertFalse(line.isOnLastLine)
    }

    func testFractionalLayoutStillCountsAsTheSameLine() {
        // Line fragments land on fractional origins; a caret a third of a point
        // off the first line is still on it.
        XCTAssertTrue(caretLine(top: 0.3).isOnFirstLine)
        XCTAssertTrue(caretLine(top: 39.7).isOnLastLine)
        XCTAssertFalse(caretLine(top: 1).isOnFirstLine)
        XCTAssertFalse(caretLine(top: 39).isOnLastLine)
    }
}
