import WhisperKit

enum AsrModelLoader {
    /// Exact model identifier for the shipped Whisper large-v3-turbo CoreML build (~626 MB,
    /// the distilled OpenAI turbo decoder, date-stamped). NEVER swap for `_turbo_632MB` /
    /// `_turbo_954MB` — those are a different, larger, streaming-optimized variant of plain
    /// large-v3, not the same model (41-RESEARCH.md Pitfall 4).
    static let modelName = "openai_whisper-large-v3-v20240930_626MB"

    /// `WhisperKit(config)` with bounded retry. WhisperKit's init runs download + prewarm +
    /// load in a single async call, but the download step can still throw on a transient
    /// HuggingFace "Connection reset by peer" mid-transfer — the exact failure mode this
    /// wrapper existed to survive when it wrapped the prior ASR SDK's Parakeet download. Keep
    /// the retry even though `WhisperKit(config)` looks like a one-liner (41-RESEARCH.md Pitfall 5).
    ///
    /// `progress` is reserved for iOS warmup UI (wired in 41-06) so both platforms route
    /// model provisioning through this one shared wrapper instead of iOS calling the SDK
    /// directly (closing the pre-existing macOS/iOS divergence — 41-PATTERNS.md). It is a
    /// no-op today because this wrapper uses the single combined `WhisperKit(config)` call
    /// (download+prewarm+load together) rather than splitting `WhisperKit.download(...)` out
    /// for granular progress reporting.
    static func loadWhisperKit(
        maxAttempts: Int = 3,
        progress: ((Double) -> Void)? = nil
    ) async throws -> WhisperKit {
        var lastError: Error?
        for attempt in 1...maxAttempts {
            do {
                let config = WhisperKitConfig(
                    model: modelName,
                    prewarm: true,
                    load: true,
                    download: true
                )
                return try await WhisperKit(config)
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
