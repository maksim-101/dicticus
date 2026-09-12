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
// Phase 50 D-05: the probe now records EVERY exit of `injectText`, not only
// the success branch (it previously logged a literal `injectionSucceeded:
// true` on success only — the two early-return exits never logged at all,
// so "zero paste failures in the logs" was never evidence). `exit` names
// which of the four branches fired: `ax_untrusted`, `clipboard_write_failed`,
// `delivery_precheck_failed`, `success`. `failure_signal` is populated only
// on `delivery_precheck_failed`, naming which D-02 signal blocked delivery:
// `secure_input` or `frontmost_changed`.
//
// Phase 50 plan 11: the restore-before-read race. A live record (2026-09-12,
// `paste-2026-09-12.jsonl` line 122, `exit: success`) shows the first
// dictation into Gemini for macOS after an idle model reload pasting the
// PREVIOUS clipboard content — its Electron renderer read the pasteboard
// asynchronously, after the old fixed-delay restore had already run. The
// `success` record now carries `restore_delay_ms` (measured wait before the
// restore decision), `changecount_after_write` and `changecount_at_restore`
// (`NSPasteboard.changeCount` before/after the wait), and `restore_performed`
// (whether the saved clipboard was actually re-installed). Reading rule for
// the next audit: a wrong-text report with `restore_performed: true` and
// `restore_delay_ms` at or above `TextInjector.clipboardRestoreDelayMilliseconds`
// falsifies the delay hypothesis and points at AX insertion instead.
//
// Phase 50 plan 12 — the same-app race (CR-01, 50-REVIEW.md 2026-09-12): a second paste or
// Revert to Raw inside a prior paste's 750 ms window used to save that paste's transcript as
// the "previous clipboard" and re-install it; calls now queue behind the open window on one
// shared `TextInjector`. Reading rule for the next audit: `waited_for_prior_ms` above `0` means
// the call queued; paired with `restore_performed: true` on that same record, the clipboard
// that came back is the user's own prior content; a wrong-clipboard report whose records all
// show `waited_for_prior_ms: 0` is a different defect.
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
    ///
    /// - Parameters:
    ///   - exit: which of `injectText`'s four branches fired — `ax_untrusted`,
    ///     `clipboard_write_failed`, `delivery_precheck_failed`, `success`.
    ///   - failureSignal: on `delivery_precheck_failed` only, which D-02 signal
    ///     blocked delivery — `secure_input` or `frontmost_changed`.
    ///   - restoreDelayMs: on `success` only (Phase 50 plan 11), the measured wait between
    ///     the Cmd+V post and the restore decision.
    ///   - changeCountAfterWrite: on `success` only, `NSPasteboard.changeCount` read directly
    ///     after our `setString`.
    ///   - changeCountAtRestore: on `success` only, `NSPasteboard.changeCount` read after the wait.
    ///   - restorePerformed: on `success` only; `false` means a third party wrote to the
    ///     pasteboard during the wait and the saved clipboard was deliberately not re-installed.
    ///   - waitedForPriorMs: on every exit after the AX guard (Phase 50 plan 12, CR-01), the
    ///     measured milliseconds this call spent waiting for a prior call's restore window to
    ///     close (`0` when it did not wait).
    public func record(secureInputEnabled: Bool, injectionSucceeded: Bool, exit: String, failureSignal: String? = nil, restoreDelayMs: Int? = nil, changeCountAfterWrite: Int? = nil, changeCountAtRestore: Int? = nil, restorePerformed: Bool? = nil, waitedForPriorMs: Int? = nil) {
        ensureDirectory()
        purgeIfNeeded()

        var line: [String: Any] = [
            "ts": Self.iso8601Timestamp(),
            "secure_input_enabled": secureInputEnabled,
            "injection_succeeded": injectionSucceeded
        ]
        line["exit"] = exit
        if let failureSignal {
            line["failure_signal"] = failureSignal
        }
        if let restoreDelayMs {
            line["restore_delay_ms"] = restoreDelayMs
        }
        if let changeCountAfterWrite {
            line["changecount_after_write"] = changeCountAfterWrite
        }
        if let changeCountAtRestore {
            line["changecount_at_restore"] = changeCountAtRestore
        }
        if let restorePerformed {
            line["restore_performed"] = restorePerformed
        }
        if let waitedForPriorMs {
            line["waited_for_prior_ms"] = waitedForPriorMs
        }
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
