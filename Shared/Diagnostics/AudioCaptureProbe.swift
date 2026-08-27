// AudioCaptureProbe — Spike 008 diagnostic for end-of-utterance clipping.
//
// COMPILED OUT unless built with `-D DEBUG_RECORDER` (same gate as DebugRecorder).
// Never present in the public Release / GitHub artifact.
//
// Splits the two clipping hypotheses for a single reproduced clip:
//   (A) capture-cut   — AVAudioEngine.stop() dropped the in-flight tap buffer
//   (B) ASR tail-drop — Parakeet TDT under-decoded the final un-padded chunk
//
// On a suspected clip (ASR text not ending in terminal punctuation) it appends one
// JSONL line recording the decode's timing, sample counts, duration and a
// trailing-silence estimate for the 16kHz buffer handed to ASR, plus the caller's
// re-transcription of that same buffer with trailing silence appended:
//   - near-zero trailing silence + padded recovers tail → (A) capture-cut
//   - healthy trailing silence  + padded still clipped  → (B) ASR tail-drop
//
// Audio dumping was removed on 2026-08-27 (quick task 260827-81z) because the
// corpus was complete; this probe no longer writes any audio file to disk. The
// 187 captures gathered before that date were moved by the user to
// ~/Library/Application Support/Dicticus/ReplayCorpus/ as a preserved experiment
// corpus and are untouched by this probe.
//
// Output: ~/Library/Application Support/Dicticus/DebugRecordings/
//   capture-YYYY-MM-DD.jsonl   (one line per suspected clip)
// Retention: 14 days, purged once per launch.

#if DEBUG_RECORDER

import Foundation

public actor AudioCaptureProbe {

    public static let shared = AudioCaptureProbe()

    private let directoryURL: URL
    private let retentionDays: Int = 14
    private var hasPurgedThisLaunch = false
    private let sampleRate: Double = 16000

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

    /// True when the ASR text shows the clip signature (does not end on terminal
    /// punctuation). Caller uses this to decide whether to pay for the padded
    /// re-transcribe — keeps clean recordings at single-transcribe latency.
    public nonisolated static func looksClipped(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = t.last else { return false }
        return !".!?\"”)".contains(last)
    }

    /// Record one suspected clip: dump the 16kHz buffer to WAV and append a JSONL line.
    /// `paddedText` is the re-transcription of the same buffer + trailing silence (nil if not run).
    public func record(
        samples16k: [Float],
        rawSampleCount: Int,
        hwSampleRate: Double,
        unpaddedText: String,
        paddedText: String?
    ) {
        ensureDirectory()
        purgeIfNeeded()

        let ts = Self.iso8601Timestamp()

        let durationS = Double(samples16k.count) / sampleRate
        let trailingSilenceMs = Self.trailingSilenceMs(samples16k, sampleRate: sampleRate)
        let recovered = paddedText.map { $0.count > unpaddedText.count }

        let line: [String: Any] = [
            "ts": ts,
            "hw_sample_rate": hwSampleRate,
            "n_samples_raw": rawSampleCount,
            "n_samples_16k": samples16k.count,
            "duration_s": durationS,
            "trailing_silence_ms": trailingSilenceMs,
            "raw_unpadded": unpaddedText,
            "raw_padded": paddedText ?? NSNull(),
            "padded_recovered_tail": recovered ?? NSNull()
        ]
        appendJsonl(line)
    }

    // MARK: - Trailing-silence estimate (RMS envelope, no VAD-internal dependency)

    /// Milliseconds of low-energy audio at the END of the buffer. Near-zero means
    /// the last word sits at the very edge → capture likely cut it (A). A healthy
    /// tail (>~250ms) with a still-clipped transcript points at ASR tail-drop (B).
    private static func trailingSilenceMs(_ samples: [Float], sampleRate: Double) -> Double {
        guard !samples.isEmpty else { return 0 }
        let win = max(1, Int(sampleRate * 0.02))   // 20ms frames
        var peak: Float = 0
        for s in samples { peak = max(peak, abs(s)) }
        guard peak > 0 else { return Double(samples.count) / sampleRate * 1000 }
        let floorThresh = peak * 0.05               // 5% of peak = "silence"
        var trailing = 0
        var i = samples.count
        while i > 0 {
            let lo = max(0, i - win)
            var rms: Float = 0
            for j in lo..<i { rms += samples[j] * samples[j] }
            rms = (rms / Float(i - lo)).squareRoot()
            if rms > floorThresh { break }
            trailing += (i - lo)
            i = lo
        }
        return Double(trailing) / sampleRate * 1000
    }

    // MARK: - Plumbing (mirrors DebugRecorder)

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func currentJsonlURL() -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return directoryURL.appendingPathComponent("capture-\(f.string(from: Date())).jsonl")
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
        for entry in entries where entry.lastPathComponent.hasPrefix("capture-") {
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
