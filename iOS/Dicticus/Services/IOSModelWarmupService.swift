import SwiftUI
import WhisperKit
import Network
import os.log

/// Manages WhisperKit large-v3-turbo CoreML warm-up state for iOS, via the shared
/// bounded-retry `AsrModelLoader` (parity with macOS `ModelWarmupService`, WHISP-02).
///
/// iOS v2.0 focuses on plain dictation; AI cleanup (LLM) is excluded to reduce memory pressure
/// and binary footprint on mobile hardware (D- تصمیم taken in STATE.md).
@MainActor
class IOSModelWarmupService: ObservableObject {

    // MARK: - LLM warmup status (D-12)

    /// LLM warmup lifecycle state, observed by Settings UI (Wave 4).
    ///
    /// iOS omits `.downloading` because the GGUF download is driven by
    /// Settings UI (D-09/D-10), not by warmup. If the GGUF is absent when
    /// Step 4 runs, Step 4 simply remains `.idle` and defers to the
    /// user-initiated download flow.
    public enum LlmStatus: Equatable {
        case idle
        case loading
        case ready
        case failed(String)

        public var label: String {
            switch self {
            case .idle:                return "Waiting"
            case .loading:             return "Loading model\u{2026}"
            case .ready:               return "Ready"
            case .failed(let reason):  return reason
            }
        }

        public var isActive: Bool { self == .loading }
    }

    // MARK: - Device eligibility (D-03)

    /// Per D-03: AI cleanup requires ≥5 GB RAM to safely coexist with the
    /// ~2.7 GB Parakeet ASR model. iPhone 12/13 (4 GB A14) are below this
    /// threshold; iPhone 14+ (6 GB) meet it.
    /// `nonisolated` so SettingsView (and any other call site, including
    /// non-main contexts) can read it without actor hops.
    public nonisolated static let requiredPhysicalMemoryBytes: UInt64 = 5 * 1024 * 1024 * 1024

    /// Whether the current device meets the RAM requirement for AI cleanup.
    /// Read at launch by `SettingsView` to decide between showing the AI
    /// Cleanup toggle or a device-unsupported explainer.
    public nonisolated static var isAiCleanupSupported: Bool {
        ProcessInfo.processInfo.physicalMemory >= requiredPhysicalMemoryBytes
    }

    // MARK: - Cellular download warning (D-05, Phase 37 Plan 02)

    /// Pure decision function: should a large download be gated behind an explicit
    /// user confirmation? `true` when the current network path is either `.expensive`
    /// (e.g. cellular, personal hotspot) or `.constrained` (Low Data Mode) — either
    /// flag alone is enough reason to warn before starting a multi-hundred-MB or
    /// multi-GB download. `nonisolated` and side-effect-free so it is unit-testable
    /// without a live `NWPathMonitor` — mirrors the `isAiCleanupSupported` idiom above.
    public nonisolated static func shouldWarnBeforeCellularDownload(isExpensive: Bool, isConstrained: Bool) -> Bool {
        isExpensive || isConstrained
    }

    /// Whether the current network path is expensive or constrained (D-05) — driven by
    /// an `NWPathMonitor` started in `init()`. Consumed by `OnboardingView.downloadStep`
    /// and `AiCleanupSection.downloadPanel` to gate their download buttons behind a
    /// confirmation dialog. Defaults to `false` so a Wi-Fi user sees no extra friction
    /// before the monitor's first path update arrives.
    @Published var isOnCellular: Bool = false

    /// Dedicated monitor for `isOnCellular` — started once in `init()`, never stopped
    /// (the flag must stay live for the app's lifetime so both download entry points
    /// always gate on current network state, not a stale snapshot).
    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "com.dicticus.cellular-path-monitor")

    @Published var isWarming = false
    @Published var isReady = false
    // IOS-ONB-01: Initialize synchronously from the filesystem so the first
    // SwiftUI frame already reflects true model presence. The previous `= false`
    // literal caused a one-frame flash on cold launch when models were present:
    // the property briefly published `false` before `checkHasModels()` ran in
    // `init()`. Using a closure initializer removes that race entirely.
    @Published var hasModels: Bool = IOSModelWarmupService.checkWhisperKitCache()
    @Published var downloadProgress: Double = 0.0
    @Published var downloadStatus: String = ""
    @Published var error: String?

    // MARK: - LLM state (Wave 3, D-12)

    /// Whether the LLM (Qwen2.5-3B-Instruct) is loaded and ready for inference.
    /// Consumed by `DictationViewModel` (Wave 4) to decide whether to route
    /// transcripts through `TextProcessingService` for AI cleanup.
    @Published public private(set) var isLlmReady: Bool = false

    /// Current LLM warmup lifecycle state — observed by Settings UI (Wave 4).
    @Published public private(set) var llmStatus: LlmStatus = .idle

    private var whisperKit: WhisperKit?

    /// llama.cpp-backed cleanup service instance — populated by Step 4 on success.
    /// Exposed via `cleanupServiceInstance` for `DictationViewModel` injection.
    private var cleanupService: CleanupService?

    /// Expose the initialized CleanupService for DictationViewModel (Wave 4).
    /// Returns nil until Step 4 (LLM warmup) completes successfully.
    public var cleanupServiceInstance: CleanupService? {
        cleanupService
    }

    /// File-scoped static token that triggers `CleanupService.initializeBackend()`
    /// exactly once per app lifetime (D-29). Referenced from `init(...)` so the
    /// backend is initialized on first `IOSModelWarmupService` creation without
    /// requiring an app-delegate hook. Swift guarantees once-only evaluation of
    /// static let initializers (thread-safe, lazy).
    private static let backendInitToken: Void = {
        CleanupService.initializeBackend()
    }()

    /// Reference to the in-flight warmup Task for cancellation support.
    private var warmupTask: Task<Void, Never>?

    /// Reference to the timeout watchdog Task.
    private var watchdogTask: Task<Void, Never>?

    /// Maximum time (seconds) to wait for model download/compilation before failing.
    private let warmupTimeoutSeconds: UInt64 = 600

    init() {
        // Fire the once-only static backend init (D-29). `_ =` ensures the
        // compiler doesn't elide the reference; Swift evaluates `backendInitToken`
        // on first touch and caches the result for subsequent instances.
        // IOS-ONB-01: checkHasModels() removed from init — hasModels now
        // self-initializes via the property closure above. checkHasModels()
        // is retained for the scenePhase.active foreground re-check (DicticusApp
        // line 60) and the warmup()/retry() call sites.
        _ = IOSModelWarmupService.backendInitToken

        // D-05 (Phase 37 Plan 02): start the cellular/constrained-path monitor.
        // pathUpdateHandler fires on pathMonitorQueue; hop to MainActor to publish.
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let shouldWarn = IOSModelWarmupService.shouldWarnBeforeCellularDownload(
                isExpensive: path.isExpensive,
                isConstrained: path.isConstrained
            )
            Task { @MainActor in
                self?.isOnCellular = shouldWarn
            }
        }
        pathMonitor.start(queue: pathMonitorQueue)
    }

    /// WhisperKit's on-disk HuggingFace cache directory for the pinned large-v3-turbo
    /// model — same layout WhisperKit uses on macOS (`~/Documents/huggingface/models/
    /// argmaxinc/whisperkit-coreml/<modelName>`), empirically confirmed against the
    /// macOS `TranscriptionService.isWhisperKitAvailable()` cache check (41-05).
    private static func whisperKitCacheDir() -> URL? {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return documentsDir
            .appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml")
            .appendingPathComponent(AsrModelLoader.modelName)
    }

    /// Whether the WhisperKit large-v3-turbo model is already cached on disk.
    private static func checkWhisperKitCache() -> Bool {
        guard let modelDir = whisperKitCacheDir() else { return false }
        return (try? FileManager.default.contentsOfDirectory(atPath: modelDir.path))?.isEmpty == false
    }

    /// Check if models are already downloaded.
    ///
    /// Re-checks the WhisperKit HuggingFace cache directory on the filesystem — see
    /// `checkWhisperKitCache()`. Retained for the scenePhase.active foreground re-check
    /// (DicticusApp) and the warmup()/retry() call sites.
    func checkHasModels() {
        hasModels = IOSModelWarmupService.checkWhisperKitCache()
    }

    /// Start WhisperKit large-v3-turbo initialization in a background Task via the
    /// shared bounded-retry `AsrModelLoader` (parity with macOS `ModelWarmupService`).
    /// Pass `force: true` from explicit user actions (Download / Retry button) so the
    /// download path is not blocked by the no-models guard.
    func warmup(force: Bool = false) {
        // D-D1 (Phase 19.5): Re-check FS on every warmup invocation to avoid
        // relying on stale init-time state after backgrounding / FS mutations.
        // The guard prevents auto-launch sites from silently kicking off a
        // ~2.7 GB download; explicit user actions bypass it via `force`.
        checkHasModels()
        guard hasModels || force else { return }
        guard !isWarming && !isReady else { return }
        isWarming = true
        error = nil
        downloadProgress = 0.0
        // Honest stage text: on a fresh install this is a large one-time download; on every
        // later launch the model is already on disk and this is just an ANE load. The old copy
        // said "Downloading…" in BOTH cases, which is why a restart showed a misleading state.
        // Size reconciled to the measured on-disk figure (626,718,238 bytes ≈ 626 MB) —
        // see 37-02-SUMMARY.md for verification. Matches the model's own filename
        // (openai_whisper-large-v3-v20240930_626MB), SettingsView, and macOS's
        // ModelWarmupService/label copy, all of which already say "~626 MB".
        downloadStatus = hasModels
            ? "Loading speech model\u{2026}"
            : "Downloading speech model\u{2026} (first run, ~626 MB)"

        let warmupLog = Logger(subsystem: "com.dicticus", category: "warmup")
        let warmupStart = Date()
        warmupLog.info("warmup starting (force=\(force, privacy: .public), hasModels=\(self.hasModels, privacy: .public))")

        // Phase 44 Plan 14: start sampling before any model is resident, so the
        // baseline is the app's own cost and every later peak is attributable.
        Task {
            await MemoryProbe.shared.startSampling()
            await MemoryProbe.shared.mark("baseline_pre_models")
        }

        // WhisperKit download-progress callback, routed through the shared bounded-retry
        // AsrModelLoader (parity with macOS). AsrModelLoader.loadWhisperKit's `progress`
        // parameter is a documented no-op today (its single combined WhisperKitConfig call
        // doesn't split download from construction) — wired here so the UI hook exists for
        // whenever granular progress reporting lands, rather than a silent gap.
        let progressHandler: @Sendable (Double) -> Void = { [weak self] fractionCompleted in
            Task { @MainActor in
                guard let self else { return }
                self.downloadProgress = fractionCompleted
                self.downloadStatus = "Downloading speech model\u{2026} (\(Int(fractionCompleted * 100))%)"
            }
        }

        warmupTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                // Step 1: Download + prewarm + load WhisperKit large-v3-turbo CoreML models
                // via the shared bounded-retry wrapper (parity with macOS ModelWarmupService).
                warmupLog.info("Step 1: AsrModelLoader.loadWhisperKit starting")
                let wk = try await AsrModelLoader.loadWhisperKit(progress: progressHandler)
                let step1Elapsed = Date().timeIntervalSince(warmupStart)
                warmupLog.info("Step 1: AsrModelLoader.loadWhisperKit returned (elapsed=\(step1Elapsed, privacy: .public)s)")

                try Task.checkCancellation()

                await MainActor.run {
                    self?.downloadProgress = 1.0
                    self?.downloadStatus = "Ready"
                    self?.whisperKit = wk
                    self?.isWarming = false
                    self?.isReady = true
                    self?.hasModels = true
                    self?.watchdogTask?.cancel()
                    self?.watchdogTask = nil
                }
                warmupLog.info("ASR pipeline ready — UI unblocked")

                // Phase 44 Plan 14: Whisper is resident, the LLM is not. The gap
                // between this and `llm_loaded` is the model swap's real cost.
                await MemoryProbe.shared.mark("asr_ready")

                // Step 4: LLM warmup (D-12). Conditional on AI Cleanup toggle + RAM gate + GGUF cache.
                // Download is triggered by Settings UI (D-09/D-10), NOT by warmup. If the GGUF
                // is not yet cached, Step 4 skips silently and `llmStatus` remains `.idle`.
                //
                // Critical ordering: the MainActor.run above publishes `isReady = true` BEFORE
                // this block starts, so ASR is usable even if Step 4 fails — plain dictation
                // never blocks on LLM availability (graceful degradation, D-26).
                try Task.checkCancellation()

                // Read AppGroup-scoped toggle (matches SettingsView.appGroupBinding suite).
                let appGroupDefaults = UserDefaults(suiteName: "group.com.dicticus") ?? UserDefaults.standard
                let aiCleanupEnabled = appGroupDefaults.bool(forKey: "aiCleanupEnabled")
                let hasEnoughRam = IOSModelWarmupService.isAiCleanupSupported  // D-03
                let isCached = IOSModelDownloadService.isModelCached()

                // Phase 44 Plan 14: record the gate's three inputs to the probe artifact.
                // Step 4 skipping is silent by design, which makes a "stuck preparing" launch
                // indistinguishable from a working one without this line.
                let gateNote = "aiCleanupEnabled=\(aiCleanupEnabled) hasEnoughRam=\(hasEnoughRam) isCached=\(isCached) path=\(IOSModelDownloadService.modelPath().lastPathComponent)"
                await MemoryProbe.shared.mark("llm_gate", note: gateNote)

                guard aiCleanupEnabled, hasEnoughRam, isCached else {
                    warmupLog.info("Step 4 skipped — aiCleanupEnabled=\(aiCleanupEnabled, privacy: .public), hasEnoughRam=\(hasEnoughRam, privacy: .public), isCached=\(isCached, privacy: .public)")
                    return  // Leaves llmStatus = .idle, isLlmReady = false — safe default
                }

                do {
                    await MainActor.run { self?.llmStatus = .loading }
                    warmupLog.info("Step 4: CleanupService.loadModel starting (off-MainActor)")

                    let modelPath = IOSModelDownloadService.modelPath().path
                    // Phase 20.06 hotfix: CleanupService.init and .loadModel are now
                    // nonisolated, so `llama_model_load_from_file` (synchronous ~30s C call)
                    // runs on this detached task instead of blocking MainActor.
                    // Phase 44 Plan 14: 25 s (was 8 s). iOS decodes ~2.5-3x slower than the Mac, and
                    // AI Cleanup is a deliberate toggle+shortcut, not automatic — so the budget is
                    // generous enough for the common range and the rare over-long utterance surfaces
                    // an honest "inserted without cleanup" notice instead of a silent discard.
                    // `-llmTimeoutSeconds <n>` overrides it (the benchmark runs untimed).
                    let timeoutOverride = UserDefaults.standard.double(forKey: "llmTimeoutSeconds")
                    let cleanup = CleanupService(
                        inferenceTimeoutSeconds: timeoutOverride > 0 ? timeoutOverride : 25.0
                    )
                    try cleanup.loadModel(from: modelPath)
                    let step4Elapsed = Date().timeIntervalSince(warmupStart)
                    warmupLog.info("Step 4: CleanupService.loadModel done (elapsed=\(step4Elapsed, privacy: .public)s)")

                    await MainActor.run {
                        self?.cleanupService = cleanup
                        self?.isLlmReady = true
                        self?.llmStatus = .ready
                    }
                    warmupLog.info("Step 4 complete — LLM loaded and ready")

                    // Phase 44 Plan 14: `-llmCleanupBenchmark 1` runs the corpus latency
                    // benchmark against the just-loaded model. Inert without the argument.
                    if CleanupBenchmark.isEnabled {
                        await CleanupBenchmark.run(
                            using: cleanup,
                            model: IOSModelDownloadService.activeModelFileName
                        )
                    }
                    if CleanupBenchmark.isOverflowProbeEnabled {
                        await CleanupBenchmark.runOverflowProbe(
                            using: cleanup,
                            model: IOSModelDownloadService.activeModelFileName
                        )
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    warmupLog.error("Step 4 failed: \(error.localizedDescription, privacy: .public)")
                    await MainActor.run {
                        self?.llmStatus = .failed("AI cleanup unavailable")
                        self?.isLlmReady = false
                    }
                    // Do NOT re-throw — ASR already published readiness; plain dictation still works.
                }
            } catch is CancellationError {
                warmupLog.error("warmup cancelled")
                await MainActor.run {
                    self?.isWarming = false
                    self?.error = "Model load timed out or was cancelled."
                    self?.watchdogTask?.cancel()
                    self?.watchdogTask = nil
                }
            } catch {
                warmupLog.error("warmup failed: \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    self?.isWarming = false
                    self?.error = "Model load failed: \(error.localizedDescription)"
                    self?.watchdogTask?.cancel()
                    self?.watchdogTask = nil
                }
            }
        }

        watchdogTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: (self?.warmupTimeoutSeconds ?? 600) * 1_000_000_000)
            guard let self else { return }
            if self.isWarming {
                self.cancelWarmup()
            }
        }
    }

    /// Cancel an in-flight warmup task.
    func cancelWarmup() {
        warmupTask?.cancel()
        warmupTask = nil
        isWarming = false
    }

    /// Reset error state and retry warmup. Explicit user action — passes
    /// `force: true` so the no-models guard does not block the download path.
    func retry() {
        error = nil
        isReady = false
        warmup(force: true)
    }

    /// Expose the initialized WhisperKit instance for IOSTranscriptionService.
    /// Returns nil until warm-up completes.
    var whisperKitInstance: WhisperKit? {
        whisperKit
    }

}
