import AppKit

/// Plays the completion sound. Sounds can be either:
/// - a bundled custom file (e.g. "pop" -> Resources/pop.wav), referenced by bare name, or
/// - a built-in macOS sound, referenced with a "sys:" prefix (e.g. "sys:Glass").
enum SoundPlayer {
    static let noneID = "none"

    /// A bundled sound reserved for the "all done" celebration. Hidden from the
    /// other pickers so it's only offered where it makes sense.
    static let celebrationOnlyID = "meadow"

    /// The 14 named macOS system sounds (from /System/Library/Sounds).
    static let systemSoundNames = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
        "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink",
    ]

    /// Custom sounds bundled in the app (file names without extension), sorted.
    /// Excludes celebration-only sounds — see `celebrationOnlyID`.
    static var bundledSoundNames: [String] {
        let urls = Bundle.main.urls(forResourcesWithExtension: "wav", subdirectory: nil) ?? []
        return urls.map { $0.deletingPathExtension().lastPathComponent }
            .filter { $0 != celebrationOnlyID }
            .sorted()
    }

    /// Plays the sound identified by `id`. No-op for `none`/empty.
    static func play(_ id: String) {
        guard id != noneID, !id.isEmpty else { return }

        if id.hasPrefix("sys:") {
            NSSound(named: String(id.dropFirst(4)))?.play()
            return
        }
        if let url = Bundle.main.url(forResource: id, withExtension: "wav") {
            NSSound(contentsOf: url, byReference: true)?.play()
            return
        }
        // Last resort: treat as a named sound.
        NSSound(named: id)?.play()
    }
}
