import Foundation

/// What re-launching an already-running Signal does. With no Dock icon and the
/// menu bar item hidden, reopen is the user's only way back to Preferences, so
/// it opens them alongside the panel (#17).
enum ReopenPolicy {
    struct Actions: Equatable {
        let presentPanel: Bool
        let openPreferences: Bool
    }

    static func actions(menuBarIconVisible: Bool) -> Actions {
        Actions(presentPanel: true, openPreferences: !menuBarIconVisible)
    }
}
