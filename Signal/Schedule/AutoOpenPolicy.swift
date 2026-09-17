import Foundation

/// Decides when an unsolicited open — the daily prompt or a quick glance —
/// should stay quiet. Signal interrupting a user who is already looking at it,
/// or nagging about a day whose tasks are all ticked off, is noise rather than
/// a signal. Pure Foundation on purpose: it compiles into the app-host-less
/// test bundle, so the rule is unit-tested without the notch or SwiftData.
enum AutoOpenPolicy {
    /// The unsolicited opens this policy governs. User-initiated opens (hotkey,
    /// menu, launch) never consult it.
    enum Trigger: Equatable { case dailyPrompt, glance }

    enum SkipReason: Equatable {
        /// The user already has Signal up (the panel or the schedule overview).
        case alreadyOpen
        /// Every task for today is done — nothing left to prompt for.
        case allTasksComplete
    }

    /// What's on screen right now, mirrored from `NotchController`. Preferences,
    /// Stats, What's New and Onboarding are ordinary windows and don't count:
    /// only the notch surfaces are what a prompt would land on top of.
    struct UIState: Equatable {
        var isPanelVisible = false
        /// `NotchController.mode == .interactive`; false while a glance is showing.
        var isPanelInteractive = false
        var isOverviewVisible = false
    }

    /// Why `trigger` should stay quiet right now, or `nil` to go ahead.
    ///
    /// "Already open" is checked first: when the user is looking at Signal, the
    /// completion state is beside the point — the reason nothing happens is that
    /// they're already there.
    static func skipReason(for trigger: Trigger, ui: UIState, allTasksComplete: Bool) -> SkipReason? {
        if ui.isOverviewVisible { return .alreadyOpen }
        if ui.isPanelVisible {
            switch trigger {
            case .glance:
                // A peek never stacks on top of something that's already up.
                return .alreadyOpen
            case .dailyPrompt:
                // A panel the user opened themselves is left alone; a running
                // glance isn't "already open" in that sense, so the prompt
                // still fires and upgrades the peek to an interactive panel.
                if ui.isPanelInteractive { return .alreadyOpen }
            }
        }
        if allTasksComplete { return .allTasksComplete }
        return nil
    }
}
