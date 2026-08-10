import SwiftUI
@preconcurrency import ActivityKit
import UIKit
@preconcurrency import AVFAudio
import UserNotifications

@MainActor
class DictationViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case preparingLiveActivity
        case recording
        case transcribing
    }

    @Published var state: State = .idle {
        didSet {
            // Publish isRecording flag to App Group defaults so DictateIntent
            // can toggle-to-stop without opening the app a second time (D-01a).
            let isRecording = state == .recording
            DicticusIPCBridge.defaults?.set(isRecording, forKey: DicticusIPCBridge.Key.isRecording)
            // Clear batch list when a new recording starts — stale batch must not linger
            // across sessions (the new session will produce its own delivery batch).
            if state == .recording {
                recentlyDelivered = []
            }
        }
    }
    @Published var lastResult: String?
    @Published var error: String?
    @Published var isShortcutLaunch: Bool = false
    /// Batch of transcripts delivered on the most-recent foreground return.
    /// Populated by `deliverPendingTranscriptsIfNeeded()` when ≥1 background sessions completed.
    /// The home screen shows a list when count > 1 (most-recent is already in `lastResult`).
    /// Cleared when a new recording starts.
    @Published var recentlyDelivered: [TranscriptionEntry] = []

    // Soft-cap intervals — injectable so unit tests can use tiny values (D-03).
    var capFinalizeSeconds: Double = 300  // 5:00 — auto-finalize
    var capWarningSeconds: Double = 270   // 4:30 — pre-cap warning


    // Set by DicticusApp once warmup completes (property injection). Phase 46-02:
    // recording no longer depends on this being non-nil — see startDictation().
    var transcriptionService: (any TranscriptionProviding)? {
        didSet {
            if transcriptionService != nil {
                error = nil
            }
        }
    }

    // Phase 46-02 (D-01): recorder is now independent of ASR model readiness.
    // Injectable so tests can drive DictationViewModel without a microphone.
    var audioRecorder: AudioRecording = AudioRecorder()
    // Phase 46-02 (D-01/D-09/D-10): durable queue of captured-but-not-yet-transcribed
    // recordings. Injectable so tests never touch the real user database.
    var pendingStore: PendingRecordingStore = .shared

    init() {
        audioRecorder.onSilenceDetected = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                // Disable silence auto-stop while backgrounded (Finding 2).
                // The user may pause to think/read in another app; killing the recording
                // after 2.5 s of silence would discard in-progress dictation silently.
                // The ~5-min soft cap and the Live Activity Stop button bound backgrounded
                // recordings. Foreground silence auto-stop (2.5 s) is preserved.
                guard !self.isBackgroundedProvider() else { return }
                await self.stopDictation()
            }
        }
    }

    // Phase 19 Wave 5: CleanupService injection seam (CLEAN-01 / CLEAN-02).
    // Set by DicticusApp once warmup Step 4 completes (property injection).
    // When non-nil + AppGroup `aiCleanupEnabled` is true, stopDictation routes
    // through TextProcessingService with mode=.aiCleanup. Consumed lazily at
    // stopDictation() time, so no didSet hook is needed.
    var cleanupService: CleanupProvider?

    // MARK: - Test seams (36-04)

    /// Test seam for backgrounded-state detection. Defaults to the real UIKit check.
    /// Injected in unit tests to avoid depending on real app lifecycle (UIApplication
    /// is not available in the test host without a running UIApplication).
    var isBackgroundedProvider: () -> Bool = {
        UIApplication.shared.applicationState != .active
    }

    /// Test seam for clipboard writes. Defaults to UIPasteboard.general.
    /// Injected in unit tests to assert "no clipboard write" without touching the real pasteboard.
    var clipboardWriter: (String) -> Void = { text in
        UIPasteboard.general.string = text
    }

    /// Test seam for notification posting. Defaults to the real UNUserNotificationCenter.
    /// Injected in unit tests to capture title/body without OS notification infrastructure.
    var notificationPoster: (_ title: String, _ body: String) async -> Void = { title, body in
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "transcriptReady-\(UUID().uuidString)",
            content: content,
            trigger: nil  // deliver immediately
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    // Test seam: injectable HistoryService. Defaults to .shared; tests inject makeForTesting.
    var historyService: HistoryService = .shared

    /// Test seam for the microphone permission request. Defaults to the real system
    /// API. Phase 46-02 removed the `transcriptionService != nil` guard that used to
    /// return `startDictation()` early — so this call is now reached on every
    /// invocation, including from tests. In a headless Simulator test run,
    /// `AVAudioApplication.requestRecordPermission()` has no window to present a TCC
    /// prompt against and blocks indefinitely (confirmed empirically), so tests MUST
    /// inject this seam rather than exercise the real API.
    var permissionRequester: () async -> Bool = {
        await AVAudioApplication.requestRecordPermission()
    }

    nonisolated(unsafe) private var currentActivity: Activity<DictationAttributes>?
    // WR-04: notificationObservers is accessed only from @MainActor context; no need for
    // nonisolated(unsafe) (which would disable Swift's concurrency check for this property
    // and allow silent data races from any future background Task access).
    private var notificationObservers: [NSObjectProtocol] = []
    private var finalizeBackgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var capWarningTask: Task<Void, Never>?
    private var capFinalizeTask: Task<Void, Never>?

    func startDictation(fromShortcut: Bool = false) async {
        guard state == .idle else {
            return
        }
        isShortcutLaunch = fromShortcut

        // Phase 46-02 (D-01/D-03): recording is gated on microphone permission ONLY.
        // No warm-up or model-availability check on this path — that guard is exactly
        // what made a jetsammed app's Shortcut dead (see 46-CONTEXT.md D-01..D-03).

        // STEP 1: Request microphone permission
        let permissionGranted = await permissionRequester()
        guard permissionGranted else {
            self.error = "Microphone access denied. Enable in Settings > Privacy > Microphone."
            return
        }

        // iOS 18 AudioRecordingIntent requires an active Live Activity when a background
        // audio session is active (confirmed by spike run 1 fatal crash without one).
        // The Live Activity uses startedAt:Date + Text(timerInterval:) for a widget-autonomous
        // elapsed timer that ticks without app-driven activity.update() calls.
        state = .recording
        do {
            // Persist start time so a freshly-launched process can detect a stale cap
            // and finalize-on-relaunch if the recording exceeded the cap while backgrounded (ADDENDUM B).
            DicticusIPCBridge.defaults?.set(Date().timeIntervalSince1970,
                                            forKey: DicticusIPCBridge.Key.recordingStartedAt)
            try startLiveActivity()
            _ = try audioRecorder.startRecording()
            startCapTimers()
            await requestNotificationAuthorizationIfNeeded()
        } catch {
            await endLiveActivity()
            self.error = error.localizedDescription
            state = .idle
        }
    }

    func stopDictation() async {
        guard state == .recording else {
            return
        }
        cancelCapTimers()
        state = .transcribing

        // Determine whether we are backgrounded BEFORE any async work.
        // isBackgroundedProvider is injectable for unit tests (avoids UIApplication dependency).
        let isBackgrounded = isBackgroundedProvider()

        // Phase 46-02 (D-01): stop the recorder to obtain a durable RecordingArtifact
        // FIRST, independent of whether a transcriber exists yet.
        let artifact: RecordingArtifact
        do {
            artifact = try audioRecorder.stopRecording()
        } catch {
            await endLiveActivity()
            DicticusIPCBridge.defaults?.removeObject(forKey: DicticusIPCBridge.Key.recordingStartedAt)
            self.error = error.localizedDescription
            state = .idle
            return
        }

        // A sub-threshold clip is a determination that there is nothing to
        // transcribe, not a failure to hold (D-01/D-10 apply to real audio only).
        if artifact.durationSeconds < Double(IOSTranscriptionService.minimumDurationSeconds) {
            try? FileManager.default.removeItem(at: artifact.fileURL)
            await endLiveActivity()
            DicticusIPCBridge.defaults?.removeObject(forKey: DicticusIPCBridge.Key.recordingStartedAt)
            self.error = "Recording too short."
            state = .idle
            return
        }

        // Durable BEFORE anything else can go wrong (D-01).
        guard let pendingRow = pendingStore.enqueue(artifact) else {
            await endLiveActivity()
            DicticusIPCBridge.defaults?.removeObject(forKey: DicticusIPCBridge.Key.recordingStartedAt)
            self.error = "Could not save recording."
            state = .idle
            return
        }

        guard let transcriptionService else {
            // D-05: no model yet — the interaction ends immediately, with no error and
            // no notification. The transcript arrives via drainPendingRecordingsIfNeeded()
            // once the model becomes ready.
            await endLiveActivity()
            DicticusIPCBridge.defaults?.removeObject(forKey: DicticusIPCBridge.Key.recordingStartedAt)
            error = nil
            state = .idle
            return
        }

        do {
            let result = try await transcriptionService.transcribe(wavURL: artifact.fileURL)

            if isBackgrounded {
                // BACKGROUND PATH (SPIKE constraints 1+2 / IOSBG-02):
                // - NEVER run GPU/Metal (LLM cleanup) — kIOGPUCommandBufferCallbackErrorBackgroundExecutionNotPermitted
                // - NEVER write UIPasteboard — iOS hard-blocks backgrounded clipboard writes
                // Force .plain so TextProcessingService runs only Dictionary→ITN (CPU, allowed).
                // The entry is saved by TextProcessingService.process() itself.
                let processor = TextProcessingService(cleanupService: nil,
                                                       historyService: self.historyService)
                _ = await processor.process(
                    text: result.text,
                    language: result.language,
                    mode: .plain,
                    confidence: Double(result.confidence)
                )

                // Append the most-recent persisted entry's UUID to the pending list.
                // TextProcessingService.process() calls HistoryService.save() + load() —
                // the new entry is now at .entries.first (createdAt DESC).
                // We query the most-recent UUID here because process() doesn't surface it.
                if let uuid = self.historyService.entries.first?.uuid {
                    let defaults = DicticusIPCBridge.defaults
                    var list = defaults?.stringArray(forKey: DicticusIPCBridge.Key.pendingTranscriptUUIDs) ?? []
                    list.append(uuid.uuidString)
                    defaults?.set(list, forKey: DicticusIPCBridge.Key.pendingTranscriptUUIDs)
                    // Also write the legacy single-key for any older build reading it.
                    defaults?.set(uuid.uuidString, forKey: DicticusIPCBridge.Key.pendingTranscriptUUID)
                }

                // Post away-stop notification (D-02a) — only on background path.
                // Body contains NO transcript text (T-36-08 / security).
                await notificationPoster("Dictation ready",
                                         "Recording stopped — your transcript is waiting. Tap to open Dicticus.")

            } else {
                // FOREGROUND PATH — unchanged from 36-02:
                // Toggle-respecting mode, TextProcessingService.process() (saves entry), clipboard write.
                let wantsAiCleanup = (UserDefaults(suiteName: "group.com.dicticus") ?? .standard).bool(forKey: "aiCleanupEnabled")
                let llmReady = cleanupService?.isLoaded ?? false
                let mode: DictationMode = Self.selectMode(wantsAiCleanup: wantsAiCleanup, llmReady: llmReady)

                // Route through the shared pipeline:
                //   Dictionary -> ITN -> Swiss ITN -> [LLM cleanup] -> History.
                // TextProcessingService.process() itself saves the TranscriptionEntry
                // (Step 4 of the pipeline) so we MUST NOT call HistoryService here
                // or every dictation would create a duplicate row.
                let processor = TextProcessingService(cleanupService: cleanupService,
                                                       historyService: self.historyService)
                let cleaned = await processor.process(
                    text: result.text,
                    language: result.language,
                    mode: mode,
                    confidence: Double(result.confidence)
                )

                clipboardWriter(cleaned)
                lastResult = cleaned
                // Do NOT tag pendingTranscriptUUID — foreground delivery is inline.
            }
            error = nil
            // Transcript delivered — the pending recording is resolved. Removes the
            // WAV bytes and the row (D-02).
            pendingStore.delete(pendingRow)

        } catch let transcriptionError as TranscriptionError {
            switch transcriptionError {
            case .tooShort:
                self.error = "Recording too short."
            case .silenceOnly:
                self.error = "No speech detected."
            case .noResult:
                self.error = "Could not understand audio."
            case .unexpectedLanguage:
                self.error = "Unsupported language detected."
            case .modelNotReady:
                self.error = "Model not ready."
            case .busy:
                self.error = "System busy."
            case .notRecording:
                self.error = "Not recording."
            }
            // Transcription failed — leave the pending row queued (D-10 hold). 46-03
            // adds markFailed()/retry(); for this plan the row simply stays queued.
        } catch {
            self.error = error.localizedDescription
        }

        await endLiveActivity()
        DicticusIPCBridge.defaults?.removeObject(forKey: DicticusIPCBridge.Key.recordingStartedAt)
        state = .idle
    }

    /// Finalize a recording that was stopped from a background context (e.g. StopDictationIntent
    /// invoked from the Live Activity). Wraps stopDictation() in a background task so the
    /// async transcribe tail completes before iOS suspends the process.
    func finalizeIfRecording() {
        guard state == .recording else { return }
        finalizeBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "FinalizeDictation") { [weak self] in
            self?.endFinalizeBackgroundTask()
        }
        Task { @MainActor in
            await stopDictation()
            endFinalizeBackgroundTask()
        }
    }

    private func endFinalizeBackgroundTask() {
        guard finalizeBackgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(finalizeBackgroundTask)
        finalizeBackgroundTask = .invalid
    }

    /// Testable seam for cleanup mode selection (D-13 / D-23 gating).
    static func selectMode(wantsAiCleanup: Bool, llmReady: Bool) -> DictationMode {
        return (wantsAiCleanup && llmReady) ? .aiCleanup : .plain
    }

    // MARK: - Soft-cap timers (D-03)

    func startCapTimers() {
        cancelCapTimers()
        capWarningTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(capWarningSeconds))
            guard !Task.isCancelled else { return }
            // Warning is best-effort foreground-only: activity.update() is blocked in
            // background audio mode (RESEARCH Pitfall 4). The auto-finalize at 5:00
            // is the load-bearing bound; the warning fires if the app is in foreground.
            if UIApplication.shared.applicationState == .active {
                self.error = "Recording will auto-stop soon (5-minute limit)."
            }
        }
        capFinalizeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(capFinalizeSeconds))
            guard !Task.isCancelled else { return }
            await self.stopDictation()
        }
    }

    private func cancelCapTimers() {
        capWarningTask?.cancel()
        capWarningTask = nil
        capFinalizeTask?.cancel()
        capFinalizeTask = nil
    }

    private func startLiveActivity() throws {
        let activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
        guard activitiesEnabled else { return }

        // ADDENDUM A: Reconcile orphaned Live Activities before requesting a new one.
        // Without this, a mid-recording termination leaves a permanent phantom "Recording…"
        // banner — the orphan's Stop button can't dismiss it because the new process has
        // no reference in `currentActivity`. Each new startLiveActivity() would stack
        // another duplicate, making lock-screen unrecoverable.
        reconcileOrphanedActivities()

        let startedAt = Date.now
        // staleDate backstop: if the app dies mid-recording the system auto-marks the
        // activity stale after cap + generous slack (ADDENDUM A — system-side safety net).
        let staleDate = startedAt.addingTimeInterval(capFinalizeSeconds + 60)
        currentActivity = try Activity.request(
            attributes: DictationAttributes(),
            content: ActivityContent(
                state: DictationAttributes.ContentState(isRecording: true, startedAt: startedAt),
                staleDate: staleDate
            ),
            pushType: nil
        )
    }

    private func endLiveActivity() async {
        await currentActivity?.end(
            ActivityContent(
                state: DictationAttributes.ContentState(isRecording: false, startedAt: Date.now),
                staleDate: nil
            ),
            dismissalPolicy: .after(.now + 3)
        )
        currentActivity = nil
    }

    /// Reconcile orphaned Live Activities (ADDENDUM A).
    /// Called on launch (from DicticusApp) and before each new recording to prevent
    /// phantom "Recording…" banners from a previous process that terminated mid-recording.
    func reconcileOrphanedActivities() {
        let allActivities = Activity<DictationAttributes>.activities
        for activity in allActivities {
            // An activity is orphaned if it's not backed by this process's currentActivity.
            // Any activity other than currentActivity is either a stale orphan or a
            // ghost from a prior process — end it immediately.
            if activity.id != currentActivity?.id {
                Task {
                    await activity.end(
                        ActivityContent(
                            state: DictationAttributes.ContentState(isRecording: false, startedAt: Date.now),
                            staleDate: nil
                        ),
                        dismissalPolicy: .immediate
                    )
                }
            }
        }
    }

    // MARK: - Foreground handling (D-02 / D-02b / D-05 / Finding 1 second-session fix)

    /// Central foreground handler called from DicticusApp's .active scenePhase event.
    ///
    /// Decision: when `pendingDictation` is true the user pressed the Action Button to start a
    /// NEW recording. The new session WINS — delivery is deferred to the next idle foreground.
    /// This eliminates the race where delivery sets state=.transcribing while startDictation()
    /// waits on guard state==.idle, leaving the app permanently stuck at .transcribing (Finding 1).
    ///
    /// Session-1 transcript is never lost: it remains persisted in History and stays tagged via
    /// pendingTranscriptUUID; deliverPendingTranscriptsIfNeeded() will deliver it on the NEXT
    /// foreground where the user is NOT immediately requesting a new recording.
    ///
    /// Factored into DictationViewModel (not kept in the View) so unit tests can drive it directly
    /// without depending on the real SwiftUI/App lifecycle.
    func handleForeground(pendingDictation: Bool) async {
        if pendingDictation {
            // New recording requested: skip delivery this cycle, start the session.
            // checkPendingIntent() consumes the pendingDictation flag and schedules startDictation()
            // after its 500 ms sleep, at which point state will be .idle (delivery never ran).
            checkPendingIntent()
        } else {
            // Normal idle foreground: deliver any transcript persisted while backgrounded,
            // drain any recording that was captured before the model was ready (D-05),
            // then check whether a pending intent arrived just before the phase transition.
            await deliverPendingTranscriptsIfNeeded()
            await drainPendingRecordingsIfNeeded()
            checkPendingIntent()
        }
    }

    // MARK: - Pending-recording drain (Phase 46-02/46-03, D-05/D-09/D-10/D-11)

    /// D-10/D-11: maps a failed transcription attempt to what happens to its audio.
    /// A named, directly-testable function rather than an inline switch, per
    /// 46-03-PLAN.md's "make it a named function ... so it is directly testable."
    ///
    /// | Outcome | Disposition | Why |
    /// |---|---|---|
    /// | `.tooShort` | discard | a sub-threshold clip is a determination there is nothing to transcribe |
    /// | `.silenceOnly` | discard | the gates concluded there is no speech — holding it would fill the queue with nothing said |
    /// | `.noResult`/`.unexpectedLanguage`/`.modelNotReady`/`.busy`/`.notRecording` | hold | something said may be in there and the attempt failed to get it out |
    /// | any other thrown error (I/O, decode, unreadable file) | hold | same — a WAV that won't open is held, not deleted; the user decides |
    enum RecordingFailureDisposition: Equatable {
        case discard
        case hold(reason: String)
    }

    static func failureDisposition(for error: Error) -> RecordingFailureDisposition {
        guard let transcriptionError = error as? TranscriptionError else {
            return .hold(reason: error.localizedDescription)
        }
        switch transcriptionError {
        case .tooShort, .silenceOnly:
            return .discard
        case .noResult:
            return .hold(reason: "Could not understand audio.")
        case .unexpectedLanguage:
            return .hold(reason: "Unsupported language detected.")
        case .modelNotReady:
            return .hold(reason: "Model not ready.")
        case .busy:
            return .hold(reason: "System busy.")
        case .notRecording:
            return .hold(reason: "Not recording.")
        }
    }

    /// Re-entrancy guard so two near-simultaneous triggers (e.g. `isReady` flipping
    /// AND a foreground return in the same instant) cannot both drain concurrently.
    private var isDrainingPendingRecordings = false

    /// Drains the FULL arrival-ordered queue of `PendingRecording`s (a recording
    /// captured before the ASR model was ready, or several stacked during one
    /// warm-up — D-09) once a transcriber is available. Called after
    /// `warmupService.isReady` publishes true, on every normal idle foreground, and
    /// from `retryPendingRecording(_:)`.
    ///
    /// Carries the same race-avoidance guard shape already applied twice to this
    /// codebase before this: `guard state == .idle` (as
    /// `deliverPendingTranscriptsIfNeeded()` does) and a `pendingDictation` App-Group
    /// re-check (as the `isLlmReady` handler in `DicticusApp.swift` does) — without
    /// both, a recording that arrives while this drain is mid-flight would reopen the
    /// WR-03 / Finding-1 double-start race.
    func drainPendingRecordingsIfNeeded() async {
        guard state == .idle else { return }
        guard let transcriptionService else { return }
        guard !isDrainingPendingRecordings else { return }

        let pendingDictation = DicticusIPCBridge.defaults?.bool(forKey: "pendingDictation") ?? false
        guard !pendingDictation else { return }

        isDrainingPendingRecordings = true
        defer { isDrainingPendingRecordings = false }

        await drainQueue(using: transcriptionService)
    }

    /// Entry point for the UI's Retry action (D-11, built by a later plan). Resets a
    /// failed row to `.queued` and immediately attempts a drain. Safe to call when no
    /// transcriber exists yet — `drainPendingRecordingsIfNeeded()`'s own guard makes
    /// that a no-op, leaving the row queued and waiting, matching the copy
    /// `46-UI-SPEC` promises ("we'll try again automatically once the model
    /// reloads").
    func retryPendingRecording(_ recording: PendingRecording) async {
        guard state == .idle else { return }
        pendingStore.requeue(recording)
        await drainPendingRecordingsIfNeeded()
    }

    /// Mirrors `deliverPendingTranscriptsIfNeeded()`'s "read the full batch, process
    /// each independently, don't abort on one failure" idiom: a failure on one row
    /// leaves the rest of the queue intact for the next trigger, rather than aborting
    /// the whole drain.
    private func drainQueue(using transcriptionService: any TranscriptionProviding) async {
        let isBackgrounded = isBackgroundedProvider()
        var deliveredWhileBackgrounded: [TranscriptionEntry] = []

        for row in pendingStore.queuedInArrivalOrder {
            guard let fileURL = try? pendingStore.fileURL(for: row) else { continue }
            pendingStore.markTranscribing(row)

            do {
                let result = try await transcriptionService.transcribe(wavURL: fileURL)

                // Mirrors stopDictation()'s background/foreground split exactly, so
                // the LLM never re-enters a default path: backgrounded is always
                // forced to .plain (GPU forbidden in background); foregrounded
                // follows the same toggle+readiness selection as every other
                // delivery path.
                let mode: DictationMode
                let cleanupProvider: CleanupProvider?
                if isBackgrounded {
                    mode = .plain
                    cleanupProvider = nil
                } else {
                    let wantsAiCleanup = (UserDefaults(suiteName: "group.com.dicticus") ?? .standard).bool(forKey: "aiCleanupEnabled")
                    let llmReady = cleanupService?.isLoaded ?? false
                    mode = Self.selectMode(wantsAiCleanup: wantsAiCleanup, llmReady: llmReady)
                    cleanupProvider = cleanupService
                }

                // TextProcessingService.process() saves the TranscriptionEntry itself
                // (Step 4 of the pipeline) — never call HistoryService here directly,
                // or every drained recording would double-write.
                let processor = TextProcessingService(cleanupService: cleanupProvider,
                                                       historyService: self.historyService)
                _ = await processor.process(
                    text: result.text,
                    language: result.language,
                    mode: mode,
                    confidence: Double(result.confidence)
                )

                if isBackgrounded, let entry = self.historyService.entries.first {
                    deliveredWhileBackgrounded.append(entry)
                    let defaults = DicticusIPCBridge.defaults
                    var list = defaults?.stringArray(forKey: DicticusIPCBridge.Key.pendingTranscriptUUIDs) ?? []
                    list.append(entry.uuid.uuidString)
                    defaults?.set(list, forKey: DicticusIPCBridge.Key.pendingTranscriptUUIDs)
                    defaults?.set(entry.uuid.uuidString, forKey: DicticusIPCBridge.Key.pendingTranscriptUUID)
                }

                // Resolved — removes the WAV bytes and the row (D-02).
                pendingStore.delete(row)
            } catch {
                switch Self.failureDisposition(for: error) {
                case .discard:
                    pendingStore.delete(row)
                case .hold(let reason):
                    pendingStore.markFailed(row, reason: reason)
                }
            }
        }

        // Batched notification (planner's discretion per 46-CONTEXT.md): exactly one
        // notification per drain pass that delivered at least one transcript while
        // backgrounded, not one per recording. No transcript text in the body under
        // any circumstances (T-36-08 / security) — the count-only body for N>1
        // extends that same constraint to the new batched case.
        if isBackgrounded, !deliveredWhileBackgrounded.isEmpty {
            if deliveredWhileBackgrounded.count == 1 {
                await notificationPoster("Dictation ready",
                                         "Recording stopped — your transcript is waiting. Tap to open Dicticus.")
            } else {
                await notificationPoster("Dictation ready",
                                         "\(deliveredWhileBackgrounded.count) transcripts are ready. Tap to open Dicticus.")
            }
        }
    }

    /// Deliver all pending transcripts (persisted while backgrounded) on foreground.
    /// Called from handleForeground() when no new recording is being started.
    ///
    /// Batch semantics: reads the full `pendingTranscriptUUIDs` list (appended by each background stop).
    ///
    /// Toggle ON + LLM ready: each pending entry is cleaned via the LLM, the History row is
    /// updated in place (same uuid/id, mode="cleanup"), and then the cleaned most-recent text
    /// goes to clipboard + lastResult. The pending list is cleared.
    ///
    /// Toggle OFF: all entries remain plain. Clipboard/lastResult/recentlyDelivered set to plain
    /// most-recent. Pending list cleared.
    ///
    /// Toggle ON + LLM not ready: deliver plain to clipboard/lastResult/recentlyDelivered for
    /// immediate UX, but do NOT clear the pending list — so the isLlmReady retry can clean and
    /// persist once the LLM finishes warming up. Once an entry has mode="cleanup" it is skipped
    /// by the retry (idempotent).
    ///
    /// Legacy migration: if only the old single `pendingTranscriptUUID` key is present (no list
    /// key), treat it as a one-element list so pending transcripts from older builds are not lost.
    func deliverPendingTranscriptsIfNeeded() async {
        // Skip delivery if a recording/transcription is already in progress.
        // This prevents a race where the .active scenePhase handler sets state=.transcribing
        // while startDictation() (triggered by a second Action Button press) is waiting on
        // guard state == .idle — the guard would fail and the second session would silently
        // no-op, leaving an orphaned Live Activity as the only stop surface (Finding 1).
        guard state == .idle else { return }

        let defaults = DicticusIPCBridge.defaults

        // Resolve pending UUID list — support both new list key and legacy single-key.
        var pendingUUIDStrings: [String] = defaults?.stringArray(forKey: DicticusIPCBridge.Key.pendingTranscriptUUIDs) ?? []
        if pendingUUIDStrings.isEmpty,
           let legacyUUID = defaults?.string(forKey: DicticusIPCBridge.Key.pendingTranscriptUUID),
           !legacyUUID.isEmpty {
            // Migrate legacy single key into a one-element list.
            pendingUUIDStrings = [legacyUUID]
        }

        guard !pendingUUIDStrings.isEmpty else {
            return  // No pending — common foreground-stop case delivered inline.
        }

        // Resolve all pending entries from History (order: oldest first — matches append order).
        let allEntries = self.historyService.entries
        let pendingEntries: [TranscriptionEntry] = pendingUUIDStrings.compactMap { uuidString in
            guard let uuid = UUID(uuidString: uuidString) else { return nil }
            return allEntries.first(where: { $0.uuid == uuid })
        }

        guard !pendingEntries.isEmpty else {
            // No entries found — clear stale tags and return.
            defaults?.removeObject(forKey: DicticusIPCBridge.Key.pendingTranscriptUUIDs)
            defaults?.removeObject(forKey: DicticusIPCBridge.Key.pendingTranscriptUUID)
            return
        }

        // Show processing state while cleanup may run (D-02b).
        state = .transcribing

        let wantsAiCleanup = (UserDefaults(suiteName: "group.com.dicticus") ?? .standard).bool(forKey: "aiCleanupEnabled")
        let llmReady = cleanupService?.isLoaded ?? false

        if wantsAiCleanup && llmReady, let cs = cleanupService {
            // Toggle ON + LLM ready: clean EACH pending entry and persist to History.
            // Entries already cleaned (mode == "cleanup") are skipped — idempotent retry.
            var cleanedEntries: [TranscriptionEntry] = []
            var anyPersistFailed = false
            for entry in pendingEntries {
                if entry.mode == "cleanup" {
                    // Already cleaned by a prior retry — no duplicate work.
                    cleanedEntries.append(entry)
                    continue
                }
                let cleanedText = await cs.cleanup(
                    text: entry.text,
                    language: entry.language,
                    dictionaryContext: nil
                )
                var updated = entry
                updated.text = cleanedText
                updated.mode = "cleanup"
                // CR-02: look up the persisted entry by UUID to guarantee id is the
                // real SQLite rowid (in-memory `entry` may have been constructed without
                // a save round-trip in edge cases). If the lookup fails, fall back to
                // the in-memory copy — update() will log and return false if id == nil.
                let persisted = self.historyService.entries.first(where: { $0.uuid == entry.uuid })
                if let persisted {
                    updated.id = persisted.id
                }
                let persistOK = self.historyService.update(updated)
                if !persistOK {
                    anyPersistFailed = true
                }
                cleanedEntries.append(updated)
            }
            // Reload so the in-memory entries list reflects persisted cleaned text.
            self.historyService.load()

            guard let mostRecentCleaned = cleanedEntries.last else {
                // Defensive: loop produced no output (Task cancelled mid-cleanup?).
                state = .idle; return
            }
            clipboardWriter(mostRecentCleaned.text)
            lastResult = mostRecentCleaned.text
            recentlyDelivered = cleanedEntries.reversed()
            error = nil

            // Only clear the pending list when every persist succeeded.
            // If any persist failed, leave the list so the next foreground can retry.
            if !anyPersistFailed {
                defaults?.removeObject(forKey: DicticusIPCBridge.Key.pendingTranscriptUUIDs)
                defaults?.removeObject(forKey: DicticusIPCBridge.Key.pendingTranscriptUUID)
            }

        } else if !wantsAiCleanup {
            // Toggle OFF: plain is the final output. Deliver and clear the list.
            guard let mostRecent = pendingEntries.last else {
                state = .idle; return
            }
            clipboardWriter(mostRecent.text)
            lastResult = mostRecent.text
            recentlyDelivered = pendingEntries.reversed()
            error = nil

            defaults?.removeObject(forKey: DicticusIPCBridge.Key.pendingTranscriptUUIDs)
            defaults?.removeObject(forKey: DicticusIPCBridge.Key.pendingTranscriptUUID)

        } else {
            // Toggle ON + LLM not yet ready: deliver plain now for immediate UX,
            // but leave the pending list intact so the isLlmReady retry can clean + persist.
            guard let mostRecent = pendingEntries.last else {
                state = .idle; return
            }
            clipboardWriter(mostRecent.text)
            lastResult = mostRecent.text
            recentlyDelivered = pendingEntries.reversed()
            error = nil
            // DO NOT clear pendingTranscriptUUIDs — the LLM-ready retry needs it.
        }

        state = .idle
    }

    // MARK: - Notification (D-02a)

    /// Request notification authorization just-in-time with .provisional (silent, no blocking dialog).
    /// Called from startDictation() so authorization is sought without blocking the capture/persist/deliver path.
    /// A denied/undetermined permission MUST NOT prevent persistence or foreground delivery.
    private func requestNotificationAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        // .provisional delivers silently to Notification Center; no alert dialog shown to user.
        try? await center.requestAuthorization(options: [.alert, .sound, .provisional])
    }

    func setupNotificationObserver() {
        // CR-03: re-entry guard — ContentView's .task {} can re-run on every view re-appear
        // (sheet dismiss, tab switch). Without this guard each re-appear would add a second
        // pair of observers, eventually producing duplicate startDictation/stopDictation calls.
        guard notificationObservers.isEmpty else { return }

        let startObserver = NotificationCenter.default.addObserver(
            forName: .startDictation,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.startDictation()
            }
        }
        notificationObservers.append(startObserver)

        let stopObserver = NotificationCenter.default.addObserver(
            forName: .stopDictation,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.stopDictation()
            }
        }
        notificationObservers.append(stopObserver)

        checkPendingIntent()
    }

    func checkPendingIntent() {
        let shared = DicticusIPCBridge.defaults
        let hasPending = shared?.bool(forKey: "pendingDictation") == true
        if hasPending {
            shared?.set(false, forKey: "pendingDictation")
            let shortcut = shared?.bool(forKey: "isShortcutLaunch") ?? false
            shared?.set(false, forKey: "isShortcutLaunch")
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                await self.startDictation(fromShortcut: shortcut)
            }
        }
    }

    @MainActor deinit {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
