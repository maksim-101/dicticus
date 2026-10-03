#if DEBUG_RECORDER
import XCTest
@testable import Dicticus

/// Quick task 261003-jej: per-token WhisperKit logprobs and per-word confidence in the debug record.
/// Pure tests: no test here calls process() or DebugRecorder.record(), so the real corpus is untouched.
final class AsrTokenTraceTests: XCTestCase {

    private typealias Seg = DebugCleanupRecord.AsrSegment
    private typealias Trace = DebugCleanupRecord.AsrTokenTrace

    private let specialBegin = 50257

    private func decode(_ id: Int) -> String {
        switch id {
        case 100: return " Hello"
        case 200: return " wor"
        case 300: return "ld"
        default: return "<\(id)>"
        }
    }

    private func split(_ ids: [Int]) -> (words: [String], wordTokens: [[Int]]) {
        (words: [" Hello", " world"], wordTokens: [[100], [200, 300]])
    }

    func testSpecialTokensExcludedAndWordMeansComputed() {
        let tokens = [50258, 50259, 50360, 50364, 100, 200, 300, 50257]
        let lps: [[Int: Float]] = [
            [50258: 0], [50259: 0], [50360: 0], [50364: 0],
            [100: -0.5], [200: -1.0], [300: -0.25],
            [50257: 0],
        ]
        let seg = Seg.build(
            tokens: tokens, tokenLogProbs: lps, temperature: 0.2, specialTokenBegin: specialBegin,
            decodeToken: decode, splitWords: split
        )
        XCTAssertEqual(seg.temperature, 0.2, accuracy: 1e-6)
        XCTAssertEqual(seg.tokens.map(\.id), [100, 200, 300])
        XCTAssertEqual(seg.tokens.map(\.text), [" Hello", " wor", "ld"])
        XCTAssertEqual(seg.tokens[0].lp ?? 9, -0.5, accuracy: 1e-6)
        XCTAssertEqual(seg.tokens[1].lp ?? 9, -1.0, accuracy: 1e-6)
        XCTAssertEqual(seg.tokens[2].lp ?? 9, -0.25, accuracy: 1e-6)
        XCTAssertEqual(seg.words?.count, 2)
        XCTAssertEqual(seg.words?[0].text, " Hello")
        XCTAssertEqual(seg.words?[0].n, 1)
        XCTAssertEqual(seg.words?[0].p ?? 9, exp(Float(-0.5)), accuracy: 1e-6)
        XCTAssertEqual(seg.words?[1].text, " world")
        XCTAssertEqual(seg.words?[1].n, 2)
        XCTAssertEqual(seg.words?[1].p ?? 9, exp(Float(-0.625)), accuracy: 1e-6)
    }

    func testMissingLogprobKeepsTokenAndDropsWords() {
        // Token 200 is looked up under a different id: lp absent.
        let lps: [[Int: Float]] = [[100: -0.5], [999: -1.0], [300: -0.25]]
        let seg = Seg.build(
            tokens: [100, 200, 300], tokenLogProbs: lps, temperature: 0, specialTokenBegin: specialBegin,
            decodeToken: decode, splitWords: split
        )
        XCTAssertEqual(seg.tokens.map(\.id), [100, 200, 300])
        XCTAssertEqual(seg.tokens[1].text, " wor")
        XCTAssertNil(seg.tokens[1].lp)
        XCTAssertNotNil(seg.tokens[0].lp)
        XCTAssertNil(seg.words)
    }

    func testShortTokenLogProbsArrayLeavesTrailingLpNil() {
        let seg = Seg.build(
            tokens: [100, 200, 300], tokenLogProbs: [[100: -0.5]], temperature: 0, specialTokenBegin: specialBegin,
            decodeToken: decode, splitWords: split
        )
        XCTAssertEqual(seg.tokens.count, 3)
        XCTAssertNil(seg.tokens[1].lp)
        XCTAssertNil(seg.tokens[2].lp)
        XCTAssertNil(seg.words)
    }

    func testSplitCountShortByOneLeavesWordsNil() {
        let lps: [[Int: Float]] = [[100: -0.5], [200: -1.0], [300: -0.25]]
        let seg = Seg.build(
            tokens: [100, 200, 300], tokenLogProbs: lps, temperature: 0, specialTokenBegin: specialBegin,
            decodeToken: decode,
            splitWords: { _ in (words: [" Hello", " world"], wordTokens: [[100], [200]]) }
        )
        XCTAssertEqual(seg.tokens.count, 3)
        XCTAssertNil(seg.words)
    }

    func testSplitReorderedGroupLeavesWordsNil() {
        let lps: [[Int: Float]] = [[100: -0.5], [200: -1.0], [300: -0.25]]
        let seg = Seg.build(
            tokens: [100, 200, 300], tokenLogProbs: lps, temperature: 0, specialTokenBegin: specialBegin,
            decodeToken: decode,
            splitWords: { _ in (words: [" world", " Hello"], wordTokens: [[200, 300], [100]]) }
        )
        XCTAssertEqual(seg.tokens.map(\.id), [100, 200, 300])
        XCTAssertNil(seg.words)
    }

    func testOnlySpecialTokensGivesEmptyTokensAndNoWords() {
        var splitCalled = false
        let seg = Seg.build(
            tokens: [50258, 50257], tokenLogProbs: [[50258: 0], [50257: 0]], temperature: 0,
            specialTokenBegin: specialBegin, decodeToken: decode,
            splitWords: { _ in splitCalled = true; return (words: [], wordTokens: []) }
        )
        XCTAssertTrue(seg.tokens.isEmpty)
        XCTAssertNil(seg.words)
        XCTAssertFalse(splitCalled)
    }

    private func trace(_ ms: Double) -> Trace {
        Trace(ms: ms, segments: [])
    }

    func testStashMatchesByTextAndConsumesOnce() {
        var stash = AsrTokenStash()
        stash.stage(trace(1), rawText: "alpha")
        stash.stage(trace(2), rawText: "beta")
        XCTAssertEqual(stash.take(rawText: "beta")?.ms, 2)
        XCTAssertEqual(stash.take(rawText: "alpha")?.ms, 1)
        XCTAssertNil(stash.take(rawText: "alpha"))
    }

    func testStashMissLeavesEntriesUntouched() {
        var stash = AsrTokenStash()
        stash.stage(trace(1), rawText: "alpha")
        XCTAssertNil(stash.take(rawText: "gamma"))
        XCTAssertEqual(stash.take(rawText: "alpha")?.ms, 1)
    }

    func testStashDropsOldestBeyondCapacity() {
        var stash = AsrTokenStash()
        for i in 0...AsrTokenStash.capacity {
            stash.stage(trace(Double(i)), rawText: "t\(i)")
        }
        XCTAssertNil(stash.take(rawText: "t0"))
        XCTAssertEqual(stash.take(rawText: "t\(AsrTokenStash.capacity)")?.ms, Double(AsrTokenStash.capacity))
        XCTAssertEqual(stash.take(rawText: "t1")?.ms, 1)
    }

    // MARK: Codable

    private func makeRecord(asr: Trace?) -> DebugCleanupRecord {
        let e = { DebugCleanupRecord.StepEntry(text: "", ms: 0) }
        let steps = DebugCleanupRecord.Steps(
            raw: e(), post_dict: e(), post_itn: e(), post_swiss: e(), post_rules: e(),
            llm_prompt: nil, llm_raw: nil, post_gate: nil, post_swiss_num: e()
        )
        return DebugCleanupRecord(
            ts: "2026-10-03T12:00:00.000Z", session_id: "s", lang: "en", lang_used: "en", mode: "plain",
            model: .init(name: "test", sha256_prefix: nil),
            sampler: .init(temp: 0.1, top_k: 1, top_p: 1.0, max_tokens: 1, seed: nil),
            steps: steps,
            dictionary_context_keys: [], dictionary_replacements: [], dictionary_blocked: [],
            anomaly: .init(degenerate_collapse: false, very_short_output: false),
            emission_counter: 0,
            asr_tokens: asr
        )
    }

    func testRecordRoundTripWithTraceAndNoWordsKey() throws {
        let seg = Seg(
            temperature: 0.4,
            tokens: [
                .init(id: 100, text: " Hello", lp: -0.5),
                .init(id: 200, text: " wor", lp: nil),
            ],
            words: nil
        )
        let data = try JSONEncoder().encode(makeRecord(asr: Trace(ms: 2.5, segments: [seg])))
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"asr_tokens\""), json)
        XCTAssertFalse(json.contains("\"words\""), json)

        let back = try JSONDecoder().decode(DebugCleanupRecord.self, from: data)
        let t = try XCTUnwrap(back.asr_tokens)
        XCTAssertEqual(t.ms, 2.5, accuracy: 1e-9)
        XCTAssertEqual(t.segments.count, 1)
        XCTAssertEqual(t.segments[0].temperature, 0.4, accuracy: 1e-6)
        XCTAssertEqual(t.segments[0].tokens.map(\.id), [100, 200])
        XCTAssertEqual(t.segments[0].tokens.map(\.text), [" Hello", " wor"])
        XCTAssertEqual(t.segments[0].tokens[0].lp ?? 9, -0.5, accuracy: 1e-6)
        XCTAssertNil(t.segments[0].tokens[1].lp)
        XCTAssertNil(t.segments[0].words)
    }

    func testPreChangeLineDecodesWithNilAndNilEncodesWithoutKey() throws {
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
            "raw": { "text": "invented sample", "ms": 0 },
            "post_dict": { "text": "", "ms": 0 },
            "post_itn": { "text": "", "ms": 0 },
            "post_swiss": { "text": "", "ms": 0 },
            "post_rules": { "text": "", "ms": 0 },
            "post_swiss_num": { "text": "", "ms": 0 }
          },
          "dictionary_context_keys": [],
          "anomaly": { "degenerate_collapse": false, "very_short_output": false },
          "emission_counter": 0
        }
        """.data(using: .utf8)!
        XCTAssertNil(try JSONDecoder().decode(DebugCleanupRecord.self, from: json).asr_tokens)

        let data = try JSONEncoder().encode(makeRecord(asr: nil))
        XCTAssertFalse(String(data: data, encoding: .utf8)!.contains("asr_tokens"))
    }
}
#endif
