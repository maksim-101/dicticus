import AVFoundation
import AudioToolbox
import CoreAudio

/// Input-device rules for `TranscriptionService` (quick tasks 261018-go0 and 261019-87x).
///
/// The pure rules are separated from CoreAudio so they are testable without hardware.
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

    /// The device a dictation records from: the system default input at key-down, whatever its
    /// transport; otherwise the first input-capable device in list order; nil leaves the audio unit
    /// alone. `holdAction` then keeps the hold on this device.
    static func select(from candidates: [Candidate], systemDefault: AudioDeviceID?) -> AudioDeviceID? {
        if let systemDefault, candidates.contains(where: { $0.id == systemDefault && $0.hasInput }) {
            return systemDefault
        }
        return candidates.first(where: { $0.hasInput })?.id
    }

    /// What to do when the default input or the engine's input unit changes during a hold.
    /// "Gone" is checked before "unit already on the press device": a unit that still reports a
    /// vanished device is mid-migration, and the follow case must be recognised there too.
    static func holdAction(pressDevice: AudioDeviceID, candidates: [Candidate], unitDevice: AudioDeviceID?) -> HoldAction {
        guard candidates.contains(where: { $0.id == pressDevice && $0.hasInput }) else { return .follow }
        return unitDevice == pressDevice ? .none : .repin(pressDevice)
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
