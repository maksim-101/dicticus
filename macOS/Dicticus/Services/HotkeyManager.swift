import SwiftUI
import AppKit
import KeyboardShortcuts
import Combine
import os

private let hotkeyLog = Logger(subsystem: "com.dicticus", category: "hotkey-manager")

/// Push-to-talk state machine coordinating hotkey events, TranscriptionService, and TextInjector.
///
/// Per D-01: Hold hotkey starts recording, release triggers transcription and paste.
/// Per D-03: Key repeat suppressed via isKeyDown flag.
/// Per D-12/D-13: AI cleanup hotkey registered but silently ignored.
/// Per D-18: Recording continues across app switches — text pastes into frontmost app on release.
/// Per D-19: Reject second hotkey while transcribing.
@MainActor
class HotkeyManager: ObservableObject {

    enum PipelineState {
        case idle
        case recording
        case transcribing
        case cleaning
    }

    /// Overall pipeline state combining recording, transcribing, and cleaning.
    @Published var pipelineState: PipelineState = .idle

    /// True while actively recording (keyDown received, keyUp not yet received).
    /// Kept for internal logic, but UI observes pipelineState.
    @Published var isRecording = false

    /// Tracks whether the last notification was a specific type, for testability.
    /// Not used in production UI — exists to verify notification posting in tests.
    @Published var lastPostedNotification: DicticusNotification?

    /// Last successful transcription text for display in menu bar dropdown (D-21).
    /// Returns nil when no transcription has occurred in this session.
    var lastTranscriptionText: String? {
        transcriptionService?.lastResult?.text
    }

    /// D-03: Suppress key repeat — ignore keyDown when already down.
    private var isKeyDown = false

    /// Mode that started the currently-active recording. Used by `handleKeyUp`
    /// to reject release events whose mode does not match — defends against
    /// spurious release events from the modifier listener (see debug session
    /// `ptt-stops-mid-hold`).
    private var activeRecordingMode: DictationMode?

    /// Phase 38 Plan 01 (D-02, CTXFMT-01/CTXFMT-02): the frontmost app's
    /// bundle ID captured at hotkey press-time, and the `DictationContext`
    /// resolved from it — stashed here (never a shared mutable global) so a
    /// mid-hold app switch still pastes into the release-time app while
    /// carrying the PRESS-time context (accepted, Pitfall 1). Cleared in
    /// `handleKeyUp` after being threaded into `TextProcessingService.process`.
    private var activeRecordingBundleID: String?
    private var activeRecordingContext: DictationContext?

    /// Phase 38 Plan 04 (D-09, CTXFMT-03): the popover's session-scoped
    /// Auto/Code/Prose/Default pin. `nil` == Auto (no pin, resolve normally).
    /// In-memory `@Published` ONLY — never written to `DicticusDefaults` or
    /// any other persistent store, so it resets to Auto (`nil`) on every app
    /// relaunch by construction. Read at press-time in `handleKeyDown` and
    /// by `liveResolvedContext()` for the popover's live-resolution label.
    @Published var contextPin: DictationContext?

    /// Weak reference to TranscriptionService — set via setup().
    private weak var transcriptionService: TranscriptionService?

    /// Reference to ModelWarmupService to check isReady before recording.
    private weak var warmupService: ModelWarmupService?

    /// Reference to TextProcessingService for dictionary, ITN, and AI cleanup pipeline.
    /// Set via setup() after warmup completes.
    var textProcessingService: TextProcessingService?

    /// Reference to CleanupService for AI cleanup mode (D-11).
    /// Set via setup() after warmup completes, or later when LLM finishes loading.
    /// Weak to avoid retain cycle.
    weak var cleanupService: CleanupService? {
        didSet { bindState() }
    }

    private var cancellables = Set<AnyCancellable>()

    /// True when KeyboardShortcuts AsyncStream consumption ends unexpectedly (rare TCC race or
    /// hotkey conflict). MenuBarView observes this so the Repair banner appears even when AX is
    /// technically granted (D-04 layer 2).
    @Published var registrationFailed: Bool = false

    /// Task handles for the two AsyncStream consumers, retained so reregisterAll() can cancel them.
    private var plainDictationTask: Task<Void, Never>?
    private var cleanupTask: Task<Void, Never>?

    /// TextInjector for clipboard-based text injection.
    /// Isolated to @MainActor via HotkeyManager's own isolation.
    private let textInjector = TextInjector()

    /// MediaRemote-backed service for PTT media auto-pause (Phase 30, MEDIA-PAUSE-01).
    /// dlopen happens once at construction; guard inside MediaController handles missing framework.
    private let mediaController = MediaController()

    /// Reference to ModifierHotkeyListener — set via setupModifierListener().
    /// Retains the listener for the app lifetime; closures route events to push-to-talk state machine.
    private var modifierListener: ModifierHotkeyListener?

    /// Configure the manager with required service references and start listening for hotkey events.
    ///
    /// Must be called after TranscriptionService is created (after warmup completes).
    /// Safe to call multiple times — KeyboardShortcuts.events(for:) creates new async streams.
    func setup(
        transcriptionService: TranscriptionService,
        warmupService: ModelWarmupService,
        textProcessingService: TextProcessingService
    ) {
        self.transcriptionService = transcriptionService
        self.warmupService = warmupService
        self.textProcessingService = textProcessingService
        self.cleanupService = warmupService.cleanupServiceInstance

        bindState()

        // D-04 layer 2: liveness — failure of KeyboardShortcuts to start/keep an AsyncStream is silent
        // in normal flow, so log + publish a recoverable flag.
        registrationFailed = false

        plainDictationTask?.cancel()
        plainDictationTask = Task { [weak self] in
            guard let self else { return }
            hotkeyLog.info("KeyboardShortcuts AsyncStream started for plainDictation")
            for await event in KeyboardShortcuts.events(for: .plainDictation) {
                switch event {
                case .keyDown: self.handleKeyDown(mode: .plain)
                case .keyUp:   self.handleKeyUp(mode: .plain)
                }
            }
            hotkeyLog.error("KeyboardShortcuts AsyncStream for plainDictation ENDED — registration may have failed")
            // The stream never finish()es, so this line is reached both on a genuine
            // registration failure AND on task cancellation (e.g. reregisterAll() tearing
            // down this task to re-bind). Only a non-cancelled termination is a real failure —
            // otherwise a healthy Re-register would falsely trip the Repair banner.
            if !Task.isCancelled {
                await MainActor.run { self.registrationFailed = true }
            }
        }

        cleanupTask?.cancel()
        cleanupTask = Task { [weak self] in
            guard let self else { return }
            hotkeyLog.info("KeyboardShortcuts AsyncStream started for aiCleanup")
            for await event in KeyboardShortcuts.events(for: .aiCleanup) {
                switch event {
                case .keyDown: self.handleKeyDown(mode: .aiCleanup)
                case .keyUp:   self.handleKeyUp(mode: .aiCleanup)
                }
            }
            hotkeyLog.error("KeyboardShortcuts AsyncStream for aiCleanup ENDED — registration may have failed")
            if !Task.isCancelled {
                await MainActor.run { self.registrationFailed = true }
            }
        }

        // Request notification permission on setup
        NotificationService.shared.setup()
    }

    /// Wire ModifierHotkeyListener into the push-to-talk state machine and start the CGEventTap.
    ///
    /// Called after ASR warmup completes (same point as setup()) so modifier hotkeys only
    /// activate when the app is ready to record. The listener's CGEventTap events are routed
    /// directly into handleKeyDown/handleKeyUp — identical pipeline to KeyboardShortcuts combos.
    ///
    /// Per D-08: modifier listener runs in parallel with KeyboardShortcuts (not replacing it).
    func setupModifierListener(_ listener: ModifierHotkeyListener) {
        self.modifierListener = listener
        listener.onComboActivated = { [weak self] mode in
            self?.handleKeyDown(mode: mode)
        }
        listener.onComboReleased = { [weak self] mode in
            self?.handleKeyUp(mode: mode)
        }
        listener.start()
    }

    /// Tear down + re-spawn KeyboardShortcuts AsyncStream consumers AND restart the
    /// ModifierHotkeyListener. Cheap escape-hatch for the post-sleep / post-login race
    /// where AX is granted but hotkeys silently failed to bind (D-06).
    func reregisterAll() {
        hotkeyLog.info("reregisterAll invoked — tearing down and re-binding hotkeys")

        plainDictationTask?.cancel()
        cleanupTask?.cancel()
        plainDictationTask = nil
        cleanupTask = nil

        if let listener = modifierListener {
            listener.stop()
            listener.start()
            hotkeyLog.info("ModifierHotkeyListener restarted")
        }

        registrationFailed = false

        plainDictationTask = Task { [weak self] in
            guard let self else { return }
            for await event in KeyboardShortcuts.events(for: .plainDictation) {
                switch event {
                case .keyDown: self.handleKeyDown(mode: .plain)
                case .keyUp:   self.handleKeyUp(mode: .plain)
                }
            }
            // See setup() for why cancellation must not flip registrationFailed.
            if !Task.isCancelled {
                await MainActor.run { self.registrationFailed = true }
            }
        }

        cleanupTask = Task { [weak self] in
            guard let self else { return }
            for await event in KeyboardShortcuts.events(for: .aiCleanup) {
                switch event {
                case .keyDown: self.handleKeyDown(mode: .aiCleanup)
                case .keyUp:   self.handleKeyUp(mode: .aiCleanup)
                }
            }
            if !Task.isCancelled {
                await MainActor.run { self.registrationFailed = true }
            }
        }
    }

    private func bindState() {
        cancellables.removeAll()
        guard let ts = transcriptionService else { return }
        
        let tsPub = ts.$state
        let csPub = cleanupService?.$state.eraseToAnyPublisher() ?? Just(.idle).eraseToAnyPublisher()
        
        Publishers.CombineLatest3($isRecording, tsPub, csPub)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRec, tsState, csState in
                if isRec || tsState == .recording { self?.pipelineState = .recording }
                else if tsState == .transcribing { self?.pipelineState = .transcribing }
                else if csState == .cleaning { self?.pipelineState = .cleaning }
                else { self?.pipelineState = .idle }
            }
            .store(in: &cancellables)
    }

    /// Phase 38 Plan 04 (D-10): the context that WOULD be resolved right now
    /// — same precedence chain `handleKeyDown` uses at real press-time
    /// (disabled -> `contextPin` -> persisted overrides -> curated map ->
    /// default) — computed live from the actual current frontmost app, for
    /// the popover's live-resolution label. Not cached: called fresh every
    /// time the popover renders so it always reflects live state.
    func liveResolvedContext() -> DictationContext {
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let contextAwareEnabled = ContextResolver.isEnabled(DicticusDefaults.suite)
        let overrides = ContextResolver.loadGuarded(from: DicticusDefaults.suite, key: ContextResolver.overridesKey).overrides
        return ContextResolver.resolve(
            bundleID: bundleID,
            pin: contextPin,
            disabled: !contextAwareEnabled,
            overrides: overrides
        )
    }

    /// Handle hotkey key-down event — start recording if conditions met.
    ///
    /// Per D-03: Suppresses key repeat via isKeyDown guard.
    /// Per D-17: Shows notification if models not ready.
    /// Per D-19: Shows notification if already transcribing.
    func handleKeyDown(mode: DictationMode) {
        // D-03: Suppress key repeat
        guard !isKeyDown else { return }
        isKeyDown = true

        // D-17: Model not ready check
        guard let warmupService, warmupService.isReady else {
            let notification = DicticusNotification.modelLoading
            lastPostedNotification = notification
            NotificationService.shared.post(notification)
            isKeyDown = false  // Reset so next press can try again
            return
        }

        // D-20: Check LLM readiness for AI cleanup mode
        if mode == .aiCleanup {
            guard let cleanupService, cleanupService.isLoaded else {
                let notification = DicticusNotification.llmLoading
                lastPostedNotification = notification
                NotificationService.shared.post(notification)
                isKeyDown = false
                return
            }
        }

        guard let service = transcriptionService else {
            isKeyDown = false
            return
        }

        // D-19: Reject while transcribing
        guard service.state == .idle else {
            let notification = DicticusNotification.busy
            lastPostedNotification = notification
            NotificationService.shared.post(notification)
            isKeyDown = false  // Reset so next press can try again
            return
        }

        // Phase 38 Plan 01 (D-02, CTXFMT-01/CTXFMT-02): capture the
        // frontmost app's bundle ID and resolve its DictationContext BEFORE
        // startRecording() — the exact D-02-mandated capture point, mirroring
        // how `mediaController`/`MediaPauseProbe` state is captured at the
        // same call site below. Local-only: bundleID/context are never sent
        // to any network endpoint (consumed only by the local prompt builder
        // + local DEBUG_RECORDER file). Session pin + user override map are
        // wired in Plans 38-03/38-04; here they are nil/empty.
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        // Plan 38-03: route both reads through ContextResolver's shared helpers
        // (single source of truth also read by the Settings row) instead of a
        // locally-duplicated absent-key-default-true check and a hard-coded
        // empty override map — the persisted override map must actually reach
        // press-time resolution or the Settings editor has no runtime effect.
        let contextAwareEnabled = ContextResolver.isEnabled(DicticusDefaults.suite)
        let overrides = ContextResolver.loadGuarded(from: DicticusDefaults.suite, key: ContextResolver.overridesKey).overrides
        let resolvedContext = ContextResolver.resolve(
            bundleID: bundleID,
            pin: contextPin,
            disabled: !contextAwareEnabled,
            overrides: overrides
        )

        do {
            try service.startRecording()
            isRecording = true
            activeRecordingMode = mode
            activeRecordingBundleID = bundleID
            activeRecordingContext = resolvedContext
            // Phase 30 MEDIA-PAUSE-01: pause media after a successful recording start.
            // Gated on the user toggle; treat absent key as true (default ON).
            let pauseEnabled = UserDefaults.standard.object(forKey: "pauseMediaDuringDictation") == nil
                ? true
                : UserDefaults.standard.bool(forKey: "pauseMediaDuringDictation")
            #if DEBUG_RECORDER
            Task {
                await MediaPauseProbe.shared.recordDispatch(dispatched: pauseEnabled, pauseMediaDuringDictation: pauseEnabled)
            }
            #endif
            if pauseEnabled {
                mediaController.pauseMediaIfPlaying()
            }
        } catch {
            let notification = DicticusNotification.recordingFailed(error)
            lastPostedNotification = notification
            NotificationService.shared.post(notification)
            isKeyDown = false
        }
    }

    /// Handle hotkey key-up event — stop recording, transcribe, and inject text.
    ///
    /// Per D-01: Release triggers transcription and paste.
    /// Per D-02: Short presses (<0.3s) silently discarded (TranscriptionError.tooShort).
    /// Per D-16: Silence-only recordings silently discarded.
    func handleKeyUp(mode: DictationMode) {
        guard isKeyDown else { return }

        // Reject release events whose mode does not match the currently-active recording.
        // Defends against spurious modifier-listener releases (debug session ptt-stops-mid-hold)
        // and against cross-talk between the modifier listener and KeyboardShortcuts paths.
        // Placed BEFORE the isKeyDown reset so a real release immediately after isn't lost.
        if let active = activeRecordingMode, active != mode {
            hotkeyLog.info("handleKeyUp rejected — mode mismatch (active=\(String(describing: active), privacy: .public) received=\(String(describing: mode), privacy: .public))")
            return
        }

        isKeyDown = false

        // Phase 30 MEDIA-PAUSE-01: resume any media we paused on press.
        // Ungated on the toggle — if toggle was off at press time, didPauseMedia is false
        // and this is already a no-op. Avoids stranding paused media if user flips toggle mid-hold.
        mediaController.resumeMediaIfPaused()

        guard let service = transcriptionService,
              service.state == .recording else {
            isRecording = false
            activeRecordingMode = nil
            activeRecordingBundleID = nil
            activeRecordingContext = nil
            return
        }

        isRecording = false
        activeRecordingMode = nil

        // Phase 38 Plan 01 (D-02): capture the press-time-resolved context
        // and bundle ID into locals BEFORE clearing session state, so the
        // Task closure below carries the SAME context that was resolved at
        // press — never re-detected at release.
        let dictationContext = activeRecordingContext ?? .default
        let dictationBundleID = activeRecordingBundleID
        activeRecordingBundleID = nil
        activeRecordingContext = nil

        // Task inherits @MainActor isolation from the enclosing @MainActor class,
        // so self.textInjector access is safe without crossing isolation boundaries.
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await service.stopRecordingAndTranscribe()

                // Delegate processing to TextProcessingService (TEXT-03)
                // Flow: Dictionary -> ITN -> [LLM Cleanup]
                let finalOutput = await self.textProcessingService?.process(
                    text: result.text,
                    language: result.language,
                    mode: mode,
                    confidence: Double(result.confidence),
                    context: dictationContext,
                    detectedBundleID: dictationBundleID
                ) ?? result.text

                // D-06: Inject final processed text into the active app
                await self.textInjector.injectText(finalOutput)

                // Phase 44 Plan 14 — honest fallback. The user pressed the AI-cleanup hotkey
                // deliberately; if cleanup was SKIPPED (too long) or TIMED OUT, tell them the text
                // went in without cleanup instead of silently pasting raw text. Only meaningful for
                // .aiCleanup mode (plain dictation never calls cleanup, so the outcome is stale).
                if mode == .aiCleanup {
                    switch CleanupService.lastCleanupOutcome {
                    case .skippedTooLong:
                        NotificationService.shared.post(.cleanupSkippedTooLong)
                    case .timedOut:
                        NotificationService.shared.post(.cleanupTimedOut)
                    case .applied, .notLoaded, .alreadyRunning, .failed:
                        break  // applied = success; the other pre-run states already notify elsewhere (llmLoading/busy)
                    }
                }

            } catch is CancellationError {
                // Task cancelled — silent
            } catch let error as TranscriptionError {
                switch error {
                case .tooShort:
                    break  // D-02: Silent discard
                case .silenceOnly:
                    break  // D-16: No notification for silence
                case .unexpectedLanguage:
                    // Non-Latin script detected — notify user (not silent, user needs to know
                    // why text was not injected)
                    let notification = DicticusNotification.unexpectedLanguage
                    self.lastPostedNotification = notification
                    NotificationService.shared.post(notification)
                default:
                    let notification = DicticusNotification.transcriptionFailed(error)
                    self.lastPostedNotification = notification
                    NotificationService.shared.post(notification)
                }
            } catch {
                let notification = DicticusNotification.transcriptionFailed(error)
                self.lastPostedNotification = notification
                NotificationService.shared.post(notification)
            }
        }
    }
}
