import AVFoundation
import AudioToolbox
import CoreAudio

/// Input-device rules for `TranscriptionService` (quick tasks 261018-go0 and 261019-87x).
///
/// Three rules: the device at key-down (`select`: the system default at that moment), the device after a
/// mid-hold engine stop (`restartDevice`: the press device while it exists, else the system default), and
/// one sample rate per hold (`SegmentResampler`).
/// The pure rules are separated from CoreAudio so they are testable without hardware.
enum AudioInputDevice {

    struct Candidate: Equatable, Sendable {
        let id: AudioDeviceID
        let name: String
        let transportType: UInt32
        let hasInput: Bool
    }

    /// The device a dictation records from: the system default input at key-down, whatever its
    /// transport; otherwise the first input-capable device in list order; nil leaves the audio unit
    /// alone. `restartDevice` keeps a restarted hold on this device while it exists.
    static func select(from candidates: [Candidate], systemDefault: AudioDeviceID?) -> AudioDeviceID? {
        if let systemDefault, candidates.contains(where: { $0.id == systemDefault && $0.hasInput }) {
            return systemDefault
        }
        return candidates.first(where: { $0.hasInput })?.id
    }

    /// The device a hold restarts on after its engine stopped mid-hold (owner decision 2026-10-19,
    /// 261019-87x plan 02): the microphone the hold started with while it is listed, alive and has input,
    /// otherwise the system default, otherwise the first input device. nil leaves the unit alone.
    static func restartDevice(pressDevice: AudioDeviceID?, candidates: [Candidate], systemDefault: AudioDeviceID?) -> AudioDeviceID? {
        if let pressDevice, candidates.contains(where: { $0.id == pressDevice && $0.hasInput }) {
            return pressDevice
        }
        return select(from: candidates, systemDefault: systemDefault)
    }

    /// Tap format built from the hardware-side rate. AVFAudio raises an NSException, not an NSError,
    /// when the tap's rate differs from the hardware's; the Swift catch in HotkeyManager cannot see
    /// it, so an unusable format must be rejected here, before `installTap`.
    static func tapFormat(sampleRate: Double, channelCount: AVAudioChannelCount) throws -> AVAudioFormat {
        guard channelCount > 0, sampleRate > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channelCount)
        else { throw TranscriptionError.inputUnavailable }
        return format
    }

    /// AVFAudio refuses a tap whose rate differs from the hardware's (261018-go0), so a restarted segment
    /// on a device with another rate is converted here to the press-time rate. That keeps one rate per
    /// hold for `transcribe`, its duration guard and `LivePreviewDecoder`. One converter lives for the whole
    /// segment: its filter state carries across tap buffers, while a converter per buffer would click at every
    /// seam. The last few frames still inside the converter at the end of a segment (about a millisecond)
    /// are not flushed.
    final class SegmentResampler: @unchecked Sendable {
        private let converter: AVAudioConverter
        private let inputFormat: AVAudioFormat
        private let outputFormat: AVAudioFormat
        private let ratio: Double
        private let sourceRate: Double
        private let targetRate: Double

        init?(from sourceRate: Double, to targetRate: Double) {
            guard sourceRate > 0, targetRate > 0,
                  let source = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sourceRate, channels: 1, interleaved: false),
                  let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: targetRate, channels: 1, interleaved: false),
                  let converter = AVAudioConverter(from: source, to: target)
            else { return nil }
            self.converter = converter
            self.inputFormat = source
            self.outputFormat = target
            self.ratio = targetRate / sourceRate
            self.sourceRate = sourceRate
            self.targetRate = targetRate
        }

        func convert(_ samples: [Float]) -> [Float] {
            guard !samples.isEmpty else { return [] }
            let outputCapacity = AVAudioFrameCount((Double(samples.count) * ratio).rounded(.up)) + 64
            guard let source = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(samples.count)),
                  let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputCapacity),
                  let sourceData = source.floatChannelData?[0]
            else { return TranscriptionService.resampleLinear(samples, from: sourceRate, to: targetRate) }
            samples.withUnsafeBufferPointer { sourceData.update(from: $0.baseAddress!, count: samples.count) }
            source.frameLength = AVAudioFrameCount(samples.count)

            var supplied = false
            var conversionError: NSError?
            // noDataNow, not endOfStream: endOfStream would flush the converter and reset it on every tap buffer.
            let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
                if supplied {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                supplied = true
                outStatus.pointee = .haveData
                return source
            }
            guard status != .error, conversionError == nil, let outputData = output.floatChannelData?[0] else {
                return TranscriptionService.resampleLinear(samples, from: sourceRate, to: targetRate)
            }
            return Array(UnsafeBufferPointer(start: outputData, count: Int(output.frameLength)))
        }
    }

    // MARK: - CoreAudio (not unit-tested)

    static func inputCandidates(includeNames: Bool = true) -> [Candidate] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr,
              size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else {
            return []
        }
        return ids.map { id in
            Candidate(id: id, name: includeNames ? deviceName(id) : "", transportType: transportType(id),
                      hasInput: hasInputStreams(id) && isAlive(id))
        }
    }

    static func systemDefaultInput() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return status == noErr && id != AudioDeviceID(kAudioObjectUnknown) ? id : nil
    }

    static func currentDevice(of unit: AudioUnit) -> AudioDeviceID? {
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, &size)
        return status == noErr && id != AudioDeviceID(kAudioObjectUnknown) ? id : nil
    }

    static func setCurrentDevice(_ id: AudioDeviceID, on unit: AudioUnit) -> OSStatus {
        var device = id
        return AudioUnitSetProperty(
            unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
            &device, UInt32(MemoryLayout<AudioDeviceID>.size))
    }

    /// A failed read counts as alive, so an unreadable property never hides a working microphone.
    private static func isAlive(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 1
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
        return !(status == noErr && value == 0)
    }

    private static func hasInputStreams(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func transportType(_ id: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
        return status == noErr ? value : kAudioDeviceTransportTypeUnknown
    }

    static func deviceName(_ id: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name)
        guard status == noErr, let resolved = name?.takeRetainedValue() else { return "unknown" }
        return resolved as String
    }

    private static func defaultInputAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
    }

    /// The queue is fixed to main because the handler hops to the main actor with
    /// `MainActor.assumeIsolated`; under Swift 6 a main-actor closure run on any other queue traps
    /// (see the AudioSampleBuffer doc comment).
    static func addDefaultInputListener(_ block: @escaping AudioObjectPropertyListenerBlock) -> OSStatus {
        var address = defaultInputAddress()
        return AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
    }

    static func removeDefaultInputListener(_ block: @escaping AudioObjectPropertyListenerBlock) -> OSStatus {
        var address = defaultInputAddress()
        return AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
    }
}
