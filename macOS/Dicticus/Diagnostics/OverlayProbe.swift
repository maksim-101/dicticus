// OverlayProbe — diagnostic for the live transcript overlay (Phase 51).
//
// Verification instrument: every overlay_show must be paired with exactly one overlay_hide
// carrying the same seq, and each dictation with a preview writes one preview_session row.
//
// PROBE ONLY — no retry, no fallback, no user-facing alert. Records sequence numbers,
// reasons, frames, counts and timings. NEVER the preview text (privacy).
//
// COMPILED OUT unless built with `-D DEBUG_RECORDER` (same gate as LlmLifecycleProbe).
//
// Output: ~/Library/Application Support/Dicticus/DebugRecordings/
//   overlay-YYYY-MM-DD.jsonl
// Retention: 14 days, purged once per launch.

#if DEBUG_RECORDER

import Foundation

public actor OverlayProbe {

    public static let shared = OverlayProbe()

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

    public func recordShow(seq: Int, anchorSource: String, flipped: Bool, frame: [Double], visibleFrame: [Double]) {
        write([
            "event": "overlay_show",
            "seq": seq,
            "anchor_source": anchorSource,
            "flipped": flipped,
            "frame": frame,
            "visible_frame": visibleFrame
        ])
    }

    public func recordHide(seq: Int, reason: String, shownMs: Double) {
        write([
            "event": "overlay_hide",
            "seq": seq,
            "reason": reason,
            "shown_ms": shownMs
        ])
    }

    public func recordSession(
        seq: Int,
        ticks: Int,
        published: Int,
        cancelledInFlight: Bool,
        drainMs: Double,
        decodeMsP50: Double,
        decodeMsMax: Double
    ) {
        write([
            "event": "preview_session",
            "seq": seq,
            "ticks": ticks,
            "published": published,
            "cancelled_in_flight": cancelledInFlight,
            "drain_ms": drainMs,
            "decode_ms_p50": decodeMsP50,
            "decode_ms_max": decodeMsMax
        ])
    }

    func recordSession(stats: LivePreviewSession.Stats, seq: Int) {
        let ms = stats.decodeDurations.map { Self.milliseconds($0) }.sorted()
        recordSession(
            seq: seq,
            ticks: stats.ticks,
            published: stats.published,
            cancelledInFlight: stats.cancelledInFlight,
            drainMs: Self.milliseconds(stats.drainDuration),
            decodeMsP50: ms.isEmpty ? 0 : ms[ms.count / 2],
            decodeMsMax: ms.last ?? 0
        )
    }

    nonisolated static func milliseconds(_ d: Duration) -> Double {
        Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }

    // MARK: - Plumbing (mirrors LlmLifecycleProbe)

    private func write(_ fields: [String: Any]) {
        ensureDirectory()
        purgeIfNeeded()
        var obj = fields
        obj["ts"] = Self.iso8601Timestamp()
        appendJsonl(obj)
    }

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func currentJsonlURL() -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return directoryURL.appendingPathComponent("overlay-\(f.string(from: Date())).jsonl")
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
        for entry in entries where entry.lastPathComponent.hasPrefix("overlay-") {
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
