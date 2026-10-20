import XCTest
import AVFoundation
import CoreAudio
@testable import Dicticus

/// Quick tasks 261018-go0 and 261019-87x: the pure rules behind the input a dictation records from.
/// Three rules: the device at key-down (`select`: the system default at that moment), the device after a
/// mid-hold engine stop (`restartDevice`: the press device while it exists, else the system default), and
/// one sample rate per hold (`SegmentResampler` converts a restarted segment to the press-time rate).
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

    func testRestartKeepsPressDeviceWhilePresent() {
        XCTAssertEqual(AudioInputDevice.restartDevice(pressDevice: 1, candidates: [builtIn, headset],
                                                      systemDefault: 2), 1)
    }

    func testRestartFollowsDefaultWhenPressDeviceGone() {
        XCTAssertEqual(AudioInputDevice.restartDevice(pressDevice: 2, candidates: [builtIn, usbMic],
                                                      systemDefault: 4), 4)
    }

    func testRestartFollowsDefaultWhenPressDeviceLostInput() {
        let inputless = Candidate(id: 2, name: "Headset",
                                  transportType: kAudioDeviceTransportTypeBluetooth, hasInput: false)
        XCTAssertEqual(AudioInputDevice.restartDevice(pressDevice: 2, candidates: [builtIn, inputless],
                                                      systemDefault: 1), 1)
    }

    func testRestartFallsBackToFirstInputWithoutDefault() {
        XCTAssertEqual(AudioInputDevice.restartDevice(pressDevice: 2, candidates: [usbMic, builtIn],
                                                      systemDefault: nil), 4)
    }

    func testRestartWithoutPressDeviceUsesDefault() {
        XCTAssertEqual(AudioInputDevice.restartDevice(pressDevice: nil, candidates: [builtIn, headset],
                                                      systemDefault: 2), 2)
    }

    func testRestartWithoutInputSelectsNothing() {
        XCTAssertNil(AudioInputDevice.restartDevice(pressDevice: 2, candidates: [], systemDefault: nil))
    }

    // MARK: - restartDevice with skipPress

    private let waveLink = Candidate(id: 5, name: "Wave Link",
                                     transportType: kAudioDeviceTransportTypeVirtual, hasInput: true)
    private let bluetoothLE = Candidate(id: 8, name: "LE Headset",
                                        transportType: kAudioDeviceTransportTypeBluetoothLE, hasInput: true)

    func testSkippedPressDeviceStillDefaultFallsBackToBuiltIn() {
        XCTAssertEqual(AudioInputDevice.restartDevice(pressDevice: 2, candidates: [usbMic, headset, builtIn],
                                                      systemDefault: 2, skipPress: true), 1)
    }

    func testSkippedPressDeviceFollowsDefaultMovedElsewhere() {
        XCTAssertEqual(AudioInputDevice.restartDevice(pressDevice: 2, candidates: [builtIn, headset, waveLink],
                                                      systemDefault: 5, skipPress: true), 5)
    }

    func testSkippedPressDeviceWithoutBuiltInUsesFirstOtherInput() {
        XCTAssertEqual(AudioInputDevice.restartDevice(pressDevice: 2, candidates: [headset, usbMic, waveLink],
                                                      systemDefault: 2, skipPress: true), 4)
    }

    func testSkippedPressDeviceAloneSelectsNothing() {
        XCTAssertNil(AudioInputDevice.restartDevice(pressDevice: 2, candidates: [headset],
                                                    systemDefault: 2, skipPress: true))
    }

    func testSkippedPressDeviceIgnoresDefaultWithoutInput() {
        let output = Candidate(id: 7, name: "USB Output",
                               transportType: kAudioDeviceTransportTypeUSB, hasInput: false)
        XCTAssertEqual(AudioInputDevice.restartDevice(pressDevice: 2, candidates: [output, headset, builtIn],
                                                      systemDefault: 7, skipPress: true), 1)
    }

    func testNotSkippedPressDeviceKeepsPressRule() {
        XCTAssertEqual(AudioInputDevice.restartDevice(pressDevice: 2, candidates: [builtIn, headset],
                                                      systemDefault: 1, skipPress: false), 2)
    }

    // MARK: - shouldSkipPress

    func testBluetoothPressWithDefaultChangeIsSkipped() {
        XCTAssertTrue(AudioInputDevice.shouldSkipPress(pressDevice: 2, candidates: [builtIn, headset],
                                                       defaultChangedDuringHold: true))
    }

    func testBluetoothLEPressWithDefaultChangeIsSkipped() {
        XCTAssertTrue(AudioInputDevice.shouldSkipPress(pressDevice: 8, candidates: [builtIn, bluetoothLE],
                                                       defaultChangedDuringHold: true))
    }

    func testBluetoothPressWithoutDefaultChangeIsKept() {
        XCTAssertFalse(AudioInputDevice.shouldSkipPress(pressDevice: 2, candidates: [builtIn, headset],
                                                        defaultChangedDuringHold: false))
    }

    func testNonBluetoothPressWithDefaultChangeIsKept() {
        for press in [builtIn, usbMic, waveLink, aggregate] {
            XCTAssertFalse(AudioInputDevice.shouldSkipPress(pressDevice: press.id, candidates: [press, headset],
                                                            defaultChangedDuringHold: true), press.name)
        }
    }

    func testUnlistedPressDeviceIsNotSkipped() {
        XCTAssertFalse(AudioInputDevice.shouldSkipPress(pressDevice: 2, candidates: [builtIn],
                                                        defaultChangedDuringHold: true))
        XCTAssertFalse(AudioInputDevice.shouldSkipPress(pressDevice: nil, candidates: [builtIn, headset],
                                                        defaultChangedDuringHold: true))
    }

    // MARK: - isStarved

    func testStarvationAfterAudioStartsAtFiveHundredMs() {
        XCTAssertFalse(AudioInputDevice.isStarved(msSinceProgress: 499, segmentHasAudio: true))
        XCTAssertTrue(AudioInputDevice.isStarved(msSinceProgress: 500, segmentHasAudio: true))
    }

    func testStarvationBeforeAudioStartsAtFifteenHundredMs() {
        XCTAssertFalse(AudioInputDevice.isStarved(msSinceProgress: 1499, segmentHasAudio: false))
        XCTAssertTrue(AudioInputDevice.isStarved(msSinceProgress: 1500, segmentHasAudio: false))
    }

    // MARK: - SegmentResampler

    private func sine(rate: Double, seconds: Double, frequency: Double = 440) -> [Float] {
        (0..<Int(rate * seconds)).map { Float(sin(2 * Double.pi * frequency * Double($0) / rate)) }
    }

    private func zeroCrossings(_ samples: [Float]) -> Int {
        var count = 0
        for i in 1..<samples.count where (samples[i - 1] < 0) != (samples[i] < 0) { count += 1 }
        return count
    }

    private func convertInChunks(_ samples: [Float], from source: Double, to target: Double) throws -> [Float] {
        let resampler = try XCTUnwrap(AudioInputDevice.SegmentResampler(from: source, to: target))
        var out: [Float] = []
        var start = 0
        while start < samples.count {
            let end = min(start + 4096, samples.count)
            out += resampler.convert(Array(samples[start..<end]))
            start = end
        }
        return out
    }

    func testResamplerUpconvertsTwentyFourToFortyEightKilohertz() throws {
        let out = try convertInChunks(sine(rate: 24000, seconds: 2), from: 24000, to: 48000)
        XCTAssertEqual(Double(out.count), 96000, accuracy: 960)
        let frequency = Double(zeroCrossings(out)) / 2 / (Double(out.count) / 48000)
        XCTAssertEqual(frequency, 440, accuracy: 440 * 0.02)
    }

    func testResamplerDownconvertsFortyEightToTwentyFourKilohertz() throws {
        let out = try convertInChunks(sine(rate: 48000, seconds: 2), from: 48000, to: 24000)
        XCTAssertEqual(Double(out.count), 48000, accuracy: 480)
        let frequency = Double(zeroCrossings(out)) / 2 / (Double(out.count) / 24000)
        XCTAssertEqual(frequency, 440, accuracy: 440 * 0.02)
    }

    func testMixedRateHoldDurationAtPressRate() throws {
        let buffer = AudioSampleBuffer()
        buffer.append(sine(rate: 24000, seconds: 1))
        buffer.append(try convertInChunks(sine(rate: 48000, seconds: 2), from: 48000, to: 24000))
        XCTAssertEqual(Double(buffer.count) / 24000, 3.0, accuracy: 0.03)
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
