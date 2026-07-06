import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    // Defaults live here (not written via `setShortcut` at launch) so a
    // shortcut the user clears stays cleared across relaunches.
    static let toggleSignal = Self("toggleSignal", default: .init(.t, modifiers: [.command, .shift]))
    static let toggleStats = Self("toggleStats", default: .init(.y, modifiers: [.command, .shift]))
}
