import XCTest
import CoreGraphics

/// The decisions behind the one-time "Signal lives here!" hint: whether the
/// status item we found is somewhere a popover would actually be seen, and that
/// the flag guarding the hint starts out false.
final class MenuBarHintPolicyTests: XCTestCase {
    /// A 1512×982 built-in display, and a status item sitting in its menu bar.
    private let mainScreen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: SettingsStore.Key.hasSeenMenuBarHint)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: SettingsStore.Key.hasSeenMenuBarHint)
        super.tearDown()
    }

    // MARK: - isAnchorOnScreen

    func testAnchorFullyInsideScreenIsOnScreen() {
        XCTAssertTrue(MenuBarHintPolicy.isAnchorOnScreen(
            anchorFrame: CGRect(x: 885, y: 951.5, width: 33, height: 29),
            screenFrames: [mainScreen]
        ))
    }

    func testAnchorClippedByScreenEdgeIsOffScreen() {
        // The menu bar is full and our item has been pushed past the edge.
        XCTAssertFalse(MenuBarHintPolicy.isAnchorOnScreen(
            anchorFrame: CGRect(x: 1500, y: 951.5, width: 33, height: 29),
            screenFrames: [mainScreen]
        ))
    }

    func testAnchorOnSecondaryScreenIsOnScreen() {
        let secondary = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        XCTAssertTrue(MenuBarHintPolicy.isAnchorOnScreen(
            anchorFrame: CGRect(x: 2400, y: 1049, width: 33, height: 29),
            screenFrames: [mainScreen, secondary]
        ))
    }

    func testEmptyAnchorIsOffScreen() {
        XCTAssertFalse(MenuBarHintPolicy.isAnchorOnScreen(
            anchorFrame: .zero,
            screenFrames: [mainScreen]
        ))
    }

    func testNoScreensIsOffScreen() {
        XCTAssertFalse(MenuBarHintPolicy.isAnchorOnScreen(
            anchorFrame: CGRect(x: 885, y: 951.5, width: 33, height: 29),
            screenFrames: []
        ))
    }

    // MARK: - The one-time flag

    func testHintFlagDefaultsToFalseAndRoundTrips() {
        SettingsStore.registerDefaults()
        XCTAssertFalse(SettingsStore.hasSeenMenuBarHint)

        SettingsStore.hasSeenMenuBarHint = true
        XCTAssertTrue(SettingsStore.hasSeenMenuBarHint)
    }

    // MARK: - Copy

    func testHintTextMatchesIssueCopy() {
        XCTAssertEqual(MenuBarHintPolicy.text, "Signal lives here!")
    }
}
