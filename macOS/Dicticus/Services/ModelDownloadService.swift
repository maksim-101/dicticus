import Foundation
import os.log

/// Downloads and caches the Qwen3.5-4B-Instruct GGUF model file on first run.
///
/// Per D-09: Download from HuggingFace on first launch.
/// Per D-10: Cache in Application Support/Dicticus/Models/.
/// Phase 44 (D-09): Qwen3.5-4B Q4_K_M GGUF from unsloth (ungated, ~2.74 GB) — swapped from
/// Qwen2.5-3B for +18% substantive repairs; passed the Phase 44 fidelity gate 104/104.
///
/// Uses URLSession.shared.download(from:) for automatic temp file handling.
/// No authentication required — unsloth repo is publicly accessible (Apache-2.0).
///
/// Phase 50 D-06/D-08 ledger: `expectedModelSHA256` below was derived 2026-09-12 from
/// TWO independent sources — a local `shasum -a 256` over the benchmarked file AND the
/// HuggingFace CDN's `x-linked-etag` response header for the same artifact — both
/// recorded as MATCH in `50-GATE-DIFF.md` §D. This turns the old elided doc-comment hash
/// (`oid 00fe7986…f11a4`) from an unverifiable claim into an enforced invariant:
/// `acquireVerifiedModel` never lets an unverified file reach `modelPath()`.
class ModelDownloadService {

    /// HuggingFace CDN URL for the ungated Qwen3.5-4B Q4_K_M GGUF.
    /// unsloth/Qwen3.5-4B-GGUF — verified ungated (HTTP 200, gated:False, 2026-07-15) and
    /// sha256-identical to the file benchmarked + fidelity-gated in Phase 44
    /// (oid 00fe7986…f11a4, 2,740,937,888 bytes). Qwen3.5 unified base+instruct in one model.
    static let modelURL = URL(string: "https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q4_K_M.gguf")!

    /// D-06/D-08: the pinned SHA-256 for `modelFileName`'s content — derived from
    /// `50-GATE-DIFF.md` §D (local `shasum -a 256` MATCH against HuggingFace's
    /// `x-linked-etag`), not typed from the elided source comment above.
    static let expectedModelSHA256 = "00fe7986ff5f6b463e62455821146049db6f9313603938a70800d1fb69ef11a4"

    /// D-08: expected byte size of the pinned GGUF, from the same §D derivation.
    static let expectedModelByteCount = 2_740_937_888

    /// D-08: at most this many hash mismatches (across an existing file plus
    /// re-downloads) are tolerated before `acquireVerifiedModel` gives up. A second
    /// mismatch disables AI cleanup for the session rather than retrying forever
    /// against a URL that may be serving corrupted or substituted content.
    static let maxVerificationFailures = 2

    /// The expected SHA-256 for `name`, or nil if `name` has no pin. Only the
    /// shipped `modelFileName` is pinned — the dev `-llmModelFileOverride` file
    /// (a DEBUG benchmark knob) has no pin and loads unverified with a warmup-log
    /// warning (T-50-04-03, accepted: a local attacker able to set that default
    /// already controls the user session).
    static func expectedSHA256(forFileName name: String) -> String? {
        name == modelFileName ? expectedModelSHA256 : nil
    }

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

    /// Check if the GGUF model file is cached AND verified (D-08). For the pinned
    /// `modelFileName`, this is the cheap stamp-based re-verify — exists AND stamp
    /// matches current size/mtime — never a bare existence check and never a hash.
    /// For an unpinned dev-override file, falls back to plain existence (no pin to
    /// verify against).
    static func isModelCached() -> Bool {
        if let expected = expectedSHA256(forFileName: activeModelFileName) {
            return ModelIntegrity.isVerifiedCheaply(modelURL: modelPath(), expectedSHA256: expected)
        }
        return FileManager.default.fileExists(atPath: modelPath().path)
    }

    /// Best-effort removal of retired GGUFs once the current model is present. Non-fatal —
    /// errors are ignored since this is a disk-reclaim convenience, not a correctness requirement.
    static func removeOrphanedModelsIfPresent() {
        let modelsDir = modelPath().deletingLastPathComponent()
        for name in legacyModelFileNames {
            try? FileManager.default.removeItem(at: modelsDir.appendingPathComponent(name))
        }
    }

    /// D-08 retry state machine: never lets an unverified file occupy `modelURL`.
    ///
    /// If a file already exists at `modelURL`, it is verified first — a match
    /// returns immediately (no download); a mismatch counts as one failure and the
    /// file + its stamp are removed before falling through to the download loop.
    /// Each download attempt hashes the downloaded temp file BEFORE moving it into
    /// place — the move (and stamp write) only happens once the hash has already
    /// matched, so any reader that sees a file at `modelURL` between the move and
    /// the stamp write is looking at content that was already confirmed correct
    /// (a slow re-hash on that narrow window is the only cost, never a wrong
    /// verdict — the concurrency truth this design relies on).
    /// After `maxVerificationFailures` total mismatches, throws
    /// `ModelIntegrityError.verificationFailed` and leaves no file at `modelURL`.
    static func acquireVerifiedModel(
        at modelURL: URL,
        expectedSHA256: String,
        download: () async throws -> URL,
        hasher: (URL) throws -> String = { try ModelIntegrity.sha256Hex(of: $0) }
    ) async throws {
        var failures = 0

        switch ModelIntegrity.verify(modelURL: modelURL, expectedSHA256: expectedSHA256, hasher: hasher) {
        case .verified:
            return
        case .mismatch:
            failures += 1
            try? FileManager.default.removeItem(at: modelURL)
            try? FileManager.default.removeItem(at: ModelIntegrity.stampURL(for: modelURL))
        case .missing:
            break
        }

        while failures < maxVerificationFailures {
            let tempURL = try await download()
            let actual = try hasher(tempURL)
            if actual == expectedSHA256 {
                try? FileManager.default.removeItem(at: modelURL)
                try FileManager.default.moveItem(at: tempURL, to: modelURL)
                try ModelIntegrity.writeStamp(for: modelURL, sha256: actual)
                return
            }
            try? FileManager.default.removeItem(at: tempURL)
            failures += 1
        }

        throw ModelIntegrityError.verificationFailed(attempts: failures)
    }

    /// Download the GGUF model from HuggingFace and cache it in Application Support.
    ///
    /// No-op if model is already cached AND verified (D-08). Creates intermediate
    /// directories if needed. Downloads ~2.74 GB on first run — called during
    /// warmup, not during inference. Reclaims disk from retired models (Gemma,
    /// Qwen2.5) on both the cache-hit and fresh-download paths (CLEANRD-01).
    ///
    /// - Throws: URLSession errors on network failure, FileManager errors on disk
    ///   write failure, `ModelIntegrityError.verificationFailed` after D-08's
    ///   retry budget is exhausted.
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

        if let expected = expectedSHA256(forFileName: activeModelFileName) {
            try await acquireVerifiedModel(
                at: modelPath(),
                expectedSHA256: expected,
                download: {
                    let (tempURL, _) = try await URLSession.shared.download(from: modelURL)
                    return tempURL
                }
            )
        } else {
            // Dev override (-llmModelFileOverride): no pin exists for this file name,
            // so it loads unverified. Accepted per T-50-04-03 — a local attacker able
            // to set this default already controls the user session.
            if !FileManager.default.fileExists(atPath: modelPath().path) {
                let (tempURL, _) = try await URLSession.shared.download(from: modelURL)
                try FileManager.default.moveItem(at: tempURL, to: modelPath())
            }
            Logger(subsystem: "com.dicticus", category: "warmup")
                .warning("LLM model file override in use — loading unverified")
        }

        removeOrphanedModelsIfPresent()
    }
}

/// D-08: an existing or freshly downloaded file failed hash verification `attempts`
/// times (across the existing-file check and any re-downloads), exceeding
/// `ModelDownloadService.maxVerificationFailures`. No file is left at the target
/// path when this is thrown.
enum ModelIntegrityError: Error, Equatable, LocalizedError {
    case verificationFailed(attempts: Int)

    var errorDescription: String? {
        switch self {
        case .verificationFailed(let attempts):
            return "Model failed verification after \(attempts) attempt(s)."
        }
    }
}
