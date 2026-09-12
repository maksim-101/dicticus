import Foundation
import CryptoKit
import os.log

/// Phase 50 D-08: turns the Phase-44-gated GGUF weights from a comment
/// (`ModelDownloadService.swift:14-17`) into an enforced, fail-closed invariant.
///
/// Verify-then-stamp: a freshly downloaded file is hashed at its temp URL before it
/// is moved into `modelPath()`; only a matching hash earns the move. A stamp sidecar
/// (`<model>.gguf.stamp.json` = `{sha256, bytes, mtime}`) is written after the move so
/// every later load can do a cheap size+mtime check instead of re-hashing 2.74 GB.
/// The stamp only ever encodes a fact this process itself already confirmed by
/// hashing — it is not a second, independent authority. Re-hash happens only when the
/// stamp is absent (the no-stamp path handles the user's pre-Phase-50 upgrade: an
/// already-downloaded file gets hashed and stamped once, on first launch after
/// upgrade) or when the file's current `bytes`/`mtime` no longer match the stamp
/// (RESEARCH Pattern 3).
///
/// Security note: this guards the integrity of a public, unsigned artifact (an
/// ungated HuggingFace GGUF) — SHA-256 is sufficient; no HMAC/signature is needed
/// because there is no secret key to protect, only silent-substitution detection
/// (T-50-04-01). A local attacker who can forge the stamp sidecar already controls
/// the user's file system and could replace the app binary itself (T-50-04-02,
/// accepted).
enum ModelIntegrity {

    /// A sidecar fact record written next to a model file once its hash is confirmed.
    struct Stamp: Codable, Equatable {
        let sha256: String
        let bytes: Int
        let mtime: TimeInterval
    }

    /// The outcome of `verify(modelURL:expectedSHA256:hasher:)`.
    enum Verdict: Equatable {
        /// The file's hash matches `expectedSHA256`. `rehashed` is true when this
        /// call actually ran the hasher (no valid stamp was present); false when
        /// the cheap stamp check alone was sufficient (RELY-02 idempotency).
        case verified(rehashed: Bool)
        /// The file exists but its hash does not equal `expectedSHA256`.
        case mismatch(actual: String)
        /// No file exists at `modelURL`.
        case missing
    }

    private static let log = Logger(subsystem: "com.dicticus", category: "model-integrity")

    /// The stamp sidecar lives next to the model file: `<model>.gguf.stamp.json`.
    static func stampURL(for modelURL: URL) -> URL {
        modelURL.appendingPathExtension("stamp.json")
    }

    /// Streaming SHA-256 over `url`, 1 MiB chunks — keeps peak memory low for a
    /// 2.74 GB file. `FileHandle.read(upToCount:)` is the streaming primitive; no
    /// full-file `Data(contentsOf:)` load (RESEARCH "Don't Hand-Roll").
    static func sha256Hex(of url: URL, chunkSize: Int = 1 << 20) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Current on-disk facts for `url` — byte size and modification time — or nil
    /// if the file does not exist or its attributes cannot be read.
    static func fileFacts(at url: URL) -> (bytes: Int, mtime: TimeInterval)? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int,
              let modDate = attrs[.modificationDate] as? Date else {
            return nil
        }
        return (bytes: size, mtime: modDate.timeIntervalSince1970)
    }

    /// Reads and decodes the stamp for `modelURL`, or nil on any absence/failure.
    static func readStamp(for modelURL: URL) -> Stamp? {
        guard let data = try? Data(contentsOf: stampURL(for: modelURL)) else { return nil }
        return try? JSONDecoder().decode(Stamp.self, from: data)
    }

    /// Pure predicate: does `stamp` exactly match the given facts and expectation?
    /// All three fields must match exactly — a changed mtime with identical content,
    /// or a changed byte count, or a different expected hash, all fail this check
    /// (RELY-02 adjacency probe).
    nonisolated static func stampMatches(
        _ stamp: Stamp?,
        bytes: Int,
        mtime: TimeInterval,
        expectedSHA256: String
    ) -> Bool {
        guard let stamp else { return false }
        return stamp.sha256 == expectedSHA256 && stamp.bytes == bytes && stamp.mtime == mtime
    }

    /// Writes the stamp sidecar for `modelURL`. Errors are swallowed with a warning
    /// log — a stamp-write failure only costs a re-hash on the next load, it is not
    /// itself a correctness failure.
    static func writeStamp(for modelURL: URL, sha256: String) throws {
        guard let facts = fileFacts(at: modelURL) else { return }
        let stamp = Stamp(sha256: sha256, bytes: facts.bytes, mtime: facts.mtime)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(stamp)
        try data.write(to: stampURL(for: modelURL), options: .atomic)
    }

    /// Verifies `modelURL` against `expectedSHA256`, using the stamp sidecar as a
    /// cheap cache: a valid stamp (bytes+mtime+sha256 all match) skips the hash
    /// entirely. Otherwise hashes and, on a match, writes/refreshes the stamp.
    /// Never deletes the file — mismatch-driven deletion is `acquireVerifiedModel`'s
    /// policy, not this pure verification step's.
    static func verify(
        modelURL: URL,
        expectedSHA256: String,
        hasher: (URL) throws -> String = { try sha256Hex(of: $0) }
    ) -> Verdict {
        guard let facts = fileFacts(at: modelURL) else { return .missing }

        let stamp = readStamp(for: modelURL)
        if stampMatches(stamp, bytes: facts.bytes, mtime: facts.mtime, expectedSHA256: expectedSHA256) {
            return .verified(rehashed: false)
        }

        let actual: String
        do {
            actual = try hasher(modelURL)
        } catch {
            log.error("Hashing failed for \(modelURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .mismatch(actual: "hash-error")
        }

        guard actual == expectedSHA256 else {
            return .mismatch(actual: actual)
        }

        do {
            try writeStamp(for: modelURL, sha256: actual)
        } catch {
            log.warning("Failed to write stamp for \(modelURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public) — will re-hash next time")
        }
        return .verified(rehashed: true)
    }

    /// The cheap re-verify path used at every load: exists AND the stamp matches
    /// current facts. Never hashes, never writes — a pure read of the file system.
    static func isVerifiedCheaply(modelURL: URL, expectedSHA256: String) -> Bool {
        guard let facts = fileFacts(at: modelURL) else { return false }
        return stampMatches(readStamp(for: modelURL), bytes: facts.bytes, mtime: facts.mtime, expectedSHA256: expectedSHA256)
    }
}
