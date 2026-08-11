import Foundation
import SwiftUI
import UIKit
@preconcurrency import AVFoundation
import os

/// Result of a completed recording — the durable unit `AudioRecorder` hands off to
/// `PendingRecordingStore`. Contains no ASR/model state: this type exists precisely so
/// captured audio can outlive the ASR model's absence (Phase 46 D-01).
struct RecordingArtifact: Sendable {
    let uuid: UUID
    let fileURL: URL
    let durationSeconds: Double
}

/// Errors thrown by `AudioRecorder` during the capture lifecycle. Deliberately
/// disjoint from `TranscriptionError` — the recorder has no ASR dependency at all.
enum RecorderError: Error {
    case busy
    case notRecording
    case fileCreationFailed
}

/// Injection seam so `DictationViewModel` can be driven in tests without a microphone.
/// Load-bearing for Task 2's end-to-end assertion, not decoration.
@MainActor
protocol AudioRecording: AnyObject {
    var isRecording: Bool { get }
    func startRecording() throws -> UUID
    func stopRecording() throws -> RecordingArtifact
    func cancelRecording()
    var onSilenceDetected: (() -> Void)? { get set }
}

/// Tap-to-disk WAV writer, deliberately separate from `AudioRecorder` itself so it is
/// unit-testable with synthesized buffers (Task 2) without driving `AVAudioEngine` or
/// the microphone. All state is guarded by an `NSLock`, mirroring the concurrency
/// discipline of the in-memory `AudioSampleBuffer` this replaces
/// (`IOSTranscriptionService.swift`, pre-46-02).
final class RecordingFileWriter: @unchecked Sendable {
    private static let log = Logger(subsystem: "com.dicticus", category: "audioRecorder")

    private let lock = NSLock()
    private let url: URL
    private let sampleRate: Double
    private var file: AVAudioFile?
    private var framesWritten: AVAudioFramePosition = 0

    init(url: URL, format: AVAudioFormat) throws {
        self.url = url
        self.sampleRate = format.sampleRate
        self.file = try AVAudioFile(forWriting: url, settings: format.settings)
    }

    /// Appends one tap-delivered buffer to the file. An I/O failure here must never
    /// crash the real-time tap callback — it is logged and swallowed. The 46-03
    /// relaunch-recovery scan is the safety net for a partially-written file, not
    /// this call site.
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard let file else { return }
        do {
            try file.write(from: buffer)
            framesWritten += AVAudioFramePosition(buffer.frameLength)
        } catch {
            Self.log.error("Failed to append audio buffer to \(self.url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Releases the file object (finalizing its RIFF header) and returns the
    /// recorded duration, derived from frames written rather than any external clock.
    @discardableResult
    func finalize() -> Double {
        lock.lock()
        defer { lock.unlock() }
        let duration = sampleRate > 0 ? Double(framesWritten) / sampleRate : 0
        file = nil
        return duration
    }

    /// Releases the file object and removes the partial file from disk. Used by
    /// `cancelRecording()` and by any early-exit path in `startRecording()`.
    func discard() {
        lock.lock()
        defer { lock.unlock() }
        file = nil
        try? FileManager.default.removeItem(at: url)
    }
}

/// Tracks the auto-stop silence window across tap callbacks. File-scope (not nested
/// in `installTap`) so `AudioRecorder.processTapBuffer` — and its tests — can
/// construct a fresh one without driving `AVAudioEngine`.
final class SilenceTracker: @unchecked Sendable {
    var startTime = Date()
    var lastSoundTime = Date()
    var didTrigger = false
}

/// One-shot gate so the D-04 haptic fires exactly once per recording, on the first
/// buffer the tap actually delivers. File-scope so `AudioRecorderTests` can assert
/// the exactly-once/zero-before-any-buffer behavior directly.
final class FirstBufferGate: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    func fireIfNeeded() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if fired { return false }
        fired = true
        return true
    }
}

/// Records the microphone straight to a WAV file on disk, with zero ASR/model
/// dependency — deliberately not importing WhisperKit or NaturalLanguage. This is the
/// structural cut Phase 46 exists to make: recording can start, run, and finish
/// whether or not an ASR model is loaded.
@MainActor
final class AudioRecorder: AudioRecording {
    private static let log = Logger(subsystem: "com.dicticus", category: "audioRecorder")

    private let audioEngine = AVAudioEngine()
    private var writer: RecordingFileWriter?
    private var currentUUID: UUID?
    private var currentFileURL: URL?

    private(set) var isRecording = false

    @AppStorage("useAutoStop", store: DicticusIPCBridge.defaults)
    var useAutoStop = true

    let autoStopSilenceSeconds: Double = 2.5
    let autoStopGracePeriod: Double = 3.0

    /// Callback triggered when Auto-Stop detects sustained silence.
    var onSilenceDetected: (() -> Void)?

    /// Settable seam so the D-04 haptic-timing assertion is testable without haptic
    /// hardware. Fires exactly once per recording START, on the first buffer the
    /// tap actually delivers — never at intent-fire or button-tap time.
    ///
    /// 46-03 device-UAT (Section C, round 2, resolved 2026-08-10): a single
    /// `.medium` impact DOES fire on every real invocation path with the app
    /// foreground — both original hypotheses (missing `.prepare()`, app-not-
    /// foreground) were dead; the original "I didn't feel any specific haptic"
    /// report was a perception miss on a weak impact, not a missing call.
    ///
    /// 46-03 device-UAT (Section C, round 3): raising the SAME single impact to
    /// `.heavy` was device-confirmed still insufficient — user, verbatim: "it's
    /// still just a very faint tap." This is itself useful evidence: the ceiling
    /// on a single `UIImpactFeedbackGenerator` impact sits below this user's
    /// real-world noticeability threshold (phone in hand/pocket/on a desk,
    /// attention elsewhere) — chasing more intensity on one impulse is a dead
    /// end. Per the user's own suggestion, this now fires a short PATTERN
    /// (`fireHapticPattern`, below) rather than one impulse.
    ///
    /// `UINotificationFeedbackGenerator(.success)` (a system-defined pattern) was
    /// considered and rejected in favor of a custom multi-impact sequence: (1) a
    /// single `.heavy` impact is already CONFIRMED to physically register on
    /// this exact user's exact device, just too faintly — building on that same
    /// proven primitive with repetition is lower-risk than switching to an
    /// entirely different generator class whose felt intensity on this specific
    /// device/wear level is unverified; (2) `.success`'s semantic label ("a task
    /// just completed") is a worse fit for D-04's actual event (capture just
    /// BEGAN, an ongoing state, not a finished one) than a deliberate multi-tap
    /// that reads as "this is now ON"; (3) the user explicitly asked for "a
    /// double or triple tap," which a custom sequence implements directly.
    /// 46-03 device-UAT (Section C, round 5 — ROOT CAUSE FOUND): rounds 2-4's
    /// per-impact instrumentation proved, with data, that all 3 impacts fired
    /// every time, ~130ms apart, `appState=active` at each one — the pattern
    /// loop, the generator, and the foreground state were never the problem.
    /// The actual cause: `AVAudioSession.setAllowHapticsAndSystemSoundsDuringRecording`
    /// defaults to `false`, and iOS suppresses `UIFeedbackGenerator` haptics
    /// while a session is actively using audio input — specifically so the
    /// Taptic Engine's own motor noise cannot bleed into the recording.
    /// `startRecording()` now sets it `true` before activating the session
    /// (see the comment there). Three rounds of raising intensity/adding a
    /// pattern achieved nothing because none of them addressed suppression.
    ///
    /// **Reverted from round 4's 3x pattern back to a SINGLE impact** now
    /// that the actual blocker is gone — recommended, not defaulted: (1) a
    /// single `.heavy` impact was already the round-2/3 baseline and is
    /// expected to be more than sufficient once it can actually be felt at
    /// all, since suppression (not weakness) explains every prior "too
    /// faint"/"nothing" report, including round 3's; (2) a ~360ms rhythmic
    /// triple-tap right at the start of every recording is real audio-bleed
    /// exposure now that haptics are unmuted during capture — the iPhone's
    /// mic sits physically close to the Taptic Engine, and a burst pattern
    /// risks an audible artifact in the user's actual dictation content in a
    /// way a single brief click does not; (3) Apple defaults this flag off
    /// specifically because of that bleed risk, which is a signal to keep
    /// the haptic itself minimal even once permitted, not to treat the
    /// default as an obstacle to work around with a longer pattern.
    /// `fireHapticPattern`'s count is still fully parameterized — if a single
    /// impact turns out insufficient once genuinely felt (not suppressed),
    /// widening back to 2-3 is a one-argument change, not a redesign.
    var hapticTrigger: @MainActor @Sendable () async -> Void = {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        // haptic_fired/haptic_impact instrumentation kept per explicit
        // instruction — device re-confirmation is still needed. See
        // 46-DEVICE-TEST-PROCEDURE.md Section C.
        await AudioRecorder.fireHapticPattern(
            impactCount: 1,
            spacingMilliseconds: AudioRecorder.hapticPatternSpacingMilliseconds
        ) { index in
            generator.impactOccurred()
            await AudioRecorder.logHapticImpact(index: index)
        }
    }

    /// Per-impact diagnostic (46-03 round 4): logs the index and
    /// `UIApplication.shared.applicationState` at the instant EACH impact in
    /// the pattern actually fires — not just once for the whole pattern. If
    /// fewer than `impactCount` entries appear in `memprobe.jsonl` for a given
    /// recording, the pattern loop is not completing (cancelled Task,
    /// deallocated generator, early return); if all entries appear but the user
    /// still feels only one/zero, the OS is coalescing or suppressing them.
    static func logHapticImpact(index: Int) async {
        let stateDescription: String
        switch UIApplication.shared.applicationState {
        case .active: stateDescription = "active"
        case .inactive: stateDescription = "inactive"
        case .background: stateDescription = "background"
        @unknown default: stateDescription = "unknown"
        }
        await MemoryProbe.shared.mark("haptic_impact", note: "index=\(index) appState=\(stateDescription)")
    }

    /// 120ms between impacts: tight enough that the three impulses read as one
    /// cohesive pattern (not disconnected, unrelated taps), loose enough that
    /// each impulse is individually perceptible rather than blurring into one
    /// longer buzz — in the same range published multi-impulse haptic patterns
    /// (including Apple's own system `UINotificationFeedbackGenerator` patterns,
    /// per community teardown analysis) typically use internally.
    static let hapticPatternSpacingMilliseconds: UInt64 = 120

    /// Fires `impactCount` discrete impacts, `spacingMilliseconds` apart,
    /// invoking `impact` for each one. Extracted as a standalone, directly
    /// testable primitive so the D-04 pattern's SHAPE (count/spacing) is
    /// assertable without real haptic hardware or `UIImpactFeedbackGenerator` —
    /// `impact` is injected, matching this file's existing seam-injection style.
    ///
    /// Does NOT block or delay the start of capture: `AVAudioEngine` recording
    /// is already running by the time `onFirstBuffer()` (which awaits this) is
    /// invoked — the tap callback that calls it is itself wrapped in a
    /// fire-and-forget `Task { @MainActor in ... }` at the call site in
    /// `startRecording()`, so nothing in the real-time audio path ever awaits
    /// this function's completion.
    static func fireHapticPattern(
        impactCount: Int,
        spacingMilliseconds: UInt64,
        impact: (Int) async -> Void
    ) async {
        for i in 0..<impactCount {
            await impact(i)
            if i < impactCount - 1 {
                try? await Task.sleep(nanoseconds: spacingMilliseconds * 1_000_000)
            }
        }
    }

    /// 46-03 device-UAT instrumentation (Section C re-investigation, "no haptic
    /// felt at all"): best-effort description of how this recording was invoked,
    /// set by `DictationViewModel.startDictation(fromShortcut:)` immediately
    /// before calling `startRecording()`. Deliberately a plain stored property on
    /// the concrete class, not the `AudioRecording` protocol — so no test double
    /// needs to change for a diagnostic that exists purely to discriminate H-A
    /// (missing `.prepare()`) from H-B (app not foreground when it fires) from
    /// H-C (System Haptics/Silent/Low-Power-suppressed on the device). See
    /// `46-DEVICE-TEST-PROCEDURE.md` Section C.
    var lastInvocationContext: String = "unknown"

    /// Resolves (and creates, if needed) the app-private directory pending recordings
    /// are written to. Deliberately NOT the App Group container — the widget and
    /// intents never need the raw audio (T-46-05 mitigation is a bare filename in
    /// `PendingRecording`; this is the T-46-03 mitigation of not sharing the
    /// container in the first place). `completeUnlessOpen` (not `complete`) so a
    /// recording that continues after the screen locks is not broken mid-write.
    static func recordingsDirectory() throws -> URL {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw RecorderError.fileCreationFailed
        }
        let dir = appSupport.appendingPathComponent("Dicticus", isDirectory: true)
            .appendingPathComponent("PendingRecordings", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUnlessOpen]
        )
        var mutableDir = dir
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try mutableDir.setResourceValues(resourceValues)
        return dir
    }

    func startRecording() throws -> UUID {
        guard !isRecording else { throw RecorderError.busy }

        // iOS ONLY: activate AVAudioSession with .playAndRecord so the mic session
        // survives backgrounding (UIBackgroundModes: audio keeps it alive).
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        // 46-03 device-UAT (Section C, round 5 — root cause): confirmed via
        // AVAudioSession.h (iOS 13+, default NO) — iOS suppresses
        // UIFeedbackGenerator haptics while a session is actively using audio
        // input, specifically so the Taptic Engine's motor noise cannot bleed
        // into the recording. Rounds 2-4's probe data proved every impact
        // genuinely fired, foreground, at the configured spacing — the
        // confirmation signal was being suppressed by the very thing it exists
        // to confirm. Set BEFORE setActive(true), alongside the other session
        // configuration (category/mode/options) — this governs behavior for
        // the session's whole active lifetime, not a one-shot call, so it
        // belongs with the rest of the "prepare, then activate" sequence.
        // Re-applied on every startRecording() call rather than assumed to
        // persist across a prior setActive(false) — Apple's header does not
        // document persistence either way, and re-applying costs nothing.
        try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        try session.setActive(true)

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        let uuid = UUID()
        let destinationURL: URL
        let newWriter: RecordingFileWriter
        do {
            let dir = try Self.recordingsDirectory()
            destinationURL = dir.appendingPathComponent("\(uuid.uuidString).wav")
            // Write in the hardware's native format and trust the WAV header — do not
            // carry sample rate/channel count out of band, because a later transcribe
            // pass may run in a fresh process with no access to this AVAudioFormat.
            newWriter = try RecordingFileWriter(url: destinationURL, format: inputFormat)
        } catch {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw RecorderError.fileCreationFailed
        }

        writer = newWriter
        currentUUID = uuid
        currentFileURL = destinationURL

        let localHapticTrigger = hapticTrigger
        let localInvocationContext = lastInvocationContext

        Self.installTap(
            on: inputNode,
            format: inputFormat,
            writer: newWriter,
            autoStopEnabled: useAutoStop,
            silenceThreshold: 0.01, // RMS threshold for "silence"
            silenceDuration: autoStopSilenceSeconds,
            gracePeriod: autoStopGracePeriod,
            onSilence: { [weak self] in
                Task { @MainActor in
                    self?.onSilenceDetected?()
                }
            },
            onFirstBuffer: {
                Task { @MainActor in
                    // 46-03 device-UAT instrumentation (Section C): capture the
                    // decisive datum — app state at the instant confirmation
                    // BEGINS (before the multi-impact pattern's ~240ms runtime,
                    // not after) — via the already-established memprobe.jsonl
                    // sink (-memProbe 1 launch arg; no-op and zero overhead
                    // otherwise). See 46-DEVICE-TEST-PROCEDURE.md Section C.
                    let stateDescription: String
                    switch UIApplication.shared.applicationState {
                    case .active: stateDescription = "active"
                    case .inactive: stateDescription = "inactive"
                    case .background: stateDescription = "background"
                    @unknown default: stateDescription = "unknown"
                    }
                    await MemoryProbe.shared.mark(
                        "haptic_fired",
                        note: "appState=\(stateDescription) invocation=\(localInvocationContext)"
                    )
                    await localHapticTrigger()
                }
            }
        )

        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            newWriter.discard()
            writer = nil
            currentUUID = nil
            currentFileURL = nil
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }

        isRecording = true
        return uuid
    }

    /// Install audio tap in a nonisolated context so the closure has no actor affinity.
    /// Mirrors the pre-46-02 `IOSTranscriptionService.installTap` auto-stop logic
    /// verbatim — only the destination (writer, not an in-memory buffer) changed.
    /// The per-buffer body is extracted into `processTapBuffer` (below) so it is
    /// directly testable with synthesized buffers, without driving `AVAudioEngine`.
    nonisolated private static func installTap(
        on inputNode: AVAudioInputNode,
        format: AVAudioFormat,
        writer: RecordingFileWriter,
        autoStopEnabled: Bool,
        silenceThreshold: Float,
        silenceDuration: Double,
        gracePeriod: Double,
        onSilence: @escaping @Sendable () -> Void,
        onFirstBuffer: @escaping @Sendable () -> Void
    ) {
        let tracker = SilenceTracker()
        let firstBufferGate = FirstBufferGate()

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) {
            pcmBuffer, _ in
            processTapBuffer(
                pcmBuffer,
                writer: writer,
                tracker: tracker,
                firstBufferGate: firstBufferGate,
                autoStopEnabled: autoStopEnabled,
                silenceThreshold: silenceThreshold,
                silenceDuration: silenceDuration,
                gracePeriod: gracePeriod,
                onSilence: onSilence,
                onFirstBuffer: onFirstBuffer
            )
        }
    }

    /// Processes exactly one tap-delivered buffer: appends it to the writer, fires
    /// `onFirstBuffer` exactly once per recording (D-04 — the haptic must mark the
    /// real start of capture, not intent-fire time), and evaluates the auto-stop
    /// silence tracker. `nonisolated` and side-effect-scoped to its arguments (no
    /// AudioRecorder/actor state) so it is callable directly from tests with
    /// synthesized `AVAudioPCMBuffer`s and fresh `SilenceTracker`/`FirstBufferGate`
    /// instances — the load-bearing seam for the D-04 haptic-timing assertion.
    nonisolated static func processTapBuffer(
        _ pcmBuffer: AVAudioPCMBuffer,
        writer: RecordingFileWriter,
        tracker: SilenceTracker,
        firstBufferGate: FirstBufferGate,
        autoStopEnabled: Bool,
        silenceThreshold: Float,
        silenceDuration: Double,
        gracePeriod: Double,
        onSilence: () -> Void,
        onFirstBuffer: () -> Void
    ) {
        writer.append(pcmBuffer)

        if firstBufferGate.fireIfNeeded() {
            onFirstBuffer()
        }

        guard autoStopEnabled, let channelData = pcmBuffer.floatChannelData?[0] else { return }
        let frameCount = Int(pcmBuffer.frameLength)
        guard frameCount > 0 else { return }

        let now = Date()
        let elapsedTotal = now.timeIntervalSince(tracker.startTime)

        // Simple RMS calculation to detect "sound"
        var sum: Float = 0
        for i in 0..<frameCount { let sample = channelData[i]; sum += sample * sample }
        let rms = sqrt(sum / Float(frameCount))

        if rms > silenceThreshold {
            tracker.lastSoundTime = now
        } else if !tracker.didTrigger && elapsedTotal > gracePeriod {
            let silenceElapsed = now.timeIntervalSince(tracker.lastSoundTime)
            if silenceElapsed >= silenceDuration {
                tracker.didTrigger = true
                onSilence()
            }
        }
    }

    func stopRecording() throws -> RecordingArtifact {
        guard isRecording else { throw RecorderError.notRecording }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        // Release the mic session on every exit path (success or throw). Without this
        // the AVAudioSession stays active after a stop, and the next
        // AudioRecordingIntent (Action Button session 2) fatal-asserts: "active audio
        // session but without a Live Activity" (device-only).
        defer { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }

        let duration = writer?.finalize() ?? 0
        let uuid = currentUUID
        let url = currentFileURL

        writer = nil
        currentUUID = nil
        currentFileURL = nil
        isRecording = false

        guard let uuid, let url else { throw RecorderError.fileCreationFailed }
        return RecordingArtifact(uuid: uuid, fileURL: url, durationSeconds: duration)
    }

    func cancelRecording() {
        guard isRecording else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        writer?.discard()
        writer = nil
        currentUUID = nil
        currentFileURL = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
