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

        let sound: NSSound?
        if id.hasPrefix("sys:") {
            sound = NSSound(named: String(id.dropFirst(4)))
        } else if let url = Bundle.main.url(forResource: id, withExtension: "wav") {
            sound = NSSound(contentsOf: url, byReference: true)
        } else {
            // Last resort: treat as a named sound.
            sound = NSSound(named: id)
        }

        guard let sound else { return }
        // `NSSound.play()` is asynchronous, so the object must stay alive until
        // playback finishes. Without an owner the temporary is deallocated as
        // soon as this call returns — most visibly when firing from a Timer
        // callback, whose autorelease pool drains immediately — cutting the
        // sound off before it's audible. Retention keeps it playing; the
        // delegate releases it when done.
        Retainer.shared.retain(sound)
        sound.play()
    }

    /// Holds strong references to sounds while they play and drops them on the
    /// delegate callback (or if playback never starts).
    private final class Retainer: NSObject, NSSoundDelegate {
        static let shared = Retainer()

        private let lock = NSLock()
        private var playing: Set<NSSound> = []

        func retain(_ sound: NSSound) {
            sound.delegate = self
            lock.lock()
            playing.insert(sound)
            lock.unlock()
        }

        func sound(_ sound: NSSound, didFinishPlaying _: Bool) {
            lock.lock()
            playing.remove(sound)
            lock.unlock()
        }
    }
}
