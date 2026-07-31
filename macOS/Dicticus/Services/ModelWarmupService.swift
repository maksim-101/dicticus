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

@MainActor
class ModelWarmupService: ObservableObject {
    @Published var isWarming = false
    @Published var isReady = false
    @Published var error: String?

    private var whisperKit: WhisperKit?
    @Published var isLlmReady = false
    @Published var llmStatus: LlmStatus = .idle
    private var cleanupService: CleanupService?

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
                    let needsDownload = !ModelDownloadService.isModelCached()
                    warmupLog.info("LLM Step 4: cached=\(!needsDownload)")
                    if needsDownload {
                        await MainActor.run { self?.llmStatus = .downloading }
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
