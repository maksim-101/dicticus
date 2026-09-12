// LlmLifecycleProbe — diagnostic for the cleanup LLM's idle-unload/reload lifecycle
// (Phase 50 D-12).
//
// Verification instrument for RELY-03: the idle-unload mechanism (`CleanupService.unload()`,
// `ModelWarmupService`'s idle-check loop + reload) has no user-visible UI beyond the Settings
// knob, so a live confirmation that it actually frees memory and reloads on demand needs a
// truthful record of both transitions.
//
// PROBE ONLY — records the two lifecycle events. No retry, no fallback, no user-facing alert.
//
// COMPILED OUT unless built with `-D DEBUG_RECORDER` (same gate as DebugRecorder/PasteProbe).
// NEVER present in the public Release / GitHub artifact.
//
// Output: ~/Library/Application Support/Dicticus/DebugRecordings/
//   llm-YYYY-MM-DD.jsonl   (one line per unload or reload)
// Retention: 14 days, purged once per launch (same as PasteProbe/DebugRecorder).

#if DEBUG_RECORDER

import Foundation

public actor LlmLifecycleProbe {

    public static let shared = LlmLifecycleProbe()

    private let directoryURL: URL
    private let retentionDays: Int = 14
    private var hasPurgedThisLaunch = false

    private init() {
        let fm = FileManager.default
        let appSupport = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support")

        self.directoryURL = appSupport
            .appendingPathComponent("Dicticus", isDirectory: true)
            .appendingPathComponent("DebugRecordings", isDirectory: true)
    }

    /// Record an idle-triggered unload of the cleanup LLM.
    ///
    /// - Parameters:
    ///   - idleSeconds: how long the model sat idle before this unload fired.
    ///   - thresholdSeconds: the configured threshold at the time of the unload
    ///     (`-1` when the threshold was "Never", which should never actually reach
    ///     this call since `shouldUnload` returns false for a nil threshold — present
    ///     for defensive completeness).
    public func recordUnload(idleSeconds: Double, thresholdSeconds: Double) {
        ensureDirectory()
        purgeIfNeeded()
        appendJsonl([
            "ts": Self.iso8601Timestamp(),
            "event": "model_unload",
            "idle_s": idleSeconds,
            "threshold_s": thresholdSeconds
        ])
    }

    /// Record a key-down-triggered reload of the cleanup LLM.
    ///
    /// - Parameters:
    ///   - loadMs: wall-clock milliseconds the reload (download-check + `loadModel`) took.
    ///   - cleanupWaited: whether a key-up cleanup call had to `await` this reload before
    ///     proceeding (D-11) rather than the reload finishing during the recording/ASR window.
    ///   - success: whether the reload completed and the model is loaded again.
    public func recordReload(loadMs: Double, cleanupWaited: Bool, success: Bool) {
        ensureDirectory()
        purgeIfNeeded()
        appendJsonl([
            "ts": Self.iso8601Timestamp(),
            "event": "model_reload",
            "load_ms": loadMs,
            "cleanup_waited": cleanupWaited,
            "success": success
        ])
    }

    // MARK: - Plumbing (mirrors PasteProbe / DiscardProbe / FilenameMangleProbe)

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func currentJsonlURL() -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return directoryURL.appendingPathComponent("llm-\(f.string(from: Date())).jsonl")
    }

    private func appendJsonl(_ obj: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { return }
        data.append(0x0A)
        let url = currentJsonlURL()
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            if let h = try? FileHandle(forWritingTo: url) {
                defer { try? h.close() }
                try? h.seekToEnd()
                try? h.write(contentsOf: data)
            }
        } else {
            try? data.write(to: url)
        }
    }

    private func purgeIfNeeded() {
        guard !hasPurgedThisLaunch else { return }
        hasPurgedThisLaunch = true
        let cutoff = Date().addingTimeInterval(-Double(retentionDays * 86_400))
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: directoryURL, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        for entry in entries where entry.lastPathComponent.hasPrefix("llm-") {
            if let mod = try? entry.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               mod < cutoff {
                try? fm.removeItem(at: entry)
            }
        }
    }

    private nonisolated static func iso8601Timestamp(_ date: Date = Date()) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }
}

#endif
