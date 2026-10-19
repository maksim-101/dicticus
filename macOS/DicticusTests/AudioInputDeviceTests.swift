import XCTest
import AVFoundation
import CoreAudio
@testable import Dicticus

/// Quick tasks 261018-go0 and 261019-87x: the pure rules behind the input a dictation records from.
/// The hold records from the system default input at key-down (`select`); `holdAction` decides whether
/// a mid-hold change keeps that device (re-pin) or follows the new default because it vanished.
/// The tap format is built from a validated hardware format.
final class AudioInputDeviceTests: XCTestCase {

    private typealias Candidate = AudioInputDevice.Candidate

    private let builtIn = Candidate(id: 1, name: "Built-in Microphone",
                                    transportType: kAudioDeviceTransportTypeBuiltIn, hasInput: true)
    private let headset = Candidate(id: 2, name: "Headset",
                                    transportType: kAudioDeviceTransportTypeBluetooth, hasInput: true)
    private let usbMic = Candidate(id: 4, name: "USB Microphone",
                                   transportType: kAudioDeviceTransportTypeUSB, hasInput: true)
    private let aggregate = Candidate(id: 9, name: "Aggregate Device",
                                      transportType: kAudioDeviceTransportTypeAggregate, hasInput: true)

    func testBluetoothDefaultIsKept() {
        XCTAssertEqual(AudioInputDevice.select(from: [headset, builtIn], systemDefault: 2), 2)
    }

    func testVirtualDefaultIsKept() {
        let virtual = Candidate(id: 6, name: "Virtual Device",
                                transportType: kAudioDeviceTransportTypeVirtual, hasInput: true)
        XCTAssertEqual(AudioInputDevice.select(from: [virtual, builtIn], systemDefault: 6), 6)
    }

    func testBuiltInDefaultIsKept() {
        let second = Candidate(id: 3, name: "Display Microphone",
                               transportType: kAudioDeviceTransportTypeBuiltIn, hasInput: true)
        XCTAssertEqual(AudioInputDevice.select(from: [builtIn, second], systemDefault: 3), 3)
    }

    func testOutputOnlyDefaultFallsBackToFirstInput() {
        let output = Candidate(id: 7, name: "USB Output",
                               transportType: kAudioDeviceTransportTypeUSB, hasInput: false)
        XCTAssertEqual(AudioInputDevice.select(from: [output, usbMic, builtIn], systemDefault: 7), 4)
    }

    func testNoDefaultFallsBackToFirstInput() {
        XCTAssertEqual(AudioInputDevice.select(from: [usbMic, builtIn], systemDefault: nil), 4)
    }

    func testEmptyListWithoutDefaultSelectsNothing() {
        XCTAssertNil(AudioInputDevice.select(from: [], systemDefault: nil))
    }

    func testHoldKeepsUnitOnPressDevice() {
        XCTAssertEqual(AudioInputDevice.holdAction(pressDevice: 1, candidates: [builtIn, headset], unitDevice: 1),
                       AudioInputDevice.HoldAction.none)
    }

    func testHoldRepinsWhenEngineMovedUnit() {
        XCTAssertEqual(AudioInputDevice.holdAction(pressDevice: 1, candidates: [builtIn, headset, aggregate],
                                                   unitDevice: 9),
                       AudioInputDevice.HoldAction.repin(1))
    }

    func testHoldRepinsWhenUnitDeviceUnreadable() {
        XCTAssertEqual(AudioInputDevice.holdAction(pressDevice: 1, candidates: [builtIn, headset], unitDevice: nil),
                       AudioInputDevice.HoldAction.repin(1))
    }

    func testHoldFollowsWhenPressDeviceGone() {
        XCTAssertEqual(AudioInputDevice.holdAction(pressDevice: 2, candidates: [builtIn, aggregate], unitDevice: 9),
                       AudioInputDevice.HoldAction.follow)
    }

    func testHoldFollowsWhenUnitStillReportsVanishedDevice() {
        XCTAssertEqual(AudioInputDevice.holdAction(pressDevice: 2, candidates: [builtIn], unitDevice: 2),
                       AudioInputDevice.HoldAction.follow)
    }

    func testHoldFollowsWhenPressDeviceLostInput() {
        let inputless = Candidate(id: 2, name: "Headset",
                                  transportType: kAudioDeviceTransportTypeBluetooth, hasInput: false)
        XCTAssertEqual(AudioInputDevice.holdAction(pressDevice: 2, candidates: [builtIn, inputless], unitDevice: 1),
                       AudioInputDevice.HoldAction.follow)
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
