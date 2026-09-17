import XCTest

/// When the daily prompt and the quick glances are allowed to interrupt: never
/// over a Signal surface the user already has up, and never on a day whose
/// tasks are all ticked off.
final class AutoOpenPolicyTests: XCTestCase {
    private func skip(
        _ trigger: AutoOpenPolicy.Trigger,
        panel: Bool = false,
        interactive: Bool = false,
        overview: Bool = false,
        allComplete: Bool = false
    ) -> AutoOpenPolicy.SkipReason? {
        AutoOpenPolicy.skipReason(
            for: trigger,
            ui: .init(isPanelVisible: panel, isPanelInteractive: interactive, isOverviewVisible: overview),
            allTasksComplete: allComplete
        )
    }

    // MARK: - Daily prompt

    func testDailyPromptFiresOnAQuietDayWithWorkLeft() {
        XCTAssertNil(skip(.dailyPrompt))
    }

    func testDailyPromptSkipsWhenPanelIsOpenInteractively() {
        XCTAssertEqual(skip(.dailyPrompt, panel: true, interactive: true), .alreadyOpen)
    }

    func testDailyPromptSkipsWhenOverviewIsOpen() {
        XCTAssertEqual(skip(.dailyPrompt, overview: true), .alreadyOpen)
    }

    func testDailyPromptUpgradesARunningGlance() {
        // A peek isn't the user having Signal open, so the prompt still fires
        // and turns it into the interactive panel.
        XCTAssertNil(skip(.dailyPrompt, panel: true, interactive: false))
    }

    func testDailyPromptSkipsWhenAllTasksAreComplete() {
        XCTAssertEqual(skip(.dailyPrompt, allComplete: true), .allTasksComplete)
    }

    // MARK: - Glances

    func testGlanceSkipsOverAnyVisibleSurface() {
        XCTAssertEqual(skip(.glance, panel: true, interactive: true), .alreadyOpen)
        XCTAssertEqual(skip(.glance, panel: true, interactive: false), .alreadyOpen)
        XCTAssertEqual(skip(.glance, overview: true), .alreadyOpen)
    }

    func testGlanceFiresWhenNothingIsUpAndWorkIsLeft() {
        XCTAssertNil(skip(.glance))
    }

    func testGlanceSkipsWhenAllTasksAreComplete() {
        XCTAssertEqual(skip(.glance, allComplete: true), .allTasksComplete)
    }

    // MARK: - Precedence

    func testAlreadyOpenTakesPrecedenceOverAllTasksComplete() {
        XCTAssertEqual(skip(.dailyPrompt, panel: true, interactive: true, allComplete: true), .alreadyOpen)
        XCTAssertEqual(skip(.glance, overview: true, allComplete: true), .alreadyOpen)
    }
}
