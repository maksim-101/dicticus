import XCTest
@testable import Dicticus

/// Quick task 260825-q1w (D-A/D-B in the plan): calibrates `EditGuard` to
/// accept a PURE two-token hyphen join — the LLM hyphenating two ADJACENT
/// dictated tokens with no letter change on either side (`decision wise` ->
/// `decision-wise`). Every join in the 2026-08 debug logs is a PAIR: the
/// `.substitute` that introduces the hyphenated token, immediately followed
/// by the baseline's now-redundant second word, dropped either as a
/// `.delete` or as a `.substitute` against prosodic punctuation (D-B) — the
/// exemption must accept both halves or neither, or the rebuilt text glues
/// the leftover word back on (`decision-wise wise`).
///
/// POSITIVES (RED before `AcceptClass.hyphenCompoundJoin` + the exemption
/// exist, GREEN after) are real, trimmed 2026-08 records. NEGATIVES are the
/// calibration proof — they must stay GREEN (rejected) both before and
/// after this task, so the predicate never loosens as a side effect.
///
/// `self` -> `self-evaluation` is flipped to a POSITIVE here (D-A): the raw
/// record shows the paired `delete 'evaluation'` immediately after the
/// substitute — the user dictated "my self evaluation" and the LLM
/// hyphenated two adjacent dictated tokens, exactly the shape this
/// exemption exists to accept. `relation` -> `relationship` (no hyphen, no
/// adjacent partner) stays the surviving negative.
@MainActor
final class EditGuardHyphenCompoundJoinTests: XCTestCase {

    private func guardOut(_ baseline: String, _ llm: String, _ lang: String = "en", dictProtected: Set<String> = []) -> EditGuard.GuardResult {
        EditGuard.apply(rulesCleaned: baseline, llmOutput: llm, language: lang, dictProtected: dictProtected, lexicon: TestSpellLexicon.allKnown)
    }

    // MARK: - Positives

    /// cleanup-2026-08-23.jsonl #124 — delete partner.
    func testPositive_selfEvaluation_deletePartner_en() {
        let baseline = "Then my self evaluation, the whole thing is fine."
        let candidate = "Then my self-evaluation, the whole thing is fine."
        let result = guardOut(baseline, candidate)
        XCTAssertEqual(result.text, candidate)
        XCTAssertTrue(result.edits.contains {
            $0.kind == "substitute" && $0.from == "self" && $0.accepted && $0.acceptClass == "hyphenCompoundJoin"
        }, "expected the substitute self -> self-evaluation classified hyphenCompoundJoin — got: \(result.edits)")
        XCTAssertTrue(result.edits.contains {
            $0.from == "evaluation" && $0.accepted
        }, "expected the paired 'evaluation' drop to also be accepted — got: \(result.edits)")
    }

    /// cleanup-2026-08-23.jsonl #70 shape — two adjacent dictated tokens
    /// joined at a sentence-terminal boundary.
    func testPositive_codeWise_en() {
        let baseline = "So how do we do this code wise."
        let candidate = "So how do we do this code-wise."
        let result = guardOut(baseline, candidate)
        XCTAssertEqual(result.text, candidate)
        XCTAssertTrue(result.edits.contains {
            $0.kind == "substitute" && $0.from == "code" && $0.accepted && $0.acceptClass == "hyphenCompoundJoin"
        }, "expected the substitute code -> code-wise classified hyphenCompoundJoin — got: \(result.edits)")
    }

    /// cleanup-2026-08-13.jsonl #21 shape — DE, casing rides along since the
    /// rule compares `normalized`.
    func testPositive_jsonDatei_de_casingRidesAlong() {
        let baseline = "Ich habe die json datei noch nicht angeschaut."
        let candidate = "Ich habe die JSON-Datei noch nicht angeschaut."
        let result = guardOut(baseline, candidate, "de")
        XCTAssertEqual(result.text, candidate)
        XCTAssertTrue(result.edits.contains {
            $0.kind == "substitute" && $0.from == "json" && $0.accepted && $0.acceptClass == "hyphenCompoundJoin"
        }, "expected the substitute json -> JSON-Datei classified hyphenCompoundJoin — got: \(result.edits)")
    }

    // MARK: - Negatives (calibration proof — GREEN before AND after)

    /// cleanup-2026-08-25.jsonl #15 — no hyphen, no adjacent partner: a
    /// genuine derivational change, must stay rejected.
    func testNegative_relationToRelationship_derivational_en() {
        let baseline = "I want a long-term relation with us going forward."
        let candidate = "I want a long-term relationship with us going forward."
        let result = guardOut(baseline, candidate)
        XCTAssertEqual(result.text, baseline)
        XCTAssertTrue(result.edits.contains {
            $0.from == "relation" && !$0.accepted && $0.rejectClass == "derivationalSuffixChange"
        }, "expected relation -> relationship to stay rejected derivationalSuffixChange — got: \(result.edits)")
    }

    /// Hand-authored: the hyphenated target's letters do not equal the two
    /// source tokens joined by a single hyphen.
    func testNegative_lettersChangedInsideJoin_en() {
        let baseline = "The code base is fine."
        let candidate = "The code-bases is fine."
        let result = guardOut(baseline, candidate)
        XCTAssertEqual(result.text, baseline)
    }

    /// cleanup-2026-08-22.jsonl #65 shape — a three-token join. Two tokens
    /// is the calibrated line; joins spanning three or more dictated tokens
    /// stay rejected (out-of-scope section of the plan).
    func testNegative_threeTokenJoin_en() {
        let baseline = "So the delegation not script is the point."
        let candidate = "So the delegation-not-script is the point."
        let result = guardOut(baseline, candidate)
        XCTAssertEqual(result.text, baseline)
    }

    /// A join spanning a dictionary-protected token must not exempt.
    func testNegative_dictProtectedToken_en() {
        let baseline = "I use Claude Code every day."
        let candidate = "I use Claude-Code every day."
        let result = guardOut(baseline, candidate, "en", dictProtected: ["Claude"])
        XCTAssertEqual(result.text, baseline)
    }

    /// cleanup-2026-08-13.jsonl #15 shape — a genuine derivational change
    /// whose baseline pair also happens to be adjacent (deleted partner),
    /// but the candidate has NO hyphen — must stay rejected.
    func testNegative_selbstErklaerend_derivational_de() {
        let baseline = "Das ist nicht ganz selbst erklärend."
        let candidate = "Das ist nicht ganz selbstverständlich."
        let result = guardOut(baseline, candidate, "de")
        XCTAssertEqual(result.text, baseline)
    }

    // MARK: - Limitation pin (landmine 3 — documents a deliberate non-fix, GREEN before and after)

    /// A qualifying hyphen join whose atomic group also contains an
    /// independently REJECTED `contentWordDeletion` (the dropped "and")
    /// still reverts as a whole via `applyAtomicGroupCoupling` — no
    /// coupling exemption for `hyphenCompoundJoin` was added this task
    /// (landmine 3). Flipping this later is a deliberate decision, not a
    /// bug fix — it requires establishing coupling-exemption safety across
    /// a full corpus replay, out of this quick task's scope.
    func testLimitationPin_atomicGroupRevertsJoinWhenGroupmateRejected_en() {
        let baseline = "The design and decision wise and then we can go."
        let candidate = "The design and decision-wise. Then we can go."
        let result = guardOut(baseline, candidate)
        XCTAssertTrue(result.text.contains("decision wise"),
            "known limitation (landmine 3): a co-rejected groupmate reverts the whole atomic group, including the otherwise-qualifying join — got: \(result.text)")
    }
}
