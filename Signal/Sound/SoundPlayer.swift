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

    /// Plays the sound identified by `id` through the output device with UID
    /// `deviceUID`. No-op for `none`/empty. `deviceUID` may be
    /// `AudioOutputDevice.systemDefaultID` (or a device that is no longer
    /// connected), in which case macOS picks the output device as usual.
    static func play(_ id: String, on deviceUID: String = AudioOutputDevice.systemDefaultID) {
        guard id != noneID, !id.isEmpty else { return }
        guard let sound = makeSound(for: id) else { return }

        // Only enumerate devices when a specific one was asked for; the common
        // System Default path shouldn't pay for a CoreAudio round-trip.
        let target: String? = deviceUID == AudioOutputDevice.systemDefaultID
            ? nil
            : AudioOutputDevices.resolvePlaybackDevice(
                preferred: deviceUID, available: AudioOutputDevices.current()
            )

        // A device can disappear between the lookup above and the play call (or
        // be rejected outright by CoreAudio), in which case `play()` returns
        // false and no sound is ever heard. Retry on the system default so a
        // stale preference never silences a cue.
        if !start(sound, on: target), target != nil, let fallback = makeSound(for: id) {
            _ = start(fallback, on: nil)
        }
    }

    /// Builds a fresh, independently routable `NSSound` for `id`.
    ///
    /// System sounds are loaded from their file rather than via
    /// `NSSound(named:)`: that initializer hands back a cached shared instance
    /// whose `playbackDeviceIdentifier` stops taking effect after its first
    /// playback, so the second preview would come out of the wrong device.
    private static func makeSound(for id: String) -> NSSound? {
        if id.hasPrefix("sys:") {
            let name = String(id.dropFirst(4))
            let url = URL(fileURLWithPath: "/System/Library/Sounds/\(name).aiff")
            if let sound = NSSound(contentsOf: url, byReference: true) { return sound }
            return NSSound(named: name)?.copy() as? NSSound
        }
        if let url = Bundle.main.url(forResource: id, withExtension: "wav") {
            return NSSound(contentsOf: url, byReference: true)
        }
        // Last resort: treat as a named sound.
        return NSSound(named: id)?.copy() as? NSSound
    }

    /// Starts `sound` on `device` (nil = system default), returning whether
    /// playback actually began.
    private static func start(_ sound: NSSound, on device: String?) -> Bool {
        sound.playbackDeviceIdentifier = device
        // `NSSound.play()` is asynchronous, so the object must stay alive until
        // playback finishes. Without an owner the temporary is deallocated as
        // soon as this call returns — most visibly when firing from a Timer
        // callback, whose autorelease pool drains immediately — cutting the
        // sound off before it's audible. Retention keeps it playing; the
        // delegate releases it when done.
        Retainer.shared.retain(sound)
        guard sound.play() else {
            // The delegate never fires when playback fails to start, so drop
            // the reference here instead of leaking it.
            Retainer.shared.release(sound)
            return false
        }
        return true
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

        func release(_ sound: NSSound) {
            lock.lock()
            playing.remove(sound)
            lock.unlock()
        }

        func sound(_ sound: NSSound, didFinishPlaying _: Bool) {
            release(sound)
        }
    }
}
