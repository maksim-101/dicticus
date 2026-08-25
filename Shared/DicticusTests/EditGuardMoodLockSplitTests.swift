import XCTest
@testable import Dicticus

/// Quick task 260825-q1w (D-C in the plan): scopes the mood-lock revert
/// (`RejectionClass.moodLockSentenceInitialVerb`) to violations actually
/// CAUSED BY A REORDER. `EditGuard.rebuild`'s mood-lock loop compares
/// `firstWordToken(baseline, sentenceIndex:)` against
/// `firstWordToken(tokens, sentenceIndex:)` by SENTENCE INDEX — a
/// candidate-side sentence SPLIT shifts every later candidate sentence
/// index by one, so a pure split (no reordering) can silently compare two
/// different sentences and misfire as a mood flip (landmine 5, the
/// 2026-08-23 false positive).
///
/// POSITIVE (RED before the guard exists, GREEN after) is the real, live
/// record. NEGATIVES pin the German/mood-protection proof — including a new
/// adversarial split+reorder case, per
/// `feedback_spike_corpus_adversarial_breadth`: a split must not give a
/// genuine verb-fronting reorder a free pass.
@MainActor
final class EditGuardMoodLockSplitTests: XCTestCase {

    private func guardOut(_ baseline: String, _ llm: String, _ lang: String = "en") -> EditGuard.GuardResult {
        EditGuard.apply(rulesCleaned: baseline, llmOutput: llm, language: lang, lexicon: TestSpellLexicon.allKnown)
    }

    private func assertMoodLockFired(_ result: EditGuard.GuardResult, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(result.edits.contains { $0.rejectClass == "moodLockSentenceInitialVerb" },
            "expected a moodLockSentenceInitialVerb rejection — got: \(result.edits)", file: file, line: line)
    }

    private func assertMoodLockDidNotFire(_ result: EditGuard.GuardResult, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(result.edits.contains { $0.rejectClass == "moodLockSentenceInitialVerb" },
            "expected no moodLockSentenceInitialVerb rejection — got: \(result.edits)", file: file, line: line)
    }

    // MARK: - Positive: live cleanup-2026-08-23.jsonl #11 — a no-reorder split

    func testPositive_noReorderSplitSurvivesMoodLock_en() {
        let baseline = "Because I guess this is more ambiguous in nature right because delegation downward is about cost efficiency does the senior super advisor Need to do all the work? No."
        let candidate = "Because I guess this is more ambiguous in nature, right, because delegation downward is about cost efficiency. Does the senior super advisor need to do all the work? No."
        let result = guardOut(baseline, candidate)
        XCTAssertTrue(result.text.contains("cost efficiency. Does the senior super advisor need to do all the work?"),
            "expected the split + both casing fixes to survive — got: \(result.text)")
        assertMoodLockDidNotFire(result)
    }

    // MARK: - Negatives: verb-fronting reorders still reject

    /// fx-mov-func-en-moodlock pair.
    func testNegative_verbFrontingEn() {
        let baseline = "You can push the commits and then I'm wondering where do we stand."
        let candidate = "Can you push the commits and then I'm wondering where we stand."
        let result = guardOut(baseline, candidate)
        XCTAssertEqual(result.text, baseline)
        assertMoodLockFired(result)
    }

    /// fx-mov-func-de-moodlock pair.
    func testNegative_verbFrontingDe() {
        let baseline = "Er kommt morgen."
        let candidate = "Kommt er morgen?"
        let result = guardOut(baseline, candidate, "de")
        XCTAssertEqual(result.text, baseline)
        assertMoodLockFired(result)
    }

    /// New adversarial negative: a genuine verb-fronting reorder coexists
    /// with an UNRELATED, benign sentence split elsewhere in the same
    /// utterance. The split must not buy the reorder a free pass — "kommt"
    /// lost its baseline left-neighbour "er", so the first sentence is a
    /// genuine fronting, independent of whatever splitting happens later.
    /// The later split (no reorder, no mood-mark change) is legitimately
    /// accepted on its own merits — see the positive fixture above — so
    /// only the reordered sentence's reversion is asserted here.
    func testNegative_splitPlusReorderStillRejectsDe() {
        let baseline = "Er kommt morgen. Das Update ist fertig und wir sind bereit."
        let candidate = "Kommt er morgen. Das Update ist fertig. Und wir sind bereit."
        let result = guardOut(baseline, candidate, "de")
        XCTAssertTrue(result.text.hasPrefix("Er kommt morgen."),
            "expected the genuine verb-fronting reorder to revert to baseline order — got: \(result.text)")
        assertMoodLockFired(result)
    }
}
