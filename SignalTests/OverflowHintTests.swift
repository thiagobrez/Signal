import XCTest
import CoreGraphics

/// Placement of the scroll hints around the notch list: they fade in only past
/// a small dead-zone, and they sit outside the viewport so they never draw over
/// a row's text (#44).
final class OverflowHintTests: XCTestCase {
    func testDeadZoneHidesHintWithinFourPoints() {
        XCTAssertFalse(OverflowHint.isShown(overflow: 0))
        XCTAssertFalse(OverflowHint.isShown(overflow: 4))
        XCTAssertFalse(OverflowHint.isShown(overflow: -10))
        XCTAssertTrue(OverflowHint.isShown(overflow: 4.5))
        XCTAssertTrue(OverflowHint.isShown(overflow: 28))
    }

    func testTopHintIsPushedAboveTheViewport() {
        XCTAssertEqual(OverflowHint.offset(for: .top, gap: 10), -10)
    }

    func testBottomHintIsPushedBelowTheViewport() {
        XCTAssertEqual(OverflowHint.offset(for: .bottom, gap: 10), 10)
    }

    func testHintNeverOverlapsTheViewportWhenTallerGapIsGiven() {
        // The chevron glyph is 8pt tall at 11pt semibold; the offset has to
        // carry all of it past the viewport edge.
        XCTAssertGreaterThanOrEqual(abs(OverflowHint.offset(for: .top, gap: 10)), 8)
    }
}
