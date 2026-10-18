import XCTest
import AVFoundation
import CoreAudio
@testable import Dicticus

/// Quick task 261018-go0: the pure rules behind pinning the engine to the built-in microphone
/// and building the tap from a validated hardware format.
final class AudioInputDeviceTests: XCTestCase {

    private typealias Candidate = AudioInputDevice.Candidate

    private let builtIn = Candidate(id: 1, name: "Built-in Microphone",
                                    transportType: kAudioDeviceTransportTypeBuiltIn, hasInput: true)
    private let headset = Candidate(id: 2, name: "Headset",
                                    transportType: kAudioDeviceTransportTypeBluetooth, hasInput: true)

    func testBluetoothDefaultSelectsBuiltIn() {
        XCTAssertEqual(AudioInputDevice.select(from: [headset, builtIn], systemDefault: 2), 1)
    }

    func testBuiltInDefaultAmongBuiltInsIsKept() {
        let second = Candidate(id: 3, name: "Studio Display Microphone",
                               transportType: kAudioDeviceTransportTypeBuiltIn, hasInput: true)
        XCTAssertEqual(AudioInputDevice.select(from: [builtIn, second], systemDefault: 3), 3)
    }

    func testOutputOnlyBuiltInFallsBackToSystemDefault() {
        let speakers = Candidate(id: 1, name: "Speakers",
                                 transportType: kAudioDeviceTransportTypeBuiltIn, hasInput: false)
        let usb = Candidate(id: 4, name: "USB Microphone",
                            transportType: kAudioDeviceTransportTypeUSB, hasInput: true)
        XCTAssertEqual(AudioInputDevice.select(from: [speakers, usb], systemDefault: 4), 4)
    }

    func testContinuityAndVirtualDefaultsSelectBuiltIn() {
        let continuity = Candidate(id: 5, name: "Phone Camera Microphone",
                                   transportType: kAudioDeviceTransportTypeContinuityCaptureWireless, hasInput: true)
        let virtual = Candidate(id: 6, name: "Virtual Device",
                                transportType: kAudioDeviceTransportTypeVirtual, hasInput: true)
        XCTAssertEqual(AudioInputDevice.select(from: [continuity, virtual, builtIn], systemDefault: 5), 1)
    }

    func testEmptyListWithoutDefaultSelectsNothing() {
        XCTAssertNil(AudioInputDevice.select(from: [], systemDefault: nil))
    }

    func testTapFormatKeepsHardwareRateAndChannels() throws {
        let format = try AudioInputDevice.tapFormat(sampleRate: 24000, channelCount: 1)
        XCTAssertEqual(format.sampleRate, 24000)
        XCTAssertEqual(format.channelCount, 1)
        XCTAssertEqual(format.commonFormat, .pcmFormatFloat32)
        XCTAssertFalse(format.isInterleaved)
    }

    func testTapFormatRejectsZeroChannels() {
        XCTAssertThrowsError(try AudioInputDevice.tapFormat(sampleRate: 48000, channelCount: 0)) {
            XCTAssertEqual($0 as? TranscriptionError, .inputUnavailable)
        }
    }

    func testTapFormatRejectsZeroSampleRate() {
        XCTAssertThrowsError(try AudioInputDevice.tapFormat(sampleRate: 0, channelCount: 1)) {
            XCTAssertEqual($0 as? TranscriptionError, .inputUnavailable)
        }
    }
}
