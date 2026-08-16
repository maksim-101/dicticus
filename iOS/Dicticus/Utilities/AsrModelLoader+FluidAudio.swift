import FluidAudio

/// iOS-only FluidAudio/Parakeet TDT v3 loader half of `AsrModelLoader` (Phase 47.1,
/// D-04 engine swap). Mirrors `AsrModelLoader+WhisperKit.loadWhisperKit`'s exact
/// 3-attempt/linear-backoff retry skeleton — `AsrModels.downloadAndLoad` hits the
/// same HuggingFace download path the retry wrapper was built to survive
/// (`project_asr_download_retry`).
extension AsrModelLoader {
    /// Exact model identifier for the shipped Parakeet TDT v3 CoreML build, per
    /// FluidAudio's own `ModelNames.ASR.Repo.parakeetV3` rawValue
    /// (`FluidInference/parakeet-tdt-0.6b-v3-coreml`, confirmed against the
    /// resolved 0.15.5 package source — 47.1-RESEARCH.md).
    static let parakeetModelName = "FluidInference/parakeet-tdt-0.6b-v3-coreml"

    /// Download + load Parakeet TDT v3 via FluidAudio, with bounded retry to survive
    /// transient HuggingFace "Connection reset by peer" errors during the ~1.1GB
    /// model download. Returns a warm `AsrManager` plus a freshly-made `TdtDecoderState`
    /// (the caller owns and recreates the decoder state per-utterance — D-02/Pitfall 5,
    /// never persisted across transcribe calls).
    static func loadFluidAudio(
        maxAttempts: Int = 3,
        progress: ((Double) -> Void)? = nil
    ) async throws -> (AsrManager, TdtDecoderState) {
        var lastError: Error?
        for attempt in 1...maxAttempts {
            do {
                let models = try await AsrModels.downloadAndLoad(version: .v3, progressHandler: progress)
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
