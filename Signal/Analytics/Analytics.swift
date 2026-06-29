import Foundation
import TelemetryDeck

/// Thin wrapper over our analytics provider (TelemetryDeck) so call sites stay
/// provider-agnostic and every event name lives in one place.
///
/// Privacy: TelemetryDeck collects no personal data. It derives an anonymous,
/// salted per-install identifier, which is what lets us count *users* (e.g. how
/// many people finished all three to-dos) without ever identifying anyone.
enum Analytics {
    /// TelemetryDeck app identifier, injected at build time from the
    /// `TELEMETRYDECK_APP_ID` xcconfig value via Signal/Info.plist — so the real
    /// ID lives in the gitignored Config/Analytics.local.xcconfig and never hits
    /// the public repo. When unset, analytics is a silent no-op and the app
    /// builds and runs fine. See Config/Analytics.local.xcconfig.example.
    private static let appID: String = {
        let value = Bundle.main.object(forInfoDictionaryKey: "TelemetryDeckAppID") as? String
        return value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }()

    private static var isEnabled: Bool { !appID.isEmpty }

    /// Call once at launch, before any signals are sent.
    static func start() {
        guard isEnabled else { return }
        TelemetryDeck.initialize(config: .init(appID: appID))
    }

    /// How the Signal panel was brought up. Lets us tell deliberate opens
    /// (hotkey / menu) apart from the app prompting on its own.
    enum OpenSource: String {
        case manual    // hotkey or menu-bar toggle
        case launch    // auto-opened at login
        case scheduled // the daily prompt fired
    }

    /// The interactive Signal panel was presented. Drives "opens per day".
    static func signalOpened(source: OpenSource) {
        send("signalOpened", ["source": source.rawValue])
    }

    /// All three of today's to-dos became complete. Drives "users completing the
    /// three tasks per day" — TelemetryDeck reports both event count and unique
    /// users for the same signal.
    static func dayCompleted() {
        send("dayCompleted")
    }

    private static func send(_ name: String, _ parameters: [String: String] = [:]) {
        guard isEnabled else { return }
        TelemetryDeck.signal(name, parameters: parameters)
    }
}
