import Foundation

/// The decisions behind the one-time menu bar hint, kept free of AppKit so the
/// test bundle can pin them: the copy, the timings, and whether the status item
/// we found is somewhere the user can actually see a popover.
enum MenuBarHintPolicy {
    /// The hint's copy. Deliberately a constant: the tests assert on it.
    static let text = "Signal lives here!"

    /// How long to wait after onboarding finishes before showing the hint, so
    /// the onboarding window has closed and the app is back to `.accessory`.
    static let presentationDelay: TimeInterval = 0.75

    /// How long the hint stays up when the user doesn't click anything.
    static let autoDismissDelay: TimeInterval = 6

    /// Gap between attempts to find a visible status item.
    static let anchorRetryInterval: TimeInterval = 1

    /// How many times to retry before giving up silently. A menu bar that is
    /// full (our item overflowed), hidden by a third-party manager, or simply
    /// not created yet must not burn the one-time flag.
    static let anchorRetryLimit = 5

    /// Whether a popover anchored to `anchorFrame` would be visible: the frame
    /// has to be non-empty and fully inside one screen. A status item pushed
    /// past the edge of the menu bar reports a frame that spills off the
    /// screen (or none at all), and anchoring to it would draw the hint in
    /// mid-air or not at all.
    static func isAnchorOnScreen(anchorFrame: CGRect, screenFrames: [CGRect]) -> Bool {
        guard !anchorFrame.isEmpty else { return false }
        return screenFrames.contains { $0.contains(anchorFrame) }
    }
}
