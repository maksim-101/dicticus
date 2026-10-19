import AVFoundation
import AudioToolbox
import CoreAudio

/// Input-device selection and tap-format rules for `TranscriptionService` (quick task 261018-go0).
///
/// The two pure rules are separated from CoreAudio so they are testable without hardware.
enum AudioInputDevice {

    struct Candidate: Equatable, Sendable {
        let id: AudioDeviceID
        let name: String
        let transportType: UInt32
        let hasInput: Bool
    }

    enum HoldAction: Equatable, Sendable {
        case none
        case repin(AudioDeviceID)
        case follow
    }

    /// RED stub (build 17 behaviour: nothing re-asserts the press device).
    static func holdAction(pressDevice: AudioDeviceID, candidates: [Candidate], unitDevice: AudioDeviceID?) -> HoldAction {
        .none
    }

    /// The device the engine's input unit should use. Prefers a built-in input so that a headset,
    /// Continuity or virtual device becoming the system default cannot reconfigure a dictation
    /// mid-hold; falls back to the system default when the Mac has no built-in input (nil leaves
    /// the audio unit alone).
    static func select(from candidates: [Candidate], systemDefault: AudioDeviceID?) -> AudioDeviceID? {
        let builtInInput = { (id: AudioDeviceID) -> Bool in
            candidates.contains { $0.id == id && $0.hasInput && $0.transportType == kAudioDeviceTransportTypeBuiltIn }
        }
        if let systemDefault, builtInInput(systemDefault) { return systemDefault }
        if let first = candidates.first(where: { $0.hasInput && $0.transportType == kAudioDeviceTransportTypeBuiltIn }) {
            return first.id
        }
        return systemDefault
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

    // MARK: - CoreAudio (not unit-tested)

    static func inputCandidates() -> [Candidate] {
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
            Candidate(id: id, name: deviceName(id), transportType: transportType(id), hasInput: hasInputStreams(id))
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

    private static func deviceName(_ id: AudioDeviceID) -> String {
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
}
