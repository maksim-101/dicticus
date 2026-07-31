// DiscardProbe — debug-session diagnostic for the silent discard paths in
// TranscriptionService.stopRecordingAndTranscribe() / IOSTranscriptionService's
// twin (whisper-dictation-dropout debug session, 2026-07-05).
//
// COMPILED OUT unless built with `-D DEBUG_RECORDER` (same gate as DebugRecorder
// and AudioCaptureProbe). Never present in the public Release / GitHub artifact.
//
// All silence-defense layers plus the empty-result guard are silent by design
// (D-02/D-16, HotkeyManager.swift catch block) — the user intentionally gets no
// notification for a legitimate short/silent press. That silence also means
// zero footprint in any other log when a layer misfires on REAL speech (or fails
// to fire on true silence). This probe exists purely to observe which layer
// fires and why, without changing the silent UX.
//
// Cycle 1 (Layer 3 hypothesis, REFUTED): NoSpeechDiscard.looksLikeSilence checks
// noSpeechProb alone; WhisperKit's own documented silence formula
// (Configurations.swift) is noSpeechProb > threshold AND avgLogProb <
// logProbThreshold. Recording avgLogProb per segment alongside noSpeechProb
// (the `segments` field below) lets that hypothesis be tested, but the actual
// root cause turned out to be the old fixed-threshold EnergyVAD pre-filter,
// which was removed entirely (Option c).
//
// Cycle 2: removing the EnergyVAD pre-filter fixed the dropout but regressed
// D-09 — Whisper's CONFIDENT silence hallucinations ("Thank you") have a LOW
// noSpeechProb, so Layer 3 cannot catch them. AdaptiveVoiceGate reintroduces
// an input-energy gate calibrated to each clip's own noise floor. The
// `gateNoiseFloor`/`gateThreshold` fields capture that gate's decision on the
// discard path ("silenceOnly_energyGate") — the ongoing regression net. A
// temporary pass-path probe ("voiceGate_pass") also logged PASSING clips
// during this cycle, to observe how much headroom quiet-speech presses had
// above the new threshold before trusting the constants; it was removed
// 2026-07-05 after on-device verification confirmed both directions
// (silence discarded, quiet/normal speech transcribed).
//
// Cycle 3 (quick task 260719-9a6, MEASURE-FIRST): the discard paths above were
// always the only place per-segment noSpeechProb/avgLogProb got logged — a
// SUCCESSFUL transcription never wrote anything, so a mid-utterance ASR
// phantom (a fabricated clause inserted during a pause, distinct from D-09's
// whole-clip silence hallucination) had no observable per-segment signal to
// investigate. `reason: "pass"` is a new record() call on the pass path
// (TranscriptionService.swift/IOSTranscriptionService.swift, right after the
// no-speech discard guard) that logs every segment of every kept
// transcription through this same writer, so a future session can check
// whether a phantom segment is separable from real speech by its own
// noSpeechProb/avgLogProb. `SegmentInfo.startSeconds`/`endSeconds` were added
// alongside it (both optional, default nil) to carry each segment's position
// in the clip when available.
//
// Output: ~/Library/Application Support/Dicticus/DebugRecordings/discard-YYYY-MM-DD.jsonl
// Retention: 14 days, purged once per launch.

#if DEBUG_RECORDER

import Foundation

public actor DiscardProbe {

    public static let shared = DiscardProbe()

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

    /// One segment's silence-relevant fields, captured at Layer 3.
    public struct SegmentInfo: Sendable {
        public let text: String
        public let noSpeechProb: Float
        public let avgLogProb: Float
        /// Segment position in the clip, when the caller has it (e.g. WhisperKit's
        /// TranscriptionSegment.start/.end). Optional so existing discard-path call
        /// sites (which never captured this) compile unchanged.
        public let startSeconds: Float?
        public let endSeconds: Float?

        public init(text: String, noSpeechProb: Float, avgLogProb: Float, startSeconds: Float? = nil, endSeconds: Float? = nil) {
            self.text = text
            self.noSpeechProb = noSpeechProb
            self.avgLogProb = avgLogProb
            self.startSeconds = startSeconds
            self.endSeconds = endSeconds
        }
    }

    /// Record one silent discard event. All parameters besides `reason` and
    /// `platform` are optional because each call site has different data
    /// available at the point of recording.
    public func record(
        reason: String,
        platform: String,
        rawSampleCount: Int,
        resampledSampleCount: Int,
        hwSampleRate: Double,
        durationSeconds: Float,
        rms: Float? = nil,
        peak: Float? = nil,
        vadFrameCount: Int? = nil,
        vadTrueFrameCount: Int? = nil,
        vadMaxFrameEnergy: Float? = nil,
        gateNoiseFloor: Float? = nil,
        gateThreshold: Float? = nil,
        segments: [SegmentInfo]? = nil
    ) {
        ensureDirectory()
        purgeIfNeeded()

        var line: [String: Any] = [
            "ts": Self.iso8601Timestamp(),
            "reason": reason,
            "platform": platform,
            "raw_sample_count": rawSampleCount,
            "resampled_sample_count": resampledSampleCount,
            "hw_sample_rate": hwSampleRate,
            "duration_s": durationSeconds
        ]
        if let rms { line["rms"] = rms }
        if let peak { line["peak"] = peak }
        if let vadFrameCount { line["vad_frame_count"] = vadFrameCount }
        if let vadTrueFrameCount { line["vad_true_frame_count"] = vadTrueFrameCount }
        if let vadMaxFrameEnergy { line["vad_max_frame_energy"] = vadMaxFrameEnergy }
        if let gateNoiseFloor { line["gate_noise_floor"] = gateNoiseFloor }
        if let gateThreshold { line["gate_threshold"] = gateThreshold }
        if let segments {
            line["segment_count"] = segments.count
            line["segments"] = segments.map { seg -> [String: Any] in
                var segLine: [String: Any] = [
                    "text": seg.text,
                    "no_speech_prob": seg.noSpeechProb,
                    "avg_log_prob": seg.avgLogProb
                ]
                if let startSeconds = seg.startSeconds { segLine["start_s"] = startSeconds }
                if let endSeconds = seg.endSeconds { segLine["end_s"] = endSeconds }
                return segLine
            }
        }

        appendJsonl(line)
    }

    // MARK: - Plumbing (mirrors AudioCaptureProbe)

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func currentJsonlURL() -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return directoryURL.appendingPathComponent("discard-\(f.string(from: Date())).jsonl")
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
        for entry in entries where entry.lastPathComponent.hasPrefix("discard-") {
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
