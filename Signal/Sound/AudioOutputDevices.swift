import CoreAudio
import Combine
import Foundation

/// A CoreAudio device that can play audio, identified by its persistent UID.
///
/// The UID (not the numeric `AudioDeviceID`, which is only valid for the
/// current boot/connection) is what gets stored in preferences and handed to
/// `NSSound.playbackDeviceIdentifier`.
struct AudioOutputDevice: Identifiable, Hashable {
    /// Sentinel stored in preferences for "whatever macOS is using".
    static let systemDefaultID = "default"

    let uid: String
    let name: String

    var id: String { uid }
}

/// Enumeration and resolution of the Mac's audio output devices.
enum AudioOutputDevices {
    /// Shown in the picker for a remembered device that is no longer connected,
    /// so the selection stays visible instead of rendering as a blank row.
    static let unavailableName = "Unavailable device"

    /// Every device with at least one output stream, sorted by name.
    static func current() -> [AudioOutputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &dataSize) == noErr,
              dataSize > 0
        else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &dataSize, &ids) == noErr else {
            return []
        }

        return ids
            .filter(hasOutputStreams)
            .compactMap { id in
                guard let uid = stringProperty(kAudioDevicePropertyDeviceUID, of: id),
                      let name = stringProperty(kAudioObjectPropertyName, of: id),
                      !uid.isEmpty, !name.isEmpty
                else { return nil }
                return AudioOutputDevice(uid: uid, name: name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The device identifier to hand to `NSSound`, or `nil` for "let macOS
    /// decide" — which covers both the System Default sentinel and a remembered
    /// device that is currently unplugged.
    static func resolvePlaybackDevice(
        preferred: String,
        available: [AudioOutputDevice]
    ) -> String? {
        guard preferred != AudioOutputDevice.systemDefaultID,
              !preferred.isEmpty,
              available.contains(where: { $0.uid == preferred })
        else { return nil }
        return preferred
    }

    /// The device rows to offer in a picker, keeping `selected` representable
    /// even when that device has gone away.
    static func pickerOptions(
        available: [AudioOutputDevice],
        selected: String
    ) -> [AudioOutputDevice] {
        guard selected != AudioOutputDevice.systemDefaultID,
              !selected.isEmpty,
              !available.contains(where: { $0.uid == selected })
        else { return available }
        return available + [AudioOutputDevice(uid: selected, name: unavailableName)]
    }

    // MARK: - CoreAudio plumbing

    private static func hasOutputStreams(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(device, &address, 0, nil, &dataSize)
        return status == noErr && dataSize > 0
    }

    private static func stringProperty(
        _ selector: AudioObjectPropertySelector,
        of device: AudioDeviceID
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(device, &address, 0, nil, &dataSize, pointer)
        }
        guard status == noErr, let value else { return nil }
        return value as String
    }
}

/// Keeps a live list of output devices for SwiftUI, refreshing on hot-plug so
/// the Preferences pickers update while the window is open.
@MainActor
final class AudioOutputDeviceMonitor: ObservableObject {
    @Published private(set) var devices: [AudioOutputDevice] = AudioOutputDevices.current()

    private var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private var listener: AudioObjectPropertyListenerBlock?

    init() {
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            // The block is dispatched on the main queue, but CoreAudio can't
            // know that, so hop explicitly to satisfy the isolation checker.
            Task { @MainActor [weak self] in
                self?.devices = AudioOutputDevices.current()
            }
        }
        listener = block
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block
        )
    }

    deinit {
        guard let listener else { return }
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, listener
        )
    }
}
