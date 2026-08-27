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
// Cycle 4 (quick task 260825-q2f, HONEST SCHEMA): `SegmentInfo.noSpeechProb`
// was a fabricated constant, not a measurement. Root cause: `argmax-oss-swift`
// 1.0.0 `Sources/WhisperKit/Core/TextDecoder.swift:802` contains literally
// `let noSpeechProb: Float = 0 // TODO: implement no speech prob`, the sole
// writer of `DecodingResult.noSpeechProb`, which `SegmentSeeker.swift:134,178`
// then copies onto every `TranscriptionSegment`. The app-side mapping in
// TranscriptionService was never the defect — it faithfully forwarded a zero
// the SDK itself never computes. Verified 2026-08-25 against
// `raw.githubusercontent.com/argmaxinc/argmax-oss-swift/main`: the same stub
// line is still present on upstream `main`, so an SDK bump alone does not fix
// this. `noSpeechProb` is now `Float?` with no default, forcing every call
// site to be explicit, and is omitted from the JSONL entirely rather than
// written as 0 — an audit now reads absence plus a machine-readable
// `no_speech_prob_source` reason, not a silent fabrication. Two real
// per-segment signals WhisperKit does compute — `compressionRatio` (the
// classical repetitive-hallucination detector) and `temperature` — are added
// alongside it so the audit still gains signal instead of just losing one.
// A real value IS theoretically reachable without forking (a pass-through
// `LogitsFiltering` via the public `WhisperKitConfig(logitsFilters:)` hook
// reading softmax P(no-speech) at the post-SOT position), but the value is
// per decode *window* and, under `chunkingStrategy: .vad` with concurrent
// workers, the window-to-segment mapping is not recoverable from outside the
// SDK — recorded in `.planning/backlog/whisper-no-speech-prob-unavailable.md`
// rather than guessed. Scope guard: instrumentation only, no gating logic
// added or changed; confidence gating was measured and rejected in spike
// 260805-qx7.
//
// Cycle 5 (quick task 260826-8ec, UNIFORM ENERGY/VAD METRICS): the 7th confirmed live
// case landed 2026-08-26T03:53:35.649Z in discard-2026-08-26.jsonl — a 1.9s recording
// in which the user said nothing, decoded to a single segment "Thank you." with
// avg_log_prob -0.293 and compression_ratio 0.857, reason `pass`, and pasted at the
// cursor. That record carried NO energy fields at all: `rms`/`peak`/`vad_true_frame_count`
// previously appeared only on the `silenceOnly_energyGate` discard record, so the
// working hypothesis for a future rule — a genuine spoken "Thank you." has real speech
// frames, a hallucinated one has near-zero — could not be tested against the pass path,
// because the pass path never wrote the data. This cycle adds the same seven energy/VAD
// fields to all five discard-log reasons (`tooShort`, `silenceOnly_energyGate`,
// `silenceOnly_noSpeechDiscard`, `pass`, `noResult`) plus a record-level
// `energy_metrics_source` marker distinguishing values reused from the clip's live gate
// evaluation from values recomputed inside the probe block because the gate had not run
// yet. This cycle adds OBSERVATION ONLY — the discriminator it enables does not exist
// and is not proposed here; confidence gating was separately measured and rejected in
// spike 260805-qx7.
//
// Cycle 6 (quick task 260827-81z, BOILERPLATE-HALLUCINATION REASON): adds a sixth
// discard-log reason, `boilerplateHallucination`, for BoilerplateHallucination's
// whole-utterance closed-list exact-match discard (e.g. "Thank you.") on the macOS
// decode path. It carries the same energy/VAD fields as the other five reasons; the
// matched phrase itself is not a separate field — it is already visible in the
// record's `segments` text.
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
        /// No default value: the caller must state explicitly, at every construction
        /// site, whether a real value is available. WhisperKit 1.0.0 never populates
        /// this (see the cycle-4 header note above), so every current call site passes
        /// `nil` — but that is a call-site decision, not a silent struct default.
        public let noSpeechProb: Float?
        public let avgLogProb: Float
        /// Real per-segment signals WhisperKit does compute (TextDecoder.swift:794,
        /// :796-800), carried on TranscriptionSegment (Models.swift:582-584).
        /// `compressionRatio` is the classical repetitive-hallucination detector.
        public let compressionRatio: Float?
        public let temperature: Float?
        /// Segment position in the clip, when the caller has it (e.g. WhisperKit's
        /// TranscriptionSegment.start/.end). Optional so existing discard-path call
        /// sites (which never captured this) compile unchanged.
        public let startSeconds: Float?
        public let endSeconds: Float?

        public init(
            text: String,
            noSpeechProb: Float?,
            avgLogProb: Float,
            compressionRatio: Float? = nil,
            temperature: Float? = nil,
            startSeconds: Float? = nil,
            endSeconds: Float? = nil
        ) {
            self.text = text
            self.noSpeechProb = noSpeechProb
            self.avgLogProb = avgLogProb
            self.compressionRatio = compressionRatio
            self.temperature = temperature
            self.startSeconds = startSeconds
            self.endSeconds = endSeconds
        }
    }

    /// Machine-readable reason a `SegmentInfo.noSpeechProb` is nil, emitted at the
    /// record level as `no_speech_prob_source`. WhisperKit 1.0.0's decoder never
    /// computes this value (see the cycle-4 header note above) — this is the sole
    /// reason string in use today, defined once so call sites reference the constant
    /// rather than repeating the literal.
    public static let noSpeechProbUnavailable = "unavailable:whisperkit-1.0.0-decoder-stub"

    /// Machine-readable source marker for a record's energy/VAD fields, emitted at the
    /// record level as `energy_metrics_source` (quick task 260826-8ec). Four of the five
    /// call sites reuse `gateFrameEnergies`/`gateDecision` already computed by the live
    /// Layer 2 gate evaluation earlier in `transcribe()`; the `tooShort` site sits before
    /// the gate has been consulted and must recompute the same metrics purely to observe
    /// them. Defined once so call sites reference the constant rather than repeating a
    /// literal, and so an audit can tell a live-gate reuse apart from a pre-gate probe
    /// recompute instead of assuming they are the same measurement.
    public static let energyMetricsSourceLiveGate = "live_gate"
    public static let energyMetricsSourceProbeRecompute = "probe_recompute"

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
        segments: [SegmentInfo]? = nil,
        lowConfidenceShort: Bool? = nil,
        noSpeechProbSource: String? = nil,
        energyMetricsSource: String? = nil
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
        if let lowConfidenceShort { line["low_confidence_short"] = lowConfidenceShort }
        if let noSpeechProbSource { line["no_speech_prob_source"] = noSpeechProbSource }
        if let energyMetricsSource { line["energy_metrics_source"] = energyMetricsSource }
        if let segments {
            line["segment_count"] = segments.count
            line["segments"] = segments.map { seg -> [String: Any] in
                var segLine: [String: Any] = [
                    "text": seg.text,
                    "avg_log_prob": seg.avgLogProb
                ]
                if let noSpeechProb = seg.noSpeechProb { segLine["no_speech_prob"] = noSpeechProb }
                if let compressionRatio = seg.compressionRatio { segLine["compression_ratio"] = compressionRatio }
                if let temperature = seg.temperature { segLine["temperature"] = temperature }
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
