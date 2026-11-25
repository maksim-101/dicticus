import Foundation
import WhisperKit

/// macOS-only WhisperKit half of `AsrModelLoader` (Phase 47.1, D-04 engine swap).
/// Relocated VERBATIM out of `Shared/Utilities/AsrModelLoader.swift` — macOS keeps
/// WhisperKit unchanged; only the iOS engine changes in this phase.
extension AsrModelLoader {
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
                    downloadBase: whisperDownloadBase(),
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

    /// Root of WhisperKit's model and tokenizer cache. HubApi's own default base is the
    /// user's Documents folder; under any base the layout is `models/<org>/<repo>`, so this
    /// keeps the familiar HuggingFace layout inside Dicticus's Application Support folder.
    static func whisperDownloadBase() -> URL {
        ModelDownloadService.modelPath()
            .deletingLastPathComponent()
            .appendingPathComponent("huggingface", isDirectory: true)
    }

    static let whisperRepoSubpath = "models/argmaxinc/whisperkit-coreml"
    static let whisperTokenizerSubpath = "models/openai/whisper-large-v3"

    static let legacyWhisperMigrationKey = "whisperModelsMigratedFromDocumentsV1"

    enum LegacyWhisperMigration: Equatable {
        case alreadyRan
        case noPriorInstall
        case destinationExists
        case nothingToMove
        case moved
        case failed(String)
    }

    /// One-shot move of the already-downloaded model from `~/Documents/huggingface` into
    /// `whisperDownloadBase()`. Never deletes anything. A fresh install (no
    /// `hasCompletedOnboarding`) never touches the Documents folder; the first Documents
    /// access is the `legacyVariant` existence check below.
    @discardableResult
    static func migrateLegacyWhisperModelIfNeeded(
        defaults: UserDefaults = DicticusDefaults.suite,
        legacyBase: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("huggingface", isDirectory: true),
        newBase: URL = whisperDownloadBase(),
        fileManager: FileManager = .default
    ) -> LegacyWhisperMigration {
        if defaults.bool(forKey: legacyWhisperMigrationKey) { return .alreadyRan }
        defer { defaults.set(true, forKey: legacyWhisperMigrationKey) }

        if !defaults.bool(forKey: PermissionManager.onboardingKey) { return .noPriorInstall }

        let destRepo = newBase.appendingPathComponent(whisperRepoSubpath, isDirectory: true)
        let destVariant = destRepo.appendingPathComponent(modelName, isDirectory: true)
        if fileManager.fileExists(atPath: destVariant.path) { return .destinationExists }

        let legacyRepo = legacyBase.appendingPathComponent(whisperRepoSubpath, isDirectory: true)
        let legacyVariant = legacyRepo.appendingPathComponent(modelName, isDirectory: true)
        if !fileManager.fileExists(atPath: legacyVariant.path) { return .nothingToMove }

        do {
            try fileManager.createDirectory(at: destRepo, withIntermediateDirectories: true)
            try fileManager.moveItem(at: legacyVariant, to: destVariant)

            let sidecarSubpath = ".cache/huggingface/download/\(modelName)"
            let legacyMeta = legacyRepo.appendingPathComponent(sidecarSubpath, isDirectory: true)
            let destMeta = destRepo.appendingPathComponent(sidecarSubpath, isDirectory: true)
            if fileManager.fileExists(atPath: legacyMeta.path), !fileManager.fileExists(atPath: destMeta.path) {
                try fileManager.createDirectory(
                    at: destMeta.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.moveItem(at: legacyMeta, to: destMeta)
            }

            let destTokenizer = newBase.appendingPathComponent(whisperTokenizerSubpath, isDirectory: true)
            let legacyTokenizer = legacyBase.appendingPathComponent(whisperTokenizerSubpath, isDirectory: true)
            if !fileManager.fileExists(atPath: destTokenizer.path),
               fileManager.fileExists(atPath: legacyTokenizer.appendingPathComponent("tokenizer.json").path) {
                try fileManager.createDirectory(
                    at: destTokenizer.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.copyItem(at: legacyTokenizer, to: destTokenizer)
            }
            return .moved
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
