// PasteProbe — diagnostic for the paste-time secure-input state (quick task 260830-si1).
//
// Diagnoses an open, unexplained production bug: dictated text reaches the
// history DB but the final NSPasteboard + Cmd+V step no-ops at the cursor.
// A read of the competitor app Handy (MIT, src-tauri/src/secure_input.rs)
// surfaced a strong candidate: macOS silently suppresses synthesized
// keystrokes (CGEventTap) while Carbon's IsSecureEventInputEnabled() is true
// — a password field has focus, or a terminal has "Secure Keyboard Entry" on.
// That matches the symptom exactly: the pipeline completes, but the
// synthesized Cmd+V does nothing.
//
// PROBE ONLY — reads and records the flag at the moment of paste. No retry,
// no fallback, no user-facing alert, no Carbon shortcut-registration path.
// Follow-on work is gated on what this instrument shows in the field.
//
// COMPILED OUT unless built with `-D DEBUG_RECORDER` (same gate as DebugRecorder).
// NEVER present in the public Release / GitHub artifact.
//
// Output: ~/Library/Application Support/Dicticus/DebugRecordings/
//   paste-YYYY-MM-DD.jsonl   (one line per paste/injection attempt)
// Retention: 14 days, purged once per launch (same as DebugRecorder).

#if DEBUG_RECORDER

import Foundation
import Carbon.HIToolbox

public actor PasteProbe {

    public static let shared = PasteProbe()

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

    /// Read Carbon's secure-input flag. Call from the main actor immediately
    /// before Cmd+V synthesis, so the read reflects state at the moment paste
    /// is attempted, not whenever the actor gets around to logging it.
    public nonisolated static func secureInputEnabled() -> Bool {
        IsSecureEventInputEnabled()
    }

    /// Record one paste/injection attempt.
    public func record(secureInputEnabled: Bool, injectionSucceeded: Bool) {
        ensureDirectory()
        purgeIfNeeded()

        let line: [String: Any] = [
            "ts": Self.iso8601Timestamp(),
            "secure_input_enabled": secureInputEnabled,
            "injection_succeeded": injectionSucceeded
        ]
        appendJsonl(line)
    }

    // MARK: - Plumbing (mirrors DiscardProbe / FilenameMangleProbe)

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func currentJsonlURL() -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return directoryURL.appendingPathComponent("paste-\(f.string(from: Date())).jsonl")
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
        for entry in entries where entry.lastPathComponent.hasPrefix("paste-") {
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
