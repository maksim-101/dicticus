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
    /// The app-wide shared instance (Phase 50 plan 12, CR-01) — `revertToRaw` pastes through
    /// the same one so the pasteboard busy window covers both callers.
    private let textInjector = TextInjector.shared

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

    /// What a `.aiCleanup` key-down should do, given the cleanup LLM's current state.
    ///
    /// Phase 50 D-11 widens the old binary D-20 guard (present-and-loaded, or abort)
    /// into a three-way table: an idle-unloaded model no longer blocks recording — it
    /// starts recording AND kicks a reload, so the reload runs in parallel with the
    /// recording + ASR time that already elapses before cleanup would need the model.
    /// `isLoaded` can be false for two different reasons that must NOT be conflated:
    /// the initial launch load still in flight (abort, as before D-11), or the model
    /// was idle-unloaded (reload and proceed). `isLoaded == true` always wins, even
    /// against a stale `idleUnloaded` flag, since the model being loaded right now is
    /// the ground truth the caller actually needs.
    enum AiCleanupKeyDownAction: Equatable {
        case proceed
        case reloadAndProceed
        case abortLlmLoading
    }

    /// Pure decision table backing `AiCleanupKeyDownAction`. `nonisolated` and static
    /// so it is trivially unit-testable without constructing a `HotkeyManager`.
    nonisolated static func aiCleanupKeyDownAction(cleanupServicePresent: Bool, isLoaded: Bool, idleUnloaded: Bool) -> AiCleanupKeyDownAction {
        guard cleanupServicePresent else { return .abortLlmLoading }
        if isLoaded { return .proceed }
        if idleUnloaded { return .reloadAndProceed }
        return .abortLlmLoading
    }

    /// What `handleKeyUp` should tell the user, given a paste `Outcome` (Phase 50 D-02, WR-03;
    /// D-3 revised by quick 260920-9m8). Both undeliverable outcomes are worth a notification,
    /// each with the wording that is true for its clipboard state: `.fallbackToClipboard` means
    /// the transcript is sitting on the clipboard as a real user copy; `.undeliverableClipboardUntouched`
    /// means the fallback setting is off and the pasteboard was never touched. `.delivered` needs
    /// nothing. `.blocked` is silent for all three of its causes: accessibility already posted its
    /// own notification, a failed clipboard write restored the original silently, and a call
    /// cancelled mid-wait (WR-07) never touched the clipboard at all — a paste-undeliverable
    /// notice for any of these would be a lie. `static` so it is testable without constructing a
    /// `HotkeyManager`; left MainActor-isolated with the enclosing class since `TextInjector.Outcome`
    /// is nested in a `@MainActor` type.
    static func notification(for outcome: TextInjector.Outcome) -> DicticusNotification? {
        switch outcome {
        case .fallbackToClipboard:
            return .pasteUndeliverable
        case .undeliverableClipboardUntouched:
            return .pasteUndeliverableClipboardUntouched
        case .delivered, .blocked:
            return nil
        }
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

        // Phase 50-09 (D-02 gap): this press supersedes any notice left over from the
        // previous one — a fresh .modelLoading/.llmLoading/.busy/.recordingFailed post
        // below sets a new notice for THIS press if applicable.
        NotificationService.shared.unreadNotice = nil

        // D-17: Model not ready check
        guard let warmupService, warmupService.isReady else {
            let notification = DicticusNotification.modelLoading
            lastPostedNotification = notification
            NotificationService.shared.post(notification)
            isKeyDown = false  // Reset so next press can try again
            return
        }

        // D-20 widened by Phase 50 D-11: an idle-unloaded LLM no longer aborts —
        // it starts recording and kicks a reload in parallel. See
        // aiCleanupKeyDownAction's doc comment for the full three-way table.
        if mode == .aiCleanup {
            let action = Self.aiCleanupKeyDownAction(
                cleanupServicePresent: cleanupService != nil,
                isLoaded: cleanupService?.isLoaded ?? false,
                idleUnloaded: warmupService.isCleanupUnloaded
            )
            switch action {
            case .abortLlmLoading:
                let notification = DicticusNotification.llmLoading
                lastPostedNotification = notification
                NotificationService.shared.post(notification)
                isKeyDown = false
                return
            case .reloadAndProceed:
                warmupService.reloadCleanupServiceIfNeeded()
            case .proceed:
                break
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
            // quick-260825-q2i: kick off a background LLM warm-up the moment an
            // AI-cleanup recording starts, so the cold-inference cost lands during
            // the user's speaking time instead of after they release the hotkey.
            // Fire-and-forget: warmUp() itself returns immediately and re-checks
            // isLoaded, so no extra readiness guard is needed here. Never fires for
            // .plain — the LLM must not be touched on that path.
            if mode == .aiCleanup {
                cleanupService?.warmUp()
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
    /// Per D-16: Silence-only recordings silently discarded (includes .noResult — see
    /// TranscriptionFailureRouter, quick task 260831-nt6).
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

        // Phase 50 D-02: captured at RELEASE (not press) so a deliberate app switch during the
        // hold is honoured, while a switch during the ASR/LLM wait (the window that actually
        // matters for delivery) is caught. Consumed by TextInjector's delivery pre-check below.
        let releaseFrontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        // Task inherits @MainActor isolation from the enclosing @MainActor class,
        // so self.textInjector access is safe without crossing isolation boundaries.
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await service.stopRecordingAndTranscribe()

                // Phase 50 D-11: if the key-down reload is still running, wait for it
                // HERE — before TextProcessingService.process's isLoaded gate
                // (TextProcessingService.swift:266) — so a real cleanup never falls
                // through to the rules-only path just because the model reload hadn't
                // finished yet. `.llmLoading` is shown only when there's actually
                // something to wait for; a failed reload surfaces the existing
                // `.cleanupFailed` (raw text still pastes — D-19's fallback contract).
                if mode == .aiCleanup, let warmupService = self.warmupService {
                    if warmupService.isCleanupReloadInFlight {
                        let n = DicticusNotification.llmLoading
                        self.lastPostedNotification = n
                        NotificationService.shared.post(n)
                    }
                    if case .failed = await warmupService.awaitCleanupReload() {
                        let n = DicticusNotification.cleanupFailed
                        self.lastPostedNotification = n
                        NotificationService.shared.post(n)
                    }
                }

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

                // Phase 50 D-02: Inject final processed text into the active app; consume the
                // outcome instead of discarding it (was: Bool result thrown away, HotkeyManager:438).
                let outcome = await self.textInjector.injectText(finalOutput, expectedFrontmostBundleID: releaseFrontmostBundleID)
                if let notification = Self.notification(for: outcome) {
                    self.lastPostedNotification = notification
                    NotificationService.shared.post(notification)
                }

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
                // D-02/D-16 + quick task 260831-nt6: silent vs. notify-worthy is decided by
                // TranscriptionFailureRouter, not inline here — see its doc comment for why
                // .noResult joins .tooShort/.silenceOnly as silent.
                switch TranscriptionFailureRouter.route(error) {
                case .silent:
                    break
                case .notifyUnexpectedLanguage:
                    // Non-Latin script detected — notify user (not silent, user needs to know
                    // why text was not injected)
                    let notification = DicticusNotification.unexpectedLanguage
                    self.lastPostedNotification = notification
                    NotificationService.shared.post(notification)
                case .notifyTranscriptionFailed:
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
