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
}
