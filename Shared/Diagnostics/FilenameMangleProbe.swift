// FilenameMangleProbe — PROBE ONLY. Logs candidate filename/date-string mangling
// occurrences to a local JSONL for recurrence analysis. NO correction rule is built
// here. Rule-building (token-reassembly or context-anchored dictionary entry) is
// DEFERRED behind a recurrence gate per D-11: one confirmed occurrence ("cleanup-
// 2026-06-16.jsonl" → "cleanup 2026.json L", STATE.md 2026-06-16) is insufficient
// signal to justify a speculative rule whose false-positive risk on ordinary
// hyphenated or dotted prose (e.g. "proto-1975 stamp", "v2.0.1 release notes")
// is unacceptable. Collect data first; decide after recurrence is confirmed.
//
// Mirrors AudioCaptureProbe exactly: `#if DEBUG_RECORDER` wrap, `public actor` +
// `static let shared`, DebugRecordings dir resolution, 14-day purge-once-per-launch,
// ISO8601 timestamp helper, appendJsonl.
//
// COMPILED OUT unless built with `-D DEBUG_RECORDER` (same gate as DebugRecorder and
// AudioCaptureProbe). NEVER present in the public Release / GitHub artifact.
//
// Output: ~/Library/Application Support/Dicticus/DebugRecordings/
//   filename-probe-YYYY-MM-DD.jsonl   (one line per CANDIDATE MATCH ONLY)
// Retention: 14 days, purged once per launch (same as DebugRecorder).
//
// Detection signatures (probe reads postItn; NEVER mutates text):
//   (a) A 4-digit token (\b\d{4}\b) adjacent to / within 2 tokens of a file-extension
//       fragment from the closed list: .json .jsonl .swift .md .txt .log .py .yaml
//       .toml .sh  — the observed "2026.json" shape.
//   (b) A trailing single-letter token after a file-extension fragment — the "L" in
//       "cleanup 2026.json L" (interpreted as the ".jsonl" extension split to ".json"
//       + space + "L").
// Candidate logs are INTENTIONALLY broad (false positives in the LOG are acceptable;
// false positives in a CORRECTION are not — hence probe-only).
// Records NOTHING when no candidate matches — keeps the log signal-dense.

#if DEBUG_RECORDER

import Foundation

public actor FilenameMangleProbe {

    public static let shared = FilenameMangleProbe()

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

    // MARK: - Public interface

    /// Inspect `postItn` for candidate filename/date-string mangling signatures.
    /// Appends a JSONL line ONLY when a candidate is detected. Never mutates text.
    /// - Parameters:
    ///   - raw: original ASR output before any processing
    ///   - postItn: text after ITN + Step 2a + Step 2a.5 (the production post-ITN form)
    public func record(raw: String, postItn: String) {
        guard let (matched, fragment) = Self.findCandidate(in: postItn) else { return }
        ensureDirectory()
        purgeIfNeeded()

        let line: [String: Any] = [
            "ts": Self.iso8601Timestamp(),
            "raw": raw,
            "post_itn": postItn,
            "candidate_pattern_matched": matched,
            "fragment": fragment
        ]
        appendJsonl(line)
    }

    // MARK: - Detection (pure, nonisolated — no text mutation)

    /// Returns `(patternLabel, matchedFragment)` when a mangling candidate is found,
    /// `nil` when the text is clean. Exported `nonisolated` for unit-test access.
    nonisolated static func findCandidate(in text: String) -> (String, String)? {
        // Closed extension list (covers file types encountered in Dicticus usage logs)
        let extensions = [".jsonl", ".json", ".swift", ".md", ".txt", ".log", ".py", ".yaml", ".toml", ".sh"]

        // Tokenise on whitespace for positional checks
        let tokens = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)

        for (i, token) in tokens.enumerated() {
            // (a) Extension fragment that is a standalone token (e.g. ".json", ".md")
            let tokenLower = token.lowercased()
            if extensions.contains(where: { tokenLower == $0 || tokenLower.hasPrefix($0) }) {
                // Check whether a 4-digit year/number is within 2 positions on either side
                let window = max(0, i - 2)...min(tokens.count - 1, i + 2)
                for j in window where j != i {
                    if tokens[j].range(of: #"^\d{4}$"#, options: .regularExpression) != nil {
                        return ("(a) 4-digit token near extension fragment", "\(tokens[j]) \(token)")
                    }
                }

                // (b) Trailing single-letter token after the extension fragment
                // e.g. ".json" followed by "L" → ".jsonl" was split
                if i + 1 < tokens.count {
                    let next = tokens[i + 1]
                    if next.count == 1 && next.first?.isLetter == true {
                        return ("(b) single-letter suffix after extension fragment", "\(token) \(next)")
                    }
                }
            }

            // (a) Extension embedded at end of a token like "2026.json" (no space split)
            for ext in extensions where ext.count > 1 {
                if tokenLower.hasSuffix(ext) && tokenLower != ext {
                    // Confirm a 4-digit sequence precedes the extension inside the token
                    let stem = String(tokenLower.dropLast(ext.count))
                    if stem.range(of: #"\d{4}$"#, options: .regularExpression) != nil {
                        return ("(a) 4-digit stem + embedded extension in single token", token)
                    }
                }
            }
        }

        return nil
    }

    // MARK: - Plumbing (mirrors AudioCaptureProbe / DebugRecorder)

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func currentJsonlURL() -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return directoryURL.appendingPathComponent("filename-probe-\(f.string(from: Date())).jsonl")
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
        for entry in entries where entry.lastPathComponent.hasPrefix("filename-probe-") {
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
