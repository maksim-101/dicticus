// MediaPauseProbe — debug-session diagnostic for MediaController's PTT
// media-pause tiers (quick task 260725-mediaprobe, MEASURE-FIRST).
//
// The user's tier-2 (CoreAudio output-mute) YouTube fallback stopped working
// and every exit path in MediaController.pauseMediaIfPlaying() /
// resumeMediaIfPaused() is currently silent — no signal distinguishes "no
// player was playing", "ScriptingBridge paused a player", "tier-2 muted
// output", or "tier-2 attempted and failed". This probe logs every
// invocation so a future debug-build session can see which branch fired and
// why, without changing the silent UX (COMPILED OUT unless built with
// `-D DEBUG_RECORDER`, same gate as DiscardProbe/AudioCaptureProbe — never
// present in the public Release / GitHub artifact).
//
// Also logs the HotkeyManager call site (dispatched + the
// pauseMediaDuringDictation setting value) so "never called" (toggle off) is
// distinguishable from "called and failed" (toggle on, all tiers no-op).
//
// Output: ~/Library/Application Support/Dicticus/DebugRecordings/mediapause-YYYY-MM-DD.jsonl
// Retention: 14 days, purged once per launch.

#if DEBUG_RECORDER

import Foundation

public actor MediaPauseProbe {

    public static let shared = MediaPauseProbe()

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

    /// One player's tier-1 (ScriptingBridge) outcome for a single pause invocation.
    public struct PlayerOutcome: Sendable {
        public let name: String
        public let running: Bool
        public let stateValue: String?
        public let stateErrorNumber: Int?
        public let pauseAttempted: Bool
        public let pauseErrorNumber: Int?
        public let paused: Bool

        public init(
            name: String,
            running: Bool,
            stateValue: String? = nil,
            stateErrorNumber: Int? = nil,
            pauseAttempted: Bool = false,
            pauseErrorNumber: Int? = nil,
            paused: Bool = false
        ) {
            self.name = name
            self.running = running
            self.stateValue = stateValue
            self.stateErrorNumber = stateErrorNumber
            self.pauseAttempted = pauseAttempted
            self.pauseErrorNumber = pauseErrorNumber
            self.paused = paused
        }
    }

    /// Record one `pauseMediaIfPlaying()` invocation.
    ///
    /// Tier-2b (260725-b4f) params are optional/defaulted so the existing macOS caller
    /// contract before that change, and the inert iOS build, are unaffected until a
    /// caller actually passes them.
    public func recordPause(
        players: [PlayerOutcome],
        pausedApp: String?,
        tier2Reached: Bool,
        isOutputMutedResult: Bool?,
        muteAttempted: Bool,
        setOutputMutedResult: Bool?,
        didMuteOutput: Bool,
        outputDeviceName: String,
        tier2bGuardResult: Bool? = nil,
        tier2bToggleAttempted: Bool? = nil,
        tier2bToggleSent: Bool? = nil,
        tier2bDlsymDegrade: Bool? = nil,
        didToggleMediaRemote: Bool? = nil,
        tier2bRMS: Double? = nil,
        tier2bTapStatus: String? = nil
    ) {
        ensureDirectory()
        purgeIfNeeded()

        var line: [String: Any] = [
            "ts": Self.iso8601Timestamp(),
            "event": "pause",
            "called": true,
            "tier2_reached": tier2Reached,
            "mute_attempted": muteAttempted,
            "did_mute_output": didMuteOutput,
            "output_device_name": outputDeviceName,
            "players": players.map { p -> [String: Any] in
                var playerLine: [String: Any] = [
                    "name": p.name,
                    "running": p.running,
                    "pause_attempted": p.pauseAttempted,
                    "paused": p.paused
                ]
                if let stateValue = p.stateValue { playerLine["state_value"] = stateValue }
                if let stateErrorNumber = p.stateErrorNumber { playerLine["state_error_number"] = stateErrorNumber }
                if let pauseErrorNumber = p.pauseErrorNumber { playerLine["pause_error_number"] = pauseErrorNumber }
                return playerLine
            }
        ]
        if let pausedApp { line["paused_app"] = pausedApp }
        if let isOutputMutedResult { line["is_output_muted_result"] = isOutputMutedResult }
        if let setOutputMutedResult { line["set_output_muted_result"] = setOutputMutedResult }
        if let tier2bGuardResult { line["tier2b_guard_result"] = tier2bGuardResult }
        if let tier2bToggleAttempted { line["tier2b_toggle_attempted"] = tier2bToggleAttempted }
        if let tier2bToggleSent { line["tier2b_toggle_sent"] = tier2bToggleSent }
        if let tier2bDlsymDegrade { line["tier2b_dlsym_degrade"] = tier2bDlsymDegrade }
        if let didToggleMediaRemote { line["did_toggle_media_remote"] = didToggleMediaRemote }
        if let tier2bRMS { line["tier2b_rms"] = tier2bRMS }
        if let tier2bTapStatus { line["tier2b_tap_status"] = tier2bTapStatus }

        appendJsonl(line)
    }

    /// Record one `resumeMediaIfPaused()` invocation.
    ///
    /// Tier-2b (260725-b4f) params are optional/defaulted so the existing macOS caller
    /// contract before that change, and the inert iOS build, are unaffected until a
    /// caller actually passes them.
    public func recordResume(
        resumedPlayer: String?,
        resumeErrorNumber: Int?,
        unmuteAttempted: Bool,
        unmuteResult: Bool?,
        didMuteOutputBefore: Bool,
        tier2bResumeToggleAttempted: Bool? = nil,
        tier2bResumeToggleSent: Bool? = nil
    ) {
        ensureDirectory()
        purgeIfNeeded()

        var line: [String: Any] = [
            "ts": Self.iso8601Timestamp(),
            "event": "resume",
            "called": true,
            "unmute_attempted": unmuteAttempted,
            "did_mute_output_before": didMuteOutputBefore
        ]
        if let resumedPlayer { line["resumed_player"] = resumedPlayer }
        if let resumeErrorNumber { line["resume_error_number"] = resumeErrorNumber }
        if let unmuteResult { line["unmute_result"] = unmuteResult }
        if let tier2bResumeToggleAttempted { line["tier2b_resume_toggle_attempted"] = tier2bResumeToggleAttempted }
        if let tier2bResumeToggleSent { line["tier2b_resume_toggle_sent"] = tier2bResumeToggleSent }

        appendJsonl(line)
    }

    /// Record the HotkeyManager call site — dispatched or skipped, plus the current
    /// `pauseMediaDuringDictation` setting value. Distinguishes "never called" (toggle
    /// off) from "called and failed" (all tiers no-op).
    public func recordDispatch(dispatched: Bool, pauseMediaDuringDictation: Bool) {
        ensureDirectory()
        purgeIfNeeded()

        let line: [String: Any] = [
            "ts": Self.iso8601Timestamp(),
            "event": "dispatch",
            "dispatched": dispatched,
            "pause_media_during_dictation": pauseMediaDuringDictation
        ]

        appendJsonl(line)
    }

    // MARK: - Plumbing (mirrors DiscardProbe)

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func currentJsonlURL() -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return directoryURL.appendingPathComponent("mediapause-\(f.string(from: Date())).jsonl")
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
        for entry in entries where entry.lastPathComponent.hasPrefix("mediapause-") {
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
