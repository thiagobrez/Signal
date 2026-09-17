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

    // MARK: - dragEdge

    /// Four 22pt rows in a 100pt viewport, with a one-row edge zone.
    private let viewport: CGFloat = 100
    private let edgeZone: CGFloat = 22

    func testDragEdgeIsZeroWellInsideTheViewport() {
        // Row 1 spans 32...54 — clear of both zones (0...22 and 78...100).
        let rows = layout([22, 22, 22, 22])
        XCTAssertEqual(
            rows.dragEdge(of: 1, offset: 0, scrollOrigin: 0,
                          viewportHeight: viewport, edgeZone: edgeZone),
            0
        )
    }

    func testDragEdgeReportsTopWhenDraggedUp() {
        // Dragged up 20, the row's top is at 12 — inside the top zone.
        let rows = layout([22, 22, 22, 22])
        XCTAssertEqual(
            rows.dragEdge(of: 1, offset: -20, scrollOrigin: 0,
                          viewportHeight: viewport, edgeZone: edgeZone),
            -1
        )
    }

    func testDragEdgeReportsBottomWhenDraggedDown() {
        // Dragged down 30, the row's bottom is at 84 — past 78.
        let rows = layout([22, 22, 22, 22])
        XCTAssertEqual(
            rows.dragEdge(of: 1, offset: 30, scrollOrigin: 0,
                          viewportHeight: viewport, edgeZone: edgeZone),
            1
        )
    }

    func testDragEdgeIsMeasuredAgainstTheScrolledViewport() {
        // Row 2 sits at 64 in the content, but the list is scrolled by 60, so
        // on screen its top is at 4 — pressed against the top edge.
        let rows = layout([22, 22, 22, 22])
        XCTAssertEqual(
            rows.dragEdge(of: 2, offset: 0, scrollOrigin: 60,
                          viewportHeight: viewport, edgeZone: edgeZone),
            -1
        )
    }

    func testDragEdgeOutOfRangeIsZero() {
        let rows = layout([22, 22, 22, 22])
        XCTAssertEqual(
            rows.dragEdge(of: 9, offset: 0, scrollOrigin: 0,
                          viewportHeight: viewport, edgeZone: edgeZone),
            0
        )
    }

    func testDragEdgeUsesTheShiftedTopOfAScheduledRow() {
        // The section block above row 2 pushes it to 114, so with the list at
        // the top it's below the fold entirely — the bottom edge.
        let rows = NotchRowLayout(heights: [22, 22, 22, 22], spacing: spacing, extras: [2: 50])
        XCTAssertEqual(
            rows.dragEdge(of: 2, offset: 0, scrollOrigin: 0,
                          viewportHeight: viewport, edgeZone: edgeZone),
            1
        )
    }

    // MARK: - clampedToViewport

    func testClampedToViewportLeavesAnInsideOffsetAlone() {
        let rows = layout([22, 22, 22, 22])
        XCTAssertEqual(
            rows.clampedToViewport(10, of: 1, scrollOrigin: 0, viewportHeight: viewport),
            10
        )
    }

    func testClampedToViewportStopsTheRowFlushWithTheTop() {
        // Row 1's slot starts at 32, so it can't be pulled up further than that.
        let rows = layout([22, 22, 22, 22])
        XCTAssertEqual(
            rows.clampedToViewport(-50, of: 1, scrollOrigin: 0, viewportHeight: viewport),
            -32
        )
    }

    func testClampedToViewportStopsTheRowFlushWithTheBottom() {
        // Its bottom stops at 100: 0 + 100 - 22 - 32.
        let rows = layout([22, 22, 22, 22])
        XCTAssertEqual(
            rows.clampedToViewport(80, of: 1, scrollOrigin: 0, viewportHeight: viewport),
            46
        )
    }

    func testClampedToViewportFollowsTheScroll() {
        // Scrolled by 30, row 1 is only 2pt below the top edge.
        let rows = layout([22, 22, 22, 22])
        XCTAssertEqual(
            rows.clampedToViewport(-10, of: 1, scrollOrigin: 30, viewportHeight: viewport),
            -2
        )
    }

    func testClampedToViewportUsesTheShiftedTopOfAScheduledRow() {
        // Row 2 sits at 114 with the section block above it, so from a list
        // resting at the top it has to come up 114 to sit flush.
        let rows = NotchRowLayout(heights: [22, 22, 22, 22], spacing: spacing, extras: [2: 50])
        XCTAssertEqual(
            rows.clampedToViewport(-200, of: 2, scrollOrigin: 0, viewportHeight: viewport),
            -114
        )
    }

    func testClampedToViewportLeavesARowTallerThanTheViewportAlone() {
        // Nothing to clamp to: the row can't fit however it's positioned.
        let rows = layout([22, 200])
        XCTAssertEqual(
            rows.clampedToViewport(-500, of: 1, scrollOrigin: 0, viewportHeight: viewport),
            -500
        )
    }

    func testClampedToViewportOutOfRangeIsUnchanged() {
        XCTAssertEqual(
            layout([22]).clampedToViewport(40, of: 7, scrollOrigin: 0, viewportHeight: viewport),
            40
        )
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
