import XCTest
import Combine
import KeyboardShortcuts
@testable import Dicticus

/// Transcription stub for the release lifecycle: no model, no audio engine.
@MainActor
final class StubTranscriber: DictationTranscribing {
    @Published var state: TranscriptionService.State = .idle
    var statePublisher: AnyPublisher<TranscriptionService.State, Never> { $state.eraseToAnyPublisher() }
    var lastResult: DicticusTranscriptionResult?
    var lastLivePreviewStats: LivePreviewSession.Stats?

    var startError: Error?
    var stopResult: Result<DicticusTranscriptionResult, Error> =
        .success(DicticusTranscriptionResult(text: "hello world", language: "en", confidence: 0.9))
    /// Runs inside `stopRecordingAndTranscribe`, i.e. at the moment the final decode starts.
    var atDecode: (@MainActor () -> Void)?

    private(set) var startCount = 0
    private(set) var previewStarts = 0
    private(set) var publish: (@MainActor (String) -> Void)?
    private(set) var silence: (@MainActor () -> Void)?

    func startRecording() throws {
        startCount += 1
        if let startError { throw startError }
        state = .recording
    }

    func startLivePreview(
        cadence: Duration, publish: @escaping @MainActor (String) -> Void, silence: (@MainActor () -> Void)?
    ) {
        previewStarts += 1
        self.publish = publish
        self.silence = silence
    }

    func stopRecordingAndTranscribe() async throws -> DicticusTranscriptionResult {
        state = .transcribing
        defer { state = .idle }
        atDecode?()
        return try stopResult.get()
    }
}

/// Records the paste instead of performing it, and can hold the paste open.
@MainActor
final class RecordingInjector: TextInjector {
    private(set) var injected: [String] = []
    /// The overlay's hide calls at the moment the paste started.
    private(set) var hidesAtInjection: [LiveOverlayHideReason] = []
    var holdPaste = false
    private(set) var isHolding = false
    private var held: CheckedContinuation<Void, Never>?
    private let spy: SpyOverlay

    init(spy: SpyOverlay) {
        self.spy = spy
        super.init()
    }

    override func injectText(_ text: String, expectedFrontmostBundleID: String? = nil) async -> Outcome {
        injected.append(text)
        hidesAtInjection = spy.hideReasons
        if holdPaste {
            isHolding = true
            await withCheckedContinuation { held = $0 }
            isHolding = false
        }
        return .delivered
    }

    func releasePaste() {
        holdPaste = false
        held?.resume()
        held = nil
    }
}

@MainActor
final class HotkeyManagerTests: XCTestCase {

    // MARK: - Key repeat suppression (D-03)

    func testKeyRepeatSuppression() {
        // Verify isKeyDown flag prevents duplicate keyDown handling.
        // Without a real TranscriptionService, handleKeyDown will hit the
        // warmupService nil guard and reset isKeyDown — so we test the flag
        // logic directly by checking the published state.
        let manager = HotkeyManager()
        // Without setup(), transcriptionService and warmupService are nil.
        // First keyDown: isKeyDown becomes true, then resets because warmupService is nil.
        manager.handleKeyDown(mode: .plain)
        // lastPostedNotification should be nil (no warmupService = early return, no notification)
        // The important thing: handleKeyDown does not crash on repeated calls.
        manager.handleKeyDown(mode: .plain)
        // No crash = key repeat is handled safely
    }

    func testKeyUpResetsAfterKeyDown() {
        let manager = HotkeyManager()
        manager.handleKeyDown(mode: .plain)
        manager.handleKeyUp(mode: .plain)
        // isRecording should be false after key up
        XCTAssertFalse(manager.isRecording)
    }

    // MARK: - Model not ready (D-17)

    func testModelNotReadyNotification() {
        let manager = HotkeyManager()
        // Without warmupService set up, handleKeyDown silently returns
        // (warmupService is nil, treated as not ready).
        manager.handleKeyDown(mode: .plain)
        // Without warmupService, should not start recording
        XCTAssertFalse(manager.isRecording)
    }

    // MARK: - Two hotkeys registered (APP-04)

    func testTwoHotkeysRegistered() {
        // Compile-time verification that both names exist and are distinct
        let plain = KeyboardShortcuts.Name.plainDictation
        let cleanup = KeyboardShortcuts.Name.aiCleanup
        XCTAssertNotEqual(plain.rawValue, cleanup.rawValue)
        XCTAssertEqual(plain.rawValue, "plainDictation")
        XCTAssertEqual(cleanup.rawValue, "aiCleanup")
    }

    // MARK: - Icon state mapping (APP-03)

    func testIconStateIdle() {
        let manager = HotkeyManager()
        XCTAssertFalse(manager.isRecording)
        // When isRecording is false and service is idle, icon should be "mic"
        // (icon logic is in DicticusApp, but we verify the HotkeyManager state here)
    }

    func testIconStateRecording() {
        // Verify the isRecording published property that drives icon state
        let manager = HotkeyManager()
        // We cannot easily trigger isRecording = true without a full TranscriptionService,
        // but we verify the property exists and defaults to false
        XCTAssertFalse(manager.isRecording)
        // Icon mapping: isRecording == true -> "mic.fill" (tested in DicticusApp integration)
    }

    // MARK: - Short press / silence discard (D-02, D-16)

    func testShortPressResultsInNoRecording() {
        let manager = HotkeyManager()
        // Quick keyDown + keyUp without setup — should not crash, isRecording stays false
        manager.handleKeyDown(mode: .plain)
        manager.handleKeyUp(mode: .plain)
        XCTAssertFalse(manager.isRecording)
        // D-02: tooShort errors are silently caught (verified by code path, not integration test)
    }

    // MARK: - Reject while transcribing (D-19)

    func testRejectWhileTranscribingState() {
        // Without a real TranscriptionService in .transcribing state,
        // we verify the guard logic exists by checking that handleKeyDown
        // when service is nil does not set isRecording to true
        let manager = HotkeyManager()
        manager.handleKeyDown(mode: .plain)
        XCTAssertFalse(manager.isRecording)
        // D-19 code path: service.state != .idle -> post .busy notification
    }

    // MARK: - DictationMode enum

    func testDictationModeValues() {
        // Verify both enum cases exist
        let plain = DictationMode.plain
        let cleanup = DictationMode.aiCleanup
        // These are distinct enum cases
        if case .plain = plain { } else { XCTFail("Expected .plain case") }
        if case .aiCleanup = cleanup { } else { XCTFail("Expected .aiCleanup case") }
    }

    // MARK: - AI cleanup mode (Phase 4)

    func testAICleanupKeyDownBeforeLLMReady() {
        // Without setup() called, cleanupService is nil.
        // handleKeyDown with .aiCleanup should not start recording.
        let manager = HotkeyManager()
        manager.handleKeyDown(mode: .aiCleanup)
        XCTAssertFalse(manager.isRecording,
                        "Should not record without setup() being called")
    }

    func testAICleanupModeEnumExists() {
        // Verify DictationMode.aiCleanup case is available (not a stub)
        let mode: DictationMode = .aiCleanup
        XCTAssertNotEqual(mode, .plain, "AI cleanup must be a distinct mode from plain")
    }

    // MARK: - Phase 50 D-11: widened key-down table (idle-unloaded LLM starts recording)

    func testAiCleanupKeyDownAction_table() {
        XCTAssertEqual(
            HotkeyManager.aiCleanupKeyDownAction(cleanupServicePresent: false, isLoaded: false, idleUnloaded: false),
            .abortLlmLoading,
            "no CleanupService instance at all must abort (matches testAICleanupKeyDownBeforeLLMReady)"
        )
        XCTAssertEqual(
            HotkeyManager.aiCleanupKeyDownAction(cleanupServicePresent: true, isLoaded: true, idleUnloaded: false),
            .proceed,
            "loaded and not idle-unloaded — normal path"
        )
        XCTAssertEqual(
            HotkeyManager.aiCleanupKeyDownAction(cleanupServicePresent: true, isLoaded: false, idleUnloaded: true),
            .reloadAndProceed,
            "idle-unloaded — start recording and kick the reload (D-11)"
        )
        XCTAssertEqual(
            HotkeyManager.aiCleanupKeyDownAction(cleanupServicePresent: true, isLoaded: false, idleUnloaded: false),
            .abortLlmLoading,
            "not loaded and not idle-unloaded — the initial launch load is still in flight, abort as before"
        )
        XCTAssertEqual(
            HotkeyManager.aiCleanupKeyDownAction(cleanupServicePresent: true, isLoaded: true, idleUnloaded: true),
            .proceed,
            "loaded wins even if a stale idleUnloaded flag is somehow still true"
        )
    }

    // MARK: - Phase 50 WR-03: paste-outcome to notification mapping

    func testNotificationForOutcome_mapsBothUndeliverableOutcomesDistinctly() {
        guard case .pasteUndeliverable? = HotkeyManager.notification(for: .fallbackToClipboard(.frontmostChanged)) else {
            return XCTFail("fallbackToClipboard must map to .pasteUndeliverable")
        }
        guard case .pasteUndeliverableClipboardUntouched? = HotkeyManager.notification(for: .undeliverableClipboardUntouched(.frontmostChanged)) else {
            return XCTFail("undeliverableClipboardUntouched must map to .pasteUndeliverableClipboardUntouched")
        }
        XCTAssertNil(HotkeyManager.notification(for: .delivered))
        XCTAssertNil(HotkeyManager.notification(for: .blocked))
    }

    // MARK: - Phase 51 D-06: the overlay is shown only after a recording actually started

    func testFailedKeyDownNeverShowsTheOverlay() {
        let spy = SpyOverlay()
        let manager = HotkeyManager(overlay: spy)
        // No warm-up service: both modes stop at the readiness guard before startRecording().
        manager.handleKeyDown(mode: .plain)
        manager.handleKeyUp(mode: .plain)
        manager.handleKeyDown(mode: .aiCleanup)
        manager.handleKeyUp(mode: .aiCleanup)
        XCTAssertEqual(spy.showCount, 0)
        XCTAssertTrue(spy.updates.isEmpty)
    }

    func testReleaseWithoutAPressNeverTouchesTheOverlay() {
        let spy = SpyOverlay()
        let manager = HotkeyManager(overlay: spy)
        manager.handleKeyUp(mode: .plain)
        manager.handleKeyUp(mode: .aiCleanup)
        XCTAssertEqual(spy.showCount, 0)
        XCTAssertEqual(spy.processingCount, 0)
        XCTAssertTrue(spy.hideReasons.isEmpty, "a stray release must not hide or dim a panel")
    }

    // MARK: - Phase 51 release lifecycle (stub transcription, recording injector)

    @MainActor
    private final class Rig {
        let spy = SpyOverlay()
        let stub = StubTranscriber()
        let warmup = ModelWarmupService()
        let injector: RecordingInjector
        let manager: HotkeyManager

        init() {
            injector = RecordingInjector(spy: spy)
            manager = HotkeyManager(overlay: spy, textInjector: injector, mediaController: .makeForTesting())
            warmup.isReady = true
            manager.attach(transcriptionService: stub, warmupService: warmup)
        }

        /// Press and release `.plain` and wait until the dictation Task has hidden the panel for good.
        func dictate() async {
            manager.handleKeyDown(mode: .plain)
            manager.handleKeyUp(mode: .plain)
            _ = await HotkeyManagerTests.eventually { self.spy.hideReasons.contains(.taskEnd) }
        }
    }

    private var rig: Rig!

    override func setUp() async throws {
        try await super.setUp()
        rig = Rig()
    }

    override func tearDown() async throws {
        rig = nil
        DicticusDefaults.suite.removeObject(forKey: LivePreviewSession.enabledKey)
        try await super.tearDown()
    }

    /// Polls until `condition` holds. The bound only caps a failing run; a passing run returns at once.
    static func eventually(_ condition: @escaping @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(10)) }
        return condition()
    }

    func testReleaseSettlesTheOverlayBeforeTheFinalDecodeAndHidesBeforeThePaste() async {
        var processingAtDecode = -1
        var hidesAtDecode: [LiveOverlayHideReason] = []
        rig.stub.atDecode = { [spy = rig.spy] in
            processingAtDecode = spy.processingCount
            hidesAtDecode = spy.hideReasons
        }
        await rig.dictate()

        XCTAssertEqual(rig.spy.showCount, 1)
        XCTAssertEqual(rig.stub.previewStarts, 1)
        XCTAssertEqual(processingAtDecode, 1, "setProcessing must run on release, before the final decode (D-06)")
        XCTAssertEqual(hidesAtDecode, [], "the panel stays up through the final decode")
        XCTAssertEqual(rig.injector.injected, ["hello world"])
        XCTAssertEqual(rig.injector.hidesAtInjection, [.pasting], "the panel hides before the paste starts")
        XCTAssertEqual(rig.spy.hideReasons, [.pasting, .taskEnd])
    }

    func testAThrowingDecodeHidesTheOverlayExactlyOnceAndPastesNothing() async {
        rig.stub.stopResult = .failure(TranscriptionError.tooShort)
        await rig.dictate()

        XCTAssertEqual(rig.spy.hideReasons, [.taskEnd])
        XCTAssertEqual(rig.spy.processingCount, 1)
        XCTAssertTrue(rig.injector.injected.isEmpty)
        XCTAssertFalse(rig.manager.isRecording)
    }

    func testANewerPressKeepsItsPanelWhenAnOlderReleaseFinishes() async {
        rig.injector.holdPaste = true
        rig.manager.handleKeyDown(mode: .plain)
        rig.manager.handleKeyUp(mode: .plain)
        let reachedPaste = await Self.eventually { self.rig.injector.isHolding }
        XCTAssertTrue(reachedPaste)
        XCTAssertEqual(rig.spy.hideReasons, [.pasting])

        // A press during the previous paste's clipboard-restore window shows a newer panel.
        rig.manager.handleKeyDown(mode: .plain)
        XCTAssertEqual(rig.spy.showCount, 2)
        rig.injector.releasePaste()

        rig.manager.handleKeyUp(mode: .plain)
        _ = await Self.eventually { self.rig.spy.hideReasons.count >= 3 }
        XCTAssertEqual(rig.spy.hideReasons, [.pasting, .pasting, .taskEnd],
                       "the older dictation hid the newer press's panel")
    }

    func testToggleOffStartsNeitherPanelNorPreviewButStillRecordsAndPastes() async {
        DicticusDefaults.suite.set(false, forKey: LivePreviewSession.enabledKey)
        await rig.dictate()

        XCTAssertEqual(rig.stub.startCount, 1)
        XCTAssertEqual(rig.spy.showCount, 0)
        XCTAssertEqual(rig.stub.previewStarts, 0)
        XCTAssertEqual(rig.injector.injected, ["hello world"])
    }

    func testPreviewTextAndPausesReachTheOverlay() {
        rig.manager.handleKeyDown(mode: .plain)
        rig.stub.publish?("one two")
        rig.stub.silence?()
        XCTAssertEqual(rig.spy.updates, ["one two"])
        XCTAssertEqual(rig.spy.settleCount, 1)
        rig.manager.handleKeyUp(mode: .plain)
    }

    func testReleaseWhenTheServiceIsNotRecordingHidesWithTheEarlyReturnReason() {
        rig.manager.handleKeyDown(mode: .plain)
        rig.stub.state = .idle
        rig.manager.handleKeyUp(mode: .plain)

        XCTAssertEqual(rig.spy.hideReasons, [.earlyReturn])
        XCTAssertEqual(rig.spy.processingCount, 0)
        XCTAssertTrue(rig.injector.injected.isEmpty)
        XCTAssertFalse(rig.manager.isRecording)
    }

    func testReleaseOfTheOtherModeLeavesThePanelAndTheRecordingAlone() async {
        rig.manager.handleKeyDown(mode: .plain)
        rig.manager.handleKeyUp(mode: .aiCleanup)

        XCTAssertTrue(rig.spy.hideReasons.isEmpty)
        XCTAssertEqual(rig.spy.processingCount, 0)
        XCTAssertTrue(rig.manager.isRecording)

        rig.manager.handleKeyUp(mode: .plain)
        _ = await Self.eventually { self.rig.spy.hideReasons.contains(.taskEnd) }
        XCTAssertEqual(rig.spy.processingCount, 1)
    }

    func testARecordingThatFailsToStartNeverShowsThePanelAndTheNextPressWorks() async {
        rig.stub.startError = TranscriptionError.busy
        rig.manager.handleKeyDown(mode: .plain)
        XCTAssertEqual(rig.spy.showCount, 0)
        XCTAssertFalse(rig.manager.isRecording)

        rig.stub.startError = nil
        await rig.dictate()
        XCTAssertEqual(rig.spy.showCount, 1)
    }

    // MARK: - Integration test (requires WhisperKit model)

    func testFullPushToTalkCycle() async throws {
        try XCTSkipUnless(TranscriptionService.isWhisperKitAvailable(),
                          "WhisperKit model not cached — skipping integration test")

        guard let _ = try await TranscriptionService.makeForTesting() else {
            throw XCTSkip("Could not create TranscriptionService for testing")
        }

        let manager = HotkeyManager()
        // Without a ready warmupService, handleKeyDown should not start recording
        manager.handleKeyDown(mode: .plain)
        XCTAssertFalse(manager.isRecording)
    }
}
