import SwiftUI
import WhisperKit
import os.log

/// Manages WhisperKit large-v3-turbo warm-up state (download + prewarm + load via the
/// shared bounded-retry AsrModelLoader), plus sequential LLM (Qwen2.5-3B-Instruct via
/// llama.cpp) initialization for AI cleanup.
///
/// Called once at app launch to trigger background CoreML model compilation and download.
/// First-launch download is ~626 MB (WhisperKit large-v3-turbo CoreML package). After a
/// successful load, the stale Parakeet cache (~2.69 GB) is purged (WHISP-02 / D-06).
/// CoreML encoder compilation takes ~3.4 s on first run; subsequent launches use cached
/// compilation and are fast (~162 ms warm load).
///
/// D-07/D-08: LLM warmup runs sequentially after ASR to avoid memory pressure spikes.
/// D-09: Qwen2.5-3B-Instruct GGUF (~1.93 GB) downloaded from HuggingFace on first run (CLEANRD-01).
/// Threat T-04-08: Sequential loading + existing 600-second watchdog covers combined warmup.
/// Threat T-02.1-03: Compilation runs on Task.detached(priority: .utility) to avoid
/// blocking the main thread. [weak self] prevents retain cycles on app quit.
/// Threat T-02.1-02: Audio samples are never persisted; only held in memory during
/// a single recording session.
/// LLM loading status — observable by the menu bar dropdown for progress indication.
enum LlmStatus: Equatable {
    case idle
    case downloading
    case loading
    case ready
    case failed(String)

    var label: String {
        switch self {
        case .idle:                return "Waiting"
        case .downloading:         return "Downloading model\u{2026}"
        case .loading:             return "Loading model\u{2026}"
        case .ready:               return "Ready"
        case .failed(let reason):  return reason
        }
    }

    var isActive: Bool {
        self == .downloading || self == .loading
    }
}

extension ModelWarmupService {
    /// D-08: shown when a GGUF fails verification a second time — `acquireVerifiedModel`
    /// has already deleted the bad file, so a relaunch downloads afresh. AI cleanup
    /// stays disabled for the rest of this session (`isLlmReady` false, `cleanupService`
    /// nil) rather than looping retries indefinitely against a possibly-corrupted URL.
    static let verificationFailedStatus = "Model failed verification \u{2014} Retry download."

    // MARK: - Phase 50 D-10/D-11: idle unload of the cleanup LLM

    /// `UserDefaults` key backing the Settings knob (`AiCleanupPane.IdleUnloadFormRow`).
    /// Stores an `Int` number of minutes; `0` means "Never".
    /// `nonisolated`: read from `idleUnloadThreshold(from:)`, which runs off-MainActor
    /// (called from the idle-unload `Task` loop).
    nonisolated static let idleUnloadDefaultsKey = "llmIdleUnloadMinutes"

    /// Default idle period before the cleanup LLM is unloaded, in minutes — used both
    /// as the Settings row's default selection and as the fallback when the key is
    /// absent or holds a value outside the picker's range.
    nonisolated static let idleUnloadDefaultMinutes = 10

    /// The picker's fixed options, in minutes (excluding "Never", which is `0` and
    /// rendered separately in `IdleUnloadFormRow`).
    nonisolated static let idleUnloadOptionsMinutes = [5, 10, 30]

    /// How often the idle-unload loop wakes to check whether the threshold has been
    /// crossed. An unload therefore lands within `[threshold, threshold + 60s)` of the
    /// last activity, never exactly at the threshold instant.
    nonisolated static let idleCheckIntervalSeconds: UInt64 = 60

    /// Read the configured idle-unload threshold, in seconds, from `defaults`.
    ///
    /// - Absent key, or a negative (garbage) value: falls back to
    ///   `idleUnloadDefaultMinutes`.
    /// - `0`: "Never" — returns `nil`, which `shouldUnload` always treats as false.
    /// - Any other positive value: minutes × 60.
    nonisolated static func idleUnloadThreshold(from defaults: UserDefaults) -> TimeInterval? {
        guard let stored = defaults.object(forKey: idleUnloadDefaultsKey) as? Int, stored >= 0 else {
            return TimeInterval(idleUnloadDefaultMinutes * 60)
        }
        guard stored > 0 else { return nil }
        return TimeInterval(stored * 60)
    }

    /// Pure predicate mirroring `CleanupService.shouldWarmUp`'s shape: should the idle
    /// tick unload the model given when it was last used?
    ///
    /// `nil` threshold ("Never") always returns false, independent of elapsed time.
    /// Otherwise, inclusive at the boundary (`>=`) — elapsed time exactly equal to the
    /// threshold counts as idle, matching `shouldWarmUp`'s documented convention.
    nonisolated static func shouldUnload(lastActivityAt: Date, now: Date, idleThreshold: TimeInterval?) -> Bool {
        guard let idleThreshold else { return false }
        return now.timeIntervalSince(lastActivityAt) >= idleThreshold
    }
}

@MainActor
class ModelWarmupService: ObservableObject {
    @Published var isWarming = false
    @Published var isReady = false
    @Published var error: String?

    private var whisperKit: WhisperKit?
    @Published var isLlmReady = false
    @Published var llmStatus: LlmStatus = .idle
    private var cleanupService: CleanupService?

    // MARK: - Phase 50 D-10/D-11: idle unload / reload lifecycle

    /// Whether the cleanup LLM was unloaded by the idle-check tick. `isLlmReady` and
    /// `llmStatus` are NOT touched by this — AI cleanup remains "Ready" per D-12; only
    /// this flag (and the key-down table) knows the model needs a reload before use.
    @Published private(set) var isCleanupUnloaded = false

    /// Whether a reload is currently in flight — used by the key-up path to decide
    /// whether to surface `.llmLoading` while it waits.
    var isCleanupReloadInFlight: Bool { reloadTask != nil }

    /// When the model was last (re)loaded — the idle clock's fallback when the service
    /// has never actually run an inference (`cleanupService.lastInferenceAt == nil`),
    /// per the RELY-03 "empty" edge case: a loaded-but-never-used model still holds its
    /// ~2.7 GB, so the clock must start somewhere other than "never".
    private var llmLoadedAt: Date?

    /// The idle-check loop — a `Task.sleep` loop mirroring `watchdogTask`'s idiom
    /// (no `Timer`, no `DispatchSourceTimer`), started once the LLM first finishes
    /// loading and left running for the app's lifetime.
    private var idleUnloadTask: Task<Void, Never>?

    /// The in-flight reload triggered by `reloadCleanupServiceIfNeeded()`. Non-nil for
    /// the duration of one reload; `awaitCleanupReload()` awaits its `.value`.
    private var reloadTask: Task<Bool, Never>?

    /// How many key-up callers are currently awaiting `reloadTask`, purely for the
    /// `cleanupWaited` field on the `LlmLifecycleProbe.recordReload` call.
    private var reloadWaiterCount = 0

    /// Outcome of `awaitCleanupReload()`.
    enum CleanupReloadWait: Equatable {
        /// No reload was in flight — either the model was already loaded, or a prior
        /// reload attempt failed and none is currently running (retried on the next
        /// key-down).
        case notNeeded
        /// The reload finished successfully; `waitedMs` is how long this caller waited.
        case loaded(waitedMs: Double)
        /// The reload failed (or none is in flight AND the model is still marked
        /// unloaded) — the caller should treat this like `.notLoaded`.
        case failed
    }

    /// Reference to the in-flight warmup Task for cancellation support.
    private var warmupTask: Task<Void, Never>?

    /// Reference to the timeout watchdog Task — cancelled when warmup succeeds
    /// to avoid a 600-second sleeping Task lingering after fast warm loads (~162 ms).
    private var watchdogTask: Task<Void, Never>?

    /// Maximum time (seconds) to wait for model download/compilation before failing.
    /// 10-minute ceiling covers first-launch ~626 MB WhisperKit CoreML download on slower
    /// hardware and initial CoreML compilation.
    private let warmupTimeoutSeconds: UInt64 = 600

    /// Whether the warm-up row should be visible in the dropdown.
    /// True while loading (isWarming) or when loading failed (error != nil).
    /// False when ready — row disappears entirely per UI-SPEC.
    var showWarmupRow: Bool {
        isWarming || error != nil
    }

    /// Status text for the dropdown warm-up row.
    /// Returns nil when ready (row is hidden). Returns error string on failure.
    var statusText: String? {
        if isWarming {
            return "Preparing models\u{2026}"  // "Preparing models…" — ellipsis character (UI-SPEC copywriting)
        } else if let error = error {
            return error
        }
        return nil
    }

    /// Start WhisperKit large-v3-turbo initialization in a background Task.
    ///
    /// Per D-08: called immediately at app launch, not on first hotkey press.
    /// Downloads + prewarms + loads WhisperKit large-v3-turbo CoreML models from
    /// HuggingFace on first launch via the shared bounded-retry AsrModelLoader.
    /// Subsequent launches use cached CoreML compilation and are fast.
    ///
    /// Guard prevents duplicate calls — safe to call multiple times.
    func warmup() {
        guard !isWarming && !isReady else { return }
        isWarming = true
        error = nil

        warmupTask = Task.detached(priority: .utility) { [weak self] in
            do {
                // Step 1: Download + prewarm + load WhisperKit large-v3-turbo CoreML
                // models from HuggingFace via the shared bounded-retry wrapper. First run
                // downloads ~626 MB; subsequent runs use cached CoreML package.
                let wk = try await AsrModelLoader.loadWhisperKit()

                try Task.checkCancellation()

                // ASR is ready — publish immediately so plain dictation works
                // even if LLM loading fails or takes a long time.
                await MainActor.run {
                    self?.whisperKit = wk
                    self?.isWarming = false
                    self?.isReady = true
                    self?.watchdogTask?.cancel()
                    self?.watchdogTask = nil
                }

                // WHISP-02 / D-06: purge the stale Parakeet cache only AFTER a successful
                // WhisperKit load — never before, so a failed download leaves no data-loss
                // window (the old Parakeet models stay usable until Whisper is confirmed).
                let warmupLog = Logger(subsystem: "com.dicticus", category: "warmup")
                if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                    let parakeetCache = appSupport.appendingPathComponent("FluidAudio/Models")
                    if FileManager.default.fileExists(atPath: parakeetCache.path) {
                        do {
                            try FileManager.default.removeItem(at: parakeetCache)
                            warmupLog.info("Purged stale Parakeet cache at \(parakeetCache.path)")
                        } catch {
                            warmupLog.error("Failed to purge Parakeet cache: \(error.localizedDescription)")
                        }
                    }
                }

                // Step 4: Download + initialize LLM for AI cleanup (D-07, D-08).
                // Sequential after ASR to avoid memory pressure spikes (D-08).
                // Downloads ~1.93 GB Qwen2.5-3B GGUF on first run from HuggingFace CDN (D-09, CLEANRD-01).
                // Non-fatal: if LLM fails, plain dictation still works.
                do {
                    let cached = ModelDownloadService.isModelCached()
                    let fileExists = FileManager.default.fileExists(atPath: ModelDownloadService.modelPath().path)
                    warmupLog.info("LLM Step 4: cached=\(cached) fileExists=\(fileExists)")
                    if !fileExists {
                        // No file at all — a genuine download.
                        await MainActor.run { self?.llmStatus = .downloading }
                    } else if !cached {
                        // A file exists but isn't yet cheaply verified — the
                        // first-launch-after-upgrade hash (10-30s for 2.74 GB) is
                        // running, not a download. Distinguishing this from
                        // .downloading avoids a misleading "Downloading model…"
                        // label while D-08's verify-then-stamp does its one-time work.
                        await MainActor.run { self?.llmStatus = .loading }
                    }

                    try await ModelDownloadService.downloadIfNeeded()
                    warmupLog.info("LLM download complete, loading model...")

                    await MainActor.run { self?.llmStatus = .loading }

                    let modelPath = ModelDownloadService.modelPath().path
                    warmupLog.info("LLM model path: \(modelPath)")
                    // Phase 20.06 hotfix: CleanupService.init and .loadModel are now
                    // nonisolated, so `llama_model_load_from_file` (synchronous ~30s C
                    // call) runs on this detached task instead of blocking MainActor.
                    CleanupService.initializeBackend()
                    // Preserve pre-extraction macOS timeout (5 s) — the shared
                    // init default is 8 s, tuned for iOS (D-04).
                    // `-llmTimeoutSeconds <n>` overrides the 5 s default so the benchmark can run
                    // UNTIMED — a truncated inference cannot tell you what the work actually needs.
                    // Phase 44 Plan 14: 20 s (was 5 s). AI Cleanup is a deliberate Ctrl+Shift+D,
                    // not automatic, so a longer budget is acceptable; the old 5 s silently discarded
                    // Qwen3.5's completed work on long utterances. The output-budget guard caps how
                    // long an inference can run, and anything past that surfaces an honest "inserted
                    // without cleanup" notice rather than a silent fallback.
                    let timeoutOverride = UserDefaults.standard.double(forKey: "llmTimeoutSeconds")
                    let cleanup = CleanupService(
                        inferenceTimeoutSeconds: timeoutOverride > 0 ? timeoutOverride : 20.0
                    )
                    try cleanup.loadModel(from: modelPath)

                    warmupLog.info("LLM model loaded successfully")
                    await MainActor.run {
                        self?.cleanupService = cleanup
                        self?.isLlmReady = true
                        self?.llmStatus = .ready
                        // Phase 50 D-10: the idle clock starts now; the loop itself
                        // starts once, here, and runs for the app's lifetime.
                        self?.llmLoadedAt = Date()
                        self?.startIdleUnloadLoop()
                    }

                    // Phase 44 Plan 14: same benchmark as iOS, same 8 real corpus utterances, so
                    // the two platforms' latency numbers are directly comparable.
                    if CleanupBenchmark.isEnabled {
                        await CleanupBenchmark.run(
                            using: cleanup,
                            model: ModelDownloadService.activeModelFileName
                        )
                    }
                } catch is CancellationError {
                    warmupLog.error("LLM warmup cancelled")
                    throw CancellationError()
                } catch let error as ModelIntegrityError {
                    // D-08: acquireVerifiedModel already deleted the bad file (and its
                    // stamp) after the second mismatch — nothing to clean up here.
                    // AI cleanup stays disabled for this session; a relaunch re-runs
                    // Step 4 and downloads afresh.
                    warmupLog.error("LLM model failed verification: \(error.localizedDescription)")
                    await MainActor.run {
                        self?.llmStatus = .failed(Self.verificationFailedStatus)
                    }
                } catch {
                    warmupLog.error("LLM warmup failed: \(error.localizedDescription)")
                    await MainActor.run {
                        self?.llmStatus = .failed("AI cleanup unavailable")
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    self?.isWarming = false
                    self?.error = "Model load timed out or was cancelled. Restart app."
                    self?.watchdogTask?.cancel()
                    self?.watchdogTask = nil
                }
            } catch {
                await MainActor.run {
                    self?.isWarming = false
                    self?.error = "Model load failed. Restart app."
                    self?.watchdogTask?.cancel()
                    self?.watchdogTask = nil
                }
            }
        }

        // Timeout watchdog — cancels warmupTask if download/compilation hangs (e.g. network
        // failure during first-launch HuggingFace download). Runs separately to avoid Swift 6
        // Sendable issues with actor-isolated types in task groups.
        // Stored in watchdogTask so it can be cancelled when warmup succeeds (avoids a
        // 600-second sleeping Task lingering after fast warm loads).
        watchdogTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: (self?.warmupTimeoutSeconds ?? 600) * 1_000_000_000)
            guard let self else { return }
            if self.isWarming {
                self.cancelWarmup()
            }
        }
    }

    /// Cancel an in-flight warmup task.
    /// Immediately resets isWarming to false for responsive UI feedback.
    /// The guard in warmup() then passes again (isWarming == false, isReady == false),
    /// so calling warmup() again will retry. The task's CancellationError handler
    /// becomes a no-op since isWarming is already false.
    func cancelWarmup() {
        warmupTask?.cancel()
        warmupTask = nil
        isWarming = false
    }

    // MARK: - Phase 50 D-10/D-11: idle unload / reload lifecycle

    /// Start the idle-check loop. Called once, when the cleanup LLM first finishes
    /// loading (Step 4 of `warmup()`), and runs for the app's lifetime — mirrors
    /// `watchdogTask`'s `Task { try? await Task.sleep(...) }` idiom (no `Timer`, no
    /// `DispatchSourceTimer`, per RESEARCH "Don't Hand-Roll").
    func startIdleUnloadLoop() {
        idleUnloadTask?.cancel()
        idleUnloadTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.idleCheckIntervalSeconds * 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                self.idleUnloadTick(now: Date())
            }
        }
    }

    /// One tick of the idle-check loop. Reads the configured threshold and the
    /// service's actual last-activity timestamp, and unloads when `shouldUnload` says
    /// the model has been idle long enough.
    ///
    /// A tick that finds a reload already in flight, or finds the model already
    /// unloaded (or not loaded at all), is a no-op — `cleanupService.unload()`'s own
    /// `isInferring`/`warmUpTask` guard additionally covers "a real cleanup or
    /// warm-up is running right now": that call returns `false` and this tick simply
    /// does nothing, retrying a full threshold later on the next tick (D-10's
    /// "adjacency" edge case — the completing inference bumps `lastInferenceAt`, so
    /// the next eligible unload is a full threshold after that, not an immediate
    /// retry).
    func idleUnloadTick(now: Date) {
        guard let cleanupService, cleanupService.isLoaded, reloadTask == nil else { return }
        let threshold = Self.idleUnloadThreshold(from: DicticusDefaults.suite)
        // D-10 "empty" edge case: a loaded-but-never-inferred model still holds its
        // ~2.7 GB, so the clock falls back to the load time, not "never idle".
        let lastActivity = cleanupService.lastInferenceAt ?? llmLoadedAt ?? now
        guard Self.shouldUnload(lastActivityAt: lastActivity, now: now, idleThreshold: threshold) else { return }

        if cleanupService.unload() {
            isCleanupUnloaded = true
            #if DEBUG_RECORDER
            Task {
                await LlmLifecycleProbe.shared.recordUnload(
                    idleSeconds: now.timeIntervalSince(lastActivity),
                    thresholdSeconds: threshold ?? -1
                )
            }
            #endif
        }
        // unload() returning false means an inference or warm-up is in flight right
        // now (D-10's mid-cleanup guard) — this tick simply skips.
    }

    /// Reload the (idle-unloaded) cleanup LLM on the SAME `CleanupService` instance —
    /// never a new one (D-09's strong-ref finding: `TextProcessingService`,
    /// `HotkeyManager`, and this class all hold the same instance).
    ///
    /// Triggered from `HotkeyManager.handleKeyDown` when `aiCleanupKeyDownAction`
    /// returns `.reloadAndProceed` (D-11). Runs `downloadIfNeeded()` first — the
    /// cheap stamp check (D-08) — before `loadModel`, so a reload re-verifies the
    /// file exactly like a fresh launch would. `unload()` has already nil'd the
    /// pointers, so `loadModel`'s DEBUG assert cannot fire here.
    ///
    /// No-op if no reload is needed (`isCleanupUnloaded == false`), one is already
    /// running, or there is no `cleanupService` to reload.
    func reloadCleanupServiceIfNeeded() {
        guard isCleanupUnloaded, reloadTask == nil, let cleanupService else { return }
        let start = Date()
        reloadTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try await ModelDownloadService.downloadIfNeeded()
                try cleanupService.loadModel(from: ModelDownloadService.modelPath().path)
                let loadMs = Date().timeIntervalSince(start) * 1000
                let waited = await MainActor.run { () -> Bool in
                    guard let self else { return false }
                    self.isCleanupUnloaded = false
                    self.llmLoadedAt = Date()
                    let w = self.reloadWaiterCount > 0
                    self.reloadWaiterCount = 0
                    self.reloadTask = nil
                    return w
                }
                #if DEBUG_RECORDER
                await LlmLifecycleProbe.shared.recordReload(loadMs: loadMs, cleanupWaited: waited, success: true)
                #endif
                return true
            } catch {
                // isCleanupUnloaded stays true — the next key-down retries. A
                // ModelIntegrityError here means the stamp no longer matches and
                // re-verification failed twice — the same session-disable as at
                // launch (Step 4's catch arm).
                await MainActor.run {
                    self?.llmStatus = .failed("AI cleanup unavailable")
                    self?.reloadWaiterCount = 0
                    self?.reloadTask = nil
                }
                #if DEBUG_RECORDER
                await LlmLifecycleProbe.shared.recordReload(
                    loadMs: Date().timeIntervalSince(start) * 1000,
                    cleanupWaited: false,
                    success: false
                )
                #endif
                return false
            }
        }
    }

    /// Await an in-flight reload (D-11: the key-up path calls this between
    /// `stopRecordingAndTranscribe()` and `TextProcessingService.process`, so
    /// `isLoaded` is true by the time `process` checks it).
    ///
    /// Returns `.notNeeded` when no reload is in flight and the model is not marked
    /// unloaded (the common case — nothing to wait for). Returns `.failed` when no
    /// reload is in flight but the model IS still marked unloaded (a prior reload
    /// attempt failed and none is currently retrying).
    func awaitCleanupReload() async -> CleanupReloadWait {
        guard let reloadTask else { return isCleanupUnloaded ? .failed : .notNeeded }
        reloadWaiterCount += 1
        let start = Date()
        let ok = await reloadTask.value
        return ok ? .loaded(waitedMs: Date().timeIntervalSince(start) * 1000) : .failed
    }

    /// Expose the initialized WhisperKit instance for TranscriptionService.
    /// Returns nil until warm-up completes. TranscriptionService consumes this instance
    /// directly to avoid redundant initialization.
    var whisperKitInstance: WhisperKit? {
        whisperKit
    }

    /// Expose the initialized CleanupService for DicticusApp wiring.
    /// Returns nil until LLM warm-up completes (Step 4 of warmup sequence).
    /// Now @Published — DicticusApp observes changes directly.
    var cleanupServiceInstance: CleanupService? {
        cleanupService
    }
}
