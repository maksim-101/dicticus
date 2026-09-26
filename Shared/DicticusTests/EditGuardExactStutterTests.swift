import XCTest
@testable import Dicticus

/// Quick task 260926-dbi: regression net for exact-adjacent-stutter deletion
/// survival through the two coupled-revert flip loops
/// (`applyAtomicGroupCoupling`, `applySentenceCoupledRevert`). Per
/// `.planning/debug/audit-2026-09-26/D-silent-self-correction.md` §1 and
/// §6.4, four live records (cited by ts only, no dictation text quoted:
/// `2026-09-12T09:26:12.949Z`, `2026-09-12T15:15:22.710Z`,
/// `2026-09-19T04:01:16.679Z`, `2026-09-20T05:13:08.876Z`) show the LLM
/// correctly deleting one copy of an exact adjacent duplicate ("for for",
/// "the The", etc.), which the coupled-revert passes then silently undid
/// whenever something else in the same raw sentence was rejected. A fifth
/// live row, `2026-08-15T14:37:11.911Z`, shows the same defect via
/// `applyAtomicGroupCoupling` rather than `applySentenceCoupledRevert`.
/// Fixed by `EditGuard.isExactAdjacentStutterDelete`, consulted by both flip
/// loops.
///
/// Every fixture below is INVENTED — different topic, invented names, no
/// personal facts, ordinary dictionary words throughout (never a coined
/// word, so `debugEG`'s default lexicon and the tests' `TestSpellLexicon
/// .allKnown` never diverge on which tokens are known). `dbi_privacy_check
/// .py` in the quick task directory verifies no 5-word shingle overlap with
/// the staged corpus.
///
/// P1-P5 are RED before the fix (actual = expected with the deleted
/// duplicate restored, proving the fixture carries the defect shape per
/// 49.6 D-12); N1-N6 are GREEN both before and after — each pins one clause
/// of the predicate. P1, P2, P3 and P5 place the content trigger multiple
/// `.keep` tokens away from the stutter pair, so only
/// `applySentenceCoupledRevert` (never `applyAtomicGroupCoupling`) flips
/// the pre-fix delete (M2's target). P4 places the stutter delete directly
/// adjacent to two rejected `contentWordDeletion`s in one keep-bounded
/// cluster, so `applyAtomicGroupCoupling` flips the pre-fix delete first
/// (M1's target); post-fix, both loops must independently exempt it (a
/// delete `applyAtomicGroupCoupling` exempts is still `accepted
/// disfluencyCollapse` when `applySentenceCoupledRevert` runs immediately
/// after in the same `rebuild` call, and that pass's own flip loop would
/// otherwise sweep it).
@MainActor
final class EditGuardExactStutterTests: XCTestCase {

    private func guardOut(_ baseline: String, _ llm: String, _ lang: String = "en") -> String {
        EditGuard.apply(rulesCleaned: baseline, llmOutput: llm, language: lang, lexicon: TestSpellLexicon.allKnown).text
    }

    private func guardResult(_ baseline: String, _ llm: String, _ lang: String = "en") -> EditGuard.GuardResult {
        EditGuard.apply(rulesCleaned: baseline, llmOutput: llm, language: lang, lexicon: TestSpellLexicon.allKnown)
    }

    // MARK: - P1: SCR shape, English "for for", trigger several keeps before the stutter

    /// Content trigger (`vendor`->`seller`, rejected) sits 4 keeps before the
    /// stutter delete; an LLM comma insert and a sentence-initial casing fix
    /// are both independently reverted by the same coupled-sentence
    /// trigger; the LLM's final `.` survives (260926-bbz exemption). Pre-fix
    /// (verified via `debugEG`) the stutter delete's rejectClass is
    /// `sentenceCoupledRevert` — `applyAtomicGroupCoupling` never sees it,
    /// because a `.keep` separates it from every other non-keep edit.
    func testP1_scrShapeForForTriggerSeveralKeepsBefore() {
        let baseline = "he emailed the vendor about the invoice for for the shipment and then closed the ticket by evening"
        let llm = "He emailed the seller about the invoice for the shipment, and then closed the ticket by evening."
        let expected = "he emailed the vendor about the invoice for the shipment and then closed the ticket by evening."
        let out = guardOut(baseline, llm)
        let result = guardResult(baseline, llm)
        XCTAssertEqual(out, expected, "edits: \(result.edits)")
        guard let stutter = result.edits.first(where: { $0.kind == "delete" && $0.from == "for" }) else {
            return XCTFail("no delete edit for 'for'")
        }
        XCTAssertTrue(stutter.accepted)
        XCTAssertEqual(stutter.acceptClass, "disfluencyCollapse")
        // Guards against a too-broad predicate: the unrelated comma insert
        // in the same triggered raw sentence must still revert.
        XCTAssertTrue(result.edits.contains { $0.kind == "insert" && $0.to == "," && $0.rejectClass == "sentenceCoupledRevert" })
        XCTAssertTrue(result.edits.contains { $0.kind == "substitute" && $0.from == "vendor" && $0.to == "seller" && $0.rejectClass == "contentWordIdentityChange" })
        let v = EditGuardMergeAtomicityTests.neitherSourceViolations(output: out, sourceA: baseline, sourceB: llm)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(out)")
    }

    // MARK: - P2: casing variant "the The"

    /// `debugEG` confirms EditDiff keeps the earlier lowercase `the` and
    /// deletes the later `The` — the expected string follows that. Pins
    /// case-insensitive `normalized` equality in clause (b).
    func testP2_scrShapeCasingVariantTheThe() {
        let baseline = "we discussed the The proposal for the client and then reviewed the budget early"
        let llm = "We discussed the proposal for the buyer, and then reviewed the budget early."
        let expected = "we discussed the proposal for the client and then reviewed the budget early."
        let out = guardOut(baseline, llm)
        let result = guardResult(baseline, llm)
        XCTAssertEqual(out, expected, "edits: \(result.edits)")
        guard let stutter = result.edits.first(where: { $0.kind == "delete" && $0.from == "The" }) else {
            return XCTFail("no delete edit for 'The'")
        }
        XCTAssertTrue(stutter.accepted)
        XCTAssertEqual(stutter.acceptClass, "disfluencyCollapse")
        XCTAssertTrue(result.edits.contains { $0.kind == "substitute" && $0.from == "client" && $0.to == "buyer" && $0.rejectClass == "contentWordIdentityChange" })
        let v = EditGuardMergeAtomicityTests.neitherSourceViolations(output: out, sourceA: baseline, sourceB: llm)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(out)")
    }

    // MARK: - P3: pronoun "I I" at sentence start

    /// Exercises the `disfluencyIndices`-before-`pronounDeleted` path in
    /// `classifyDelete`: the duplicate `I` is classified `disfluencyCollapse`,
    /// never reaching the D-04 pronoun lock. Content trigger
    /// (`invoice`->`receipt`) sits several keeps after the stutter.
    func testP3_scrShapePronounStutterIAtSentenceStart() {
        let baseline = "I I called the client about the invoice and then updated the record today"
        let llm = "I called the client about the receipt and then updated the record today."
        let expected = "I called the client about the invoice and then updated the record today."
        let out = guardOut(baseline, llm)
        let result = guardResult(baseline, llm)
        XCTAssertEqual(out, expected, "edits: \(result.edits)")
        guard let stutter = result.edits.first(where: { $0.kind == "delete" && $0.from == "I" }) else {
            return XCTFail("no delete edit for 'I'")
        }
        XCTAssertTrue(stutter.accepted)
        XCTAssertEqual(stutter.acceptClass, "disfluencyCollapse")
        XCTAssertTrue(result.edits.contains { $0.kind == "substitute" && $0.from == "invoice" && $0.to == "receipt" && $0.rejectClass == "contentWordIdentityChange" })
        let v = EditGuardMergeAtomicityTests.neitherSourceViolations(output: out, sourceA: baseline, sourceB: llm)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(out)")
    }

    // MARK: - P4: atomic shape "in in terms of" — the M1 target

    /// The LLM deletes the second `in` together with `terms` and `of`, so
    /// the stutter delete shares one keep-bounded cluster with two rejected
    /// `contentWordDeletion`s. Pre-fix (verified via `debugEG`) the stutter
    /// delete's rejectClass is `atomicGroupRevert`, not
    /// `sentenceCoupledRevert` — this fixture fails if only
    /// `applySentenceCoupledRevert` is fixed. Expected: baseline minus
    /// exactly the one duplicated `in`, with `terms of` restored (the
    /// rejected content deletions revert to raw) and no reordered or
    /// doubled token (the materialize-anchor check).
    func testP4_atomicShapeInInTermsOf() {
        let baseline = "let's talk about everything in in terms of the budget for this quarter"
        let llm = "Let's talk about everything in the budget for this quarter."
        let expected = "let's talk about everything in terms of the budget for this quarter."
        let out = guardOut(baseline, llm)
        let result = guardResult(baseline, llm)
        XCTAssertEqual(out, expected, "edits: \(result.edits)")
        guard let stutter = result.edits.first(where: { $0.kind == "delete" && $0.from == "in" }) else {
            return XCTFail("no delete edit for 'in'")
        }
        XCTAssertTrue(stutter.accepted)
        XCTAssertEqual(stutter.acceptClass, "disfluencyCollapse")
        XCTAssertTrue(result.edits.contains { $0.kind == "delete" && $0.from == "terms" && $0.rejectClass == "contentWordDeletion" })
        XCTAssertTrue(result.edits.contains { $0.kind == "delete" && $0.from == "of" && $0.rejectClass == "contentWordDeletion" })
        let v = EditGuardMergeAtomicityTests.neitherSourceViolations(output: out, sourceA: baseline, sourceB: llm)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(out)")
    }

    // MARK: - P5: German "mit mit"

    /// SCR shape in German, mirroring P1. Content trigger
    /// (`kunden`->`käufer`) is one keep away from the stutter — still a
    /// separate atomic cluster (a `.keep` always closes a cluster), so only
    /// `applySentenceCoupledRevert` flips the pre-fix delete.
    func testP5_scrShapeGermanMitMit() {
        let baseline = "ich habe das protokoll mit mit dem kunden besprochen und dann die rechnung heute geprüft"
        let llm = "Ich habe das protokoll mit dem käufer besprochen und dann die rechnung heute geprüft."
        let expected = "ich habe das protokoll mit dem kunden besprochen und dann die rechnung heute geprüft."
        let out = guardOut(baseline, llm, "de")
        let result = guardResult(baseline, llm, "de")
        XCTAssertEqual(out, expected, "edits: \(result.edits)")
        guard let stutter = result.edits.first(where: { $0.kind == "delete" && $0.from == "mit" }) else {
            return XCTFail("no delete edit for 'mit'")
        }
        XCTAssertTrue(stutter.accepted)
        XCTAssertEqual(stutter.acceptClass, "disfluencyCollapse")
        XCTAssertTrue(result.edits.contains { $0.kind == "substitute" && $0.from == "kunden" && $0.to == "käufer" && $0.rejectClass == "contentWordIdentityChange" })
        let v = EditGuardMergeAtomicityTests.neitherSourceViolations(output: out, sourceA: baseline, sourceB: llm)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(out)")
    }

    // MARK: - N1: German relative pronoun "die die" — a legitimate double, excluded

    /// "eine Lösung die die Kosten senkt" shape — the LLM wrongly collapses
    /// a legitimate double (relative pronoun immediately followed by an
    /// object). GREEN both before and after: `die` is on the German
    /// exclusion set, so clause (c) blocks the exemption and the delete
    /// keeps reverting exactly as before.
    func testN1_germanRelativePronounDieDieExcluded() {
        let baseline = "wir brauchen eine lösung die die kosten senkt und den umsatz steigert"
        let llm = "Wir brauchen eine lösung die kosten senkt und den umsatz erhöht."
        let expected = baseline + "."
        let out = guardOut(baseline, llm, "de")
        let result = guardResult(baseline, llm, "de")
        XCTAssertEqual(out, expected, "edits: \(result.edits)")
        guard let dieDelete = result.edits.first(where: { $0.kind == "delete" && $0.from == "die" }) else {
            return XCTFail("no delete edit for 'die'")
        }
        XCTAssertFalse(dieDelete.accepted)
        XCTAssertEqual(dieDelete.rejectClass, "sentenceCoupledRevert")
        let v = EditGuardMergeAtomicityTests.neitherSourceViolations(output: out, sourceA: baseline, sourceB: llm)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(out)")
    }

    // MARK: - N2: English "that that" — complementizer + demonstrative, excluded

    /// GREEN both before and after: `that` is on the English exclusion set.
    func testN2_englishThatThatExcluded() {
        let baseline = "she told him that that decision affected the entire team and the budget"
        let llm = "She told him that decision affected the whole team and the funding."
        let expected = baseline + "."
        let out = guardOut(baseline, llm)
        let result = guardResult(baseline, llm)
        XCTAssertEqual(out, expected, "edits: \(result.edits)")
        guard let thatDelete = result.edits.first(where: { $0.kind == "delete" && $0.from == "that" }) else {
            return XCTFail("no delete edit for 'that'")
        }
        XCTAssertFalse(thatDelete.accepted)
        XCTAssertEqual(thatDelete.rejectClass, "sentenceCoupledRevert")
        let v = EditGuardMergeAtomicityTests.neitherSourceViolations(output: out, sourceA: baseline, sourceB: llm)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(out)")
    }

    // MARK: - N3: number word "one one" — pins the numericValue clause

    /// GREEN both before and after: `one` is a `NumberRevert.enWords` key,
    /// so `EditGuardTokenizer.numericValue` is non-nil and clause (c) blocks
    /// the exemption regardless of the exclusion set.
    func testN3_numberWordOneOneExcluded() {
        let baseline = "the code for the item is one one four and the price increased"
        let llm = "The code for the item is one four and the cost increased."
        let expected = baseline + "."
        let out = guardOut(baseline, llm)
        let result = guardResult(baseline, llm)
        XCTAssertEqual(out, expected, "edits: \(result.edits)")
        guard let oneDelete = result.edits.first(where: { $0.kind == "delete" && $0.from == "one" }) else {
            return XCTFail("no delete edit for 'one'")
        }
        XCTAssertFalse(oneDelete.accepted)
        XCTAssertEqual(oneDelete.rejectClass, "sentenceCoupledRevert")
        let v = EditGuardMergeAtomicityTests.neitherSourceViolations(output: out, sourceA: baseline, sourceB: llm)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(out)")
    }

    // MARK: - N4: near-duplicate inflection pair "product products" — pins exact normalized equality

    /// GREEN both before and after: `products` and `product` have different
    /// `normalized` text, so clause (b)'s exact-equality requirement never
    /// fires — this is `disfluencyCollapse`'s near-duplicate criterion B
    /// path, deliberately left context-dependent (49.6 D-02).
    func testN4_inflectionNearDuplicateProductProductsNotExempt() {
        let baseline = "we delivered the product products to the client yesterday and confirmed the order today"
        let llm = "We delivered the product to the buyer yesterday and confirmed the order today."
        let expected = baseline + "."
        let out = guardOut(baseline, llm)
        let result = guardResult(baseline, llm)
        XCTAssertEqual(out, expected, "edits: \(result.edits)")
        guard let productsDelete = result.edits.first(where: { $0.kind == "delete" && $0.from == "products" }) else {
            return XCTFail("no delete edit for 'products'")
        }
        XCTAssertFalse(productsDelete.accepted)
        XCTAssertEqual(productsDelete.rejectClass, "sentenceCoupledRevert")
        let v = EditGuardMergeAtomicityTests.neitherSourceViolations(output: out, sourceA: baseline, sourceB: llm)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(out)")
    }

    // MARK: - N5: multi-word block "to the to the" — pins single-token adjacency

    /// GREEN both before and after: each deleted token's immediate baseline
    /// neighbour is a DIFFERENT word (the deleted `to`'s neighbour is a kept
    /// `the`, the deleted `the`'s neighbour is a deleted `to`), so clause
    /// (b) never finds a same-word `.keep` neighbour for either delete —
    /// this is criterion B's multi-word block-repeat path, which the exact
    /// single-token predicate deliberately does not cover.
    func testN5_multiWordBlockToTheToTheNotExempt() {
        let baseline = "he walked to the to the store and bought the supplies for the office"
        let llm = "He walked to the store and bought the goods for the office."
        let expected = baseline + "."
        let out = guardOut(baseline, llm)
        let result = guardResult(baseline, llm)
        XCTAssertEqual(out, expected, "edits: \(result.edits)")
        let blockDeletes = result.edits.filter { $0.kind == "delete" && ($0.from == "to" || $0.from == "the") }
        XCTAssertEqual(blockDeletes.count, 2)
        for edit in blockDeletes {
            XCTAssertFalse(edit.accepted)
            XCTAssertEqual(edit.rejectClass, "sentenceCoupledRevert")
        }
        let v = EditGuardMergeAtomicityTests.neitherSourceViolations(output: out, sourceA: baseline, sourceB: llm)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(out)")
    }

    // MARK: - N6: substitute neighbour "the the" — pins the .keep requirement

    /// GREEN both before and after: the LLM substitutes the first `the`
    /// (`the`->`a`) and deletes the second — the delete's immediate
    /// neighbour is a `.substitute`, not a `.keep`, so clause (b) never
    /// fires even though the substitute's `from` text matches.
    func testN6_substituteNeighbourTheTheNotExempt() {
        let baseline = "she opened the the door and welcomed the visitors warmly today"
        let llm = "She opened a door and welcomed the guests warmly today."
        let expected = baseline + "."
        let out = guardOut(baseline, llm)
        let result = guardResult(baseline, llm)
        XCTAssertEqual(out, expected, "edits: \(result.edits)")
        guard let theDelete = result.edits.first(where: { $0.kind == "delete" && $0.from == "the" }) else {
            return XCTFail("no delete edit for 'the'")
        }
        XCTAssertFalse(theDelete.accepted)
        XCTAssertEqual(theDelete.rejectClass, "sentenceCoupledRevert")
        XCTAssertTrue(result.edits.contains { $0.kind == "substitute" && $0.from == "the" && $0.to == "a" })
        let v = EditGuardMergeAtomicityTests.neitherSourceViolations(output: out, sourceA: baseline, sourceB: llm)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(out)")
    }
}
