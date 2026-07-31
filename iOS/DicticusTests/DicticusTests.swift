import XCTest
@testable import Dicticus

final class DicticusTests: XCTestCase {
    func testPlaceholder() throws {
        XCTAssertTrue(true)
    }
}

#if DEBUG_RECORDER
/// Phase 27-02: Codable round-trip contract for DebugCleanupRecord with the
/// new dictionary_replacements + dictionary_blocked fields (D-06, D-07).
///
/// Pins the JSONL schema: empty arrays must serialize to literal `[]`
/// (not absent keys) so downstream log analyses can rely on every record
/// carrying both fields. Populated entries must round-trip with full field
/// fidelity including the Double-valued `ratio` (within accuracy 0.001).
///
/// Cross-platform parity (feedback_cleanup_cross_platform_parity): byte-
/// identical between macOS and iOS test targets.
@MainActor
final class DebugCleanupRecordCodableTests: XCTestCase {

    func testDebugCleanupRecordCodableRoundTrip_DefaultEmpty() {
        let record = DebugCleanupRecord(
            ts: "2026-05-26T12:00:00.000Z",
            session_id: "test-session",
            lang: "en",
            lang_used: "en",
            mode: "plain",
            model: DebugCleanupRecord.ModelInfo(name: "test", sha256_prefix: nil),
            sampler: DebugCleanupRecord.SamplerInfo(temp: 0.1, top_k: 1, top_p: 1.0, max_tokens: 1, seed: nil),
            steps: DebugCleanupRecord.Steps(
                raw: DebugCleanupRecord.StepEntry(text: "", ms: 0),
                post_dict: DebugCleanupRecord.StepEntry(text: "", ms: 0),
                post_itn: DebugCleanupRecord.StepEntry(text: "", ms: 0),
                post_swiss: DebugCleanupRecord.StepEntry(text: "", ms: 0),
                post_rules: DebugCleanupRecord.StepEntry(text: "", ms: 0),
                llm_prompt: nil,
                llm_raw: nil,
                post_gate: nil,
                post_swiss_num: DebugCleanupRecord.StepEntry(text: "", ms: 0)
            ),
            dictionary_context_keys: [],
            dictionary_replacements: [],
            dictionary_blocked: [],
            anomaly: DebugCleanupRecord.Anomaly(degenerate_collapse: false, very_short_output: false),
            emission_counter: 0
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try! encoder.encode(record)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"dictionary_replacements\":[]"),
            "Phase 27-02: empty dictionary_replacements must serialize to literal [] (not absent) — got: \(json)")
        XCTAssertTrue(json.contains("\"dictionary_blocked\":[]"),
            "Phase 27-02: empty dictionary_blocked must serialize to literal [] (not absent) — got: \(json)")

        let decoder = JSONDecoder()
        let roundtrip = try! decoder.decode(DebugCleanupRecord.self, from: data)
        XCTAssertTrue(roundtrip.dictionary_replacements.isEmpty)
        XCTAssertTrue(roundtrip.dictionary_blocked.isEmpty)
    }

    func testDebugCleanupRecordCodableRoundTrip_WithEntries() {
        let repl = DebugCleanupRecord.DictionaryReplacementEntry(key: "Dicticos", from: "Dicticos", to: "Dicticus")
        let block = DebugCleanupRecord.DictionaryBlockedEntry(key: "Gemini", from: "remind", to: "Gemini", ratio: 0.333)
        let steps = DebugCleanupRecord.Steps(
            raw: DebugCleanupRecord.StepEntry(text: "", ms: 0),
            post_dict: DebugCleanupRecord.StepEntry(text: "", ms: 0),
            post_itn: DebugCleanupRecord.StepEntry(text: "", ms: 0),
            post_swiss: DebugCleanupRecord.StepEntry(text: "", ms: 0),
            post_rules: DebugCleanupRecord.StepEntry(text: "", ms: 0),
            llm_prompt: nil,
            llm_raw: nil,
            post_gate: nil,
            post_swiss_num: DebugCleanupRecord.StepEntry(text: "", ms: 0)
        )
        let anomaly = DebugCleanupRecord.Anomaly(degenerate_collapse: false, very_short_output: false)
        let record = DebugCleanupRecord(
            ts: "2026-05-26T12:00:00.000Z",
            session_id: "test-session",
            lang: "en",
            lang_used: "en",
            mode: "plain",
            model: DebugCleanupRecord.ModelInfo(name: "test", sha256_prefix: nil),
            sampler: DebugCleanupRecord.SamplerInfo(temp: 0.1, top_k: 1, top_p: 1.0, max_tokens: 1, seed: nil),
            steps: steps,
            dictionary_context_keys: [],
            dictionary_replacements: [repl],
            dictionary_blocked: [block],
            anomaly: anomaly,
            emission_counter: 0
        )
        let data = try! JSONEncoder().encode(record)
        let roundtrip = try! JSONDecoder().decode(DebugCleanupRecord.self, from: data)
        XCTAssertEqual(roundtrip.dictionary_replacements.count, 1)
        XCTAssertEqual(roundtrip.dictionary_replacements[0].key, "Dicticos")
        XCTAssertEqual(roundtrip.dictionary_replacements[0].from, "Dicticos")
        XCTAssertEqual(roundtrip.dictionary_replacements[0].to, "Dicticus")
        XCTAssertEqual(roundtrip.dictionary_blocked.count, 1)
        XCTAssertEqual(roundtrip.dictionary_blocked[0].key, "Gemini")
        XCTAssertEqual(roundtrip.dictionary_blocked[0].from, "remind")
        XCTAssertEqual(roundtrip.dictionary_blocked[0].to, "Gemini")
        XCTAssertEqual(roundtrip.dictionary_blocked[0].ratio, 0.333, accuracy: 0.001)
    }

    /// Phase 27 WR-02: pre-Phase-27 JSONL lines lack `dictionary_replacements` and
    /// `dictionary_blocked` keys entirely. The decoder must tolerate their absence
    /// and default both to `[]`, otherwise external replay tooling cannot read
    /// historical capture files written before the schema extension landed.
    func testDebugCleanupRecordDecode_PrePhase27_TolerantToMissingDictionaryFields() {
        // Synthetic pre-Phase-27 JSONL: no dictionary_replacements / dictionary_blocked keys.
        let json = """
        {
          "ts": "2026-05-20T12:00:00.000Z",
          "session_id": "legacy-session",
          "lang": "en",
          "lang_used": "en",
          "mode": "plain",
          "model": { "name": "test", "sha256_prefix": null },
          "sampler": { "temp": 0.1, "top_k": 1, "top_p": 1.0, "max_tokens": 1, "seed": null },
          "steps": {
            "raw": { "text": "", "ms": 0 },
            "post_dict": { "text": "", "ms": 0 },
            "post_itn": { "text": "", "ms": 0 },
            "post_swiss": { "text": "", "ms": 0 },
            "post_rules": { "text": "", "ms": 0 },
            "llm_prompt": null,
            "llm_raw": null,
            "post_gate": null,
            "post_swiss_num": { "text": "", "ms": 0 }
          },
          "dictionary_context_keys": [],
          "anomaly": { "degenerate_collapse": false, "very_short_output": false },
          "emission_counter": 0
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        let record = try! decoder.decode(DebugCleanupRecord.self, from: json)
        XCTAssertTrue(record.dictionary_replacements.isEmpty,
            "Phase 27 WR-02: missing dictionary_replacements must default to [] (not fail decode)")
        XCTAssertTrue(record.dictionary_blocked.isEmpty,
            "Phase 27 WR-02: missing dictionary_blocked must default to [] (not fail decode)")
        XCTAssertEqual(record.ts, "2026-05-20T12:00:00.000Z")
        XCTAssertEqual(record.session_id, "legacy-session")
    }

    // MARK: - Phase 28 R3: prompt_version round-trip tests

    func testDebugCleanupRecordCodableRoundTrip_PromptVersionDefault_v19d() {
        // Construct with default prompt_version; encode; decode; assert "v19d".
        let record = DebugCleanupRecord(
            ts: "2026-05-27T05:00:00.000Z",
            session_id: "test-session",
            lang: "en",
            lang_used: "en",
            mode: "cleanup",
            model: DebugCleanupRecord.ModelInfo(name: "gemma-4-e2b", sha256_prefix: nil),
            sampler: DebugCleanupRecord.SamplerInfo(temp: 0.1, top_k: 40, top_p: 0.9, max_tokens: 512, seed: nil),
            steps: DebugCleanupRecord.Steps(
                raw: DebugCleanupRecord.StepEntry(text: "hello", ms: 0),
                post_dict: DebugCleanupRecord.StepEntry(text: "hello", ms: 1),
                post_itn: DebugCleanupRecord.StepEntry(text: "hello", ms: 1),
                post_swiss: DebugCleanupRecord.StepEntry(text: "hello", ms: 0),
                post_rules: DebugCleanupRecord.StepEntry(text: "hello", ms: 0),
                llm_prompt: nil,
                llm_raw: nil,
                post_gate: nil,
                post_swiss_num: DebugCleanupRecord.StepEntry(text: "hello", ms: 0)
            ),
            dictionary_context_keys: [],
            dictionary_replacements: [],
            dictionary_blocked: [],
            anomaly: DebugCleanupRecord.Anomaly(degenerate_collapse: false, very_short_output: false),
            emission_counter: 1
            // prompt_version uses default "v19d"
        )
        let data = try! JSONEncoder().encode(record)
        let decoded = try! JSONDecoder().decode(DebugCleanupRecord.self, from: data)
        XCTAssertEqual(decoded.prompt_version, "v19d", "Default prompt_version must round-trip as 'v19d' (Phase 28 R3)")
    }

    func testDebugCleanupRecordCodableRoundTrip_ExplicitPromptVersion_v19c() {
        // Construct with explicit prompt_version "v19c"; encode; decode; assert "v19c".
        let record = DebugCleanupRecord(
            ts: "2026-05-27T05:00:00.000Z",
            session_id: "test-session",
            lang: "en",
            lang_used: "en",
            mode: "cleanup",
            model: DebugCleanupRecord.ModelInfo(name: "gemma-4-e2b", sha256_prefix: nil),
            sampler: DebugCleanupRecord.SamplerInfo(temp: 0.1, top_k: 40, top_p: 0.9, max_tokens: 512, seed: nil),
            steps: DebugCleanupRecord.Steps(
                raw: DebugCleanupRecord.StepEntry(text: "hello", ms: 0),
                post_dict: DebugCleanupRecord.StepEntry(text: "hello", ms: 1),
                post_itn: DebugCleanupRecord.StepEntry(text: "hello", ms: 1),
                post_swiss: DebugCleanupRecord.StepEntry(text: "hello", ms: 0),
                post_rules: DebugCleanupRecord.StepEntry(text: "hello", ms: 0),
                llm_prompt: nil,
                llm_raw: nil,
                post_gate: nil,
                post_swiss_num: DebugCleanupRecord.StepEntry(text: "hello", ms: 0)
            ),
            dictionary_context_keys: [],
            dictionary_replacements: [],
            dictionary_blocked: [],
            anomaly: DebugCleanupRecord.Anomaly(degenerate_collapse: false, very_short_output: false),
            emission_counter: 1,
            prompt_version: "v19c"
        )
        let data = try! JSONEncoder().encode(record)
        let decoded = try! JSONDecoder().decode(DebugCleanupRecord.self, from: data)
        XCTAssertEqual(decoded.prompt_version, "v19c", "Explicit prompt_version 'v19c' must round-trip correctly (Phase 28 R3)")
    }

    func testDebugCleanupRecordDecode_TolerantToMissingPromptVersion() {
        // Hand-craft a JSON dict matching pre-Phase-28 schema (no prompt_version key).
        // Decode via JSONDecoder; assert decoded.prompt_version == "v19c" (decodeIfPresent default).
        let json = """
        {
          "ts": "2026-05-25T04:00:00.000Z",
          "session_id": "legacy-session",
          "lang": "en",
          "lang_used": "en",
          "mode": "cleanup",
          "model": { "name": "gemma-4-e2b", "sha256_prefix": null },
          "sampler": { "temp": 0.1, "top_k": 40, "top_p": 0.9, "max_tokens": 512, "seed": null },
          "steps": {
            "raw": { "text": "test", "ms": 0 },
            "post_dict": { "text": "test", "ms": 0 },
            "post_itn": { "text": "test", "ms": 0 },
            "post_swiss": { "text": "test", "ms": 0 },
            "post_rules": { "text": "test", "ms": 0 },
            "llm_prompt": null,
            "llm_raw": null,
            "post_gate": null,
            "post_swiss_num": { "text": "test", "ms": 0 }
          },
          "dictionary_context_keys": [],
          "dictionary_replacements": [],
          "dictionary_blocked": [],
          "anomaly": { "degenerate_collapse": false, "very_short_output": false },
          "emission_counter": 1
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        let decoded = try! decoder.decode(DebugCleanupRecord.self, from: json)
        XCTAssertEqual(decoded.prompt_version, "v19c",
                       "Missing prompt_version key must decode as 'v19c' (Phase 28 R3 decodeIfPresent default, mirrors Phase 27 WR-02 pattern)")
    }
}
#endif
