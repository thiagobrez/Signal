import XCTest

/// Covers the pure parts of the output-device preference: which UID playback
/// should use for a stored selection, and which rows the picker offers. The
/// CoreAudio enumeration itself depends on the machine's hardware, so it's only
/// checked for internal consistency.
final class AudioOutputDevicesTests: XCTestCase {
    private let speakers = AudioOutputDevice(uid: "BuiltInSpeakerDevice", name: "MacBook Speakers")
    private let headphones = AudioOutputDevice(uid: "AirPodsUID", name: "AirPods")

    private var available: [AudioOutputDevice] { [headphones, speakers] }

    // MARK: - resolvePlaybackDevice

    func testSystemDefaultResolvesToNoExplicitDevice() {
        XCTAssertNil(
            AudioOutputDevices.resolvePlaybackDevice(
                preferred: AudioOutputDevice.systemDefaultID, available: available
            )
        )
    }

    func testEmptySelectionResolvesToNoExplicitDevice() {
        XCTAssertNil(
            AudioOutputDevices.resolvePlaybackDevice(preferred: "", available: available)
        )
    }

    func testConnectedDeviceResolvesToItsUID() {
        XCTAssertEqual(
            AudioOutputDevices.resolvePlaybackDevice(
                preferred: speakers.uid, available: available
            ),
            speakers.uid
        )
    }

    func testDisconnectedDeviceFallsBackToSystemDefault() {
        XCTAssertNil(
            AudioOutputDevices.resolvePlaybackDevice(
                preferred: "GoneUID", available: available
            )
        )
    }

    // MARK: - pickerOptions

    func testPickerOptionsPassAvailableDevicesThrough() {
        let options = AudioOutputDevices.pickerOptions(
            available: available, selected: speakers.uid
        )
        XCTAssertEqual(options.map(\.uid), available.map(\.uid))
    }

    func testPickerOptionsAppendPlaceholderForMissingSelection() {
        let options = AudioOutputDevices.pickerOptions(available: available, selected: "GoneUID")
        XCTAssertEqual(options.count, available.count + 1)
        XCTAssertEqual(options.last?.uid, "GoneUID")
        XCTAssertEqual(options.last?.name, AudioOutputDevices.unavailableName)
    }

    func testPickerOptionsAddNoPlaceholderForSystemDefault() {
        let options = AudioOutputDevices.pickerOptions(
            available: available, selected: AudioOutputDevice.systemDefaultID
        )
        XCTAssertEqual(options.map(\.uid), available.map(\.uid))
    }

    func testPickerOptionsAddNoPlaceholderForEmptySelection() {
        let options = AudioOutputDevices.pickerOptions(available: available, selected: "")
        XCTAssertEqual(options.map(\.uid), available.map(\.uid))
    }

    // MARK: - Live enumeration

    /// Whatever this machine reports, the list has to be usable as picker rows:
    /// no blanks, no duplicate tags. The list itself may legitimately be empty
    /// on a headless CI runner, so its size isn't asserted.
    func testCurrentDevicesHaveUniqueNonEmptyUIDs() {
        let devices = AudioOutputDevices.current()
        for device in devices {
            XCTAssertFalse(device.uid.isEmpty)
            XCTAssertFalse(device.name.isEmpty)
        }
        XCTAssertEqual(Set(devices.map(\.uid)).count, devices.count)
    }

    // MARK: - SoundPlayer

    func testPlayIsNoOpForNoneWithADeviceSelected() {
        SoundPlayer.play(SoundPlayer.noneID, on: speakers.uid)
        SoundPlayer.play("", on: speakers.uid)
    }
}
