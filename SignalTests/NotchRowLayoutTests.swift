import XCTest
import CoreGraphics

/// The list geometry behind the notch panel, now that rows wrap and no longer
/// share one fixed height: stack height, per-row tops, the visibility test that
/// decides whether a focused row has to be scrolled into view, and the
/// drag-to-reorder thresholds.
final class NotchRowLayoutTests: XCTestCase {
    private let spacing: CGFloat = 10

    private func layout(_ heights: [CGFloat]) -> NotchRowLayout {
        NotchRowLayout(heights: heights, spacing: spacing)
    }

    // MARK: - contentHeight

    func testContentHeightSumsRowsAndGaps() {
        // Two gaps between three rows, one of them wrapped onto a second line.
        XCTAssertEqual(layout([22, 40, 22]).contentHeight, 104)
    }

    func testContentHeightOfEmptyListIsZero() {
        XCTAssertEqual(layout([]).contentHeight, 0)
    }

    func testContentHeightOfSingleRowHasNoGap() {
        XCTAssertEqual(layout([22]).contentHeight, 22)
    }

    // MARK: - top

    func testTopOfRowIsPrefixSum() {
        let rows = layout([22, 40, 22])
        XCTAssertEqual(rows.top(of: 0), 0)
        XCTAssertEqual(rows.top(of: 1), 32)
        XCTAssertEqual(rows.top(of: 2), 82)
    }

    // MARK: - isVisible

    func testIsVisibleUsesRowOwnHeight() {
        // The wrapped row spans 32...72; a 60pt viewport can't hold all of it
        // from the top of the list, but can once scrolled by 20.
        let rows = layout([22, 40, 22])
        XCTAssertFalse(rows.isVisible(1, scrollOrigin: 0, viewportHeight: 60))
        XCTAssertTrue(rows.isVisible(1, scrollOrigin: 20, viewportHeight: 60))
    }

    func testIsVisibleAllowsFractionalSlack() {
        // A row resting a fraction of a point outside the viewport still counts
        // as visible — SwiftUI's scrolling settles at fractional offsets.
        let rows = layout([22, 40, 22])
        XCTAssertTrue(rows.isVisible(1, scrollOrigin: 32.5, viewportHeight: 40))
        XCTAssertFalse(rows.isVisible(1, scrollOrigin: 34, viewportHeight: 40))
    }

    func testIsVisibleOutOfRangeIsFalse() {
        XCTAssertFalse(layout([22]).isVisible(3, scrollOrigin: 0, viewportHeight: 200))
    }

    // MARK: - swapStep

    func testSwapStepDownUsesNeighbourStride() {
        // Passing a wrapped row below takes 50pt of travel, so half of that.
        let rows = layout([22, 40])
        XCTAssertNil(rows.swapStep(from: 0, offset: 24))
        let step = rows.swapStep(from: 0, offset: 26)
        XCTAssertEqual(step?.to, 1)
        XCTAssertEqual(step?.distance, 50)
    }

    func testSwapStepUpUsesNeighbourStride() {
        let rows = layout([40, 22])
        XCTAssertNil(rows.swapStep(from: 1, offset: -24))
        let step = rows.swapStep(from: 1, offset: -26)
        XCTAssertEqual(step?.to, 0)
        XCTAssertEqual(step?.distance, 50)
    }

    func testSwapStepAtListEndsIsNil() {
        let rows = layout([22, 22])
        XCTAssertNil(rows.swapStep(from: 0, offset: -100))
        XCTAssertNil(rows.swapStep(from: 1, offset: 100))
    }

    func testSwapStepWithoutTravelIsNil() {
        XCTAssertNil(layout([22, 22]).swapStep(from: 0, offset: 0))
    }

    // MARK: - boundaryLimit

    func testBoundaryLimitIsHalfOwnStride() {
        let rows = layout([22, 40])
        XCTAssertEqual(rows.boundaryLimit(at: 0), 16)
        XCTAssertEqual(rows.boundaryLimit(at: 1), 25)
    }

    // MARK: - extras (the block between the regular and scheduled sections)

    func testExtrasAddToContentHeight() {
        // Three 22pt rows and two gaps is 86; the section block above row 2
        // adds its 50 on top.
        let rows = NotchRowLayout(heights: [22, 22, 22], spacing: spacing, extras: [2: 50])
        XCTAssertEqual(rows.contentHeight, 136)
    }

    func testTopIncludesExtrasAtAndAboveRow() {
        // The block sits above row 2, so rows 0 and 1 are where they always
        // were and everything from row 2 down is pushed past it.
        let rows = NotchRowLayout(heights: [22, 22, 22], spacing: spacing, extras: [2: 50])
        XCTAssertEqual(rows.top(of: 0), 0)
        XCTAssertEqual(rows.top(of: 1), 32)
        XCTAssertEqual(rows.top(of: 2), 114)
    }

    func testIsVisibleAccountsForExtras() {
        // Row 2 spans 114...136 with the block in place, so a 60pt viewport
        // resting at the top no longer reaches it.
        let rows = NotchRowLayout(heights: [22, 22, 22], spacing: spacing, extras: [2: 50])
        XCTAssertFalse(rows.isVisible(2, scrollOrigin: 0, viewportHeight: 60))
        XCTAssertTrue(rows.isVisible(2, scrollOrigin: 80, viewportHeight: 60))
    }

    func testEmptyExtrasIsBackwardsCompatible() {
        // A list with no scheduled section measures exactly as it did before.
        let plain = layout([22, 40, 22])
        let empty = NotchRowLayout(heights: [22, 40, 22], spacing: spacing, extras: [:])
        XCTAssertEqual(empty.contentHeight, plain.contentHeight)
        XCTAssertEqual(empty.top(of: 2), plain.top(of: 2))
    }

    func testStrideIgnoresExtras() {
        // The drag's unit of travel never spans the section gap — the view
        // clamps the swap at the boundary instead.
        let rows = NotchRowLayout(heights: [22, 22, 22], spacing: spacing, extras: [2: 50])
        XCTAssertEqual(rows.stride(of: 1), 32)
        XCTAssertEqual(rows.boundaryLimit(at: 1), 16)
    }
}
