import FluidAudio
import Foundation

/// iOS-only FluidAudio/Parakeet Ultra loader half of `AsrModelLoader` (Phase 47.1
/// engine swap to FluidAudio; model moved from Parakeet TDT v3 to Parakeet Ultra in
/// quick task 261017-qlv). Mirrors `AsrModelLoader+WhisperKit.loadWhisperKit`'s exact
/// 3-attempt/linear-backoff retry skeleton — `AsrModels.downloadAndLoad` hits the
/// same HuggingFace download path the retry wrapper was built to survive
/// (`project_asr_download_retry`).
extension AsrModelLoader {
    /// The one model-version constant. It feeds the download, the cache folder and the
    /// existence check, so the check always reads the folder the download wrote.
    /// Ultra is Moondream's post-training of NVIDIA's parakeet-tdt-0.6b-v3 (same
    /// architecture, tokenizer and decoder contract; only the weights differ).
    static let parakeetModelVersion: AsrModelVersion = .ultra

    /// Exact model identifier for the shipped Parakeet Ultra CoreML build, per
    /// FluidAudio's own `ModelNames.ASR.Repo.parakeetUltra` rawValue at v0.17.7
    /// (`FluidInference/parakeet-ultra-coreml`).
    static let parakeetModelName = "FluidInference/parakeet-ultra-coreml"

    /// FluidAudio's sandboxed cache folder for `parakeetModelVersion`
    /// (`<App Support>/FluidAudio/Models/parakeet-ultra/`; the folder name is the repo
    /// name without its `-coreml` suffix). Always derived with an
    /// explicit version: the version-less FluidAudio overload defaults to v3.
    static var parakeetCacheDirectory: URL {
        AsrModels.defaultCacheDirectory(for: parakeetModelVersion)
    }

    /// Whether the Parakeet Ultra model files are already on disk.
    static func parakeetModelsExist() -> Bool {
        AsrModels.modelsExist(at: parakeetCacheDirectory, version: parakeetModelVersion)
    }

    /// Cache folder of the retired Parakeet TDT v3 model, a sibling of the Ultra folder.
    /// Used only to reclaim its space after Ultra loaded.
    static var retiredParakeetV3CacheDirectory: URL {
        AsrModels.defaultCacheDirectory(for: .v3)
    }

    /// Download + load Parakeet Ultra via FluidAudio, with bounded retry to survive
    /// transient HuggingFace "Connection reset by peer" errors during the ~630 MB
    /// model download. Returns a warm `AsrManager` plus a freshly-made `TdtDecoderState`
    /// (the caller owns and recreates the decoder state per-utterance — D-02/Pitfall 5,
    /// never persisted across transcribe calls).
    static func loadFluidAudio(
        maxAttempts: Int = 3,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> (AsrManager, TdtDecoderState) {
        var lastError: Error?
        var progressHandler: ProgressHandler?
        if let progress {
            progressHandler = { (downloadProgress: DownloadProgress) in
                progress(downloadProgress.fractionCompleted)
            }
        }
        for attempt in 1...maxAttempts {
            do {
                let models = try await AsrModels.downloadAndLoad(version: parakeetModelVersion, progressHandler: progressHandler)
                let asrManager = AsrManager(config: .default)
                try await asrManager.loadModels(models)
                let decoderState = TdtDecoderState.make(decoderLayers: await asrManager.decoderLayerCount)
                return (asrManager, decoderState)
            } catch {
                lastError = error
                if attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 2_000_000_000)
                }
            }
        }
        throw lastError!
    }
}
