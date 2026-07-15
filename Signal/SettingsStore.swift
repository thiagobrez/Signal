import Foundation

/// Thin namespace over `UserDefaults` for non-SwiftUI code (Scheduler, Store).
/// `PreferencesView` reads/writes the same keys via `@AppStorage`.
enum SettingsStore {
    enum Key {
        static let hasSeenOnboarding = "hasSeenOnboarding"
        static let lastSeenWhatsNewVersion = "lastSeenWhatsNewVersion"
        static let showWhatsNewAfterUpdates = "showWhatsNewAfterUpdates"
        static let hasRequestedReview = "hasRequestedReview"
        static let didMigrateToggleSignalShortcut = "didMigrateToggleSignalShortcut"
        static let carryOverIncomplete = "carryOverIncomplete"
        static let openOnLaunch = "openOnLaunch"
        static let dailyPromptEnabled = "dailyPromptEnabled"
        static let dailyPromptHour = "dailyPromptHour"
        static let dailyPromptMinute = "dailyPromptMinute"
        static let glancesEnabled = "glancesEnabled"
        static let glanceCount = "glanceCount"
        static let glanceWindowStartHour = "glanceWindowStartHour"
        static let glanceWindowEndHour = "glanceWindowEndHour"
        static let glanceDurationSeconds = "glanceDurationSeconds"
        static let completionSound = "completionSound"
        static let celebrationSound = "celebrationSound"
        static let openSound = "openSound"
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.hasSeenOnboarding: false,
            // lastSeenWhatsNewVersion is deliberately unregistered: nil means
            // "fresh install or pre-What's-New build", which must be told
            // apart from any real version.
            Key.showWhatsNewAfterUpdates: true,
            Key.hasRequestedReview: false,
            Key.didMigrateToggleSignalShortcut: false,
            Key.carryOverIncomplete: true,
            Key.openOnLaunch: true,
            Key.dailyPromptEnabled: true,
            Key.dailyPromptHour: 9,
            Key.dailyPromptMinute: 0,
            Key.glancesEnabled: true,
            Key.glanceCount: 3,
            Key.glanceWindowStartHour: 10,
            Key.glanceWindowEndHour: 18,
            Key.glanceDurationSeconds: 5.0,
            Key.completionSound: "pop",
            Key.celebrationSound: "sys:Hero",
            Key.openSound: "sys:Blow",
        ])
    }

    private static var d: UserDefaults { .standard }

    /// Read/write: the onboarding controller flips this once the user finishes
    /// (or dismisses) the first-launch onboarding window.
    static var hasSeenOnboarding: Bool {
        get { d.bool(forKey: Key.hasSeenOnboarding) }
        set { d.set(newValue, forKey: Key.hasSeenOnboarding) }
    }

    /// Read/write: the marketing version whose release notes the user has seen
    /// (or been credited with). Nil until seeded — after onboarding on fresh
    /// installs, or silently on the first launch of a pre-existing install.
    static var lastSeenWhatsNewVersion: String? {
        get { d.string(forKey: Key.lastSeenWhatsNewVersion) }
        set { d.set(newValue, forKey: Key.lastSeenWhatsNewVersion) }
    }

    /// Whether the What's New window auto-shows after an update. The checkbox
    /// in that window writes this via `@AppStorage`.
    static var showWhatsNewAfterUpdates: Bool { d.bool(forKey: Key.showWhatsNewAfterUpdates) }

    /// Read/write: flipped the first time the App Store build asks for a
    /// rating after a completed day, so the ask only ever happens once.
    static var hasRequestedReview: Bool {
        get { d.bool(forKey: Key.hasRequestedReview) }
        set { d.set(newValue, forKey: Key.hasRequestedReview) }
    }

    /// Read/write: flipped after the one-time move of installs still on the
    /// old auto-written ⌃⌥S default over to the new ⌘⇧T default.
    static var didMigrateToggleSignalShortcut: Bool {
        get { d.bool(forKey: Key.didMigrateToggleSignalShortcut) }
        set { d.set(newValue, forKey: Key.didMigrateToggleSignalShortcut) }
    }

    static var carryOverIncomplete: Bool { d.bool(forKey: Key.carryOverIncomplete) }
    static var openOnLaunch: Bool { d.bool(forKey: Key.openOnLaunch) }
    static var dailyPromptEnabled: Bool { d.bool(forKey: Key.dailyPromptEnabled) }
    static var dailyPromptHour: Int { d.integer(forKey: Key.dailyPromptHour) }
    static var dailyPromptMinute: Int { d.integer(forKey: Key.dailyPromptMinute) }
    static var glancesEnabled: Bool { d.bool(forKey: Key.glancesEnabled) }
    static var glanceCount: Int { d.integer(forKey: Key.glanceCount) }
    static var glanceWindowStartHour: Int { d.integer(forKey: Key.glanceWindowStartHour) }
    static var glanceWindowEndHour: Int { d.integer(forKey: Key.glanceWindowEndHour) }
    static var glanceDurationSeconds: Double { d.double(forKey: Key.glanceDurationSeconds) }
    static var completionSound: String { d.string(forKey: Key.completionSound) ?? "pop" }
    static var celebrationSound: String { d.string(forKey: Key.celebrationSound) ?? "sys:Hero" }
    static var openSound: String { d.string(forKey: Key.openSound) ?? "sys:Blow" }
}
