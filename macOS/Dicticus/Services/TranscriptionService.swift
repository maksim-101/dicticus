import SwiftUI
import Combine
import WhisperKit
@preconcurrency import AVFoundation
import NaturalLanguage
import os

private let audioLog = Logger(subsystem: "com.dicticus", category: "audio")

/// Errors thrown by TranscriptionService during the record-transcribe cycle.
enum TranscriptionError: Error, Sendable {
    /// Recording was shorter than minimumDurationSeconds (D-06 in 02-RESEARCH.md).
    case tooShort
    /// No voice activity detected — adaptive energy gate, no-speech-prob discard (D-10 in 02.1-RESEARCH.md), or every chunk of the decode dropped as a ship-list phantom (quick task 261008-gb2).
    case silenceOnly
    /// ASR engine returned no transcription results.
    case noResult
    /// ASR models not available (model not warmed up).
    case modelNotReady
    /// stopRecordingAndTranscribe() called when not recording.
    case notRecording
    /// startRecording() called while already recording or transcribing.
    case busy
    /// ASR output contains non-Latin script (Cyrillic, CJK, Arabic, etc.) — likely an
    /// ASR hallucination when the spoken language doesn't match model expectations.
    case unexpectedLanguage
    /// The input device reports zero channels or a zero sample rate after the pin, so no tap can be built.
    /// Thrown from startRecording() so HotkeyManager's existing catch posts recordingFailed instead of an
    /// NSException escaping installTap.
    case inputUnavailable
    /// The engine stopped during a hold, could not be restarted, and what was captured is under the minimum
    /// duration or decodes to nothing. Thrown from stopRecordingAndTranscribe() so the hold notifies instead
    /// of ending silently.
    case inputInterrupted
}

/// Thread-safe audio sample buffer for real-time AVAudioEngine tap callbacks.
/// Extracted as a standalone Sendable class so the tap closure doesn't inherit
/// @MainActor isolation from TranscriptionService — Swift 6 enforces actor
/// isolation on closures defined inside @MainActor methods even when self
/// isn't captured, causing a runtime crash on the audio thread.
final class AudioSampleBuffer: @unchecked Sendable {
    private var samples: [Float] = []
    private let lock = NSLock()

    func append(_ newSamples: [Float]) {
        lock.lock()
        samples.append(contentsOf: newSamples)
        lock.unlock()
    }

    func drain() -> [Float] {
        lock.lock()
        let result = samples
        samples.removeAll()
        lock.unlock()
        return result
    }

    func clear() {
        lock.lock()
        samples.removeAll()
        lock.unlock()
    }

    /// Non-destructive copy of the newest `maxSamples` samples. The lock is held for
    /// the one array copy only; callers resample after it is released.
    func snapshotTail(maxSamples: Int) -> [Float] {
        lock.lock()
        let result = Array(samples.suffix(max(0, maxSamples)))
        lock.unlock()
        return result
    }

    /// Non-destructive copy of every sample at or after `index`, with the buffer length at
    /// the moment of the copy. Both come from one critical section, so `end` is exactly
    /// where `samples` stops even while the audio thread keeps appending.
    func snapshot(from index: Int) -> (samples: [Float], end: Int) {
        lock.lock()
        let end = samples.count
        let result = index >= end ? [] : Array(samples[max(0, index)..<end])
        lock.unlock()
        return (result, end)
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return samples.count
    }
}

/// The engine handed to the restart task. The main actor never touches the engine while a restart runs:
/// `handleConfigurationChange` returns while `restartTask` is set and key-up awaits every pending restart,
/// so one context at a time owns it, the same contract as AudioSampleBuffer.
private struct CaptureEngine: @unchecked Sendable {
    let engine: AVAudioEngine
}

/// Result of one restart attempt (at most two tries), computed off the main actor.
private struct InputRestartOutcome: Sendable {
    let started: Bool
    let tries: Int
    let device: AudioDeviceID?
    let deviceName: String
    let converted: Bool
}

/// Core ASR pipeline: record audio via AVAudioEngine, apply silence-discard
/// checks, transcribe via WhisperKit large-v3-turbo, and detect language
/// post-hoc with NLLanguageRecognizer.
///
/// Silence defense (WHISP-03; see whisper-dictation-dropout debug session for
/// the two-cycle history — cycle 1 removed the fixed-threshold EnergyVAD
/// pre-filter that misclassified genuine speech as silence on some
/// microphones; cycle 2 reintroduced Layer 2 as an adaptive, clip-relative gate
/// after cycle 1's removal reopened D-09 silence-hallucination pastes):
///   1. Minimum duration guard: discard clips shorter than 0.3s (D-11 in 02.1-CONTEXT.md)
///   2. Adaptive voice-activity gate: discard if no frame's energy dwarfs the clip's own noise floor (AdaptiveVoiceGate)
///   3. Boilerplate-hallucination discard: discard a whole-utterance closed-list match, e.g. "Thank you." (BoilerplateHallucination, quick task 260827-81z); also a lone "you"/"and"/"-" when the clip is under 1.5 s or the gate found no voice (quick task 260930-s1g)
///   4. No-speech discard: discard if every segment's noSpeechProb exceeds threshold (NoSpeechDiscard, WHISP-03)
///   5. Near-silent short-clip discard: a clip under 2.5 s with at most 2 voiced frames is discarded after decode (AdaptiveVoiceGate.isNearSilentShortClip, quick task 261008-gb2)
///
/// Between the decode and the checks above, the per-chunk phantom drop (BoilerplateHallucination.chunkDropReasons, quick task 261008-gb2) removes a chunk of the decode that is only a ship-list phrase (when other chunks exist) or is tagged with a language other than German or English; the checks read the kept chunks only. When every chunk is removed the clip is a silent discard, or the "Unexpected language" notice when a language drop was the cause.
///
/// Consumes ModelWarmupService.whisperKitInstance directly.
/// Does NOT create its own WhisperKit instances outside of test support.
///
/// Phase 3 will call startRecording() on hotkey press and
/// stopRecordingAndTranscribe() on hotkey release.
@MainActor
class TranscriptionService: ObservableObject {

    // MARK: - State machine

    /// Pipeline state. Phase 3 observes this for UI feedback (e.g., pulsing icon during recording).
    enum State: Equatable, Sendable {
        case idle
        case recording
        case transcribing
    }

    @Published var state: State = .idle
    @Published var lastResult: DicticusTranscriptionResult?
    @Published var error: String?

    // MARK: - Configuration

    /// Legacy VAD probability threshold retained for API/test compatibility. The
    /// original EnergyVAD pre-filter that once consulted an energy-based threshold
    /// was removed 2026-07-05 (whisper-dictation-dropout debug session, cycle 1); its
    /// reintroduced replacement (AdaptiveVoiceGate, cycle 2) uses its own adaptive
    /// constants, not this value — this field is no longer consulted by the
    /// transcription pipeline at all.
    static let vadProbabilityThreshold: Float = 0.75

    /// Legacy silence threshold retained for API/test compatibility (see
    /// `vadProbabilityThreshold`). Not consulted by the current pipeline.
    var silenceThreshold: Float = TranscriptionService.vadProbabilityThreshold

    /// Minimum recording duration in seconds (D-11 in 02.1-CONTEXT.md).
    /// Sub-0.3s clips are noise or accidental key presses, not speech.
    let minimumDurationSeconds: Float = 0.3

    /// Phase 50 D-01: clips at/above this duration always proceed to WhisperKit
    /// (Layer 3), even when the Layer 2 adaptive gate reports no voice. This is
    /// an eligibility predicate, NOT a threshold — it never reintroduces a fixed
    /// absolute energy value; `AdaptiveVoiceGate`'s constants are untouched.
    ///
    /// Motivated by `discard-2026-09-09.jsonl` 08:16:05 / 08:16:32 / 08:25:52 /
    /// 08:26:19 / 09:43:56 — a low-gain input device whose speech peaked
    /// 0.0036-0.0059, under `AdaptiveVoiceGate.defaultAbsoluteFloor` (0.006) —
    /// and `discard-2026-09-10.jsonl` 05:17:23, where a noisy room raised the
    /// ratio threshold above a 4.5s clip's peak. Corpus gap: the longest genuine
    /// silent tap was 1.3s, the shortest wrongly discarded speech was 2.7s;
    /// this constant sits in that gap. Accepted risk: a long deliberately-silent
    /// hold may now decode a confident Whisper hallucination ("Thank you.") —
    /// visible and deletable, unlike speech lost silently before this change.
    /// Layer 3 (`BoilerplateHallucination`, `NoSpeechDiscard`, `noResult`) is
    /// the backstop for that case. See memory `project_whisper_adaptive_vad_fix`.
    nonisolated static let gateBypassDurationSeconds: Float = 2.0

    /// Phase 50 D-01: pure eligibility predicate for the Layer 2 guard. A clip
    /// proceeds to WhisperKit if the adaptive gate detected voice OR the clip's
    /// duration alone clears `gateBypassDurationSeconds` — the bypass only ever
    /// widens what reaches WhisperKit, never narrows it.
    nonisolated static func shouldProceedPastEnergyGate(voiceDetected: Bool, durationSeconds: Float) -> Bool {
        voiceDetected || durationSeconds >= gateBypassDurationSeconds
    }

    // MARK: - Private

    private let whisperKit: WhisperKit
    /// Each input device's recent speaking level, read for the Layer 2 gate's absolute floor.
    private let voiceLevels: InputVoiceLevelStore
    private let audioEngine = AVAudioEngine()
    /// Thread-safe buffer for audio samples — see AudioSampleBuffer doc comment.
    private let sampleBuffer = AudioSampleBuffer()
    /// Target sample rate for WhisperKit (16kHz mono).
    private let sampleRate: Double = 16000

    /// The input a hold was captured from. `deviceName` and `sampleRate` are fixed at key-down: the device
    /// the audio unit was on and the hardware-side rate the tap was built from (later reads of the engine's
    /// formats can go stale mid-hold). Every restarted segment is converted to `sampleRate`. `deviceNameAtRelease`,
    /// `restartCount`, `deviceNames`, `audioLost` and `missingMs` are filled at key-up for the discard log.
    struct CaptureInput: Sendable, Equatable {
        let deviceName: String
        let sampleRate: Double
        var deviceNameAtRelease: String? = nil
        var restartCount: Int? = nil
        var deviceNames: [String]? = nil
        var audioLost: Bool? = nil
        var missingMs: Double? = nil
    }
    private var captureInput: CaptureInput?
    // Written once in init and read only in deinit, which is nonisolated in Swift 6 (CleanupService precedent).
    private nonisolated(unsafe) var configurationObserver: NSObjectProtocol?
    private nonisolated(unsafe) var defaultInputListener: AudioObjectPropertyListenerBlock?

    private var holdPressDevice: AudioDeviceID?
    private var holdRestartCount = 0
    private var holdDeviceNames: [String] = []
    /// Total stop-to-restart time of the hold; a gap this long is audio the recording never heard.
    private var holdGapMs: Double = 0
    /// Set at key-up so no new restart starts while the hold is released; reset by the next key-down.
    private var holdReleasing = false
    private var restartTask: Task<Void, Never>?
    /// A default-input change was seen during the hold; reset by the next key-down.
    private var holdDefaultChanged = false
    private var holdStartedAt = ContinuousClock.now
    /// Polls the sample count during a hold; a recording that stops receiving audio without the engine
    /// stopping (2026-10-19 check (b): AUHAL moved the running unit itself) is restarted from here.
    private var watchdogTask: Task<Void, Never>?
    private var watchdogLastCount = 0
    private var watchdogProgressAt = ContinuousClock.now
    private var watchdogSegmentHasAudio = false
    private var watchdogCapLogged = false
    private static let watchdogInterval: Duration = .milliseconds(100)
    private static let maxHoldRestarts = 3
    private nonisolated static let restartRetryDelay: Duration = .milliseconds(500)
    /// Restart gaps up to this long are not announced to the user.
    private static let maxRestartGapMs: Double = 2000

    // MARK: - Initialization

    /// Initialize with a warm WhisperKit instance from ModelWarmupService.
    /// - Parameter whisperKit: Initialized WhisperKit instance from ModelWarmupService.whisperKitInstance
    init(whisperKit: WhisperKit, voiceLevels: InputVoiceLevelStore = InputVoiceLevelStore()) {
        self.whisperKit = whisperKit
        self.voiceLevels = voiceLevels
        pinInputDevice(site: "init")
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: audioEngine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleConfigurationChange() }
        }
        let block: AudioObjectPropertyListenerBlock = { @Sendable [weak self] _, _ in
            MainActor.assumeIsolated { self?.handleDefaultInputChange() }
        }
        let listenerStatus = AudioInputDevice.addDefaultInputListener(block)
        if listenerStatus == noErr {
            defaultInputListener = block
        } else {
            audioLog.error("input default listener status=\(Int(listenerStatus), privacy: .public)")
        }
    }

    deinit {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        if let defaultInputListener {
            let status = AudioInputDevice.removeDefaultInputListener(defaultInputListener)
            if status != noErr { audioLog.error("input default listener remove status=\(Int(status), privacy: .public)") }
        }
    }

    // MARK: - Input device

    /// Point the engine's input unit at the device `AudioInputDevice.select` picks, which is the system
    /// default input at this moment. Get-compare-set: an unconditional set reconfigures the unit on every
    /// press, which can post a configuration change at the start of the hold. Returns the id and name of
    /// the device the unit ends on.
    @discardableResult
    private func pinInputDevice(site: String) -> (id: AudioDeviceID?, name: String) {
        guard let unit = audioEngine.inputNode.audioUnit else {
            audioLog.error("input pin site=\(site, privacy: .public) no audio unit")
            return (nil, "unknown")
        }
        let candidates = AudioInputDevice.inputCandidates()
        let systemDefault = AudioInputDevice.systemDefaultInput()
        let target = AudioInputDevice.select(from: candidates, systemDefault: systemDefault)
        let before = AudioInputDevice.currentDevice(of: unit)
        var status: OSStatus = noErr
        if let target, target != before {
            status = AudioInputDevice.setCurrentDevice(target, on: unit)
        }
        let after = AudioInputDevice.currentDevice(of: unit)
        let current = candidates.first { $0.id == after }
        let isBuiltIn = { (c: AudioInputDevice.Candidate) in
            c.hasInput && c.transportType == kAudioDeviceTransportTypeBuiltIn
        }
        let name = current?.name ?? "unknown"
        let onBuiltIn = current.map(isBuiltIn) ?? false
        let builtInAvailable = candidates.contains(where: isBuiltIn)
        audioLog.notice("input pin site=\(site, privacy: .public) device=\(Int(after ?? 0), privacy: .public) systemDefault=\(Int(systemDefault ?? 0), privacy: .public) builtIn=\(onBuiltIn, privacy: .public) builtInAvailable=\(builtInAvailable, privacy: .public) changed=\(after != before, privacy: .public) status=\(Int(status), privacy: .public) name=\(name, privacy: .private)")
        return (after, name)
    }

    private func handleConfigurationChange() {
        guard state == .recording, restartTask == nil else {
            audioLog.notice("configuration change ignored state=\(String(describing: self.state), privacy: .public) restarting=\(self.restartTask != nil, privacy: .public)")
            return
        }
        // Read only now: while the restart task runs it owns the engine.
        if audioEngine.isRunning {
            audioLog.notice("configuration change ignored state=\(String(describing: self.state), privacy: .public) running=true")
            return
        }
        audioLog.error("configuration change stopped the engine mid-hold samples=\(self.sampleBuffer.count, privacy: .public)")
        restartCapture()
    }

    /// Log only, with no CoreAudio read: the new default's id is logged off-main in every `input restart try`
    /// line. The timestamp next to AUHAL's own device-change lines shows whether the engine follows a later
    /// default change after a restart.
    private func handleDefaultInputChange() {
        guard state == .recording else { return }
        holdDefaultChanged = true
        audioLog.notice("input default changed restarting=\(self.restartTask != nil, privacy: .public)")
    }

    /// Restart the hold's capture after its engine stopped. No CoreAudio call runs here: the work happens in
    /// `restartEngine` on a detached task.
    private func restartCapture() {
        guard !holdReleasing, let capture = captureInput else { return }
        guard holdRestartCount < Self.maxHoldRestarts else {
            audioLog.error("input restart cap reached count=\(self.holdRestartCount, privacy: .public) samples=\(self.sampleBuffer.count, privacy: .public)")
            return
        }
        holdRestartCount += 1
        let attempt = holdRestartCount
        let begun = ContinuousClock.now
        let press = holdPressDevice
        let pressRate = capture.sampleRate
        let defaultChanged = holdDefaultChanged
        audioLog.notice("input restart begin attempt=\(attempt, privacy: .public) press=\(Int(press ?? 0), privacy: .public) pressRate=\(pressRate, privacy: .public) samples=\(self.sampleBuffer.count, privacy: .public)")
        let handle = CaptureEngine(engine: audioEngine)
        let buffer = sampleBuffer
        restartTask = Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) {
                await Self.restartEngine(handle, buffer: buffer, pressDevice: press, pressRate: pressRate, defaultChanged: defaultChanged, attempt: attempt)
            }.value
            self?.finishRestart(outcome, attempt: attempt, begun: begun)
        }
    }

    private func finishRestart(_ outcome: InputRestartOutcome, attempt: Int, begun: ContinuousClock.Instant) {
        restartTask = nil
        watchdogProgressAt = ContinuousClock.now
        watchdogLastCount = sampleBuffer.count
        watchdogSegmentHasAudio = false
        let elapsedMs = Self.milliseconds(ContinuousClock.now - begun)
        holdGapMs += elapsedMs
        if outcome.started { holdDeviceNames.append(outcome.deviceName) }
        if outcome.started {
            audioLog.notice("input restart result attempt=\(attempt, privacy: .public) started=true tries=\(outcome.tries, privacy: .public) device=\(Int(outcome.device ?? 0), privacy: .public) converted=\(outcome.converted, privacy: .public) elapsedMs=\(elapsedMs, privacy: .public) samples=\(self.sampleBuffer.count, privacy: .public)")
        } else {
            audioLog.error("input restart result attempt=\(attempt, privacy: .public) started=false tries=\(outcome.tries, privacy: .public) device=\(Int(outcome.device ?? 0), privacy: .public) converted=\(outcome.converted, privacy: .public) elapsedMs=\(elapsedMs, privacy: .public) samples=\(self.sampleBuffer.count, privacy: .public)")
        }
        // The engine died again while its notification was being ignored.
        if outcome.started, state == .recording, !holdReleasing, !audioEngine.isRunning {
            audioLog.error("input restart engine stopped again attempt=\(attempt, privacy: .public)")
            restartCapture()
        }
    }

    /// Runs on the cooperative pool, never on the main actor: in the 2026-10-19 check (b) a device set on the
    /// running unit blocked the main thread for 6.5 s, a set on a stopped unit during a Bluetooth transition
    /// is unmeasured, and device enumeration stalled in check (c). `restartTask` guarantees at most one such
    /// task, so at most one pool thread blocks. The second try re-enumerates and re-picks the device, so a
    /// press device that vanished in the meantime is followed instead.
    nonisolated private static func restartEngine(
        _ handle: CaptureEngine,
        buffer: AudioSampleBuffer,
        pressDevice: AudioDeviceID?,
        pressRate: Double,
        defaultChanged: Bool,
        attempt: Int
    ) async -> InputRestartOutcome {
        let engine = handle.engine
        let inputNode = engine.inputNode
        for attemptTry in 1...2 {
            let tryBegun = ContinuousClock.now
            // The engine is already stopped; this guarantees the device is set on a stopped unit.
            inputNode.removeTap(onBus: 0)
            engine.stop()
            let candidates = AudioInputDevice.inputCandidates(includeNames: false)
            let systemDefault = AudioInputDevice.systemDefaultInput()
            let skipPress = AudioInputDevice.shouldSkipPress(
                pressDevice: pressDevice, candidates: candidates, defaultChangedDuringHold: defaultChanged)
            let target = AudioInputDevice.restartDevice(
                pressDevice: pressDevice, candidates: candidates, systemDefault: systemDefault, skipPress: skipPress)
            let unit = inputNode.audioUnit
            var setStatus: OSStatus = noErr
            if let unit, let target, AudioInputDevice.currentDevice(of: unit) != target {
                setStatus = AudioInputDevice.setCurrentDevice(target, on: unit)
            }
            let device = unit.flatMap { AudioInputDevice.currentDevice(of: $0) }
            var started = false
            var tapRate = 0.0
            var converted = false
            var errorCode = 0
            do {
                let tap = try installCaptureTap(on: inputNode, buffer: buffer, pressRate: pressRate)
                tapRate = tap.format.sampleRate
                converted = tap.converted
                do {
                    try engine.start()
                    started = true
                } catch {
                    inputNode.removeTap(onBus: 0)
                    errorCode = (error as NSError).code
                }
            } catch {
                errorCode = (error as NSError).code
            }
            let tryMs = milliseconds(ContinuousClock.now - tryBegun)
            audioLog.notice("input restart try attempt=\(attempt, privacy: .public) try=\(attemptTry, privacy: .public) started=\(started, privacy: .public) press=\(Int(pressDevice ?? 0), privacy: .public) device=\(Int(device ?? 0), privacy: .public) systemDefault=\(Int(systemDefault ?? 0), privacy: .public) skipPress=\(skipPress, privacy: .public) setStatus=\(Int(setStatus), privacy: .public) hwRate=\(tapRate, privacy: .public) pressRate=\(pressRate, privacy: .public) converted=\(converted, privacy: .public) error=\(errorCode, privacy: .public) ms=\(tryMs, privacy: .public)")
            if started {
                return InputRestartOutcome(
                    started: true, tries: attemptTry, device: device,
                    deviceName: device.map { AudioInputDevice.deviceName($0) } ?? "unknown", converted: converted)
            }
            if attemptTry == 1 { try? await Task.sleep(for: restartRetryDelay) }
        }
        return InputRestartOutcome(started: false, tries: 2, device: nil, deviceName: "unknown", converted: false)
    }

    nonisolated private static func milliseconds(_ d: Duration) -> Double {
        Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }

    // MARK: - Recording

    /// Start recording via AVAudioEngine.
    ///
    /// Installs a tap on the input node to accumulate raw Float32 samples.
    /// The hardware's native sample rate is captured; resampling to 16kHz
    /// occurs in stopRecordingAndTranscribe() before ASR inference.
    ///
    /// - Throws: TranscriptionError.busy if already recording or transcribing.
    /// - Throws: AVFoundation error if microphone access is denied or hardware unavailable.
    func startRecording() throws {
        guard state == .idle else { throw TranscriptionError.busy }
        sampleBuffer.clear()
        // Stats belong to one hold; a hold without a preview must not report the previous one's.
        lastLivePreviewStats = nil

        let pin = pinInputDevice(site: "start")
        let inputNode = audioEngine.inputNode
        // Installed via a nonisolated helper so the tap closure does not inherit @MainActor isolation
        // (Swift 6 strict concurrency).
        let tap = try Self.installCaptureTap(on: inputNode, buffer: sampleBuffer, pressRate: nil)

        do {
            try audioEngine.start()
        } catch {
            // A tap left behind makes the next press's installTap raise an NSException.
            inputNode.removeTap(onBus: 0)
            throw error
        }
        captureInput = CaptureInput(deviceName: pin.name, sampleRate: tap.format.sampleRate)
        holdPressDevice = pin.id
        holdRestartCount = 0
        holdDeviceNames = [pin.name]
        holdGapMs = 0
        holdReleasing = false
        holdDefaultChanged = false
        holdStartedAt = ContinuousClock.now
        state = .recording
        startWatchdog()
    }

    private func startWatchdog() {
        watchdogTask?.cancel()
        watchdogLastCount = sampleBuffer.count
        watchdogProgressAt = holdStartedAt
        watchdogSegmentHasAudio = false
        watchdogCapLogged = false
        watchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.watchdogInterval)
                guard let self, !Task.isCancelled, self.state == .recording, !self.holdReleasing else { return }
                self.watchdogTick()
            }
        }
    }

    /// No audio-engine read here: `restartEngine` stops the engine itself before it sets the device.
    private func watchdogTick() {
        guard restartTask == nil else { return }
        let count = sampleBuffer.count
        let now = ContinuousClock.now
        if count != watchdogLastCount {
            watchdogLastCount = count
            watchdogProgressAt = now
            watchdogSegmentHasAudio = true
            return
        }
        let sinceProgressMs = Self.milliseconds(now - watchdogProgressAt)
        guard AudioInputDevice.isStarved(msSinceProgress: sinceProgressMs, segmentHasAudio: watchdogSegmentHasAudio) else { return }
        guard holdRestartCount < Self.maxHoldRestarts else {
            if !watchdogCapLogged {
                watchdogCapLogged = true
                audioLog.error("input starved after restart cap count=\(self.holdRestartCount, privacy: .public) samples=\(count, privacy: .public)")
            }
            return
        }
        audioLog.error("input starved ms=\(sinceProgressMs, privacy: .public) samples=\(count, privacy: .public) segmentHasAudio=\(self.watchdogSegmentHasAudio, privacy: .public)")
        holdGapMs += sinceProgressMs
        restartCapture()
    }

    /// The single place that reads the input formats and installs the capture tap, for key-down and for every
    /// restart. The tap rate comes from the hardware side: the client-side rate went stale in the 2026-10-18
    /// incident and AVFAudio raised an NSException on the mismatch. The client side supplies only the channel
    /// count (WhisperKit's recipe). A restarted segment whose hardware rate differs from `pressRate` is
    /// converted to it in the tap, so the hold's buffer has one rate.
    ///
    /// Nonisolated so the closure has no actor affinity: Swift 6 strict concurrency makes closures inside
    /// @MainActor methods inherit that isolation, and even @Sendable closures check actor identity at
    /// runtime, crashing when AVAudioEngine calls them on the real-time audio thread.
    nonisolated private static func installCaptureTap(
        on inputNode: AVAudioInputNode,
        buffer: AudioSampleBuffer,
        pressRate: Double?
    ) throws -> (format: AVAudioFormat, converted: Bool) {
        let hardwareFormat = inputNode.inputFormat(forBus: 0)
        let clientFormat = inputNode.outputFormat(forBus: 0)
        guard hardwareFormat.channelCount > 0, clientFormat.sampleRate > 0 else {
            throw TranscriptionError.inputUnavailable
        }
        let tapFormat = try AudioInputDevice.tapFormat(
            sampleRate: hardwareFormat.sampleRate, channelCount: clientFormat.channelCount)
        var segmentResampler: AudioInputDevice.SegmentResampler?
        if let pressRate, abs(tapFormat.sampleRate - pressRate) > 1.0 {
            guard let resampler = AudioInputDevice.SegmentResampler(from: tapFormat.sampleRate, to: pressRate) else {
                throw TranscriptionError.inputUnavailable
            }
            segmentResampler = resampler
        }
        let resampler = segmentResampler
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) {
            pcmBuffer, _ in
            if let channelData = pcmBuffer.floatChannelData?[0] {
                let frameCount = Int(pcmBuffer.frameLength)
                let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
                buffer.append(resampler?.convert(samples) ?? samples)
            }
        }
        return (tapFormat, resampler != nil)
    }

    // MARK: - Transcription

    /// Stop recording and run the full transcription pipeline.
    ///
    /// Pipeline steps:
    ///   1. Stop AVAudioEngine recording (always stop before reading samples)
    ///   2. Resample from hardware rate to 16kHz mono (WhisperKit expects 16kHz)
    ///   3. Check minimum duration (D-11: reject clips shorter than 0.3s)
    ///   4. Adaptive voice-activity gate: reject if no frame dwarfs the clip's own noise floor
    ///   5. Transcribe via WhisperKit large-v3-turbo
    ///   5b. Per-chunk phantom drop: remove a chunk that is only a ship-list phrase (multi-chunk decode) or is tagged neither German nor English; every later step reads the kept chunks only. All chunks removed: silenceOnly, or unexpectedLanguage when a language drop was the cause
    ///   6. Boilerplate-hallucination discard: reject a whole-utterance closed-list match, e.g. "Thank you.", or a lone "you"/"and"/"-" from a clip under 1.5 s or one with no voice found by the gate
    ///   7. No-speech discard: reject if every segment's noSpeechProb exceeds threshold
    ///   7b. Near-silent short-clip discard: reject a clip under 2.5 s with at most 2 voiced frames
    ///   8. Detect language post-hoc with NLLanguageRecognizer (D-13)
    ///   9. Build DicticusTranscriptionResult
    ///
    /// - Returns: DicticusTranscriptionResult with text, language, and confidence
    /// - Throws: TranscriptionError for pipeline failures (tooShort, silenceOnly, noResult)
    func stopRecordingAndTranscribe() async throws -> DicticusTranscriptionResult {
        guard state == .recording, var capture = captureInput else { throw TranscriptionError.notRecording }

        // A restart owns the engine until it finishes. Suspending here keeps the main actor free, and
        // holdReleasing keeps a finishing restart from starting another.
        holdReleasing = true
        watchdogTask?.cancel()
        watchdogTask = nil
        let waitBegun = ContinuousClock.now
        while let task = restartTask { await task.value }
        audioLog.notice("input restart wait ms=\(Self.milliseconds(ContinuousClock.now - waitBegun), privacy: .public) restarts=\(self.holdRestartCount, privacy: .public)")

        // Read before stopping: stop() makes isRunning false. An engine found down here has no restart left.
        let running = audioEngine.isRunning
        let wallMs = Self.milliseconds(ContinuousClock.now - holdStartedAt)
        let capturedMs = Double(sampleBuffer.count) / capture.sampleRate * 1000
        let missingMs = wallMs - capturedMs
        let audioLost = TranscriptionFailureRouter.audioLost(
            engineRunning: running, totalGapMs: holdGapMs, missingMs: missingMs, maxGapMs: Self.maxRestartGapMs)
        let detectedBy: String? = audioLost ? (holdRestartCount > 0 ? "notification" : "release") : nil

        // The release device is read before stop(), which changes the unit's state.
        let releaseDevice = audioEngine.inputNode.audioUnit.flatMap { AudioInputDevice.currentDevice(of: $0) }
        capture.deviceNameAtRelease = releaseDevice.map { AudioInputDevice.deviceName($0) } ?? "unknown"
        capture.restartCount = holdRestartCount
        capture.deviceNames = holdDeviceNames
        capture.audioLost = audioLost
        capture.missingMs = missingMs
        audioLog.notice("input hold end press=\(Int(self.holdPressDevice ?? 0), privacy: .public) release=\(Int(releaseDevice ?? 0), privacy: .public) restarts=\(self.holdRestartCount, privacy: .public) lost=\(audioLost, privacy: .public) wallMs=\(wallMs, privacy: .public) capturedMs=\(capturedMs, privacy: .public) hwRate=\(self.audioEngine.inputNode.inputFormat(forBus: 0).sampleRate, privacy: .public) tapRate=\(capture.sampleRate, privacy: .public)")
        holdPressDevice = nil

        // Always stop before accessing audioSamples
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        holdReleasing = false
        state = .transcribing

        // Ensure state always resets to .idle even if transcription throws
        defer { if state == .transcribing { state = .idle } }

        let route = TranscriptionFailureRouter.holdEnd(
            audioLost: audioLost,
            capturedSeconds: Double(sampleBuffer.count) / capture.sampleRate,
            minimumSeconds: Double(minimumDurationSeconds))

        let session = livePreview
        livePreview = nil

        if route == .failInterrupted {
            // D-02: one WhisperKit instance, so an in-flight preview decode must finish before the next hold.
            if let session { lastLivePreviewStats = await session.cancelAndDrain() }
            audioLog.error("hold interrupted detectedBy=\((detectedBy ?? "release"), privacy: .public) samples=\(self.sampleBuffer.count, privacy: .public)")
            #if DEBUG_RECORDER
            await DiscardProbe.shared.recordInputInterrupted(
                detectedBy: detectedBy ?? "release",
                capturedSampleCount: sampleBuffer.count,
                captureSampleRate: capture.sampleRate,
                inputDeviceName: capture.deviceName,
                inputDeviceNameAtRelease: capture.deviceNameAtRelease,
                inputRestartCount: capture.restartCount,
                inputDevices: capture.deviceNames,
                inputAudioLost: capture.audioLost,
                inputMissingMs: capture.missingMs
            )
            #endif
            throw TranscriptionError.inputInterrupted
        }
        let inputSampleRate = capture.sampleRate

        let buffer = sampleBuffer
        let transcriptionResult: DicticusTranscriptionResult
        let gateMaxFrameEnergy: Float
        do {
            let finished = try await finishTranscription(
                previewSession: session,
                takeSamples: {
                    let samples = buffer.drain()
                    #if DEBUG_RECORDER
                    // 261016-nx0: keep the hold's audio for "Flag last preview" (a preview ran for this hold).
                    if session != nil { PreviewFlagRecorder.shared.noteSamples(samples, inputSampleRate: inputSampleRate) }
                    #endif
                    return samples
                },
                inputSampleRate: inputSampleRate,
                capture: capture
            )
            transcriptionResult = finished.result
            gateMaxFrameEnergy = finished.gateMaxFrameEnergy
        } catch let error as TranscriptionError where route == .transcribeWithLossNotice {
            throw TranscriptionFailureRouter.afterInputLoss(error)
        }
        #if DEBUG_RECORDER
        if session != nil {
            PreviewFlagRecorder.shared.noteFinal(text: transcriptionResult.text, language: transcriptionResult.language)
        }
        #endif

        if route == .transcribeWithLossNotice {
            NotificationService.shared.post(.inputLost)
        }

        if InputVoiceLevelStore.isLearnable(restartCount: capture.restartCount, audioLost: capture.audioLost) {
            voiceLevels.record(peak: gateMaxFrameEnergy, forDevice: capture.deviceName)
        }

        lastResult = transcriptionResult
        state = .idle
        return transcriptionResult
    }

    // MARK: - Live preview (Phase 51)

    /// The running live-preview session, if any. Inert unless `startLivePreview` is called.
    private var livePreview: LivePreviewSession?

    /// Stats of the most recent preview session, captured at release.
    private(set) var lastLivePreviewStats: LivePreviewSession.Stats?

    /// Start the interim decode loop for the current recording (D-04). Previews feed
    /// `publish` only; nothing from a preview reaches the final transcription (D-01).
    func startLivePreview(
        cadence: Duration,
        publish: @escaping @MainActor (String) -> Void,
        silence: (@MainActor () -> Void)? = nil
    ) {
        guard state == .recording, livePreview == nil, let captureInput else { return }
        let decoder = LivePreviewDecoder(
            whisperKit: whisperKit,
            buffer: sampleBuffer,
            inputSampleRate: captureInput.sampleRate,
            onSilence: silence
        )
        let session = LivePreviewSession(
            cadence: cadence,
            isActive: { [weak self] in self?.state == .recording },
            decode: { await decoder.decodeTail() },
            publish: publish,
            ranModel: { decoder.lastTickRanModel },
            skippedNoVoice: { decoder.skippedNoVoice }
        )
        livePreview = session
        session.start()
    }

    /// Release path shared by the hotkey and the spike harness: the preview is cancelled
    /// and awaited FIRST (D-02; WhisperKit is one non-Sendable instance), then the buffer
    /// is drained and the unchanged final decode runs (D-01).
    private func finishTranscription(
        previewSession: LivePreviewSession?,
        takeSamples: () -> [Float],
        inputSampleRate: Double,
        capture: CaptureInput? = nil
    ) async throws -> (result: DicticusTranscriptionResult, avgLogprobs: [Float], compressionRatios: [Float], gateMaxFrameEnergy: Float) {
        try await Self.releaseSequence(
            previewSession: previewSession,
            onDrained: { self.lastLivePreviewStats = $0 },
            takeSamples: takeSamples,
            decode: { try await self.transcribe(rawSamples: $0, inputSampleRate: inputSampleRate, capture: capture) }
        )
    }

    /// The order of the release path, separated from the model so a test can observe it:
    /// cancel and await the preview, then take the samples, then run the one final decode on
    /// exactly those samples.
    static func releaseSequence<Result>(
        previewSession: LivePreviewSession?,
        onDrained: (LivePreviewSession.Stats) -> Void,
        takeSamples: () -> [Float],
        decode: ([Float]) async throws -> Result
    ) async throws -> Result {
        if let previewSession {
            onDrained(await previewSession.cancelAndDrain())
        }
        return try await decode(takeSamples())
    }

    /// The transcription path proper, from raw captured samples to a result:
    /// resample → duration guard → AdaptiveVoiceGate → WhisperKit → per-chunk phantom drop → NoSpeechDiscard
    /// → script validation → language detection → confidence.
    ///
    /// Split out of `stopRecordingAndTranscribe()` (quick task 260802-ass) so archived
    /// capture WAVs can be replayed through the exact same path the live hotkey uses,
    /// without an audio engine. The live caller owns `lastResult`/`state`; this function
    /// is pure with respect to service state so a replay cannot perturb it.
    ///
    /// Returns the per-segment `avgLogprob`/`compressionRatio` alongside the result — the
    /// live path discards them, the replay harness records them. `compressionRatio`
    /// replaces the former `noSpeechProbs` element (quick task 260825-q2f): WhisperKit
    /// 1.0.0 never computes a real no-speech probability (see DiscardProbe.swift's
    /// cycle-4 header note), so that array only ever held fabricated zeros.
    private func transcribe(
        rawSamples samples: [Float],
        inputSampleRate: Double,
        capture: CaptureInput? = nil
    ) async throws -> (result: DicticusTranscriptionResult, avgLogprobs: [Float], compressionRatios: [Float], gateMaxFrameEnergy: Float) {
        // Resample to 16kHz mono if hardware sample rate differs.
        // WhisperKit requires 16kHz Float32 mono input.
        let resampledSamples: [Float]
        if abs(inputSampleRate - sampleRate) > 1.0 {
            resampledSamples = Self.resampleAudio(samples, from: inputSampleRate, to: sampleRate)
        } else {
            resampledSamples = samples
        }

        let durationSeconds = Float(resampledSamples.count) / Float(sampleRate)

        // Layer 1: Minimum duration guard (D-11)
        guard durationSeconds >= minimumDurationSeconds else {
            #if DEBUG_RECORDER
            // The Layer 2 gate has not run yet at this point in the function (it sits
            // below this guard), so this site recomputes the same metrics purely to
            // observe them — quick task 260826-8ec. The resulting decision is written
            // to the log and read by nothing; no branch below consults it.
            let energy = AudioProcessor.calculateEnergy(of: resampledSamples)
            let probeFrameEnergies = Self.frameEnergies(of: resampledSamples, sampleRate: sampleRate)
            let probeAbsoluteFloor = voiceLevels.absoluteFloor(forDevice: capture?.deviceName)
            let probeDecision = AdaptiveVoiceGate.evaluate(frameEnergies: probeFrameEnergies, absoluteFloor: probeAbsoluteFloor)
            await DiscardProbe.shared.record(
                reason: "tooShort",
                platform: "macOS",
                rawSampleCount: samples.count,
                resampledSampleCount: resampledSamples.count,
                hwSampleRate: inputSampleRate,
                durationSeconds: durationSeconds,
                rms: energy.avg,
                peak: energy.max,
                vadFrameCount: probeFrameEnergies.count,
                vadTrueFrameCount: probeDecision.framesAboveThreshold(in: probeFrameEnergies),
                vadMaxFrameEnergy: probeDecision.maxFrameEnergy,
                gateNoiseFloor: probeDecision.noiseFloor,
                gateThreshold: probeDecision.threshold,
                gateAbsoluteFloor: probeAbsoluteFloor,
                gateFrameEnergies: probeFrameEnergies,
                energyMetricsSource: DiscardProbe.energyMetricsSourceProbeRecompute,
                inputDeviceName: capture?.deviceName,
                inputSampleRate: capture?.sampleRate,
                inputDeviceNameAtRelease: capture?.deviceNameAtRelease,
                inputRestartCount: capture?.restartCount, inputDevices: capture?.deviceNames, inputAudioLost: capture?.audioLost, inputMissingMs: capture?.missingMs
            )
            #endif
            throw TranscriptionError.tooShort  // defer resets to .idle
        }

        // Layer 2: Adaptive voice-activity gate (WHISP-03 cycle 2 — reintroduces an
        // input-energy pre-filter after cycle 1 removed the fixed-threshold EnergyVAD
        // entirely; see whisper-dictation-dropout debug session). Unlike the removed
        // EnergyVAD, the threshold is computed relative to THIS clip's own noise floor,
        // so it self-calibrates across microphones instead of assuming one fixed RMS
        // ceiling. This exists because Layer 3 (NoSpeechDiscard, below) cannot catch a
        // CONFIDENT Whisper silence hallucination — a low noSpeechProb by definition —
        // so an energy gate ahead of WhisperKit is the only mechanism that can.
        //
        // The absolute floor is the press microphone's learned one (quick task 261020-dvf): a quiet
        // microphone such as an Elgato Wave XLR peaks under the built-in microphone's 0.006.
        let gateFrameEnergies = Self.frameEnergies(of: resampledSamples, sampleRate: sampleRate)
        let gateAbsoluteFloor = voiceLevels.absoluteFloor(forDevice: capture?.deviceName)
        let gateDecision = AdaptiveVoiceGate.evaluate(frameEnergies: gateFrameEnergies, absoluteFloor: gateAbsoluteFloor)
        // Phase 50 D-01: true exactly when this clip reaches WhisperKit only because
        // of the duration bypass (gate found no voice, but duration >= the constant
        // above). Used both by the guard below and by every post-gate discard-log
        // record so a future audit can size the bypassed-clip class.
        let gateBypassedByDuration = !gateDecision.voiceDetected && durationSeconds >= Self.gateBypassDurationSeconds
        // Single-sourced frames-above-threshold count (quick task 260826-8ec), bound in
        // every build since 261008-gb2: the near-silent short-clip rule below reads it, and
        // every discard-log call site at or below this point reuses it.
        let gateFramesAboveThreshold = gateDecision.framesAboveThreshold(in: gateFrameEnergies)
        // Phase 50 D-01: the energy gate alone no longer decides discard for long
        // clips — see gateBypassDurationSeconds above.
        guard Self.shouldProceedPastEnergyGate(voiceDetected: gateDecision.voiceDetected, durationSeconds: durationSeconds) else {
            #if DEBUG_RECORDER
            // Discard-path regression net only — the temporary pass-path probe used to
            // verify the quiet-speech margin during on-device UAT was removed 2026-07-05
            // once both directions (silence discarded, quiet/normal speech transcribed)
            // were confirmed on-device.
            let gateEnergy = AudioProcessor.calculateEnergy(of: resampledSamples)
            await DiscardProbe.shared.record(
                reason: "silenceOnly_energyGate",
                platform: "macOS",
                rawSampleCount: samples.count,
                resampledSampleCount: resampledSamples.count,
                hwSampleRate: inputSampleRate,
                durationSeconds: durationSeconds,
                rms: gateEnergy.avg,
                peak: gateEnergy.max,
                vadFrameCount: gateFrameEnergies.count,
                vadTrueFrameCount: gateFramesAboveThreshold,
                vadMaxFrameEnergy: gateDecision.maxFrameEnergy,
                gateNoiseFloor: gateDecision.noiseFloor,
                gateThreshold: gateDecision.threshold,
                gateAbsoluteFloor: gateAbsoluteFloor,
                gateFrameEnergies: gateFrameEnergies,
                energyMetricsSource: DiscardProbe.energyMetricsSourceLiveGate,
                inputDeviceName: capture?.deviceName,
                inputSampleRate: capture?.sampleRate,
                inputDeviceNameAtRelease: capture?.deviceNameAtRelease,
                inputRestartCount: capture?.restartCount, inputDevices: capture?.deviceNames, inputAudioLost: capture?.audioLost, inputMissingMs: capture?.missingMs
            )
            #endif
            throw TranscriptionError.silenceOnly  // defer resets to .idle
        }

        // Layer 3: Transcribe via WhisperKit large-v3-turbo.
        //
        // Whisper's seq2seq decoder does not need the trailing-silence tail-pad Parakeet's
        // TDT decoder required to flush its final token (spike 008 Fix B) — removed per the
        // 41-05 decision (Whisper has no equivalent terminal-punctuation tail-drop failure mode).
        // Do NOT reintroduce `promptTokens` here. Spike 260802 wired Whisper's
        // initial-prompt bias to pre-empt the user's German-L1 phoneme confusions and
        // measured it over 154 archived captures: it breaks ~50% of decodes into
        // noResult AND fabricates content absent from every baseline transcript. A
        // 24-file matrix with an in-batch control falsified both alternative causes
        // (detectLanguage, and the quality-fallback thresholds) — the promptTokens path
        // itself is the failure, so it is not a tuning problem. See commits 5978e66 /
        // 85a933c and .planning/quick/260802-ass-*.
        let decodeOptions = DecodingOptions(
            language: nil,
            detectLanguage: true,
            withoutTimestamps: true,
            suppressBlank: true,
            compressionRatioThreshold: 2.4,
            logProbThreshold: -1.0,
            noSpeechThreshold: 0.6,
            chunkingStrategy: .vad
        )
        let results = try await whisperKit.transcribe(audioArray: resampledSamples, decodeOptions: decodeOptions)

        // Per-chunk phantom drop (quick task 261008-gb2). A long clip comes back as one
        // result per voice-activity chunk, and a pause inside it can decode to a chunk of
        // its own that is only "Thank you." The whole-clip checks below compare the JOINED
        // text and cannot see that. Every consumer below reads the kept chunks only.
        let chunkDrops = BoilerplateHallucination.chunkDropReasons(
            results.map { (text: $0.text, language: $0.language) }
        )
        let keptResults = zip(results, chunkDrops).filter { $0.1 == nil }.map(\.0)
        let allSegments = keptResults.flatMap { $0.segments }
        let combinedText = keptResults.map(\.text).joined(separator: " ")
        #if DEBUG_RECORDER
        // Every post-decode discard-log record lists ALL original segments, a dropped
        // chunk's segments carrying `drop_reason`, so a future false positive stays visible.
        let segmentInfos: [DiscardProbe.SegmentInfo] = zip(results, chunkDrops).flatMap { result, drop in
            result.segments.map {
                DiscardProbe.SegmentInfo(
                    text: $0.text,
                    noSpeechProb: nil,
                    avgLogProb: $0.avgLogprob,
                    compressionRatio: $0.compressionRatio,
                    temperature: $0.temperature,
                    startSeconds: $0.start,
                    endSeconds: $0.end,
                    language: result.language,
                    dropReason: drop?.rawValue
                )
            }
        }
        #endif
        if keptResults.isEmpty && !results.isEmpty {
            #if DEBUG_RECORDER
            let phantomEnergy = AudioProcessor.calculateEnergy(of: resampledSamples)
            await DiscardProbe.shared.record(
                reason: "phantomSegmentsOnly",
                platform: "macOS",
                rawSampleCount: samples.count,
                resampledSampleCount: resampledSamples.count,
                hwSampleRate: inputSampleRate,
                durationSeconds: durationSeconds,
                rms: phantomEnergy.avg,
                peak: phantomEnergy.max,
                vadFrameCount: gateFrameEnergies.count,
                vadTrueFrameCount: gateFramesAboveThreshold,
                vadMaxFrameEnergy: gateDecision.maxFrameEnergy,
                gateNoiseFloor: gateDecision.noiseFloor,
                gateThreshold: gateDecision.threshold,
                gateAbsoluteFloor: gateAbsoluteFloor,
                gateFrameEnergies: gateFrameEnergies,
                segments: segmentInfos,
                noSpeechProbSource: DiscardProbe.noSpeechProbUnavailable,
                energyMetricsSource: DiscardProbe.energyMetricsSourceLiveGate,
                gateBypassedByDuration: gateBypassedByDuration,
                inputDeviceName: capture?.deviceName,
                inputSampleRate: capture?.sampleRate,
                inputDeviceNameAtRelease: capture?.deviceNameAtRelease,
                inputRestartCount: capture?.restartCount, inputDevices: capture?.deviceNames, inputAudioLost: capture?.audioLost, inputMissingMs: capture?.missingMs
            )
            #endif
            // A clip emptied by a language drop becomes the existing "Unexpected language"
            // retry notice (same as the non-Latin check below) instead of a silent loss of
            // what may be garbled real speech; one emptied by ship-list phantoms is silent.
            if chunkDrops.contains(.nonDeEnLanguage) {
                throw TranscriptionError.unexpectedLanguage
            }
            throw TranscriptionError.silenceOnly  // defer resets to .idle
        }

        // Whole-utterance boilerplate-hallucination discard (quick task 260827-81z): a
        // small closed list of Whisper subtitle-boilerplate strings ("Thank you." etc.)
        // that Whisper sometimes hallucinates into a pause with high confidence —
        // NoSpeechDiscard below cannot catch these because a confident hallucination has
        // a LOW noSpeechProb by construction. Quick task 260930-s1g adds a second closed
        // list, a lone "you"/"and"/"-", discarded when the clip is under 1.5 s or the
        // Layer-2 gate found no voice (a clip that reached Whisper via the D-01 duration
        // bypass); one reason is logged for both short-list arms. This guard is placed BEFORE the
        // `reason: "pass"` DiscardProbe block further down: a guard placed after it would
        // log the same utterance twice, once as "pass" (false — it was discarded) and once
        // as the discard.
        let boilerplateReason: String? = BoilerplateHallucination.match(combinedText) != nil
            ? "boilerplateHallucination"
            : (BoilerplateHallucination.matchShortStock(
                combinedText,
                durationSeconds: durationSeconds,
                voiceDetected: gateDecision.voiceDetected
            ) != nil ? "shortStockWordHallucination" : nil)
        if let discardReason = boilerplateReason {
            #if DEBUG_RECORDER
            let boilerplateEnergy = AudioProcessor.calculateEnergy(of: resampledSamples)
            await DiscardProbe.shared.record(
                reason: discardReason,
                platform: "macOS",
                rawSampleCount: samples.count,
                resampledSampleCount: resampledSamples.count,
                hwSampleRate: inputSampleRate,
                durationSeconds: durationSeconds,
                rms: boilerplateEnergy.avg,
                peak: boilerplateEnergy.max,
                vadFrameCount: gateFrameEnergies.count,
                vadTrueFrameCount: gateFramesAboveThreshold,
                vadMaxFrameEnergy: gateDecision.maxFrameEnergy,
                gateNoiseFloor: gateDecision.noiseFloor,
                gateThreshold: gateDecision.threshold,
                gateAbsoluteFloor: gateAbsoluteFloor,
                gateFrameEnergies: gateFrameEnergies,
                segments: segmentInfos,
                noSpeechProbSource: DiscardProbe.noSpeechProbUnavailable,
                energyMetricsSource: DiscardProbe.energyMetricsSourceLiveGate,
                gateBypassedByDuration: gateBypassedByDuration,
                inputDeviceName: capture?.deviceName,
                inputSampleRate: capture?.sampleRate,
                inputDeviceNameAtRelease: capture?.deviceNameAtRelease,
                inputRestartCount: capture?.restartCount, inputDevices: capture?.deviceNames, inputAudioLost: capture?.audioLost, inputMissingMs: capture?.missingMs
            )
            #endif
            _ = discardReason
            throw TranscriptionError.silenceOnly  // defer resets to .idle
        }

        // No-speech discard (WHISP-03 Pitfall 2): WhisperKit does not auto-blank `text` for
        // pure silence — noSpeechProb only drives internal decoder fallback, not output
        // suppression. Inspect segments ourselves before building the result.
        guard !NoSpeechDiscard.looksLikeSilence(noSpeechProbs: allSegments.map(\.noSpeechProb)) else {
            #if DEBUG_RECORDER
            let energy = AudioProcessor.calculateEnergy(of: resampledSamples)
            await DiscardProbe.shared.record(
                reason: "silenceOnly_noSpeechDiscard",
                platform: "macOS",
                rawSampleCount: samples.count,
                resampledSampleCount: resampledSamples.count,
                hwSampleRate: inputSampleRate,
                durationSeconds: durationSeconds,
                rms: energy.avg,
                peak: energy.max,
                vadFrameCount: gateFrameEnergies.count,
                vadTrueFrameCount: gateFramesAboveThreshold,
                vadMaxFrameEnergy: gateDecision.maxFrameEnergy,
                gateNoiseFloor: gateDecision.noiseFloor,
                gateThreshold: gateDecision.threshold,
                gateAbsoluteFloor: gateAbsoluteFloor,
                gateFrameEnergies: gateFrameEnergies,
                segments: segmentInfos,
                noSpeechProbSource: DiscardProbe.noSpeechProbUnavailable,
                energyMetricsSource: DiscardProbe.energyMetricsSourceLiveGate,
                gateBypassedByDuration: gateBypassedByDuration,
                inputDeviceName: capture?.deviceName,
                inputSampleRate: capture?.sampleRate,
                inputDeviceNameAtRelease: capture?.deviceNameAtRelease,
                inputRestartCount: capture?.restartCount, inputDevices: capture?.deviceNames, inputAudioLost: capture?.audioLost, inputMissingMs: capture?.missingMs
            )
            #endif
            throw TranscriptionError.silenceOnly  // defer resets to .idle
        }

        // Near-silent short-clip discard (quick task 261008-gb2, F3): a clip under 2.5 s with
        // at most 2 voiced frames. It sits after decode and after NoSpeechDiscard so the
        // discard record keeps the decoded segments (a future false positive stays visible)
        // and every earlier reason keeps its label. It narrows Phase 50 D-01 for 2.0-2.5 s
        // clips with no voiced frame: D-01's shortest low-gain real speech lasts 2.7 s, and
        // the 0-voiced real passes since 2026-09-16 start at 3.5 s. It does not apply on a quiet
        // microphone (learned floor below the default), where a real one-word clip has 1-2 voiced
        // frames (quick task 261020-dvf).
        if InputVoiceLevelStore.appliesNearSilentRule(absoluteFloor: gateAbsoluteFloor),
           AdaptiveVoiceGate.isNearSilentShortClip(durationSeconds: durationSeconds, voicedFrames: gateFramesAboveThreshold) {
            #if DEBUG_RECORDER
            let nearSilentEnergy = AudioProcessor.calculateEnergy(of: resampledSamples)
            await DiscardProbe.shared.record(
                reason: "nearSilentShortClip",
                platform: "macOS",
                rawSampleCount: samples.count,
                resampledSampleCount: resampledSamples.count,
                hwSampleRate: inputSampleRate,
                durationSeconds: durationSeconds,
                rms: nearSilentEnergy.avg,
                peak: nearSilentEnergy.max,
                vadFrameCount: gateFrameEnergies.count,
                vadTrueFrameCount: gateFramesAboveThreshold,
                vadMaxFrameEnergy: gateDecision.maxFrameEnergy,
                gateNoiseFloor: gateDecision.noiseFloor,
                gateThreshold: gateDecision.threshold,
                gateAbsoluteFloor: gateAbsoluteFloor,
                gateFrameEnergies: gateFrameEnergies,
                segments: segmentInfos,
                noSpeechProbSource: DiscardProbe.noSpeechProbUnavailable,
                energyMetricsSource: DiscardProbe.energyMetricsSourceLiveGate,
                gateBypassedByDuration: gateBypassedByDuration,
                inputDeviceName: capture?.deviceName,
                inputSampleRate: capture?.sampleRate,
                inputDeviceNameAtRelease: capture?.deviceNameAtRelease,
                inputRestartCount: capture?.restartCount, inputDevices: capture?.deviceNames, inputAudioLost: capture?.audioLost, inputMissingMs: capture?.missingMs
            )
            #endif
            throw TranscriptionError.silenceOnly  // defer resets to .idle
        }

        #if DEBUG_RECORDER
        // Quick task 260719-9a6, MEASURE-FIRST: the discard paths above already log each
        // segment's noSpeechProb/avgLogProb, but a SUCCESSFUL transcription never has —
        // there is currently no way to check whether a mid-utterance ASR phantom (a
        // fabricated clause inserted during a pause) is separable from real speech by
        // its own per-segment signals. This call has no effect on control flow or the
        // produced text; it only appends every kept segment to the same discard-*.jsonl
        // writer under reason: "pass" for a future measurement pass.
        //
        // Quick task 260826-8ec: this was the one reason with no energy/VAD fields at
        // all — the 7th confirmed live "Thank you." hallucination landed here with none.
        // rms/peak use the identical AudioProcessor.calculateEnergy(of:) call the other
        // sites already use, so the value is comparable across every historical record.
        let passEnergy = AudioProcessor.calculateEnergy(of: resampledSamples)
        await DiscardProbe.shared.record(
            reason: "pass",
            platform: "macOS",
            rawSampleCount: samples.count,
            resampledSampleCount: resampledSamples.count,
            hwSampleRate: inputSampleRate,
            durationSeconds: durationSeconds,
            rms: passEnergy.avg,
            peak: passEnergy.max,
            vadFrameCount: gateFrameEnergies.count,
            vadTrueFrameCount: gateFramesAboveThreshold,
            vadMaxFrameEnergy: gateDecision.maxFrameEnergy,
            gateNoiseFloor: gateDecision.noiseFloor,
            gateThreshold: gateDecision.threshold,
            gateAbsoluteFloor: gateAbsoluteFloor,
            gateFrameEnergies: gateFrameEnergies,
            segments: segmentInfos,
            lowConfidenceShort: LowConfidenceShort.flag(
                durationSeconds: durationSeconds,
                avgLogProbs: allSegments.map(\.avgLogprob)
            ),
            noSpeechProbSource: DiscardProbe.noSpeechProbUnavailable,
            energyMetricsSource: DiscardProbe.energyMetricsSourceLiveGate,
            gateBypassedByDuration: gateBypassedByDuration,
            inputDeviceName: capture?.deviceName,
            inputSampleRate: capture?.sampleRate,
            inputDeviceNameAtRelease: capture?.deviceNameAtRelease,
            inputRestartCount: capture?.restartCount, inputDevices: capture?.deviceNames, inputAudioLost: capture?.audioLost, inputMissingMs: capture?.missingMs
        )
        #endif

        #if DEBUG_RECORDER
        // Spike 008's Fix A/B distinction was Parakeet-specific (tail-drop vs capture-cut).
        // Kept for ongoing monitoring of genuine capture-cuts (audio severed mid-word) —
        // no second transcribe is needed.
        if AudioCaptureProbe.looksClipped(combinedText) {
            await AudioCaptureProbe.shared.record(
                samples16k: resampledSamples,
                rawSampleCount: samples.count,
                hwSampleRate: inputSampleRate,
                unpaddedText: combinedText,
                paddedText: nil
            )
        }
        #endif

        let trimmedText = combinedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            #if DEBUG_RECORDER
            let energy = AudioProcessor.calculateEnergy(of: resampledSamples)
            await DiscardProbe.shared.record(
                reason: "noResult",
                platform: "macOS",
                rawSampleCount: samples.count,
                resampledSampleCount: resampledSamples.count,
                hwSampleRate: inputSampleRate,
                durationSeconds: durationSeconds,
                rms: energy.avg,
                peak: energy.max,
                vadFrameCount: gateFrameEnergies.count,
                vadTrueFrameCount: gateFramesAboveThreshold,
                vadMaxFrameEnergy: gateDecision.maxFrameEnergy,
                gateNoiseFloor: gateDecision.noiseFloor,
                gateThreshold: gateDecision.threshold,
                gateAbsoluteFloor: gateAbsoluteFloor,
                gateFrameEnergies: gateFrameEnergies,
                segments: segmentInfos,
                noSpeechProbSource: DiscardProbe.noSpeechProbUnavailable,
                energyMetricsSource: DiscardProbe.energyMetricsSourceLiveGate,
                gateBypassedByDuration: gateBypassedByDuration,
                inputDeviceName: capture?.deviceName,
                inputSampleRate: capture?.sampleRate,
                inputDeviceNameAtRelease: capture?.deviceNameAtRelease,
                inputRestartCount: capture?.restartCount, inputDevices: capture?.deviceNames, inputAudioLost: capture?.audioLost, inputMissingMs: capture?.missingMs
            )
            #endif
            throw TranscriptionError.noResult  // defer resets to .idle
        }

        // Script validation: reject non-Latin output (ASR may output Cyrillic/CJK/Arabic
        // when spoken language doesn't match expectations — T-03-13 mitigation)
        guard !Self.containsNonLatinScript(trimmedText) else {
            throw TranscriptionError.unexpectedLanguage
        }

        // Post-hoc language detection restricted to {de, en} (D-13) — WhisperKit's native
        // result.language comes from auto-detect and drives decoding only; kept separate
        // per the 41-05 decision (lower-risk "nothing downstream changes").
        let detectedLanguage = detectLanguage(combinedText)

        // Confidence derived from segment avgLogprob (WhisperKit has no direct .confidence).
        let avgLogprobs = allSegments.map(\.avgLogprob)
        let meanLogprob = avgLogprobs.isEmpty ? 0 : avgLogprobs.reduce(0, +) / Float(avgLogprobs.count)
        let confidence = exp(meanLogprob)

        let transcriptionResult = DicticusTranscriptionResult(
            text: trimmedText,
            language: detectedLanguage,
            confidence: confidence
        )

        #if DEBUG_RECORDER
        // Quick task 261003-jej: per-token logprobs + word confidence for the cleanup record.
        // Logging only; staged under the exact text process() will receive.
        if let tokenizer = whisperKit.tokenizer {
            let traceStart = Date()
            let segments = allSegments.map { seg in
                DebugCleanupRecord.AsrSegment.build(
                    tokens: seg.tokens,
                    tokenLogProbs: seg.tokenLogProbs,
                    temperature: seg.temperature,
                    specialTokenBegin: tokenizer.specialTokens.specialTokenBegin,
                    decodeToken: { tokenizer.decode(tokens: [$0]) },
                    splitWords: { tokenizer.splitToWordTokens(tokenIds: $0) }
                )
            }
            let trace = DebugCleanupRecord.AsrTokenTrace(
                ms: Date().timeIntervalSince(traceStart) * 1000,
                segments: segments
            )
            await DebugRecorder.shared.stageAsrTokens(trace, rawText: trimmedText)
        }
        #endif

        return (transcriptionResult, avgLogprobs, allSegments.map(\.compressionRatio), gateDecision.maxFrameEnergy)
    }

    // MARK: - Adaptive voice gate support

    /// Compute per-frame RMS energies for AdaptiveVoiceGate, chunking `samples`
    /// into `frameLengthSeconds`-long windows (default 0.1s, matching the
    /// removed EnergyVAD's frame length) and reusing WhisperKit's own
    /// `AudioProcessor.calculateAverageEnergy(of:)` per chunk rather than
    /// hand-rolling an RMS calculation.
    static func frameEnergies(of samples: [Float], sampleRate: Double, frameLengthSeconds: Float = 0.1) -> [Float] {
        guard !samples.isEmpty else { return [] }
        let frameLengthSamples = max(1, Int(frameLengthSeconds * Float(sampleRate)))
        var energies: [Float] = []
        energies.reserveCapacity((samples.count + frameLengthSamples - 1) / frameLengthSamples)
        var start = 0
        while start < samples.count {
            let end = min(start + frameLengthSamples, samples.count)
            energies.append(AudioProcessor.calculateAverageEnergy(of: Array(samples[start..<end])))
            start = end
        }
        return energies
    }

    // MARK: - Resampling

    /// Resample audio from one sample rate to another.
    ///
    /// Primary path: AVAudioConverter (Apple's high-quality resampler, recommended per RESEARCH.md).
    /// Fallback: Linear interpolation if AVAudioConverter setup fails.
    ///
    /// - Parameter samples: Input audio samples at sourceSampleRate
    /// - Parameter sourceSampleRate: Native hardware sample rate (typically 44.1kHz or 48kHz)
    /// - Parameter targetSampleRate: Parakeet's required rate (16kHz)
    nonisolated static func resampleAudio(_ samples: [Float], from sourceSampleRate: Double, to targetSampleRate: Double) -> [Float] {
        // Primary path: AVAudioConverter
        guard let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sourceSampleRate,
            channels: 1,
            interleaved: false
        ),
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ),
        let converter = AVAudioConverter(from: sourceFormat, to: targetFormat),
        let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(samples.count))
        else {
            // Fallback to linear interpolation if AVAudioConverter setup fails
            return Self.resampleLinear(samples, from: sourceSampleRate, to: targetSampleRate)
        }

        // Copy samples into source buffer
        sourceBuffer.frameLength = AVAudioFrameCount(samples.count)
        if let channelData = sourceBuffer.floatChannelData?[0] {
            for i in 0..<samples.count {
                channelData[i] = samples[i]
            }
        }

        let ratio = targetSampleRate / sourceSampleRate
        let outputFrameCount = AVAudioFrameCount(Double(samples.count) * ratio)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else {
            return Self.resampleLinear(samples, from: sourceSampleRate, to: targetSampleRate)
        }

        var conversionError: NSError?
        
        // Fix for "Mutation of captured var 'didProvideData' in concurrently-executing code"
        // Use a class to wrap the boolean for thread-safe access in the closure.
        final class ConversionState: @unchecked Sendable { var didProvideData = false }
        let state = ConversionState()
        
        converter.convert(to: outputBuffer, error: &conversionError) { inNumPackets, outStatus in
            if state.didProvideData {
                outStatus.pointee = .endOfStream
                return nil
            }
            state.didProvideData = true
            outStatus.pointee = .haveData
            return sourceBuffer
        }

        if conversionError != nil {
            return Self.resampleLinear(samples, from: sourceSampleRate, to: targetSampleRate)
        }

        let frameCount = Int(outputBuffer.frameLength)
        guard let outputData = outputBuffer.floatChannelData?[0] else {
            return Self.resampleLinear(samples, from: sourceSampleRate, to: targetSampleRate)
        }
        return Array(UnsafeBufferPointer(start: outputData, count: frameCount))
    }

    /// Fallback resampler using linear interpolation.
    /// Used when AVAudioConverter setup fails (e.g., invalid format parameters).
    nonisolated static func resampleLinear(_ samples: [Float], from sourceSampleRate: Double, to targetSampleRate: Double) -> [Float] {
        let ratio = targetSampleRate / sourceSampleRate
        let outputLength = Int(Double(samples.count) * ratio)
        var output = [Float](repeating: 0, count: outputLength)

        for i in 0..<outputLength {
            let sourceIndex = Double(i) / ratio
            let lower = Int(sourceIndex)
            let upper = min(lower + 1, samples.count - 1)
            let fraction = Float(sourceIndex - Double(lower))
            output[i] = samples[lower] * (1.0 - fraction) + samples[upper] * fraction
        }

        return output
    }

    // MARK: - Script validation

    /// Latin Unicode scalar ranges that are allowed in transcription output.
    /// Covers Basic Latin, Latin Extended-A/B, Latin Extended Additional,
    /// Latin Extended-C, and Latin Extended-D blocks.
    private static let latinRanges: [ClosedRange<UInt32>] = [
        0x0000...0x007F,   // Basic Latin (ASCII)
        0x0080...0x00FF,   // Latin-1 Supplement (umlauts, accented chars)
        0x0100...0x024F,   // Latin Extended-A + B
        0x1E00...0x1EFF,   // Latin Extended Additional
        0x2C60...0x2C7F,   // Latin Extended-C
        0xA720...0xA7FF,   // Latin Extended-D
        0x0300...0x036F,   // Combining Diacritical Marks (accents on Latin base)
    ]

    /// Check if text contains non-Latin script characters (Cyrillic, CJK, Arabic, etc.).
    ///
    /// The ASR engine may output characters from unexpected scripts when the spoken
    /// language doesn't match well. This guard prevents garbled text from being injected
    /// at the user's cursor.
    ///
    /// Logic: any Unicode letter that is NOT in the Latin character sets is flagged.
    /// Numbers, punctuation, symbols, and combining marks are always allowed.
    ///
    /// Static so it can be unit tested without a WhisperKit instance.
    static func containsNonLatinScript(_ text: String) -> Bool {
        let log = Logger(subsystem: "com.dicticus", category: "validation")
        let letters = CharacterSet.letters
        
        // Symbols and punctuation we explicitly want to allow even if they aren't 'Latin'
        let allowedSymbols = CharacterSet(charactersIn: "$€£¥©®™°%‰#@&*-+=/\\|<>{}[]()\"'`^~_")
        let allowedPunctuation = CharacterSet.punctuationCharacters
        let allowedNumbers = CharacterSet.decimalDigits
        
        for scalar in text.unicodeScalars {
            // If it's a number, punctuation, or common symbol, it's fine.
            if allowedNumbers.contains(scalar) || allowedPunctuation.contains(scalar) || allowedSymbols.contains(scalar) {
                continue
            }
            
            // If it's a letter, check if it's in a Latin range.
            if letters.contains(scalar) {
                let value = scalar.value
                let isLatin = latinRanges.contains { $0.contains(value) }
                if !isLatin {
                    log.warning("Blocked non-Latin character: \(String(scalar)) (U+\(String(value, radix: 16)))")
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Language detection

    /// Word count below which NLLanguageRecognizer's unconstrained classification is too
    /// unreliable to trust for a third-language ("other") verdict — very short/ambiguous
    /// text (e.g. "ok", "hi") gets misclassified into unrelated languages at high confidence
    /// once the {de,en} constraint is lifted. Below this threshold we fall back to the
    /// original constrained behavior (always de or en).
    static let shortTextWordCountThreshold = 4

    /// Detect language of transcribed text. German and English classify as "de"/"en";
    /// any other confident classification on longer text returns "other" (D-08/MLANG-03,
    /// Phase 42-02) so non-de/en dictation can be routed to deterministic rules-only cleanup
    /// instead of the LLM. Empty/undetectable/very-short text still falls back to "en".
    ///
    /// WhisperKit's native `result.language` comes from auto-detect and drives decoding
    /// only (41-05 decision); we use Apple's NLLanguageRecognizer post-hoc on the
    /// transcribed text for the result's `language` field to keep this "nothing
    /// downstream changes" lower-risk.
    func detectLanguage(_ text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        let wordCount = text.split(whereSeparator: { $0.isWhitespace }).count
        if wordCount < Self.shortTextWordCountThreshold {
            recognizer.languageConstraints = [.german, .english]
        }
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else { return "en" }
        switch language {
        case .german: return "de"
        case .english: return "en"
        default: return "other"
        }
    }

    // MARK: - Language restriction

    /// Restrict a detected language code to the allowed set {de, en} (D-13 in 02.1-CONTEXT.md).
    ///
    /// Used as a validation layer after post-hoc language detection.
    /// Any other detected language defaults to English.
    ///
    /// - Parameter detected: Language code string
    /// - Returns: "de" or "en"
    func restrictLanguage(_ detected: String) -> String {
        let allowed: Set<String> = ["de", "en"]
        return allowed.contains(detected) ? detected : "en"
    }
}

extension TranscriptionService: DictationTranscribing {
    var statePublisher: AnyPublisher<State, Never> { $state.eraseToAnyPublisher() }
}

// MARK: - Test support

#if DEBUG
extension TranscriptionService {

    /// Static wrapper for `restrictLanguage` allowing unit tests to call it without
    /// a WhisperKit instance. This avoids a protocol-based architecture just for testing.
    ///
    /// Tests call: `TranscriptionService.testRestrictLanguage("fr") == "en"`
    static func testRestrictLanguage(_ detected: String) -> String {
        let allowed: Set<String> = ["de", "en"]
        return allowed.contains(detected) ? detected : "en"
    }

    /// Static wrapper for `detectLanguage` allowing unit tests to call it without
    /// a WhisperKit instance.
    ///
    /// Tests call: `TranscriptionService.testDetectLanguage("Dies ist ein Satz") == "de"`
    static func testDetectLanguage(_ text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        let wordCount = text.split(whereSeparator: { $0.isWhitespace }).count
        if wordCount < shortTextWordCountThreshold {
            recognizer.languageConstraints = [.german, .english]
        }
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else { return "en" }
        switch language {
        case .german: return "de"
        case .english: return "en"
        default: return "other"
        }
    }

    /// Returns true if the WhisperKit large-v3-turbo model is cached on this machine.
    /// Used by tests to conditionally skip model-dependent tests.
    static func isWhisperKitAvailable() -> Bool {
        let modelDir = AsrModelLoader.whisperDownloadBase()
            .appendingPathComponent(AsrModelLoader.whisperRepoSubpath)
            .appendingPathComponent(AsrModelLoader.modelName)
        return (try? FileManager.default.contentsOfDirectory(atPath: modelDir.path))?.isEmpty == false
    }

    /// Attempt to create a TranscriptionService using a WhisperKit-backed instance.
    /// Returns nil if initialization fails (model not cached, etc.).
    /// Used by tests that need an actual service instance.
    static func makeForTesting() async throws -> TranscriptionService? {
        do {
            let wk = try await AsrModelLoader.loadWhisperKit()
            return TranscriptionService(whisperKit: wk)
        } catch {
            return nil
        }
    }

    /// Replay already-captured samples through the live transcription path.
    ///
    /// Used by the archived-WAV replay harness (quick task 260802-ass) to measure ASR
    /// behaviour across recordings without an audio engine. Because it calls the same
    /// `transcribe(rawSamples:inputSampleRate:)` the hotkey path calls, the gates
    /// (duration, AdaptiveVoiceGate, NoSpeechDiscard) apply identically — a replay that
    /// throws `.silenceOnly` is a faithful reproduction, not a harness artifact.
    func testTranscribe(
        samples: [Float],
        inputSampleRate: Double
    ) async throws -> (result: DicticusTranscriptionResult, avgLogprobs: [Float], compressionRatios: [Float], gateMaxFrameEnergy: Float) {
        try await transcribe(rawSamples: samples, inputSampleRate: inputSampleRate)
    }

    /// Preview decoder on this service's own WhisperKit instance, as production wires it.
    func testMakeLivePreviewDecoder(buffer: AudioSampleBuffer, inputSampleRate: Double) -> LivePreviewDecoder {
        LivePreviewDecoder(whisperKit: whisperKit, buffer: buffer, inputSampleRate: inputSampleRate)
    }

    /// The service's model, for spike 019's preview decoder with a recording transcribe closure.
    var testWhisperKit: WhisperKit { whisperKit }

    /// Runs the same `finishTranscription` the hotkey release path runs, so the spike
    /// measures the release path that ships.
    func testReleaseAndTranscribe(
        previewSession: LivePreviewSession?,
        samples: [Float],
        inputSampleRate: Double
    ) async throws -> (result: DicticusTranscriptionResult, stats: LivePreviewSession.Stats?) {
        let out = try await finishTranscription(
            previewSession: previewSession,
            takeSamples: { samples },
            inputSampleRate: inputSampleRate
        )
        return (out.result, previewSession == nil ? nil : lastLivePreviewStats)
    }
}
#endif
