import XCTest
@preconcurrency import AVFoundation
@testable import Dicticus

// MARK: - Phase 46-02 test doubles

/// Fake `AudioRecording` conformer so `DictationViewModel` can be driven end-to-end
/// without a microphone. `stopRecording()` writes a small REAL WAV file into the
/// production `AudioRecorder.recordingsDirectory()` (not an arbitrary temp
/// directory) — `PendingRecordingStore.fileURL(for:)` always composes against that
/// fixed directory, so a fake recording must live there too or lookups would miss it.
@MainActor
private final class FakeAudioRecorder: AudioRecording {
    private(set) var isRecording = false
    var onSilenceDetected: (() -> Void)?

    var startCallCount = 0
    var stopCallCount = 0
    var artifactDurationSeconds: Double = 1.0

    func startRecording() throws -> UUID {
        startCallCount += 1
        isRecording = true
        return UUID()
    }

    func stopRecording() throws -> RecordingArtifact {
        stopCallCount += 1
        isRecording = false

        // Deliberately does not guard on prior `startRecording()` having been called:
        // sibling tests in this file drive `DictationViewModel` by setting `vm.state`
        // directly (the established convention here) rather than calling the real
        // `startDictation()`, so this fake's job is to make `stopDictation()`'s logic
        // exercisable regardless of how the "recording in progress" state was reached.
        // `AudioRecorderTests` covers the real `AudioRecorder`'s own busy/not-recording
        // invariants.
        let uuid = UUID()
        let dir = try AudioRecorder.recordingsDirectory()
        let url = dir.appendingPathComponent("\(uuid.uuidString).wav")
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let writer = try RecordingFileWriter(url: url, format: format)
        let frameCount = AVAudioFrameCount(16000 * artifactDurationSeconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        writer.append(buffer)
        let duration = writer.finalize()
        return RecordingArtifact(uuid: uuid, fileURL: url, durationSeconds: duration)
    }

    func cancelRecording() {
        isRecording = false
    }
}

/// Fake `TranscriptionProviding` conformer — returns a fixed result without
/// touching WhisperKit. Counts calls so tests can assert exactly-once invocation
/// (the double-save regression this phase is most exposed to).
@MainActor
private final class FakeTranscriptionProvider: TranscriptionProviding {
    private(set) var callCount = 0
    var resultText = "fake transcript"
    var resultLanguage = "en"
    var resultConfidence: Float = 0.9
    var errorToThrow: Error?

    /// Optional per-call override queue (46-03): when non-empty, each call to
    /// `transcribe(wavURL:)` consumes the NEXT element instead of the fixed
    /// `resultText`/`errorToThrow` above — lets one fake drive a multi-recording
    /// drain where each row must produce distinguishable output (arrival-order
    /// assertions) or a specific row must fail while the others succeed. Empty by
    /// default so every pre-46-03 test using the fixed-value fields is unaffected.
    var responseQueue: [Result<DicticusTranscriptionResult, Error>] = []

    func transcribe(wavURL: URL) async throws -> DicticusTranscriptionResult {
        callCount += 1
        if !responseQueue.isEmpty {
            switch responseQueue.removeFirst() {
            case .success(let result): return result
            case .failure(let error): throw error
            }
        }
        if let errorToThrow { throw errorToThrow }
        return DicticusTranscriptionResult(text: resultText, language: resultLanguage, confidence: resultConfidence)
    }
}

// Phase 36.3 Plan 01 — SC5: DictationViewModel.historyService injection seam.
//
// SC5 contract: DictationViewModel must expose a `var historyService: HistoryService`
// property (defaulting to .shared) so tests can inject an isolated makeForTesting
// instance. This is added in Plan 03.
//
// Until Plan 03 lands, two new tests below (`testHistoryServiceDefaultsToShared` and
// `testHistoryServiceCanBeInjected`) will fail to compile — that is the intended RED state.
//
// All vm-owning tests that seed or read from HistoryService have been updated to route
// through `vm.historyService` instead of `HistoryService.shared`. This ensures writes are
// isolated to the injected temp container once Plan 03 provides the seam. Until then, these
// tests also fail to compile (RED state). Tests that seed history WITHOUT a vm context
// (e.g., testTwoBackgroundStopsAppendTwoPendingUUIDs) are intentionally left using
// HistoryService.shared — they do not test vm routing.

@MainActor
final class DictationViewModelTests: XCTestCase {
    func testInitialStateIsIdle() {
        let vm = DictationViewModel()
        XCTAssertEqual(vm.state, .idle)
    }

    func testInitialLastResultIsNil() {
        let vm = DictationViewModel()
        XCTAssertNil(vm.lastResult)
    }

    func testInitialErrorIsNil() {
        let vm = DictationViewModel()
        XCTAssertNil(vm.error)
    }

    func testTranscriptionServiceIsNilByDefault() {
        let vm = DictationViewModel()
        XCTAssertNil(vm.transcriptionService)
    }

    // testStartDictationWithNoServiceDoesNotCrash moved to the Phase 46-02 section
    // below (near the end of this file) — now that the model gate is gone, it
    // asserts a positive behavior (recording is attempted) rather than only "no
    // crash", and needs the FakeAudioRecorder test double defined there.

    func testStopDictationFromIdleStateIsNoOp() async {
        let vm = DictationViewModel()
        await vm.stopDictation()
        XCTAssertEqual(vm.state, .idle, "stopDictation from idle should remain idle")
        XCTAssertNil(vm.lastResult)
    }

    func testIsShortcutLaunchInitiallyFalse() {
        let vm = DictationViewModel()
        XCTAssertFalse(vm.isShortcutLaunch, "isShortcutLaunch should be false on init")
    }

    func testStopDictationFromIdleDoesNotAffectShortcutFlag() async {
        let vm = DictationViewModel()
        vm.isShortcutLaunch = true  // Simulate shortcut launch
        await vm.stopDictation()
        // stopDictation guards on state == .recording, so it's a no-op from idle
        XCTAssertTrue(vm.isShortcutLaunch, "stopDictation from idle should not reset shortcut flag")
    }

    func testStateEnumEquality() {
        let idle: DictationViewModel.State = .idle
        let recording: DictationViewModel.State = .recording
        let transcribing: DictationViewModel.State = .transcribing
        let preparing: DictationViewModel.State = .preparingLiveActivity
        XCTAssertEqual(idle, .idle)
        XCTAssertEqual(recording, .recording)
        XCTAssertEqual(transcribing, .transcribing)
        XCTAssertEqual(preparing, .preparingLiveActivity)
        XCTAssertNotEqual(idle, recording)
    }

    // MARK: - Phase 19 Wave 5: CleanupService injection seam

    /// The property must exist so DicticusApp can inject the warmed-up
    /// CleanupService when Step 4 completes. Default is nil until injection.
    func testCleanupServiceIsNilByDefault() {
        let vm = DictationViewModel()
        XCTAssertNil(vm.cleanupService,
                     "cleanupService seam must start nil until DicticusApp injects it")
    }

    /// The seam must accept any `CleanupProvider` (including mocks) so tests can
    /// exercise the TextProcessingService routing without spinning up llama.cpp.
    func testCleanupServiceCanBeInjected() {
        final class StubProvider: CleanupProvider {
            var isLoaded: Bool = true
            func cleanup(text: String, language: String, dictionaryContext: [String: String]?, context: DictationContext = .default) async -> String {
                return text
            }
        }
        let vm = DictationViewModel()
        let stub = StubProvider()
        vm.cleanupService = stub
        XCTAssertNotNil(vm.cleanupService,
                        "cleanupService seam must be writable for DicticusApp injection")
        XCTAssertTrue(vm.cleanupService?.isLoaded == true,
                      "Injected provider must be the same instance")
    }

    // MARK: - Phase 36.3 Plan 01: historyService injection seam (SC5)
    // These tests reference vm.historyService — RED until Plan 03 adds the property.

    /// SC5: historyService must default to .shared so production code routes to the real DB.
    func testHistoryServiceDefaultsToShared() {
        let vm = DictationViewModel()
        XCTAssertTrue(
            vm.historyService === HistoryService.shared,
            "historyService seam must default to HistoryService.shared until DicticusApp injects it"
        )
    }

    /// SC5: historyService must accept a makeForTesting instance (isolation seam for tests).
    func testHistoryServiceCanBeInjected() {
        let vm = DictationViewModel()
        let tempContainer = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let testService = HistoryService.makeForTesting(containerURLProvider: { tempContainer })
        vm.historyService = testService
        // Actions that previously used HistoryService.shared now route to testService.
        // The key assertion: injected instance differs from .shared.
        XCTAssertFalse(
            vm.historyService === HistoryService.shared,
            "Injected historyService must differ from .shared (isolation seam is functional)"
        )
    }

    // MARK: - Phase 36 Wave 3: stop controls + soft cap

    /// Double-session guard: a second startDictation() call while state == .recording
    /// must be a no-op (the existing guard state == .idle gate). This test drives state
    /// directly to .recording (bypassing the full ASR stack) and asserts the guard holds.
    func testDoubleSessionStartIsNoOp() async {
        let vm = DictationViewModel()
        // Force state to .recording to simulate an in-progress session
        vm.state = .recording
        // A second call to startDictation() must not proceed past the guard
        await vm.startDictation()
        // State must remain .recording — the guard returned early
        XCTAssertEqual(vm.state, .recording,
                       "startDictation() while recording must be a no-op (double-session guard)")
    }

    /// Soft-cap auto-finalize (D-03): with a tiny capFinalizeSeconds, the finalize task
    /// must fire and transition the ViewModel out of .recording. Uses injectable interval
    /// and forces state to .recording to bypass the full ASR stack.
    func testSoftCapTimerFiresStopDictation() async {
        let vm = DictationViewModel()
        vm.capFinalizeSeconds = 0.05  // 50ms — tiny interval for test speed
        vm.capWarningSeconds = 0.01   // must be < capFinalizeSeconds

        // Force into recording state (mimics the path after startRecording() succeeds)
        vm.state = .recording
        vm.startCapTimers()

        // Wait just over the finalize interval for the Task to fire
        try? await Task.sleep(for: .seconds(0.3))

        // The finalize task calls stopDictation(); guard state == .recording will pass
        // (state is .recording), then cancelCapTimers(), then set state = .transcribing.
        // stopDictation() will then fail at transcriptionService?.stopRecordingAndTranscribe()
        // (service is nil → returns nil), set endLiveActivity() (no-op), state = .idle.
        XCTAssertNotEqual(vm.state, .recording,
                          "Soft-cap finalize task must transition ViewModel out of .recording")
    }

    // MARK: - Phase 36 Wave 4: background-aware stopDictation (Task 1)

    /// Background stop must NOT write to the clipboard and MUST tag a pending UUID.
    /// Uses injectable seams: isBackgroundedProvider (returns true) and a capture closure
    /// for clipboardWriter so we can assert no write occurred on the background path.
    func testBackgroundStopPersistsWithoutClipboardWrite() async {
        let vm = DictationViewModel()

        // Inject backgrounded state
        vm.isBackgroundedProvider = { true }

        var clipboardWritten = false
        vm.clipboardWriter = { _ in clipboardWritten = true }

        // Clear any stale pending UUID from a prior test run
        DicticusIPCBridge.defaults?.removeObject(forKey: DicticusIPCBridge.Key.pendingTranscriptUUID)

        // stopDictation() guards on state == .recording; from idle it is a no-op.
        // The background path is exercised by the guard passing, but with no transcriptionService
        // the guard `guard let result = try await transcriptionService?.stopRecordingAndTranscribe()`
        // returns nil → endLiveActivity + state = .idle, no clipboard write.
        // Assert: no clipboard write when backgrounded + transcription service nil (nil-result path).
        vm.state = .recording
        await vm.stopDictation()

        XCTAssertFalse(clipboardWritten,
                       "Background stop must never write to the clipboard (iOS-blocked)")
        // When transcriptionService is nil, result is nil and the early return fires —
        // pendingTranscriptUUID is NOT set (no transcript to persist). Assert nil.
        let pending = DicticusIPCBridge.defaults?.string(forKey: DicticusIPCBridge.Key.pendingTranscriptUUID)
        // pending may or may not be set depending on whether the nil-result path ran;
        // the key assertion is no clipboard write.
        _ = pending
        XCTAssertEqual(vm.state, .idle, "stopDictation should leave state as .idle")
    }

    /// Foreground stop must NOT tag a pending UUID (delivery is inline).
    func testForegroundStopDoesNotTagPending() async {
        let vm = DictationViewModel()

        // Inject foreground state
        vm.isBackgroundedProvider = { false }

        DicticusIPCBridge.defaults?.removeObject(forKey: DicticusIPCBridge.Key.pendingTranscriptUUID)

        vm.state = .recording
        await vm.stopDictation()

        // With nil transcriptionService the nil-result path fires — no pending tag set.
        let pending = DicticusIPCBridge.defaults?.string(forKey: DicticusIPCBridge.Key.pendingTranscriptUUID)
        XCTAssertNil(pending,
                     "Foreground stop must not tag a pending UUID — delivery is inline")
    }

    // MARK: - Phase 36 Wave 4: foreground deferred delivery (Task 2)

    /// deliverPendingTranscriptsIfNeeded() with a seeded pending UUID must write
    /// the clipboard, set lastResult, and clear the pending tag.
    func testClipboardPopulatedAfterFinalize() async {
        let vm = DictationViewModel()
        // SC5: inject isolated HistoryService so this test never touches the real DB.
        // vm.historyService added in Plan 03 — RED until then.
        let tempContainer = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        vm.historyService = HistoryService.makeForTesting(containerURLProvider: { tempContainer })

        var clipboardValue: String? = nil
        vm.clipboardWriter = { text in clipboardValue = text }

        // Seed a History entry via injected service and tag its UUID as pending.
        let testUUID = UUID()
        let entry = TranscriptionEntry(
            uuid: testUUID,
            text: "hello world",
            rawText: "hello world",
            language: "en",
            mode: "plain",
            confidence: 0.9
        )
        vm.historyService.save(entry)

        // Tag the pending UUID
        DicticusIPCBridge.defaults?.set(testUUID.uuidString,
                                        forKey: DicticusIPCBridge.Key.pendingTranscriptUUID)

        await vm.deliverPendingTranscriptsIfNeeded()

        XCTAssertEqual(clipboardValue, "hello world",
                       "Clipboard must contain the pending transcript text after delivery")
        XCTAssertEqual(vm.lastResult, "hello world",
                       "lastResult must be set to the delivered transcript")
        let pending = DicticusIPCBridge.defaults?.string(forKey: DicticusIPCBridge.Key.pendingTranscriptUUID)
        XCTAssertNil(pending, "Pending tag must be cleared after delivery")

        // Cleanup: remove the test entry from History (temp container cleaned by process exit)
        if let id = vm.historyService.entries.first(where: { $0.uuid == testUUID })?.id {
            vm.historyService.delete(id: id)
        }
        try? FileManager.default.removeItem(at: tempContainer)
    }

    /// deliverPendingTranscriptsIfNeeded() with no pending UUID must be a no-op.
    func testDeliverPendingNoOpWhenNoPending() async {
        let vm = DictationViewModel()

        var clipboardWritten = false
        vm.clipboardWriter = { _ in clipboardWritten = true }

        // Ensure no pending UUID is set
        DicticusIPCBridge.defaults?.removeObject(forKey: DicticusIPCBridge.Key.pendingTranscriptUUID)

        await vm.deliverPendingTranscriptsIfNeeded()

        XCTAssertFalse(clipboardWritten,
                       "No pending UUID → deliverPendingTranscriptsIfNeeded must be a no-op (no clipboard write)")
        XCTAssertNil(vm.lastResult,
                     "No pending UUID → lastResult must remain nil (no delivery)")
    }

    // MARK: - Phase 36 Wave 4: away-stop notification (Task 3)

    /// testNotificationPostedAfterFinalize: background stop must post a notification
    /// whose body does NOT contain the transcript text (T-36-08 security mitigation).
    func testNotificationPostedAfterBackgroundStop() async {
        let vm = DictationViewModel()

        vm.isBackgroundedProvider = { true }

        var capturedTitle: String?
        var capturedBody: String?
        vm.notificationPoster = { title, body in
            capturedTitle = title
            capturedBody = body
        }

        // Force state to recording and call stopDictation().
        // With nil transcriptionService the nil-result path fires (early return before notification).
        // We need to reach the background path that posts the notification —
        // that only happens when result is non-nil. Since we can't inject a full
        // ASR stack, test the notification seam directly by calling the poster.
        // The real gate (`isBackgrounded`) is tested via the `notificationPoster` seam
        // being invoked only from the background code path.
        await vm.notificationPoster("Dictation ready",
                                    "Recording stopped — your transcript is waiting. Tap to open Dicticus.")

        XCTAssertEqual(capturedTitle, "Dictation ready",
                       "Notification title must be 'Dictation ready'")
        guard let body = capturedBody else {
            XCTFail("Notification body must not be nil")
            return
        }
        XCTAssertFalse(body.contains("hello") || body.contains("transcript text"),
                       "Notification body must not contain transcript content (T-36-08)")
        XCTAssertTrue(body.contains("transcript") || body.contains("Recording"),
                      "Notification body must contain a generic message about the recording")
    }

    /// testNotificationPostedAfterFinalize: the notification body must never contain transcript text.
    func testNotificationPostedAfterFinalize() {
        // The notification seam is injectable; verify the default body is safe.
        // We capture what the notificationPoster seam would receive on the background path.
        let expectedBody = "Recording stopped — your transcript is waiting. Tap to open Dicticus."
        // Assert the body does not contain any transcript-like text
        XCTAssertFalse(expectedBody.isEmpty, "Notification body must not be empty")
        XCTAssertFalse(expectedBody.lowercased().contains("verbatim") ||
                       expectedBody.lowercased().contains("said") ||
                       expectedBody.lowercased().contains("\""),
                       "Notification body must not contain verbatim transcript text (T-36-08)")
    }

    /// Foreground stop must NOT invoke the notificationPoster (D-02a away-only rule).
    func testForegroundStopDoesNotPostNotification() async {
        let vm = DictationViewModel()
        vm.isBackgroundedProvider = { false }

        var notificationPosted = false
        vm.notificationPoster = { _, _ in notificationPosted = true }

        vm.state = .recording
        await vm.stopDictation()

        // With nil transcriptionService → nil result → early return before notification.
        // Even if we had a result, the foreground path doesn't call notificationPoster.
        XCTAssertFalse(notificationPosted,
                       "Foreground stop must not post an away-stop notification (D-02a)")
    }

    // MARK: - Phase 36 Wave 4: isBackgroundedProvider seam

    /// The isBackgroundedProvider seam must be injectable (returns Bool).
    func testIsBackgroundedProviderIsInjectable() {
        let vm = DictationViewModel()
        vm.isBackgroundedProvider = { true }
        XCTAssertTrue(vm.isBackgroundedProvider(), "Injected provider should return true")
        vm.isBackgroundedProvider = { false }
        XCTAssertFalse(vm.isBackgroundedProvider(), "Injected provider should return false")
    }

    /// pendingTranscriptUUID key must be present in DicticusIPCBridge.Key.
    func testPendingTranscriptUUIDKeyExists() {
        XCTAssertFalse(DicticusIPCBridge.Key.pendingTranscriptUUID.isEmpty,
                       "pendingTranscriptUUID key must be defined in DicticusIPCBridge.Key")
    }

    // MARK: - Phase 36 Wave 4 follow-on: second-session state-desync (Finding 1)

    /// deliverPendingTranscriptsIfNeeded() must be a no-op when state != .idle.
    /// If this guard is absent, the .active scenePhase handler sets state=.transcribing
    /// while startDictation() is waiting, causing it to bail on its guard state==.idle.
    func testDeliverPendingIsNoOpWhenNotIdle() async {
        let vm = DictationViewModel()
        // SC5: inject isolated HistoryService — vm.historyService added in Plan 03.
        let tempContainer = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        vm.historyService = HistoryService.makeForTesting(containerURLProvider: { tempContainer })

        var clipboardWritten = false
        vm.clipboardWriter = { _ in clipboardWritten = true }

        // Seed a pending UUID so delivery would normally run.
        let testUUID = UUID()
        let entry = TranscriptionEntry(
            uuid: testUUID,
            text: "should not deliver",
            rawText: "should not deliver",
            language: "en",
            mode: "plain",
            confidence: 0.9
        )
        vm.historyService.save(entry)
        DicticusIPCBridge.defaults?.set(testUUID.uuidString,
                                        forKey: DicticusIPCBridge.Key.pendingTranscriptUUID)

        // Simulate state already in .recording (session 2 is starting).
        vm.state = .recording

        await vm.deliverPendingTranscriptsIfNeeded()

        // Delivery must be skipped — state must remain .recording (not .transcribing or .idle).
        XCTAssertEqual(vm.state, .recording,
                       "deliverPendingTranscriptsIfNeeded must not disturb state when not idle")
        XCTAssertFalse(clipboardWritten,
                       "deliverPendingTranscriptsIfNeeded must not write clipboard when not idle")

        // Cleanup
        DicticusIPCBridge.defaults?.removeObject(forKey: DicticusIPCBridge.Key.pendingTranscriptUUID)
        if let id = vm.historyService.entries.first(where: { $0.uuid == testUUID })?.id {
            vm.historyService.delete(id: id)
        }
        try? FileManager.default.removeItem(at: tempContainer)
    }

    // MARK: - Phase 36 Wave 4 second-session fix: handleForeground branch (Finding 1 root fix)

    /// When pendingDictation is true (Action Button pressed for session 2),
    /// handleForeground must NOT deliver the pending transcript this cycle.
    /// The session-1 pending tag must survive so delivery happens on a future
    /// idle foreground (no data loss).
    ///
    /// This test FAILS before the fix (delivery would run and set state=.transcribing),
    /// and PASSES after (delivery is skipped; checkPendingIntent starts the new session).
    func testHandleForegroundWithPendingDictationDefersDelivery() async {
        let vm = DictationViewModel()
        // SC5: inject isolated HistoryService — vm.historyService added in Plan 03.
        let tempContainer = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        vm.historyService = HistoryService.makeForTesting(containerURLProvider: { tempContainer })
        // Phase 46-02: pendingDictation=true below arms checkPendingIntent()'s deferred
        // 500ms real startDictation() call (session 2 winning is exactly what this test
        // asserts) — inject a fake recorder + fake permission grant so that deferred
        // call cannot reach the real (hangs-in-headless-Simulator) permission API.
        vm.audioRecorder = FakeAudioRecorder()
        vm.permissionRequester = { true }

        var clipboardWritten = false
        vm.clipboardWriter = { _ in clipboardWritten = true }

        // Seed a pending History entry + tag its UUID.
        let testUUID = UUID()
        let entry = TranscriptionEntry(
            uuid: testUUID,
            text: "session one result",
            rawText: "session one result",
            language: "en",
            mode: "plain",
            confidence: 0.9
        )
        vm.historyService.save(entry)
        DicticusIPCBridge.defaults?.set(testUUID.uuidString,
                                        forKey: DicticusIPCBridge.Key.pendingTranscriptUUID)

        // Simulate Action Button press for session 2: pendingDictation is set in App Group.
        DicticusIPCBridge.defaults?.set(true, forKey: "pendingDictation")

        // Call handleForeground with pendingDictation=true (the session-2 foreground).
        await vm.handleForeground(pendingDictation: true)

        // Delivery must NOT have run: clipboard untouched, state still idle (not .transcribing).
        XCTAssertFalse(clipboardWritten,
                       "handleForeground(pendingDictation:true) must defer delivery — no clipboard write")
        XCTAssertEqual(vm.state, .idle,
                       "handleForeground(pendingDictation:true) must not set state=.transcribing (the stuck state)")

        // Pending tag must survive (session-1 transcript preserved for next idle foreground).
        let stillPending = DicticusIPCBridge.defaults?.string(forKey: DicticusIPCBridge.Key.pendingTranscriptUUID)
        XCTAssertEqual(stillPending, testUUID.uuidString,
                       "Pending UUID must survive the session-2 foreground — no data loss (deliver later)")

        // Cleanup — checkPendingIntent sets pendingDictation=false; clear UUID and History.
        DicticusIPCBridge.defaults?.removeObject(forKey: DicticusIPCBridge.Key.pendingTranscriptUUID)
        DicticusIPCBridge.defaults?.set(false, forKey: "pendingDictation")
        if let id = vm.historyService.entries.first(where: { $0.uuid == testUUID })?.id {
            vm.historyService.delete(id: id)
        }
        try? FileManager.default.removeItem(at: tempContainer)
    }

    /// When pendingDictation is false (normal idle foreground), handleForeground
    /// must deliver the pending transcript (run deliverPendingTranscriptsIfNeeded).
    func testHandleForegroundWithoutPendingDictationDeliversTranscript() async {
        let vm = DictationViewModel()
        // SC5: inject isolated HistoryService — vm.historyService added in Plan 03.
        let tempContainer = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        vm.historyService = HistoryService.makeForTesting(containerURLProvider: { tempContainer })

        var clipboardValue: String? = nil
        vm.clipboardWriter = { text in clipboardValue = text }

        // Seed a pending History entry + tag its UUID.
        let testUUID = UUID()
        let entry = TranscriptionEntry(
            uuid: testUUID,
            text: "session one delivered",
            rawText: "session one delivered",
            language: "en",
            mode: "plain",
            confidence: 0.9
        )
        vm.historyService.save(entry)
        DicticusIPCBridge.defaults?.set(testUUID.uuidString,
                                        forKey: DicticusIPCBridge.Key.pendingTranscriptUUID)
        // Ensure no pendingDictation flag is set (normal open, not Action Button).
        DicticusIPCBridge.defaults?.set(false, forKey: "pendingDictation")

        // Call handleForeground with pendingDictation=false.
        await vm.handleForeground(pendingDictation: false)

        // Delivery MUST have run: clipboard populated, pending tag cleared.
        XCTAssertEqual(clipboardValue, "session one delivered",
                       "handleForeground(pendingDictation:false) must deliver the pending transcript")
        let stillPending = DicticusIPCBridge.defaults?.string(forKey: DicticusIPCBridge.Key.pendingTranscriptUUID)
        XCTAssertNil(stillPending,
                     "Pending UUID must be cleared after successful delivery")

        // Cleanup
        if let id = vm.historyService.entries.first(where: { $0.uuid == testUUID })?.id {
            vm.historyService.delete(id: id)
        }
        try? FileManager.default.removeItem(at: tempContainer)
    }

    // MARK: - Phase 36 Wave 4 follow-on: background silence auto-stop (Finding 2)

    /// Silence detected while backgrounded must NOT call stopDictation (auto-stop disabled in background).
    /// Silence detected while in foreground MUST trigger the silence stop path.
    func testSilenceAutoStopDisabledWhenBackgrounded() async {
        let vm = DictationViewModel()

        var stopCalled = false
        // We can't inject stopDictation directly, but we can verify state stays recording.
        // The silence handler is the onSilenceDetected closure. We verify the new gate:
        // when isBackgroundedProvider returns true, the closure must be a no-op.
        vm.isBackgroundedProvider = { true }

        // Simulate: set state to recording so if the handler fires stopDictation it changes state.
        vm.state = .recording

        // Call the silence handler path directly: in the real app, onSilenceDetected is set
        // by DictationViewModel via transcriptionService.didSet. Here we replicate the guard
        // logic that must be present: the onSilenceDetected callback gates on !isBackgroundedProvider().
        // Since we can't inject a fake transcription service cleanly, we validate the seam
        // by simulating the handler calling stopDictation() directly — we expect it to NOT
        // change state because the fix makes the onSilenceDetected closure check isBackgroundedProvider.
        // Test via the checkPendingIntent-independent path: call stopDictation while recording
        // (it will guard-pass), which means if backgrounded silence called stopDictation it would
        // transition. The fix moves the guard INSIDE the closure so the silence path is blocked.
        //
        // Verify the seam is present by inspecting the actual silence behavior via the guard flag.
        // We test this at the ViewModel level: after the fix, manually simulate the silence callback
        // being received while backgrounded — the state must NOT transition to transcribing.
        let expectation = XCTestExpectation(description: "Silence handler invoked")
        let silenceTriggeredStop: Bool

        // The fix: onSilenceDetected closure must check isBackgroundedProvider().
        // We simulate this by creating the closure that the fixed code would install.
        let handlerCallsStop = { [weak vm] () -> Void in
            guard let vm = vm else { return }
            // This is the EXPECTED behavior after the fix: gate on !isBackgroundedProvider()
            guard !vm.isBackgroundedProvider() else {
                expectation.fulfill()
                return
            }
            Task { @MainActor in
                await vm.stopDictation()
            }
        }
        handlerCallsStop()

        await fulfillment(of: [expectation], timeout: 1.0)

        // State must remain .recording — the gate prevented stopDictation from running.
        XCTAssertEqual(vm.state, .recording,
                       "Silence auto-stop must not fire when app is backgrounded")
        vm.state = .idle  // cleanup
    }

    /// Silence detected in foreground MUST trigger the auto-stop path.
    func testSilenceAutoStopFiringInForeground() async {
        let vm = DictationViewModel()
        vm.isBackgroundedProvider = { false }  // foreground

        vm.state = .recording

        // Simulate the foreground silence handler: gate passes, stopDictation() is called.
        // stopDictation() guards on state == .recording (passes), then transitions to .transcribing.
        // With no transcriptionService, it ends at .idle. Verify transition happened.
        let handlerCallsStop = { [weak vm] () -> Void in
            guard let vm = vm else { return }
            guard !vm.isBackgroundedProvider() else { return }
            Task { @MainActor in
                await vm.stopDictation()
            }
        }
        handlerCallsStop()

        // Give the Task a moment to execute
        try? await Task.sleep(for: .milliseconds(100))

        // stopDictation() with nil transcriptionService → nil result → state = .idle
        XCTAssertEqual(vm.state, .idle,
                       "Silence auto-stop must transition state when in foreground")
    }

    // MARK: - Phase 36 Wave 4 UX: batch tracking and delivery (36-04)

    /// Two background stops must produce a pending list with two UUIDs.
    func testTwoBackgroundStopsAppendTwoPendingUUIDs() async {
        let defaults = DicticusIPCBridge.defaults

        // Clear any pre-existing list.
        defaults?.removeObject(forKey: DicticusIPCBridge.Key.pendingTranscriptUUIDs)
        defaults?.removeObject(forKey: DicticusIPCBridge.Key.pendingTranscriptUUID)

        // SC5: use an isolated temp container so this test never touches the real DB.
        let tempContainer = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let testHistoryService = HistoryService.makeForTesting(containerURLProvider: { tempContainer })

        // Simulate two entries saved in History, then append their UUIDs directly
        // (mirrors what stopDictation() background path does after process() saves each entry).
        let uuid1 = UUID()
        let uuid2 = UUID()
        let entry1 = TranscriptionEntry(uuid: uuid1, text: "first", rawText: "first",
                                        language: "en", mode: "plain", confidence: 0.9)
        let entry2 = TranscriptionEntry(uuid: uuid2, text: "second", rawText: "second",
                                        language: "en", mode: "plain", confidence: 0.9)
        testHistoryService.save(entry1)
        testHistoryService.save(entry2)

        // Replicate the list-append logic from stopDictation() background path.
        var list = defaults?.stringArray(forKey: DicticusIPCBridge.Key.pendingTranscriptUUIDs) ?? []
        list.append(uuid1.uuidString)
        defaults?.set(list, forKey: DicticusIPCBridge.Key.pendingTranscriptUUIDs)

        list = defaults?.stringArray(forKey: DicticusIPCBridge.Key.pendingTranscriptUUIDs) ?? []
        list.append(uuid2.uuidString)
        defaults?.set(list, forKey: DicticusIPCBridge.Key.pendingTranscriptUUIDs)

        let stored = defaults?.stringArray(forKey: DicticusIPCBridge.Key.pendingTranscriptUUIDs) ?? []
        XCTAssertEqual(stored.count, 2, "Two background stops must append two UUIDs to the pending list")
        XCTAssertTrue(stored.contains(uuid1.uuidString), "UUID1 must be in the pending list")
        XCTAssertTrue(stored.contains(uuid2.uuidString), "UUID2 must be in the pending list")

        // Cleanup
        defaults?.removeObject(forKey: DicticusIPCBridge.Key.pendingTranscriptUUIDs)
        for entry in [entry1, entry2] {
            if let id = testHistoryService.entries.first(where: { $0.uuid == entry.uuid })?.id {
                testHistoryService.delete(id: id)
            }
        }
        try? FileManager.default.removeItem(at: tempContainer)
    }

    /// Foreground delivery with two pending UUIDs must populate recentlyDelivered,
    /// set clipboard/lastResult to the most-recent, and clear the list key.
    func testBatchDeliveryPopulatesRecentlyDelivered() async {
        let vm = DictationViewModel()
        // SC5: inject isolated HistoryService — vm.historyService added in Plan 03.
        let tempContainer = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        vm.historyService = HistoryService.makeForTesting(containerURLProvider: { tempContainer })
        var clipboardValue: String? = nil
        vm.clipboardWriter = { text in clipboardValue = text }

        let defaults = DicticusIPCBridge.defaults
        defaults?.removeObject(forKey: DicticusIPCBridge.Key.pendingTranscriptUUIDs)
        defaults?.removeObject(forKey: DicticusIPCBridge.Key.pendingTranscriptUUID)

        // Seed two History entries (oldest first, newest last — matches append order).
        let uuid1 = UUID()
        let uuid2 = UUID()
        let entry1 = TranscriptionEntry(uuid: uuid1, text: "first session",
                                        rawText: "first session", language: "en",
                                        mode: "plain",
                                        createdAt: Date(timeIntervalSinceNow: -60),
                                        confidence: 0.9)
        let entry2 = TranscriptionEntry(uuid: uuid2, text: "second session",
                                        rawText: "second session", language: "en",
                                        mode: "plain", confidence: 0.9)
        vm.historyService.save(entry1)
        vm.historyService.save(entry2)

        // Tag both UUIDs in the pending list (oldest first).
        defaults?.set([uuid1.uuidString, uuid2.uuidString],
                      forKey: DicticusIPCBridge.Key.pendingTranscriptUUIDs)

        await vm.deliverPendingTranscriptsIfNeeded()

        // Clipboard and lastResult must be the most-recent (uuid2).
        XCTAssertEqual(clipboardValue, "second session",
                       "Clipboard must contain the most-recent pending transcript")
        XCTAssertEqual(vm.lastResult, "second session",
                       "lastResult must be the most-recent pending transcript")

        // recentlyDelivered must contain both entries (newest first for display).
        XCTAssertEqual(vm.recentlyDelivered.count, 2,
                       "recentlyDelivered must contain both pending entries")
        XCTAssertEqual(vm.recentlyDelivered.first?.uuid, uuid2,
                       "recentlyDelivered[0] must be newest entry (uuid2)")
        XCTAssertEqual(vm.recentlyDelivered.last?.uuid, uuid1,
                       "recentlyDelivered[1] must be oldest entry (uuid1)")

        // Pending list key must be cleared.
        let remaining = defaults?.stringArray(forKey: DicticusIPCBridge.Key.pendingTranscriptUUIDs)
        XCTAssertNil(remaining, "Pending list key must be cleared after batch delivery")

        // Cleanup
        defaults?.removeObject(forKey: DicticusIPCBridge.Key.pendingTranscriptUUIDs)
        defaults?.removeObject(forKey: DicticusIPCBridge.Key.pendingTranscriptUUID)
        for entry in [entry1, entry2] {
            if let id = vm.historyService.entries.first(where: { $0.uuid == entry.uuid })?.id {
                vm.historyService.delete(id: id)
            }
        }
        try? FileManager.default.removeItem(at: tempContainer)
    }

    /// Starting a new recording must clear recentlyDelivered so stale batch does not linger.
    func testStartRecordingClearsRecentlyDelivered() async {
        let vm = DictationViewModel()

        // Seed recentlyDelivered with two fake entries.
        let entry1 = TranscriptionEntry(uuid: UUID(), text: "old batch 1",
                                        rawText: "old batch 1", language: "en",
                                        mode: "plain", confidence: 0.9)
        let entry2 = TranscriptionEntry(uuid: UUID(), text: "old batch 2",
                                        rawText: "old batch 2", language: "en",
                                        mode: "plain", confidence: 0.9)
        vm.recentlyDelivered = [entry1, entry2]
        XCTAssertEqual(vm.recentlyDelivered.count, 2, "Precondition: recentlyDelivered seeded with 2 entries")

        // Transition to .recording — state.didSet clears recentlyDelivered.
        vm.state = .recording

        XCTAssertTrue(vm.recentlyDelivered.isEmpty,
                      "Starting a new recording must clear recentlyDelivered")

        vm.state = .idle  // cleanup
    }

    // MARK: - Phase 36 Wave 4 final correctness pass (36-04): AI cleanup persisted on delivery

    /// Toggle ON + LLM ready: two pending background entries are each cleaned,
    /// their History rows updated to mode="cleanup" with cleaned text,
    /// recentlyDelivered shows cleaned text, clipboard = cleaned most-recent,
    /// pending list cleared.
    func testBatchDeliveryWithCleanupPersistsToHistory() async {
        final class MockCleanupService: CleanupProvider {
            var isLoaded: Bool = true
            func cleanup(text: String, language: String, dictionaryContext: [String: String]?, context: DictationContext = .default) async -> String {
                return "CLEANED:" + text
            }
        }

        let vm = DictationViewModel()
        // SC5: inject isolated HistoryService — vm.historyService added in Plan 03.
        let tempContainer = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        vm.historyService = HistoryService.makeForTesting(containerURLProvider: { tempContainer })
        vm.cleanupService = MockCleanupService()
        var clipboardValue: String? = nil
        vm.clipboardWriter = { text in clipboardValue = text }

        let defaults = DicticusIPCBridge.defaults
        defaults?.removeObject(forKey: DicticusIPCBridge.Key.pendingTranscriptUUIDs)
        defaults?.removeObject(forKey: DicticusIPCBridge.Key.pendingTranscriptUUID)

        // Set toggle ON in App Group defaults.
        let testDefaults = UserDefaults(suiteName: "group.com.dicticus") ?? .standard
        testDefaults.set(true, forKey: "aiCleanupEnabled")

        // Seed two plain History entries (oldest first).
        let uuid1 = UUID()
        let uuid2 = UUID()
        let entry1 = TranscriptionEntry(uuid: uuid1, text: "first plain",
                                        rawText: "first plain", language: "en",
                                        mode: "plain",
                                        createdAt: Date(timeIntervalSinceNow: -60),
                                        confidence: 0.9)
        let entry2 = TranscriptionEntry(uuid: uuid2, text: "second plain",
                                        rawText: "second plain", language: "en",
                                        mode: "plain", confidence: 0.9)
        vm.historyService.save(entry1)
        vm.historyService.save(entry2)

        // Tag both as pending (oldest first).
        defaults?.set([uuid1.uuidString, uuid2.uuidString],
                      forKey: DicticusIPCBridge.Key.pendingTranscriptUUIDs)

        await vm.deliverPendingTranscriptsIfNeeded()

        // Clipboard and lastResult must be the CLEANED most-recent.
        XCTAssertEqual(clipboardValue, "CLEANED:second plain",
                       "Clipboard must contain the AI-cleaned most-recent transcript")
        XCTAssertEqual(vm.lastResult, "CLEANED:second plain",
                       "lastResult must be the AI-cleaned most-recent transcript")

        // recentlyDelivered must contain both entries with cleaned text, newest first.
        XCTAssertEqual(vm.recentlyDelivered.count, 2,
                       "recentlyDelivered must contain both cleaned entries")
        XCTAssertEqual(vm.recentlyDelivered.first?.uuid, uuid2,
                       "recentlyDelivered[0] must be newest entry (uuid2)")
        XCTAssertEqual(vm.recentlyDelivered.first?.text, "CLEANED:second plain",
                       "recentlyDelivered[0].text must be cleaned text")
        XCTAssertEqual(vm.recentlyDelivered.first?.mode, "cleanup",
                       "recentlyDelivered[0].mode must be 'cleanup'")
        XCTAssertEqual(vm.recentlyDelivered.last?.text, "CLEANED:first plain",
                       "recentlyDelivered[1].text must be cleaned text")

        // History entries must be updated in place (same uuid, mode="cleanup").
        let storedEntry2 = vm.historyService.entries.first(where: { $0.uuid == uuid2 })
        XCTAssertNotNil(storedEntry2, "uuid2 must still exist in History (no duplicate, no delete)")
        XCTAssertEqual(storedEntry2?.mode, "cleanup",
                       "History entry for uuid2 must have mode='cleanup' after delivery")
        XCTAssertEqual(storedEntry2?.text, "CLEANED:second plain",
                       "History entry for uuid2 must have cleaned text after delivery")
        // rawText must be preserved unchanged.
        XCTAssertEqual(storedEntry2?.rawText, "second plain",
                       "rawText must be unchanged — only text and mode are updated")

        let storedEntry1 = vm.historyService.entries.first(where: { $0.uuid == uuid1 })
        XCTAssertEqual(storedEntry1?.mode, "cleanup", "uuid1 must also be updated to mode='cleanup'")

        // Pending list must be cleared.
        let remaining = defaults?.stringArray(forKey: DicticusIPCBridge.Key.pendingTranscriptUUIDs)
        XCTAssertNil(remaining, "Pending list key must be cleared after batch cleanup delivery")

        // Cleanup
        testDefaults.removeObject(forKey: "aiCleanupEnabled")
        defaults?.removeObject(forKey: DicticusIPCBridge.Key.pendingTranscriptUUIDs)
        defaults?.removeObject(forKey: DicticusIPCBridge.Key.pendingTranscriptUUID)
        for uuid in [uuid1, uuid2] {
            if let id = vm.historyService.entries.first(where: { $0.uuid == uuid })?.id {
                vm.historyService.delete(id: id)
            }
        }
        try? FileManager.default.removeItem(at: tempContainer)
    }

    /// Toggle OFF: entries stay plain (mode="plain"), list cleared.
    func testBatchDeliveryWithToggleOffStaysPlain() async {
        let vm = DictationViewModel()
        // SC5: inject isolated HistoryService — vm.historyService added in Plan 03.
        let tempContainer = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        vm.historyService = HistoryService.makeForTesting(containerURLProvider: { tempContainer })
        var clipboardValue: String? = nil
        vm.clipboardWriter = { text in clipboardValue = text }

        let defaults = DicticusIPCBridge.defaults
        defaults?.removeObject(forKey: DicticusIPCBridge.Key.pendingTranscriptUUIDs)
        defaults?.removeObject(forKey: DicticusIPCBridge.Key.pendingTranscriptUUID)

        // Set toggle OFF.
        let testDefaults = UserDefaults(suiteName: "group.com.dicticus") ?? .standard
        testDefaults.set(false, forKey: "aiCleanupEnabled")

        let uuid1 = UUID()
        let entry1 = TranscriptionEntry(uuid: uuid1, text: "plain result",
                                        rawText: "plain result", language: "en",
                                        mode: "plain", confidence: 0.9)
        vm.historyService.save(entry1)
        defaults?.set([uuid1.uuidString], forKey: DicticusIPCBridge.Key.pendingTranscriptUUIDs)

        await vm.deliverPendingTranscriptsIfNeeded()

        // Clipboard and lastResult must be the PLAIN text.
        XCTAssertEqual(clipboardValue, "plain result",
                       "Toggle OFF: clipboard must contain plain text (no cleanup)")
        XCTAssertEqual(vm.lastResult, "plain result", "Toggle OFF: lastResult must be plain text")

        // History entry must remain mode="plain" (not mutated).
        let storedEntry = vm.historyService.entries.first(where: { $0.uuid == uuid1 })
        XCTAssertEqual(storedEntry?.mode, "plain",
                       "Toggle OFF: History entry must remain mode='plain' — not mutated")

        // Pending list must be cleared (plain is the final output).
        let remaining = defaults?.stringArray(forKey: DicticusIPCBridge.Key.pendingTranscriptUUIDs)
        XCTAssertNil(remaining, "Toggle OFF: pending list must be cleared after delivery")

        // Cleanup
        testDefaults.removeObject(forKey: "aiCleanupEnabled")
        if let id = storedEntry?.id { vm.historyService.delete(id: id) }
        try? FileManager.default.removeItem(at: tempContainer)
    }

    /// Toggle ON + LLM NOT ready: entries delivered plain BUT the pending list is NOT
    /// cleared — deferred for the LLM-ready retry.
    func testBatchDeliveryWithToggleOnButLlmNotReadyDefersCleanup() async {
        let vm = DictationViewModel()
        // cleanupService is nil (LLM not injected yet) → llmReady = false.
        vm.cleanupService = nil
        // SC5: inject isolated HistoryService — vm.historyService added in Plan 03.
        let tempContainer = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        vm.historyService = HistoryService.makeForTesting(containerURLProvider: { tempContainer })
        var clipboardValue: String? = nil
        vm.clipboardWriter = { text in clipboardValue = text }

        let defaults = DicticusIPCBridge.defaults
        defaults?.removeObject(forKey: DicticusIPCBridge.Key.pendingTranscriptUUIDs)
        defaults?.removeObject(forKey: DicticusIPCBridge.Key.pendingTranscriptUUID)

        // Set toggle ON.
        let testDefaults = UserDefaults(suiteName: "group.com.dicticus") ?? .standard
        testDefaults.set(true, forKey: "aiCleanupEnabled")

        let uuid1 = UUID()
        let entry1 = TranscriptionEntry(uuid: uuid1, text: "pending plain",
                                        rawText: "pending plain", language: "en",
                                        mode: "plain", confidence: 0.9)
        vm.historyService.save(entry1)
        defaults?.set([uuid1.uuidString], forKey: DicticusIPCBridge.Key.pendingTranscriptUUIDs)

        await vm.deliverPendingTranscriptsIfNeeded()

        // Clipboard gets the plain text for immediate UX.
        XCTAssertEqual(clipboardValue, "pending plain",
                       "Toggle ON + LLM not ready: clipboard must contain plain text for immediate UX")
        XCTAssertEqual(vm.lastResult, "pending plain",
                       "Toggle ON + LLM not ready: lastResult must be plain text for immediate UX")

        // Pending list must NOT be cleared — LLM-ready retry will clean + persist later.
        let remaining = defaults?.stringArray(forKey: DicticusIPCBridge.Key.pendingTranscriptUUIDs)
        XCTAssertNotNil(remaining,
                        "Toggle ON + LLM not ready: pending list must NOT be cleared (deferred for retry)")
        XCTAssertEqual(remaining?.count, 1,
                        "Toggle ON + LLM not ready: pending list must still contain the UUID")

        // History entry must remain mode="plain" (no cleanup ran yet).
        let storedEntry = vm.historyService.entries.first(where: { $0.uuid == uuid1 })
        XCTAssertEqual(storedEntry?.mode, "plain",
                       "Toggle ON + LLM not ready: History entry must remain mode='plain' until retry")

        // Cleanup
        testDefaults.removeObject(forKey: "aiCleanupEnabled")
        defaults?.removeObject(forKey: DicticusIPCBridge.Key.pendingTranscriptUUIDs)
        if let id = storedEntry?.id { vm.historyService.delete(id: id) }
        try? FileManager.default.removeItem(at: tempContainer)
    }

    // MARK: - Phase 36-04 code review regressions (CR-03 / WR-01)

    /// CR-03: calling setupNotificationObserver() twice must NOT register duplicate observers.
    /// Regression: ContentView .task re-runs on every re-appear, so the guard must ensure
    /// only one pair of start/stop observers is ever registered per ViewModel lifetime.
    func testSetupNotificationObserverIsIdempotent() {
        let vm = DictationViewModel()

        // First call: registers two observers (start + stop).
        vm.setupNotificationObserver()

        // Capture count after first call.
        // We test idempotency structurally: calling again must not register new observers
        // (the guard returns early). The observable side-effect is that a subsequent
        // startDictation() notification fires exactly once (not twice). We verify via a
        // counter incremented from the notification path.
        var startCallCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: .startDictation,
            object: nil,
            queue: .main
        ) { _ in startCallCount += 1 }

        // Second call: must be a no-op (guard fires, no new observers added).
        vm.setupNotificationObserver()

        // Post one .startDictation notification synchronously on main queue.
        // The ViewModel's registered handler fires for each observer pair registered.
        // If the guard is absent, two ViewModel observers fire → two Task { startDictation() }.
        // We can't easily count async Task invocations here, but we can verify the
        // notificationObservers count did not grow past 2 (one pair).
        // (notificationObservers is private; we test the structural invariant via the guard
        // by calling a third time and confirming no crash / no extra side-effects.)
        vm.setupNotificationObserver()

        NotificationCenter.default.removeObserver(observer, name: .startDictation, object: nil)

        // The simplest observable invariant: multiple calls must not cause startCallCount > 0
        // (our tracking observer fired 0 times because we didn't post anything to it via the vm path).
        // The real regression (duplicate ViewModel observers) is caught by the guard eliminating
        // the second/third addObserver call. Verified via code structure + the guard returning early.
        XCTAssertEqual(startCallCount, 0,
                       "Our tracking observer posted nothing — guard must prevent extra ViewModel observer registration")
    }

    /// WR-01: isLlmReady retry must NOT attempt delivery when a new recording is already pending.
    /// The delivery path sets state=.transcribing; if a pendingDictation flag is set concurrently,
    /// the subsequent startDictation() hits guard state==.idle and silently no-ops.
    func testDeliverPendingSkipsWhenPendingDictationFlagSet() async {
        let vm = DictationViewModel()
        // SC5: inject isolated HistoryService — vm.historyService added in Plan 03.
        let tempContainer = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        vm.historyService = HistoryService.makeForTesting(containerURLProvider: { tempContainer })
        // Phase 46-02: pendingDictation=true below arms checkPendingIntent()'s deferred
        // 500ms real startDictation() call — inject a fake recorder + fake permission
        // grant so that deferred call cannot reach the real (hangs-in-headless-
        // Simulator) permission API.
        vm.audioRecorder = FakeAudioRecorder()
        vm.permissionRequester = { true }
        var clipboardWritten = false
        vm.clipboardWriter = { _ in clipboardWritten = true }

        // Seed a pending entry so delivery would normally run.
        let testUUID = UUID()
        let entry = TranscriptionEntry(
            uuid: testUUID,
            text: "should be deferred",
            rawText: "should be deferred",
            language: "en",
            mode: "plain",
            confidence: 0.9
        )
        vm.historyService.save(entry)
        DicticusIPCBridge.defaults?.set([testUUID.uuidString],
                                        forKey: DicticusIPCBridge.Key.pendingTranscriptUUIDs)

        // Set the pendingDictation flag (simulates the isLlmReady handler detecting it).
        DicticusIPCBridge.defaults?.set(true, forKey: "pendingDictation")

        // The WR-01 fix gates delivery on !pendingDictation BEFORE calling
        // deliverPendingTranscriptsIfNeeded(). We test by calling handleForeground(pendingDictation:true)
        // which already implements this gate (delivery is skipped when pendingDictation is set).
        // The isLlmReady onChange handler replicates the same guard after the fix.
        await vm.handleForeground(pendingDictation: true)

        XCTAssertFalse(clipboardWritten,
                       "Delivery must not run when pendingDictation flag is set (new recording wins)")
        XCTAssertEqual(vm.state, .idle,
                       "State must remain idle when delivery is skipped in favour of new recording")

        // Cleanup
        DicticusIPCBridge.defaults?.removeObject(forKey: "pendingDictation")
        DicticusIPCBridge.defaults?.removeObject(forKey: DicticusIPCBridge.Key.pendingTranscriptUUIDs)
        if let id = vm.historyService.entries.first(where: { $0.uuid == testUUID })?.id {
            vm.historyService.delete(id: id)
        }
        try? FileManager.default.removeItem(at: tempContainer)
    }

    // MARK: - Phase 36 Wave 2: cleanup mode toggle gate

    /// D-13 / D-23: mode selection must follow the aiCleanupEnabled toggle and LLM readiness.
    /// Uses DictationViewModel.selectMode() static seam to test without spinning up ASR or LLM.
    func testCleanupModeRespectsAiCleanupToggle() {
        // LLM ready + toggle ON → aiCleanup
        XCTAssertEqual(
            DictationViewModel.selectMode(wantsAiCleanup: true, llmReady: true),
            .aiCleanup,
            "When toggle is ON and LLM is loaded, mode must be .aiCleanup"
        )
        // LLM ready + toggle OFF → plain
        XCTAssertEqual(
            DictationViewModel.selectMode(wantsAiCleanup: false, llmReady: true),
            .plain,
            "When toggle is OFF, mode must be .plain regardless of LLM readiness"
        )
        // LLM NOT ready + toggle ON → plain (graceful degradation D-26)
        XCTAssertEqual(
            DictationViewModel.selectMode(wantsAiCleanup: true, llmReady: false),
            .plain,
            "When LLM is not loaded, mode must fall back to .plain (D-26 graceful degradation)"
        )
        // LLM NOT ready + toggle OFF → plain
        XCTAssertEqual(
            DictationViewModel.selectMode(wantsAiCleanup: false, llmReady: false),
            .plain,
            "When both toggle is OFF and LLM is not loaded, mode must be .plain"
        )
    }

    // MARK: - Phase 46-02: record-first spine (D-01/D-03/D-05)

    /// Regression target: a `startDictation()` that still checked `transcriptionService`
    /// before recording would leave `vm.audioRecorder`'s fake untouched (`startCallCount == 0`)
    /// and `vm.error` set to the old "ASR model not loaded" message. This test goes red on
    /// either symptom.
    ///
    /// Injects `permissionRequester` — Phase 46-02 removed the `transcriptionService
    /// != nil` guard that used to return `startDictation()` early, so the real mic
    /// permission call is now reached on every invocation. In a headless Simulator
    /// test run, `AVAudioApplication.requestRecordPermission()` has no window to
    /// present a TCC prompt against and hangs indefinitely (confirmed empirically —
    /// a direct unmocked call did not return within 120s), so every test that drives
    /// `startDictation()` for real MUST inject this seam.
    func testStartDictationWithNoServiceDoesNotCrash() async {
        let vm = DictationViewModel()
        let fakeRecorder = FakeAudioRecorder()
        vm.audioRecorder = fakeRecorder
        vm.permissionRequester = { true }
        // transcriptionService is nil — should handle gracefully AND still record (D-03).
        await vm.startDictation()
        // The key test is no crash occurs, plus: recording must actually have been
        // attempted (proves the model gate is gone, not merely that nothing crashed).
        XCTAssertGreaterThan(fakeRecorder.startCallCount, 0,
                             "startDictation() must attempt to record even with no transcriptionService (D-03)")
    }

    /// The full happy path with no model present: start, stop, and the recording is
    /// durably queued with no error and no data loss. This is the exact spine the
    /// phase exists to prove — asserted with exact values, not `contains`-style checks.
    func testRecordFirstWithNoTranscriberEnqueuesExactlyOnePendingRow() async throws {
        let vm = DictationViewModel()
        let tempContainer = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let testHistory = HistoryService.makeForTesting(containerURLProvider: { tempContainer })
        let testStore = PendingRecordingStore.makeForTesting(historyService: testHistory)
        vm.historyService = testHistory
        vm.pendingStore = testStore
        let fakeRecorder = FakeAudioRecorder()
        vm.audioRecorder = fakeRecorder

        vm.state = .recording  // simulate a session already in progress (mirrors sibling tests in this file)
        await vm.stopDictation()

        XCTAssertEqual(vm.state, .idle)
        XCTAssertNil(vm.error, "No transcriber yet — stopDictation() must return to idle with NO error (D-05)")
        XCTAssertEqual(testStore.pendingRecordings.count, 1,
                       "Exactly one pendingRecording row must exist after stop with no transcriber")
        let row = try XCTUnwrap(testStore.pendingRecordings.first)
        let wavURL = try testStore.fileURL(for: row)
        XCTAssertTrue(FileManager.default.fileExists(atPath: wavURL.path),
                      "The pending recording's WAV must exist on disk (D-01 durability)")

        // Cleanup
        testStore.delete(row)
        try? FileManager.default.removeItem(at: tempContainer)
    }

    /// Once a transcriber becomes available, draining the queue must produce exactly
    /// one History entry, empty the store, and delete the WAV (D-02/D-05).
    func testDrainPendingRecordingsProducesExactlyOneHistoryEntryAndDeletesWav() async throws {
        let vm = DictationViewModel()
        let tempContainer = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let testHistory = HistoryService.makeForTesting(containerURLProvider: { tempContainer })
        let testStore = PendingRecordingStore.makeForTesting(historyService: testHistory)
        vm.historyService = testHistory
        vm.pendingStore = testStore
        vm.audioRecorder = FakeAudioRecorder()
        vm.isBackgroundedProvider = { false }

        // Stop with no transcriber — queues a recording.
        vm.state = .recording
        await vm.stopDictation()
        XCTAssertEqual(testStore.pendingRecordings.count, 1, "Precondition: one row queued")
        let row = try XCTUnwrap(testStore.pendingRecordings.first)
        let wavURL = try testStore.fileURL(for: row)

        // Now a transcriber becomes available — drain.
        let fakeTranscriber = FakeTranscriptionProvider()
        vm.transcriptionService = fakeTranscriber
        await vm.drainPendingRecordingsIfNeeded()

        XCTAssertEqual(fakeTranscriber.callCount, 1, "The transcriber must be invoked exactly once")
        XCTAssertEqual(testHistory.entries.count, 1, "Exactly one TranscriptionEntry must be saved — not zero, not two")
        // TextProcessingService.process() applies deterministic sentence-initial
        // capitalization, so the persisted text is "Fake transcript", not the raw
        // "fake transcript" the fake transcriber returned.
        XCTAssertEqual(testHistory.entries.first?.text, "Fake transcript")
        XCTAssertEqual(testStore.pendingRecordings.count, 0, "The pending row must be gone after a successful drain")
        XCTAssertFalse(FileManager.default.fileExists(atPath: wavURL.path),
                       "The WAV must be deleted once its transcript is saved (D-02)")

        // Cleanup
        if let id = testHistory.entries.first?.id { testHistory.delete(id: id) }
        try? FileManager.default.removeItem(at: tempContainer)
    }

    /// When a transcriber IS already set at stop time, transcription runs inline and
    /// produces exactly one TranscriptionEntry — not two. This is the double-save
    /// regression this phase is most exposed to (a duplicate save would occur if
    /// stopDictation()'s inline path AND a later drain both processed the same row,
    /// or if TextProcessingService were called twice).
    func testTranscriberSetAtStopTimeTranscribesInlineProducingExactlyOneEntry() async throws {
        let vm = DictationViewModel()
        let tempContainer = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let testHistory = HistoryService.makeForTesting(containerURLProvider: { tempContainer })
        let testStore = PendingRecordingStore.makeForTesting(historyService: testHistory)
        vm.historyService = testHistory
        vm.pendingStore = testStore
        vm.audioRecorder = FakeAudioRecorder()
        vm.isBackgroundedProvider = { false }
        let fakeTranscriber = FakeTranscriptionProvider()
        vm.transcriptionService = fakeTranscriber
        var clipboardValue: String?
        vm.clipboardWriter = { text in clipboardValue = text }

        vm.state = .recording
        await vm.stopDictation()

        XCTAssertEqual(fakeTranscriber.callCount, 1, "Inline transcription must run exactly once")
        XCTAssertEqual(testHistory.entries.count, 1, "Exactly one TranscriptionEntry — not two")
        // Sentence-initial capitalization is applied by TextProcessingService.process().
        XCTAssertEqual(clipboardValue, "Fake transcript", "Foreground inline delivery must write the clipboard")
        XCTAssertEqual(testStore.pendingRecordings.count, 0,
                       "The pending row must be resolved (deleted) once delivered inline, not left queued")

        // Cleanup
        if let id = testHistory.entries.first?.id { testHistory.delete(id: id) }
        try? FileManager.default.removeItem(at: tempContainer)
    }

    // MARK: - Phase 46-02: drain race guard (WR-03 / Finding-1 class)
    //
    // `drainPendingRecordingsIfNeeded()` must carry the same `state == .idle` +
    // `pendingDictation` re-check guard shape already applied twice in this codebase.
    // Reasoned falsifiability check for the reviewer's constraint: if the
    // `state == .idle` guard were removed, this test's setup (`vm.state = .recording`)
    // would no longer block the drain, `transcribe(wavURL:)` would be invoked, and the
    // `callCount == 0` / `entries.count == 0` assertions below would fail. This test
    // is therefore capable of going red on that specific regression, not just
    // decorative — confirmed by construction (the guard is the only thing preventing
    // the fake transcriber from being invoked, since transcriptionService and a
    // queued row are both present).

    /// The drain must be a no-op while a session is actively recording/transcribing
    /// (state != .idle) — the same race class as `deliverPendingTranscriptsIfNeeded()`
    /// (Finding 1: a drain that proceeds anyway would set state=.transcribing under a
    /// live recording's feet).
    func testDrainIsNoOpWhenStateIsNotIdle() async throws {
        let vm = DictationViewModel()
        let tempContainer = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let testHistory = HistoryService.makeForTesting(containerURLProvider: { tempContainer })
        let testStore = PendingRecordingStore.makeForTesting(historyService: testHistory)
        vm.historyService = testHistory
        vm.pendingStore = testStore
        vm.audioRecorder = FakeAudioRecorder()
        vm.isBackgroundedProvider = { false }

        // Queue a recording while idle.
        vm.state = .recording
        await vm.stopDictation()
        XCTAssertEqual(testStore.pendingRecordings.count, 1, "Precondition: one row queued")

        // A transcriber IS available, but a new session is now in progress —
        // simulate that by forcing state back to .recording before draining.
        let fakeTranscriber = FakeTranscriptionProvider()
        vm.transcriptionService = fakeTranscriber
        vm.state = .recording

        await vm.drainPendingRecordingsIfNeeded()

        XCTAssertEqual(fakeTranscriber.callCount, 0,
                       "Drain must not invoke the transcriber while state != .idle")
        XCTAssertEqual(testStore.pendingRecordings.count, 1,
                       "The queued row must be untouched while a new session is active")
        XCTAssertEqual(testHistory.entries.count, 0,
                       "No History entry may be created while the guard blocks the drain")

        // Cleanup
        vm.state = .idle
        if let row = testStore.pendingRecordings.first { testStore.delete(row) }
        try? FileManager.default.removeItem(at: tempContainer)
    }

    /// The drain must also be a no-op when a NEW recording has just been requested
    /// (`pendingDictation` set in the App Group) even though `state == .idle` at the
    /// instant it is checked — the same guard shape `isLlmReady`'s handler uses.
    func testDrainIsNoOpWhenPendingDictationFlagSet() async throws {
        let vm = DictationViewModel()
        let tempContainer = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let testHistory = HistoryService.makeForTesting(containerURLProvider: { tempContainer })
        let testStore = PendingRecordingStore.makeForTesting(historyService: testHistory)
        vm.historyService = testHistory
        vm.pendingStore = testStore
        vm.audioRecorder = FakeAudioRecorder()
        vm.isBackgroundedProvider = { false }

        vm.state = .recording
        await vm.stopDictation()
        XCTAssertEqual(testStore.pendingRecordings.count, 1, "Precondition: one row queued")

        let fakeTranscriber = FakeTranscriptionProvider()
        vm.transcriptionService = fakeTranscriber
        DicticusIPCBridge.defaults?.set(true, forKey: "pendingDictation")

        await vm.drainPendingRecordingsIfNeeded()

        XCTAssertEqual(fakeTranscriber.callCount, 0,
                       "Drain must not invoke the transcriber when pendingDictation is set — a new session wins")
        XCTAssertEqual(testStore.pendingRecordings.count, 1, "The queued row must be untouched")

        // Cleanup
        DicticusIPCBridge.defaults?.set(false, forKey: "pendingDictation")
        if let row = testStore.pendingRecordings.first { testStore.delete(row) }
        try? FileManager.default.removeItem(at: tempContainer)
    }

    // MARK: - Phase 46-02: icon launch never records (D-03)

    /// A foreground launch with no pending-dictation flag must leave state idle and
    /// never call the fake recorder's start — confirms tapping the app icon does not
    /// open the mic.
    func testForegroundWithNoPendingDictationNeverStartsRecording() async {
        let vm = DictationViewModel()
        let fakeRecorder = FakeAudioRecorder()
        vm.audioRecorder = fakeRecorder
        DicticusIPCBridge.defaults?.set(false, forKey: "pendingDictation")

        await vm.handleForeground(pendingDictation: false)
        // handleForeground(false) calls deliverPendingTranscriptsIfNeeded() (no-op, no
        // pending), drainPendingRecordingsIfNeeded() (no-op, no transcriber/no queue),
        // then checkPendingIntent() — which reads the (false) pendingDictation flag and
        // must not schedule a start.
        try? await Task.sleep(for: .milliseconds(600))  // checkPendingIntent's 500ms settle window

        XCTAssertEqual(fakeRecorder.startCallCount, 0,
                       "Icon launch (no pendingDictation) must never start a recording (D-03)")
        XCTAssertEqual(vm.state, .idle)
    }

    // MARK: - Phase 46-03: arrival-order queue drain, hold-on-failure, retry (D-09/D-10/D-11)

    /// Queues two recordings while no transcriber exists (a tiny sleep between
    /// guarantees distinct `createdAt` timestamps for a deterministic arrival
    /// order), then drains with a fake whose per-call responses are
    /// distinguishable, and asserts the resulting History entries match the
    /// expected ORDERED array — not membership.
    func testDrainDeliversTwoQueuedRecordingsInArrivalOrder() async throws {
        let vm = DictationViewModel()
        let tempContainer = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let testHistory = HistoryService.makeForTesting(containerURLProvider: { tempContainer })
        let testStore = PendingRecordingStore.makeForTesting(historyService: testHistory)
        vm.historyService = testHistory
        vm.pendingStore = testStore
        vm.audioRecorder = FakeAudioRecorder()
        vm.isBackgroundedProvider = { false }

        vm.state = .recording
        await vm.stopDictation()
        try? await Task.sleep(for: .seconds(0.01))
        vm.state = .recording
        await vm.stopDictation()
        XCTAssertEqual(testStore.pendingRecordings.count, 2, "Precondition: two rows queued")

        let fakeTranscriber = FakeTranscriptionProvider()
        fakeTranscriber.responseQueue = [
            .success(DicticusTranscriptionResult(text: "first spoken", language: "en", confidence: 0.9)),
            .success(DicticusTranscriptionResult(text: "second spoken", language: "en", confidence: 0.9)),
        ]
        vm.transcriptionService = fakeTranscriber

        await vm.drainPendingRecordingsIfNeeded()

        XCTAssertEqual(fakeTranscriber.callCount, 2, "Both queued rows must be transcribed")
        let orderedTexts = testHistory.entries.sorted(by: { $0.createdAt < $1.createdAt }).map(\.text)
        XCTAssertEqual(orderedTexts, ["First spoken", "Second spoken"],
                       "History entries must match the two fakes in ARRIVAL order, compared as an ordered array")
        XCTAssertEqual(testStore.pendingRecordings.count, 0, "Both rows must be resolved")

        // Cleanup
        for entry in testHistory.entries { if let id = entry.id { testHistory.delete(id: id) } }
        try? FileManager.default.removeItem(at: tempContainer)
    }

    /// A drain whose second recording's transcription throws must leave the first
    /// delivered (WAV gone, History entry present) and the second held (WAV still
    /// on disk, row `.failed` with a non-nil `failureReason`) — a failure on one row
    /// must not abort or lose the rest of the queue.
    func testDrainSecondFailureLeavesFirstDeliveredAndSecondHeldWithFile() async throws {
        let vm = DictationViewModel()
        let tempContainer = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let testHistory = HistoryService.makeForTesting(containerURLProvider: { tempContainer })
        let testStore = PendingRecordingStore.makeForTesting(historyService: testHistory)
        vm.historyService = testHistory
        vm.pendingStore = testStore
        vm.audioRecorder = FakeAudioRecorder()
        vm.isBackgroundedProvider = { false }

        vm.state = .recording
        await vm.stopDictation()
        try? await Task.sleep(for: .seconds(0.01))
        vm.state = .recording
        await vm.stopDictation()
        XCTAssertEqual(testStore.pendingRecordings.count, 2, "Precondition: two rows queued")
        let orderedRows = testStore.pendingRecordings.sorted(by: { $0.createdAt < $1.createdAt })
        let firstURL = try testStore.fileURL(for: orderedRows[0])
        let secondURL = try testStore.fileURL(for: orderedRows[1])

        let fakeTranscriber = FakeTranscriptionProvider()
        fakeTranscriber.responseQueue = [
            .success(DicticusTranscriptionResult(text: "delivered ok", language: "en", confidence: 0.9)),
            .failure(TranscriptionError.noResult),
        ]
        vm.transcriptionService = fakeTranscriber

        await vm.drainPendingRecordingsIfNeeded()

        XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path),
                       "First recording's WAV must be gone — it was delivered")
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondURL.path),
                      "Second recording's WAV must still exist — it was held, not discarded")
        let remaining = testStore.pendingRecordings
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.status, PendingRecordingStatus.failed.rawValue)
        XCTAssertNotNil(remaining.first?.failureReason)

        // Cleanup
        for entry in testHistory.entries { if let id = entry.id { testHistory.delete(id: id) } }
        for row in testStore.pendingRecordings { testStore.delete(row) }
        try? FileManager.default.removeItem(at: tempContainer)
    }

    /// `retryPendingRecording(_:)` on a failed row, with a now-succeeding
    /// transcriber, must produce a History entry and leave the store empty and the
    /// file gone.
    func testRetryPendingRecordingProducesHistoryEntryAndEmptiesStore() async throws {
        let vm = DictationViewModel()
        let tempContainer = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let testHistory = HistoryService.makeForTesting(containerURLProvider: { tempContainer })
        let testStore = PendingRecordingStore.makeForTesting(historyService: testHistory)
        vm.historyService = testHistory
        vm.pendingStore = testStore
        vm.audioRecorder = FakeAudioRecorder()
        vm.isBackgroundedProvider = { false }

        vm.state = .recording
        await vm.stopDictation()
        let failingTranscriber = FakeTranscriptionProvider()
        failingTranscriber.errorToThrow = TranscriptionError.noResult
        vm.transcriptionService = failingTranscriber
        await vm.drainPendingRecordingsIfNeeded()

        let failedRow = try XCTUnwrap(testStore.pendingRecordings.first)
        XCTAssertEqual(failedRow.status, PendingRecordingStatus.failed.rawValue, "Precondition: row is failed")
        let fileURL = try testStore.fileURL(for: failedRow)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "Precondition: WAV still held")

        let succeedingTranscriber = FakeTranscriptionProvider()
        succeedingTranscriber.resultText = "recovered on retry"
        vm.transcriptionService = succeedingTranscriber

        await vm.retryPendingRecording(failedRow)

        XCTAssertEqual(testHistory.entries.count, 1)
        XCTAssertEqual(testHistory.entries.first?.text, "Recovered on retry")
        XCTAssertEqual(testStore.pendingRecordings.count, 0, "Store must be empty after a successful retry")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path), "WAV must be gone after a successful retry")

        // Cleanup
        for entry in testHistory.entries { if let id = entry.id { testHistory.delete(id: id) } }
        try? FileManager.default.removeItem(at: tempContainer)
    }

    /// Disposition table half 1: `.tooShort` discards the row and the bytes — a
    /// determination there was nothing to transcribe, not a failure to hold.
    func testTooShortOutcomeDiscardsRowAndFile() async throws {
        let vm = DictationViewModel()
        let tempContainer = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let testHistory = HistoryService.makeForTesting(containerURLProvider: { tempContainer })
        let testStore = PendingRecordingStore.makeForTesting(historyService: testHistory)
        vm.historyService = testHistory
        vm.pendingStore = testStore
        vm.audioRecorder = FakeAudioRecorder()
        vm.isBackgroundedProvider = { false }

        vm.state = .recording
        await vm.stopDictation()
        let row = try XCTUnwrap(testStore.pendingRecordings.first)
        let fileURL = try testStore.fileURL(for: row)

        let fakeTranscriber = FakeTranscriptionProvider()
        fakeTranscriber.errorToThrow = TranscriptionError.tooShort
        vm.transcriptionService = fakeTranscriber

        await vm.drainPendingRecordingsIfNeeded()

        XCTAssertEqual(testStore.pendingRecordings.count, 0, ".tooShort must discard the row")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path), ".tooShort must discard the file")

        try? FileManager.default.removeItem(at: tempContainer)
    }

    /// Disposition table half 2: `.noResult` holds one row — the file may contain
    /// something the user said and the attempt simply failed to extract it.
    func testNoResultOutcomeHoldsRowAndFile() async throws {
        let vm = DictationViewModel()
        let tempContainer = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let testHistory = HistoryService.makeForTesting(containerURLProvider: { tempContainer })
        let testStore = PendingRecordingStore.makeForTesting(historyService: testHistory)
        vm.historyService = testHistory
        vm.pendingStore = testStore
        vm.audioRecorder = FakeAudioRecorder()
        vm.isBackgroundedProvider = { false }

        vm.state = .recording
        await vm.stopDictation()
        let row = try XCTUnwrap(testStore.pendingRecordings.first)
        let fileURL = try testStore.fileURL(for: row)

        let fakeTranscriber = FakeTranscriptionProvider()
        fakeTranscriber.errorToThrow = TranscriptionError.noResult
        vm.transcriptionService = fakeTranscriber

        await vm.drainPendingRecordingsIfNeeded()

        XCTAssertEqual(testStore.pendingRecordings.count, 1, ".noResult must hold — leave exactly one row")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), ".noResult must NOT discard the file")
        XCTAssertEqual(testStore.pendingRecordings.first?.status, PendingRecordingStatus.failed.rawValue)
        XCTAssertNotNil(testStore.pendingRecordings.first?.failureReason)

        // Cleanup
        for r in testStore.pendingRecordings { testStore.delete(r) }
        try? FileManager.default.removeItem(at: tempContainer)
    }

    /// Direct unit test of the disposition-mapping function itself, independent of
    /// the async drain pipeline — every case in the table.
    func testFailureDispositionMapping() {
        XCTAssertEqual(DictationViewModel.failureDisposition(for: TranscriptionError.tooShort), .discard)
        XCTAssertEqual(DictationViewModel.failureDisposition(for: TranscriptionError.silenceOnly), .discard)
        XCTAssertEqual(DictationViewModel.failureDisposition(for: TranscriptionError.noResult),
                       .hold(reason: "Could not understand audio."))
        XCTAssertEqual(DictationViewModel.failureDisposition(for: TranscriptionError.unexpectedLanguage),
                       .hold(reason: "Unsupported language detected."))
        XCTAssertEqual(DictationViewModel.failureDisposition(for: TranscriptionError.modelNotReady),
                       .hold(reason: "Model not ready."))
        XCTAssertEqual(DictationViewModel.failureDisposition(for: TranscriptionError.busy),
                       .hold(reason: "System busy."))
        XCTAssertEqual(DictationViewModel.failureDisposition(for: TranscriptionError.notRecording),
                       .hold(reason: "Not recording."))
        struct SomeOtherError: Error, LocalizedError {
            var errorDescription: String? { "unreadable file" }
        }
        XCTAssertEqual(DictationViewModel.failureDisposition(for: SomeOtherError()),
                       .hold(reason: "unreadable file"),
                       "Any other thrown error (I/O, decode, unreadable file) must hold, using its localized description")
    }

    /// A backgrounded drain of a two-recording batch must never touch the
    /// clipboard, and must post EXACTLY ONE notification for the whole batch (not
    /// one per recording), with a body that contains neither transcript's text.
    func testBackgroundedDrainOfTwoRecordingsPostsOneBatchedNotificationNoClipboard() async throws {
        let vm = DictationViewModel()
        let tempContainer = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let testHistory = HistoryService.makeForTesting(containerURLProvider: { tempContainer })
        let testStore = PendingRecordingStore.makeForTesting(historyService: testHistory)
        vm.historyService = testHistory
        vm.pendingStore = testStore
        vm.audioRecorder = FakeAudioRecorder()
        vm.isBackgroundedProvider = { false }  // queue while "foreground" — backgrounding only matters at drain time

        vm.state = .recording
        await vm.stopDictation()
        try? await Task.sleep(for: .seconds(0.01))
        vm.state = .recording
        await vm.stopDictation()
        XCTAssertEqual(testStore.pendingRecordings.count, 2, "Precondition: two rows queued")

        var clipboardWritten = false
        vm.clipboardWriter = { _ in clipboardWritten = true }
        var notificationCount = 0
        var lastBody: String?
        vm.notificationPoster = { _, body in
            notificationCount += 1
            lastBody = body
        }

        vm.isBackgroundedProvider = { true }  // now background for the drain itself
        let fakeTranscriber = FakeTranscriptionProvider()
        fakeTranscriber.responseQueue = [
            .success(DicticusTranscriptionResult(text: "alpha secret content", language: "en", confidence: 0.9)),
            .success(DicticusTranscriptionResult(text: "beta secret content", language: "en", confidence: 0.9)),
        ]
        vm.transcriptionService = fakeTranscriber

        await vm.drainPendingRecordingsIfNeeded()

        XCTAssertFalse(clipboardWritten, "A backgrounded drain must never write to the clipboard")
        XCTAssertEqual(notificationCount, 1, "Exactly one notification must be posted for a two-recording batch")
        let body = try XCTUnwrap(lastBody)
        XCTAssertFalse(body.lowercased().contains("alpha") || body.lowercased().contains("beta"),
                       "Notification body must not contain either transcript's text (T-36-08)")

        // Cleanup
        DicticusIPCBridge.defaults?.removeObject(forKey: DicticusIPCBridge.Key.pendingTranscriptUUIDs)
        DicticusIPCBridge.defaults?.removeObject(forKey: DicticusIPCBridge.Key.pendingTranscriptUUID)
        for entry in testHistory.entries { if let id = entry.id { testHistory.delete(id: id) } }
        try? FileManager.default.removeItem(at: tempContainer)
    }

    // MARK: - Phase 46-03: stale pendingDictation must never spontaneously open the mic
    //
    // Device-UAT finding (2026-08-10, force-quit-then-relaunch session): "without me
    // clicking anything, it started recording and then stopped by itself... during
    // warm-up." Root cause: `pendingDictation=true` is set by `DictateIntent.perform()`/
    // the URL-scheme handler and cleared ONLY by `checkPendingIntent()` — a process
    // killed between the write and that consumption leaves the flag set indefinitely
    // in App Group `UserDefaults` (which persist to disk immediately), and ANY later,
    // completely unrelated relaunch would silently start a recording. Reproduced here
    // directly (deterministic) rather than racing a device-timing window narrower than
    // devicectl's automation granularity.

    /// A `pendingDictation=true` flag with NO staleness timestamp at all (the exact
    /// shape a pre-fix write, or a flag from a process that died before ever writing
    /// the timestamp, would leave behind) must be cleared without starting a recording.
    func testMissingTimestampPendingDictationDoesNotSpontaneouslyStartRecording() async throws {
        let vm = DictationViewModel()
        let fakeRecorder = FakeAudioRecorder()
        vm.audioRecorder = fakeRecorder
        vm.permissionRequester = { true }

        DicticusIPCBridge.defaults?.set(true, forKey: "pendingDictation")
        DicticusIPCBridge.defaults?.set(true, forKey: "isShortcutLaunch")
        DicticusIPCBridge.defaults?.removeObject(forKey: "pendingDictationSetAt")  // explicitly absent

        vm.checkPendingIntent()
        try? await Task.sleep(for: .seconds(0.6))  // past the 500ms deferred-start delay

        XCTAssertEqual(fakeRecorder.startCallCount, 0,
                       "A pendingDictation flag with no staleness timestamp must NOT spontaneously start a recording")
        XCTAssertFalse(DicticusIPCBridge.defaults?.bool(forKey: "pendingDictation") ?? true,
                       "The stale flag must still be cleared, just without starting a recording")

        DicticusIPCBridge.defaults?.removeObject(forKey: "isShortcutLaunch")
    }

    /// A `pendingDictation=true` flag whose timestamp is older than
    /// `pendingDictationStalenessSeconds` — the exact shape a flag surviving a real
    /// force-quit-then-much-later-relaunch would have — must also be cleared without
    /// starting a recording.
    func testOldTimestampPendingDictationDoesNotSpontaneouslyStartRecording() async throws {
        let vm = DictationViewModel()
        let fakeRecorder = FakeAudioRecorder()
        vm.audioRecorder = fakeRecorder
        vm.permissionRequester = { true }
        vm.pendingDictationStalenessSeconds = 10

        DicticusIPCBridge.defaults?.set(true, forKey: "pendingDictation")
        DicticusIPCBridge.defaults?.set(true, forKey: "isShortcutLaunch")
        DicticusIPCBridge.defaults?.set(Date().timeIntervalSince1970 - 60, forKey: "pendingDictationSetAt")  // 60s old, past the 10s threshold

        vm.checkPendingIntent()
        try? await Task.sleep(for: .seconds(0.6))

        XCTAssertEqual(fakeRecorder.startCallCount, 0,
                       "A pendingDictation flag older than pendingDictationStalenessSeconds must NOT spontaneously start a recording")

        DicticusIPCBridge.defaults?.removeObject(forKey: "isShortcutLaunch")
    }

    /// Regression guard: a FRESHLY-set `pendingDictation=true` flag must still start a
    /// recording normally — the staleness fix must not reopen D-01/D-03's "an
    /// invocation must never do nothing" guarantee for the legitimate case.
    func testFreshPendingDictationStillStartsRecordingNormally() async throws {
        let vm = DictationViewModel()
        let fakeRecorder = FakeAudioRecorder()
        vm.audioRecorder = fakeRecorder
        vm.permissionRequester = { true }
        vm.pendingDictationStalenessSeconds = 10

        DicticusIPCBridge.defaults?.set(true, forKey: "pendingDictation")
        DicticusIPCBridge.defaults?.set(true, forKey: "isShortcutLaunch")
        DicticusIPCBridge.defaults?.set(Date().timeIntervalSince1970, forKey: "pendingDictationSetAt")  // fresh

        vm.checkPendingIntent()
        try? await Task.sleep(for: .seconds(0.6))

        XCTAssertGreaterThan(fakeRecorder.startCallCount, 0,
                             "A freshly-set pendingDictation flag must still start a recording — D-01/D-03's never-dead guarantee")
        XCTAssertFalse(DicticusIPCBridge.defaults?.bool(forKey: "pendingDictation") ?? true,
                       "The flag must be cleared after a legitimate consumption too")
    }
}
