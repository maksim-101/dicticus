import CoreAudio
import Foundation

/// A single bounded (~250ms) measurement of the system output's audio level,
/// via a CoreAudio private process tap (quick 260725-og7). Replaces the dead
/// `kAudioDevicePropertyDeviceIsRunningSomewhere` press-side gate in
/// `MediaController`, which stays `true` through confirmed silence (spike 003
/// step 3) — this samples the actual output signal and computes RMS instead.
///
/// Pipeline (macOS 14.2+ API; app targets macOS 15, no `@available` guard
/// needed): translate our own PID to an `AudioObjectID` so the tap excludes
/// Dicticus's own output -> a mono, global, exclude-self `CATapDescription`
/// (`privateTap = true`, `muteBehavior = .unmuted` so the user's playback is
/// never audibly interrupted by the sample) -> `AudioHardwareCreateProcessTap`
/// -> a private aggregate device carrying that tap -> an IOProc collecting
/// ~100ms of Float32 samples -> RMS = sqrt(sumOfSquares / frameCount).
///
/// Every non-`"sampled"` outcome returns `rms == nil` and the whole call is
/// bounded to ~250ms — a failed/denied/absent tap must never crash or block
/// dictation start. Every resource (IOProc, aggregate device, tap) is torn
/// down via `defer` on every return path, success or failure.
final class OutputLevelSampler {

    /// `"sampled"` | `"denied"` | `"failed"` | `"timeout"` — `rms` is non-nil
    /// only for `"sampled"`.
    typealias Status = String

    private static let sampleWindowSeconds: TimeInterval = 0.1
    private static let boundTimeoutSeconds: TimeInterval = 0.25

    /// Accumulates sum-of-squares + frame count across IOProc callbacks
    /// (invoked on a CoreAudio realtime thread), lock-protected since the
    /// sampling window is short (~100ms) and this is not a sustained
    /// real-time audio path.
    private final class RMSAccumulator: @unchecked Sendable {
        private let lock = NSLock()
        private var sumOfSquares: Double = 0
        private var frameCount: Int = 0
        private var startTime: DispatchTime?

        func accumulate(_ bufferList: UnsafePointer<AudioBufferList>) {
            lock.lock()
            defer { lock.unlock() }
            if startTime == nil { startTime = DispatchTime.now() }
            let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
            for buffer in abl {
                guard let data = buffer.mData else { continue }
                let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                guard count > 0 else { continue }
                let floatPtr = data.bindMemory(to: Float.self, capacity: count)
                for i in 0..<count {
                    let sample = Double(floatPtr[i])
                    sumOfSquares += sample * sample
                }
                frameCount += count
            }
        }

        func elapsedSeconds() -> TimeInterval {
            lock.lock()
            defer { lock.unlock() }
            guard let start = startTime else { return 0 }
            return Double(DispatchTime.now().uptimeNanoseconds &- start.uptimeNanoseconds) / 1_000_000_000
        }

        func rms() -> Double? {
            lock.lock()
            defer { lock.unlock() }
            guard frameCount > 0 else { return nil }
            return (sumOfSquares / Double(frameCount)).squareRoot()
        }
    }

    /// Translate our own PID to its `AudioObjectID` process object via the
    /// global `kAudioHardwarePropertyTranslatePIDToProcessObject` property
    /// (PID passed as the qualifier, per SDK doc). `kAudioObjectUnknown`
    /// (no error) means the translation itself failed to resolve.
    private func translateSelfProcessObject() -> AudioObjectID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var pid = getpid()
        var procID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr,
            UInt32(MemoryLayout<pid_t>.size), &pid, &size, &procID)
        guard status == noErr, procID != kAudioObjectUnknown else { return nil }
        return procID
    }

    /// Perform one bounded (~250ms) system-output RMS sample. `rms` is
    /// non-nil only when `status == "sampled"`. Never crashes; every
    /// resource is torn down on every return path.
    func sample() -> (rms: Double?, status: Status) {
        guard let selfProcessID = translateSelfProcessObject() else {
            return (nil, "failed")
        }

        let description = CATapDescription(monoGlobalTapButExcludeProcesses: [selfProcessID])
        description.name = "Dicticus Output Level Sampler"
        description.uuid = UUID()
        description.isPrivate = true
        // CATapUnmuted (the SDK default): audio is captured by the tap AND
        // still sent to the hardware — the user's playback is never
        // interrupted by this sample. CATapMuted would silence it.
        description.muteBehavior = .unmuted

        var tapID = AudioObjectID(kAudioObjectUnknown)
        let createTapStatus = AudioHardwareCreateProcessTap(description, &tapID)
        guard createTapStatus == noErr else {
            // The SDK exposes no dedicated "TCC denied" constant for this
            // API; kAudioHardwareIllegalOperationError ('nope') is the best
            // available discriminator for a permission-denied tap creation.
            // Behaviorally both map to "not playing" (tier-2b + mute OFF) —
            // this split only affects the calibration log field.
            let deniedStatus = createTapStatus == kAudioHardwareIllegalOperationError
            return (nil, deniedStatus ? "denied" : "failed")
        }
        defer { AudioHardwareDestroyProcessTap(tapID) }

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceNameKey: "Dicticus Output Level Aggregate",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: description.uuid.uuidString]
            ]
        ]
        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        let createAggregateStatus = AudioHardwareCreateAggregateDevice(
            aggregateDescription as CFDictionary, &aggregateID)
        guard createAggregateStatus == noErr else {
            return (nil, "failed")
        }
        defer { AudioHardwareDestroyAggregateDevice(aggregateID) }

        let accumulator = RMSAccumulator()
        let semaphore = DispatchSemaphore(value: 0)

        var ioProcID: AudioDeviceIOProcID?
        let createIOProcStatus = AudioDeviceCreateIOProcIDWithBlock(
            &ioProcID, aggregateID, nil
        ) { _, inInputData, _, _, _ in
            accumulator.accumulate(inInputData)
            if accumulator.elapsedSeconds() >= Self.sampleWindowSeconds {
                semaphore.signal()
            }
        }
        guard createIOProcStatus == noErr, let ioProcID else {
            return (nil, "failed")
        }
        defer {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }

        let startStatus = AudioDeviceStart(aggregateID, ioProcID)
        guard startStatus == noErr else {
            return (nil, "failed")
        }

        let waitResult = semaphore.wait(timeout: .now() + Self.boundTimeoutSeconds)
        guard waitResult == .success, let rms = accumulator.rms() else {
            return (nil, "timeout")
        }
        return (rms, "sampled")
    }
}
