#if DEBUG_RECORDER
import XCTest
import WhisperKit
@testable import Dicticus

/// Quick task 261003-jej: the ASR token trace is built synchronously before paste.
/// Budget: median at most 15 ms for ~300 text tokens with the real large-v3 tokenizer.
final class AsrTokenTraceLatencyTests: XCTestCase {

    private static let paragraph = """
    Yesterday I walked through the old harbour district with a colleague, and we talked about \
    how the new tram line would change the morning commute for everybody living near the river. \
    She thought the timetable was far too optimistic, while I argued that the extra stops would \
    quickly fill up once the construction noise finally stopped. Später am Nachmittag haben wir \
    noch einen Kaffee getrunken und über die Planung der nächsten Quartalsbesprechung gesprochen. \
    Wichtig ist, dass wir die Unterlagen rechtzeitig verschicken, damit alle Beteiligten genug \
    Zeit haben, sich vorzubereiten und ihre Fragen zu sammeln. Another point we discussed was \
    whether the budget for the pilot project should be split across two departments or stay with \
    a single owner, because shared responsibility often means that nobody feels responsible when \
    something goes wrong. Am Ende waren wir uns einig, dass ein kurzer schriftlicher Plan mit \
    klaren Zuständigkeiten mehr hilft als eine lange Diskussion ohne Ergebnis. We agreed to meet \
    again on Thursday morning, bring the revised numbers, and decide before lunch so that the \
    team can start the following week without any open questions about who does what. Danach \
    räumten wir den Besprechungsraum auf, schlossen die Fenster und gingen langsam zurück ins Büro.
    """

    func testTraceBuildAndEncodeMedianWithinBudget() async throws {
        let tokenizerJSON = try XCTUnwrap(
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        ).appendingPathComponent("huggingface/models/openai/whisper-large-v3/tokenizer.json")
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: tokenizerJSON.path),
            "Whisper large-v3 tokenizer not cached locally"
        )

        let tokenizer = try await ModelUtilities.loadTokenizer(for: .largev3)
        let special = tokenizer.specialTokens
        let textIds = tokenizer.encode(text: Self.paragraph).filter { $0 < special.specialTokenBegin }
        XCTAssertGreaterThanOrEqual(textIds.count, 250)
        XCTAssertLessThanOrEqual(textIds.count, 400)

        let prompt = [special.startOfTranscriptToken, special.englishToken, special.transcribeToken, special.noTimestampsToken]
        let half = textIds.count / 2
        let segmentInputs: [(tokens: [Int], logProbs: [[Int: Float]])] = [
            Array(textIds[..<half]), Array(textIds[half...]),
        ].map { part in
            let tokens = prompt + part + [special.endToken]
            let lps: [[Int: Float]] = tokens.map { id in [id: id < special.specialTokenBegin ? -0.1 : 0] }
            return (tokens, lps)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]

        func runOnce() throws -> (ms: Double, trace: DebugCleanupRecord.AsrTokenTrace) {
            let start = Date()
            let segments = segmentInputs.map { input in
                DebugCleanupRecord.AsrSegment.build(
                    tokens: input.tokens,
                    tokenLogProbs: input.logProbs,
                    temperature: 0,
                    specialTokenBegin: special.specialTokenBegin,
                    decodeToken: { tokenizer.decode(tokens: [$0]) },
                    splitWords: { tokenizer.splitToWordTokens(tokenIds: $0) }
                )
            }
            let trace = DebugCleanupRecord.AsrTokenTrace(ms: 0, segments: segments)
            _ = try encoder.encode(trace)
            return (Date().timeIntervalSince(start) * 1000, trace)
        }

        _ = try runOnce()
        var times: [Double] = []
        var last: DebugCleanupRecord.AsrTokenTrace?
        for _ in 0..<5 {
            let r = try runOnce()
            times.append(r.ms)
            last = r.trace
        }
        let median = times.sorted()[times.count / 2]
        print("ASR_TOKEN_TRACE_MEDIAN_MS=\(median)")
        XCTAssertLessThanOrEqual(median, 15, "times: \(times)")

        let trace = try XCTUnwrap(last)
        for seg in trace.segments {
            let words = try XCTUnwrap(seg.words, "real tokenizer split must satisfy the derivation checks")
            XCTAssertEqual(words.map(\.n).reduce(0, +), seg.tokens.count)
        }
        XCTAssertEqual(trace.segments.map(\.tokens.count).reduce(0, +), textIds.count)
    }
}
#endif
