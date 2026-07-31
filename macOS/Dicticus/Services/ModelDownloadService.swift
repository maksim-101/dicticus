import Foundation

/// Downloads and caches the Qwen3.5-4B-Instruct GGUF model file on first run.
///
/// Per D-09: Download from HuggingFace on first launch.
/// Per D-10: Cache in Application Support/Dicticus/Models/.
/// Phase 44 (D-09): Qwen3.5-4B Q4_K_M GGUF from unsloth (ungated, ~2.74 GB) — swapped from
/// Qwen2.5-3B for +18% substantive repairs; passed the Phase 44 fidelity gate 104/104.
///
/// Uses URLSession.shared.download(from:) for automatic temp file handling.
/// No authentication required — unsloth repo is publicly accessible (Apache-2.0).
class ModelDownloadService {

    /// HuggingFace CDN URL for the ungated Qwen3.5-4B Q4_K_M GGUF.
    /// unsloth/Qwen3.5-4B-GGUF — verified ungated (HTTP 200, gated:False, 2026-07-15) and
    /// sha256-identical to the file benchmarked + fidelity-gated in Phase 44
    /// (oid 00fe7986…f11a4, 2,740,937,888 bytes). Qwen3.5 unified base+instruct in one model.
    static let modelURL = URL(string: "https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q4_K_M.gguf")!

    /// Local cache file name — matches the URL's artifact name (lowercased). Contains "qwen3" so
    /// CleanupService's reasoning-preclose + Qwen3 EOG handling fire. The
    /// modelFileName-matches-URL invariant is asserted in ModelDownloadServiceTests.
    static let modelFileName = "qwen3.5-4b-q4_k_m.gguf"

    /// Phase 44 Plan 14: the GGUF actually loaded. Defaults to the shipped `modelFileName`;
    /// `-llmModelFileOverride <name>.gguf` points it at another on-disk GGUF so the
    /// Qwen2.5-vs-Qwen3.5 benchmark runs against one build. Mirrors the iOS constant.
    /// Shipped behaviour is byte-identical when the argument is absent.
    static var activeModelFileName: String {
        UserDefaults.standard.string(forKey: "llmModelFileOverride") ?? modelFileName
    }

    /// User-facing model name — single source of truth for UI labels so a future
    /// model swap cannot leave a stale label behind (Plan 36.6-02 swapped the backend
    /// to Qwen but the AI Cleanup views still hardcoded "Gemma 4 E2B").
    static let modelDisplayName = "Qwen3.5-4B-Instruct (Q4_K_M)"

    /// Filenames of retired GGUFs, removed best-effort so upgrading users reclaim disk:
    /// Gemma 4 E2B (~3.1 GB, pre-Qwen) and Qwen2.5-3B (~1.93 GB, superseded by Qwen3.5 in Phase 44).
    static let legacyModelFileNames = [
        "gemma-4-E2B-it-Q4_K_M.gguf",
        "qwen2.5-3b-instruct-q4_k_m.gguf",
    ]

    /// Computed path to the cached model file in Application Support.
    ///
    /// Path: ~/Library/Application Support/Dicticus/Models/qwen3.5-4b-instruct-q4_k_m.gguf
    /// Follows the same Application Support convention used by prior ASR model caches (per D-10).
    static func modelPath() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("Dicticus")
            .appendingPathComponent("Models")
            .appendingPathComponent(activeModelFileName)
    }

    /// Check if the GGUF model file is already cached on disk.
    static func isModelCached() -> Bool {
        FileManager.default.fileExists(atPath: modelPath().path)
    }

    /// Best-effort removal of retired GGUFs once the current model is present. Non-fatal —
    /// errors are ignored since this is a disk-reclaim convenience, not a correctness requirement.
    static func removeOrphanedModelsIfPresent() {
        let modelsDir = modelPath().deletingLastPathComponent()
        for name in legacyModelFileNames {
            try? FileManager.default.removeItem(at: modelsDir.appendingPathComponent(name))
        }
    }

    /// Download the GGUF model from HuggingFace and cache it in Application Support.
    ///
    /// No-op if model is already cached. Creates intermediate directories if needed.
    /// Downloads ~2.74 GB on first run — called during warmup, not during inference.
    /// Reclaims disk from retired models (Gemma, Qwen2.5) on both the cache-hit and
    /// fresh-download paths (CLEANRD-01).
    ///
    /// - Throws: URLSession errors on network failure, FileManager errors on disk write failure.
    static func downloadIfNeeded() async throws {
        guard !isModelCached() else {
            removeOrphanedModelsIfPresent()
            return
        }

        let dir = modelPath().deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )

        let (tempURL, _) = try await URLSession.shared.download(from: modelURL)
        try FileManager.default.moveItem(at: tempURL, to: modelPath())
        removeOrphanedModelsIfPresent()
    }
}
