// DebugRecorder — local-only engineering diagnostics for the cleanup pipeline.
//
// COMPILED OUT in any build that doesn't pass `-D DEBUG_RECORDER` (i.e. the
// public `Dicticus` scheme used by `scripts/build-dmg.sh` and the GitHub
// Release artifact). The whole file becomes empty when the flag is absent;
// no symbols, no JSON encoder, no Application Support directory access.
//
// Captures full LLM payloads (assembled prompt, raw pre-gate output, sampler
// params, per-step intermediates and latencies) to JSONL on disk for offline
// replay of failures like the "T"/"W" degenerate-collapse bug. Distinct from
// HistoryService, which persists user-facing transcripts only.
//
// Output: ~/Library/Application Support/Dicticus/DebugRecordings/cleanup-YYYY-MM-DD.jsonl
// Retention: 14 days, purged once per launch.

#if DEBUG_RECORDER

import Foundation

// MARK: - Record schema

public struct DebugCleanupRecord: Codable, Sendable {
    public let ts: String
    public let session_id: String
    public let lang: String
    public let lang_used: String            // Phase 25.1-01: alias of `lang` so jq queries against either field name produce correct results (closes 25-04 §Gap 1)
    public let mode: String
    public let model: ModelInfo
    public let sampler: SamplerInfo
    public let steps: Steps
    /// LLM context targeting hints (input-side dictionary key matches). Narrowed in Phase 27: no longer overloaded with actually-applied replacements — see dictionary_replacements.
    public let dictionary_context_keys: [String]
    public let dictionary_replacements: [DictionaryReplacementEntry]
    public let dictionary_blocked: [DictionaryBlockedEntry]
    public let anomaly: Anomaly
    public let emission_counter: Int        // Phase 25.1-01: monotonic per process — multi-day capture can prove dual-emission fired on every cycle (closes 25-04 §Gap 2)
    public let prompt_version: String       // Phase 28 R3 (Plan 28-01): prompt variant tag for JSONL analysis; defaults to "v19d" on new records.
    /// Phase 38 Plan 01 (CTXFMT-02): the frontmost app's bundle ID captured
    /// at hotkey press-time. Local-only diagnostics — never sent to any
    /// network endpoint. `nil` when absent (e.g. no frontmost app, iOS, or
    /// pre-Phase-38 JSONL).
    public let detected_bundle_id: String?
    /// Phase 38 Plan 01 (D-10, CTXFMT-01): the raw value of the
    /// `DictationContext` resolved for this run. `nil` on pre-Phase-38 JSONL.
    public let resolved_context: String?

    // Phase 27 WR-02: custom decoder tolerates pre-Phase-27 JSONL where the
    // dictionary_replacements / dictionary_blocked keys are absent. Both
    // default to `[]` on missing-key, matching the encode-as-`[]` contract
    // pinned by DebugCleanupRecordCodableTests.testDebugCleanupRecordCodableRoundTrip_DefaultEmpty.
    // Synthesized encoder (Codable) is unchanged and continues to emit the
    // fields explicitly — only decode is relaxed.
    private enum CodingKeys: String, CodingKey {
        case ts, session_id, lang, lang_used, mode, model, sampler, steps
        case dictionary_context_keys, dictionary_replacements, dictionary_blocked
        case anomaly, emission_counter, prompt_version
        case detected_bundle_id, resolved_context
    }

    public init(
        ts: String,
        session_id: String,
        lang: String,
        lang_used: String,
        mode: String,
        model: ModelInfo,
        sampler: SamplerInfo,
        steps: Steps,
        dictionary_context_keys: [String],
        dictionary_replacements: [DictionaryReplacementEntry],
        dictionary_blocked: [DictionaryBlockedEntry],
        anomaly: Anomaly,
        emission_counter: Int,
        prompt_version: String = "v19d",
        detected_bundle_id: String? = nil,
        resolved_context: String? = nil
    ) {
        self.ts = ts
        self.session_id = session_id
        self.lang = lang
        self.lang_used = lang_used
        self.mode = mode
        self.model = model
        self.sampler = sampler
        self.steps = steps
        self.dictionary_context_keys = dictionary_context_keys
        self.dictionary_replacements = dictionary_replacements
        self.dictionary_blocked = dictionary_blocked
        self.anomaly = anomaly
        self.emission_counter = emission_counter
        self.prompt_version = prompt_version
        self.detected_bundle_id = detected_bundle_id
        self.resolved_context = resolved_context
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.ts = try c.decode(String.self, forKey: .ts)
        self.session_id = try c.decode(String.self, forKey: .session_id)
        self.lang = try c.decode(String.self, forKey: .lang)
        self.lang_used = try c.decode(String.self, forKey: .lang_used)
        self.mode = try c.decode(String.self, forKey: .mode)
        self.model = try c.decode(ModelInfo.self, forKey: .model)
        self.sampler = try c.decode(SamplerInfo.self, forKey: .sampler)
        self.steps = try c.decode(Steps.self, forKey: .steps)
        self.dictionary_context_keys = try c.decode([String].self, forKey: .dictionary_context_keys)
        // Phase 27 WR-02: tolerate missing keys in pre-Phase-27 JSONL.
        self.dictionary_replacements = try c.decodeIfPresent([DictionaryReplacementEntry].self, forKey: .dictionary_replacements) ?? []
        self.dictionary_blocked = try c.decodeIfPresent([DictionaryBlockedEntry].self, forKey: .dictionary_blocked) ?? []
        self.anomaly = try c.decode(Anomaly.self, forKey: .anomaly)
        self.emission_counter = try c.decode(Int.self, forKey: .emission_counter)
        // Phase 28 R3 (Plan 28-01): backward-compat decode for pre-Phase-28 JSONL — default to "v19c" when key absent. Mirrors Phase 27 WR-02 pattern at L91-93.
        self.prompt_version = try c.decodeIfPresent(String.self, forKey: .prompt_version) ?? "v19c"
        // Phase 38 Plan 01: tolerant decode for pre-Phase-38 JSONL — both default to nil when absent.
        self.detected_bundle_id = try c.decodeIfPresent(String.self, forKey: .detected_bundle_id) ?? nil
        self.resolved_context = try c.decodeIfPresent(String.self, forKey: .resolved_context) ?? nil
    }

    public struct ModelInfo: Codable, Sendable {
        public let name: String
        public let sha256_prefix: String?
    }

    public struct SamplerInfo: Codable, Sendable {
        public let temp: Double
        public let top_k: Int
        public let top_p: Double
        public let max_tokens: Int
        public let seed: UInt32?
    }

    public struct StepEntry: Codable, Sendable {
        public let text: String
        public let ms: Double
    }

    public struct LLMPromptEntry: Codable, Sendable {
        public let text: String
        public let tokens_est: Int
    }

    public struct LLMRawEntry: Codable, Sendable {
        public let text: String
        public let ms: Double
    }

    /// Phase 44 Plan 11 (D-11): the wire form of `EditGuard.ClassifiedEdit` —
    /// one classified edit, ready to serialize into `GateEntry.edits`.
    /// Field names/types are a direct passthrough of `ClassifiedEdit` so no
    /// translation layer is needed at the call site.
    public struct EditRecord: Codable, Sendable {
        public let kind: String
        public let from: String?
        public let to: String?
        public let accepted: Bool
        public let accept_class: String?
        public let reject_class: String?

        public init(
            kind: String,
            from: String?,
            to: String?,
            accepted: Bool,
            accept_class: String?,
            reject_class: String?
        ) {
            self.kind = kind
            self.from = from
            self.to = to
            self.accepted = accepted
            self.accept_class = accept_class
            self.reject_class = reject_class
        }
    }

    /// Phase 44 Plan 11 (D-11 forensics): `edits`, `fail_closed_reason`,
    /// `accepted_by_class`, and `rejected_by_class` are Plan 11 additions —
    /// every one of them is OPTIONAL. `GateEntry` is `Codable` and the 44-01
    /// corpus snapshot's historical JSONL records were written before these
    /// fields existed; a required new field would break every historical
    /// decode and destroy the phase's own evidence base
    /// (`testHistoricalGateEntriesStillDecode` proves this holds for ≥50 real
    /// records). `verdict`'s meaning is unchanged in shape but its semantics
    /// widen: `"passed"` when zero edits were rejected AND no fail-closed
    /// path fired; `"rejected"` otherwise — so existing corpus queries that
    /// key off `verdict` keep working unmodified. `edit_distance` stays nil;
    /// the edit guard does not compute a scalar distance (D-01: token-level
    /// diff, never a similarity ratio).
    public struct GateEntry: Codable, Sendable {
        public let text: String
        public let verdict: String
        public let edit_distance: Double?
        public let ms: Double
        public let edits: [EditRecord]?
        public let fail_closed_reason: String?
        public let accepted_by_class: [String: Int]?
        public let rejected_by_class: [String: Int]?

        public init(
            text: String,
            verdict: String,
            edit_distance: Double?,
            ms: Double,
            edits: [EditRecord]? = nil,
            fail_closed_reason: String? = nil,
            accepted_by_class: [String: Int]? = nil,
            rejected_by_class: [String: Int]? = nil
        ) {
            self.text = text
            self.verdict = verdict
            self.edit_distance = edit_distance
            self.ms = ms
            self.edits = edits
            self.fail_closed_reason = fail_closed_reason
            self.accepted_by_class = accepted_by_class
            self.rejected_by_class = rejected_by_class
        }
    }

    public struct Steps: Codable, Sendable {
        public let raw: StepEntry
        public let post_dict: StepEntry
        public let post_itn: StepEntry
        public let post_swiss: StepEntry
        public let post_rules: StepEntry
        public let llm_prompt: LLMPromptEntry?
        public let llm_raw: LLMRawEntry?
        public let post_gate: GateEntry?
        public let post_swiss_num: StepEntry
    }

    public struct Anomaly: Codable, Sendable {
        public let degenerate_collapse: Bool
        public let very_short_output: Bool
    }

    public struct DictionaryReplacementEntry: Codable, Sendable {
        public let key: String
        public let from: String
        public let to: String

        public init(key: String, from: String, to: String) {
            self.key = key
            self.from = from
            self.to = to
        }
    }

    public struct DictionaryBlockedEntry: Codable, Sendable {
        public let key: String
        public let from: String
        public let to: String
        public let ratio: Double

        public init(key: String, from: String, to: String, ratio: Double) {
            self.key = key
            self.from = from
            self.to = to
            self.ratio = ratio
        }
    }
}

// MARK: - Recorder actor

public actor DebugRecorder {

    public static let shared = DebugRecorder()

    private let directoryURL: URL
    private let retentionDays: Int = 14
    private var hasPurgedThisLaunch = false
    private var emissionCounter: Int = 0

    /// Test-only — last record handed to record(_:). Always nil in production builds (file is fully gated by #if DEBUG_RECORDER).
    public private(set) var lastRecordForTests: DebugCleanupRecord?

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

    public func nextEmissionCounter() -> Int {
        emissionCounter += 1
        return emissionCounter
    }

    public func record(_ rec: DebugCleanupRecord) {
        lastRecordForTests = rec
        ensureDirectory()
        purgeIfNeeded()

        let url = currentFileURL()
        guard let line = encodeLine(rec) else { return }
        appendLine(line, to: url)
    }

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    private func currentFileURL() -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        let day = f.string(from: Date())
        return directoryURL.appendingPathComponent("cleanup-\(day).jsonl")
    }

    private func encodeLine(_ rec: DebugCleanupRecord) -> Data? {
        let enc = JSONEncoder()
        enc.outputFormatting = [.withoutEscapingSlashes]
        guard var data = try? enc.encode(rec) else { return nil }
        data.append(0x0A)  // newline (JSONL)
        return data
    }

    private func appendLine(_ data: Data, to url: URL) {
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
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        for entry in entries where entry.pathExtension == "jsonl" {
            if let mod = try? entry.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate,
               mod < cutoff {
                try? fm.removeItem(at: entry)
            }
        }
    }

    public nonisolated static func iso8601Timestamp(_ date: Date = Date()) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }
}

// MARK: - In-process trace handed from CleanupService → TextProcessingService.

/// Captured by CleanupService at the end of `cleanup(...)`; consumed by
/// TextProcessingService to build the on-disk record. Sendable across the
/// MainActor → actor hop into DebugRecorder.
public struct CleanupServiceTrace: Sendable {
    public let prompt: String
    public let llmRaw: String
    public let llmMs: Double
    public let modelName: String
    public let samplerTemp: Double
    public let samplerTopK: Int
    public let samplerTopP: Double
    public let samplerMaxTokens: Int

    public init(
        prompt: String,
        llmRaw: String,
        llmMs: Double,
        modelName: String,
        samplerTemp: Double,
        samplerTopK: Int,
        samplerTopP: Double,
        samplerMaxTokens: Int
    ) {
        self.prompt = prompt
        self.llmRaw = llmRaw
        self.llmMs = llmMs
        self.modelName = modelName
        self.samplerTemp = samplerTemp
        self.samplerTopK = samplerTopK
        self.samplerTopP = samplerTopP
        self.samplerMaxTokens = samplerMaxTokens
    }
}

#endif
