import SwiftUI
import FluidAudio
import Network
import os.log

/// Manages FluidAudio/Parakeet TDT v3 CoreML warm-up state for iOS (Phase 47.1, D-04
/// engine swap — replaces WhisperKit large-v3-turbo), via the shared bounded-retry
/// `AsrModelLoader` (parity with macOS `ModelWarmupService`, WHISP-02).
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
    /// True when this warm-up is the first one to complete successfully for the
    /// current app build + model combination (260815-ait Fix 5). Drives the honest
    /// "First-time setup…" copy on the first post-install/-update ANE recompile
    /// (~60–90s observed), vs. the fast "Loading speech model…" copy every cached
    /// warm-up sees after that. Recomputed at the start of every `warmup()` call
    /// from `isFirstWarmup(storedVersionKey:currentVersionKey:)` — the small pure,
    /// testable predicate this fix is built around.
    @Published private(set) var isFirstWarmupForCurrentVersion: Bool = false
    /// When the current warm-up run began. Drives the `WarmupStatusBanner`'s "loading"
    /// stage elapsed-time readout (`Text(startedAt, style: .timer)`) — the honest
    /// substitute for a determinate bar on a stage whose progress genuinely cannot be
    /// measured (D-07). Set at the same point `isWarming` becomes true; cleared on
    /// every path back to `isWarming == false` (success, cancel, failure) so a stale
    /// timer never survives into the next warm-up attempt.
    @Published private(set) var warmupStartedAt: Date?
    // IOS-ONB-01: Initialize synchronously from the filesystem so the first
    // SwiftUI frame already reflects true model presence. The previous `= false`
    // literal caused a one-frame flash on cold launch when models were present:
    // the property briefly published `false` before `checkHasModels()` ran in
    // `init()`. Using a closure initializer removes that race entirely.
    @Published var hasModels: Bool = IOSModelWarmupService.checkFluidAudioCache()
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

    private var asrManager: AsrManager?

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

    /// Whether the Parakeet TDT v3 model is already cached on disk — FluidAudio's own
    /// `AsrModels.modelsExist(at:)` over its sandboxed Application Support cache
    /// directory (`<App Support>/FluidAudio/Models/parakeet-tdt-0.6b-v3-coreml/`,
    /// identical mechanism on iOS + macOS, no hand-built Documents-dir path logic
    /// needed unlike WhisperKit's HuggingFace cache — 47.1-RESEARCH.md).
    private static func checkFluidAudioCache() -> Bool {
        AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory())
    }

    /// Check if models are already downloaded.
    ///
    /// Re-checks the FluidAudio model cache directory on the filesystem — see
    /// `checkFluidAudioCache()`. Retained for the scenePhase.active foreground re-check
    /// (DicticusApp) and the warmup()/retry() call sites.
    func checkHasModels() {
        hasModels = IOSModelWarmupService.checkFluidAudioCache()
    }

    // MARK: - First-warmup detection (260815-ait Fix 5)

    /// `UserDefaults.standard` key holding the version key (see
    /// `currentWarmupVersionKey`) of the last warm-up that completed successfully.
    private static let lastWarmedUpVersionDefaultsKey = "lastWarmedUpVersionKey"

    /// Identifies "this exact app build + model" for `isFirstWarmup` below.
    /// Combines the app build number — an ANE recompile can be triggered by an
    /// app update even when the model file itself is unchanged — with the model
    /// name, so a future model swap is also honestly flagged as a first warm-up.
    private static var currentWarmupVersionKey: String {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        return "\(build)::\(AsrModelLoader.parakeetModelName)"
    }

    /// Pure, directly-testable predicate: true when no warm-up has completed
    /// successfully for `currentVersionKey` yet (`storedVersionKey` is `nil` or
    /// differs). Deliberately version-keyed rather than a one-time `Bool` — a
    /// future app/model update's first warm-up must be flagged honestly again,
    /// not silently treated as "already warmed" because some earlier build once
    /// completed a warm-up.
    nonisolated static func isFirstWarmup(storedVersionKey: String?, currentVersionKey: String) -> Bool {
        storedVersionKey != currentVersionKey
    }

    /// Start Parakeet TDT v3 initialization in a background Task via the
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
        warmupStartedAt = Date()
        error = nil
        downloadProgress = 0.0
        isFirstWarmupForCurrentVersion = Self.isFirstWarmup(
            storedVersionKey: UserDefaults.standard.string(forKey: Self.lastWarmedUpVersionDefaultsKey),
            currentVersionKey: Self.currentWarmupVersionKey
        )
        // Honest stage text: on a fresh install this is a large one-time download; on every
        // later launch the model is already on disk and this is just an ANE load. The old copy
        // said "Downloading…" in BOTH cases, which is why a restart showed a misleading state.
        // Phase 47.1: size updated to the Parakeet TDT v3 CoreML package's ~1.1 GB
        // (`FluidInference/parakeet-tdt-0.6b-v3-coreml`, 47.1-RESEARCH.md) — the prior
        // "~626 MB" figure was WhisperKit large-v3-turbo's on-disk size.
        //
        // 260815-ait Fix 5: an on-disk model still pays a one-time ANE recompile
        // (~60–90s observed) the first time a given build/model combination warms
        // up — the plain "Loading speech model…" copy looked hung during that
        // window. `isFirstWarmupForCurrentVersion` distinguishes that case.
        downloadStatus = hasModels
            ? (isFirstWarmupForCurrentVersion
                ? "First-time setup \u{2014} preparing the speech model. This can take up to a minute."
                : "Loading speech model\u{2026}")
            : "Downloading speech model\u{2026} (first run, ~1.1 GB)"

        let warmupLog = Logger(subsystem: "com.dicticus", category: "warmup")
        let warmupStart = Date()
        warmupLog.info("warmup starting (force=\(force, privacy: .public), hasModels=\(self.hasModels, privacy: .public))")

        // Phase 44 Plan 14: start sampling before any model is resident, so the
        // baseline is the app's own cost and every later peak is attributable.
        Task {
            await MemoryProbe.shared.startSampling()
            await MemoryProbe.shared.mark("baseline_pre_models")
        }

        // FluidAudio download-progress callback, routed through the shared bounded-retry
        // AsrModelLoader (parity with macOS). `AsrModels.downloadAndLoad`'s
        // `progressHandler` parameter is real (not a no-op like the prior WhisperKit
        // wrapper's), so this hook now drives genuine granular progress reporting.
        let progressHandler: @Sendable (Double) -> Void = { [weak self] fractionCompleted in
            Task { @MainActor in
                guard let self else { return }
                self.downloadProgress = fractionCompleted
                self.downloadStatus = "Downloading speech model\u{2026} (\(Int(fractionCompleted * 100))%)"
            }
        }

        warmupTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                // Step 1: Download + load Parakeet TDT v3 CoreML models via the shared
                // bounded-retry wrapper (parity with macOS ModelWarmupService).
                warmupLog.info("Step 1: AsrModelLoader.loadFluidAudio starting")
                let (am, _) = try await AsrModelLoader.loadFluidAudio(progress: progressHandler)
                let step1Elapsed = Date().timeIntervalSince(warmupStart)
                warmupLog.info("Step 1: AsrModelLoader.loadFluidAudio returned (elapsed=\(step1Elapsed, privacy: .public)s)")

                try Task.checkCancellation()

                await MainActor.run {
                    self?.downloadProgress = 1.0
                    self?.downloadStatus = "Ready"
                    self?.asrManager = am
                    self?.isWarming = false
                    self?.warmupStartedAt = nil
                    self?.isReady = true
                    self?.hasModels = true
                    self?.watchdogTask?.cancel()
                    self?.watchdogTask = nil
                    // 260815-ait Fix 5: record this build/model as warmed-up so the
                    // NEXT warm-up (this launch's re-foreground, or the next cold
                    // launch) sees the fast copy instead of "First-time setup…".
                    UserDefaults.standard.set(
                        IOSModelWarmupService.currentWarmupVersionKey,
                        forKey: IOSModelWarmupService.lastWarmedUpVersionDefaultsKey
                    )
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
                    self?.warmupStartedAt = nil
                    self?.error = "Model load timed out or was cancelled."
                    self?.watchdogTask?.cancel()
                    self?.watchdogTask = nil
                }
            } catch {
                warmupLog.error("warmup failed: \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    self?.isWarming = false
                    self?.warmupStartedAt = nil
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
        warmupStartedAt = nil
    }

    /// Reset error state and retry warmup. Explicit user action — passes
    /// `force: true` so the no-models guard does not block the download path.
    func retry() {
        error = nil
        isReady = false
        warmup(force: true)
    }

    /// Expose the initialized AsrManager instance for IOSTranscriptionService.
    /// Returns nil until warm-up completes.
    var asrManagerInstance: AsrManager? {
        asrManager
    }

}
