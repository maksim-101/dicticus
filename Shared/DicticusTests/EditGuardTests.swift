import XCTest
@testable import Dicticus

/// Phase 44 Plan 10: the classify + rebuild test suite. Table-driven over
/// EVERY fixture in `EditGuardFixtures.all` (the scoreboard), plus the named
/// one-off assertions the plan's `<behavior>` block calls out explicitly.
///
/// `testAllFixturesRebuildToExpectedText` is the single most important test
/// in this file — it proves `EditGuard.apply` REBUILDS the correct text, not
/// merely that it accepts/rejects the right verdict. A guard that rejects
/// correctly but rebuilds the wrong string is exactly the "pass/fail gate"
/// failure mode this phase replaces.
///
/// `@MainActor`: `EditGuard` is `@MainActor`-isolated (matches
/// `PerSentenceGateTests`'s precedent for the gate it replaces).
@MainActor
final class EditGuardTests: XCTestCase {

    // MARK: - The scoreboard: every fixture, checked for expectedText

    func testAllFixturesRebuildToExpectedText() {
        var failures: [String] = []
        for fixture in EditGuardFixtures.all {
            let result = EditGuard.apply(
                rulesCleaned: fixture.baseline,
                llmOutput: fixture.candidate,
                language: fixture.language,
                lexicon: TestSpellLexicon.allKnown
            )
            if result.text != fixture.expectedText {
                failures.append(
                    "[\(fixture.id)] verdict=\(fixture.expectedVerdict.rawValue) class=\(fixture.expectedClass)\n" +
                    "    expected: \"\(fixture.expectedText)\"\n" +
                    "    actual:   \"\(result.text)\""
                )
            }
        }
        if !failures.isEmpty {
            XCTFail(
                "(\(EditGuardFixtures.all.count - failures.count)/\(EditGuardFixtures.all.count)) fixtures matched expectedText. " +
                "\(failures.count) did not:\n\n" + failures.joined(separator: "\n\n")
            )
        }
    }

    // MARK: - Rebuild invariant: never nil on any fixture

    /// Success criterion: "`rebuild` returns non-nil on every fixture (the
    /// multiset invariant holds)."
    func testRebuildNeverReturnsNilOnAnyFixture() {
        for fixture in EditGuardFixtures.all {
            let baseline = EditGuardTokenizer.tokenize(fixture.baseline)
            let candidate = EditGuardTokenizer.tokenize(fixture.candidate)
            let edits = EditDiff.diff(baseline: baseline, candidate: candidate)
            let classified = EditGuard.classify(
                edits: edits, baseline: baseline, candidate: candidate,
                language: fixture.language, dictProtected: [], lexicon: TestSpellLexicon.allKnown
            )
            let rebuilt = EditGuard.rebuild(
                baseline: baseline, candidate: candidate, edits: edits,
                classified: classified, language: fixture.language
            )
            XCTAssertNotNil(rebuilt, "[\(fixture.id)] rebuild returned nil — multiset invariant violated")
        }
    }

    // MARK: - D-01: the architecture proof

    /// "A sentence containing BOTH a genuine repair and a corruption yields
    /// a string containing the repair and not the corruption. No pass/fail
    /// gate can produce that string." — unsatisfiable by any sentence-level
    /// gate; this is the reason D-01 exists.
    func testD01BundledFixtureKeepsRepairAndDropsCorruption() {
        let fixture = EditGuardFixtures.d01BundledFixture
        let result = EditGuard.apply(rulesCleaned: fixture.baseline, llmOutput: fixture.candidate, language: fixture.language, lexicon: TestSpellLexicon.allKnown)
        XCTAssertEqual(result.text, fixture.expectedText)
        XCTAssertNotEqual(result.text, fixture.baseline, "the repair must survive")
        XCTAssertNotEqual(result.text, fixture.candidate, "the corruption must NOT survive")
    }

    // MARK: - D-04: moves accepted, mood-lock fires precisely

    func testGermanVerbFinalWordOrderRepairIsAccepted() throws {
        let fixture = try requireFixture("fx-mov-func-de-wordorder")
        let result = EditGuard.apply(rulesCleaned: fixture.baseline, llmOutput: fixture.candidate, language: fixture.language, lexicon: TestSpellLexicon.allKnown)
        XCTAssertEqual(result.text, fixture.expectedText, "the broken V2-in-a-weil-clause repair must survive — this is the phase's core value")
    }

    func testMoodLockFiresOnStatementToQuestionReorder() throws {
        let fixture = try requireFixture("fx-mov-func-en-moodlock")
        let result = EditGuard.apply(rulesCleaned: fixture.baseline, llmOutput: fixture.candidate, language: fixture.language, lexicon: TestSpellLexicon.allKnown)
        XCTAssertEqual(result.text, fixture.expectedText, "mood-lock must revert 'Can you push' back to 'You can push' — neither version adds '?'")
    }

    func testMoodLockDoesNotOverFireOnAlsoMoechteIch() throws {
        let fixture = try requireFixture("fx-mov-content-de-moodlock-falsepos")
        let result = EditGuard.apply(rulesCleaned: fixture.baseline, llmOutput: fixture.candidate, language: fixture.language, lexicon: TestSpellLexicon.allKnown)
        XCTAssertEqual(result.text, fixture.expectedText, "the sentence still starts with 'Also' — mood-lock must not fire")
    }

    // MARK: - D-03: digit hard lock

    func testDigitValueChangeIsBlocked() throws {
        let fixture = try requireFixture("fx-sub-digit-en-value")
        let result = EditGuard.apply(rulesCleaned: fixture.baseline, llmOutput: fixture.candidate, language: fixture.language, lexicon: TestSpellLexicon.allKnown)
        XCTAssertEqual(result.text, fixture.expectedText, "10,011 must survive intact — the D-03 blindspot fixture")
    }

    func testDigitFormChangeIsAcceptedForNumberRevertToOwn() throws {
        let fixture = try requireFixture("fx-sub-digit-de-numberform")
        let result = EditGuard.apply(rulesCleaned: fixture.baseline, llmOutput: fixture.candidate, language: fixture.language, lexicon: TestSpellLexicon.allKnown)
        XCTAssertEqual(result.text, fixture.expectedText, "10 -> zehn is a same-value form change; NumberRevert must remain reachable")
    }

    // MARK: - D-04: pronoun lock, including the gender-flip gap closure

    func testPronounPersonFlipIsBlocked() throws {
        let fixture = try requireFixture("fx-sub-pronoun-de-personflip")
        let result = EditGuard.apply(rulesCleaned: fixture.baseline, llmOutput: fixture.candidate, language: fixture.language, lexicon: TestSpellLexicon.allKnown)
        XCTAssertEqual(result.text, fixture.expectedText, "Du wohnst -> Ich wohne is the named live corruption")
    }

    /// 44-03's raised gap: "him" -> "her" are BOTH third person, so
    /// `PronounPersonMap` alone cannot distinguish them. Closed via
    /// `EditGuard.pronounFamily` — see that table's doc comment for the
    /// chosen mechanism.
    func testPronounGenderFlipIsBlockedDespiteSameGrammaticalPerson() throws {
        let fixture = try requireFixture("fx-sub-pronoun-en-genderflip")
        let result = EditGuard.apply(rulesCleaned: fixture.baseline, llmOutput: fixture.candidate, language: fixture.language, lexicon: TestSpellLexicon.allKnown)
        XCTAssertEqual(result.text, fixture.expectedText, "him -> her must revert despite both being third person")
    }

    func testPronounDeletionIsBlocked() throws {
        let fixture = try requireFixture("fx-del-pronoun-en-sentenceinitial")
        let result = EditGuard.apply(rulesCleaned: fixture.baseline, llmOutput: fixture.candidate, language: fixture.language, lexicon: TestSpellLexicon.allKnown)
        XCTAssertEqual(result.text, fixture.expectedText, "You can push -> Push must restore the dropped 'You'")
    }

    // MARK: - D-05: all seven particle deletions rejected

    func testAllSevenD05ParticleDeletionsAreRejected() {
        let ids = [
            "fx-del-filler-de-si-noch", "fx-del-filler-de-si-doch",
            "fx-del-filler-en-interior-actually", "fx-del-filler-en-interior-like",
            "fx-del-filler-en-interior-right", "fx-del-filler-en-interior-imean",
            "fx-del-filler-en-terminal-well"
        ]
        for id in ids {
            guard let fixture = EditGuardFixtures.all.first(where: { $0.id == id }) else {
                XCTFail("fixture \(id) missing from EditGuardFixtures.all")
                continue
            }
            let result = EditGuard.apply(rulesCleaned: fixture.baseline, llmOutput: fixture.candidate, language: fixture.language, lexicon: TestSpellLexicon.allKnown)
            XCTAssertEqual(result.text, fixture.expectedText, "[\(id)] particle deletion must be rejected — the filler reading is the minority reading")
        }
    }

    func testGenuineFillerDeletionsAreAccepted() throws {
        for id in ["fx-del-filler-de-si-aehm", "fx-del-filler-en-interior-umuh", "fx-del-filler-de-interior-repetition"] {
            let fixture = try requireFixture(id)
            let result = EditGuard.apply(rulesCleaned: fixture.baseline, llmOutput: fixture.candidate, language: fixture.language, lexicon: TestSpellLexicon.allKnown)
            XCTAssertEqual(result.text, fixture.expectedText, "[\(id)] genuine acoustic filler / verbatim repetition must be accepted")
        }
    }

    // MARK: - D-06: insertion negatives (including the coupled-run fixtures)

    func testD06InsertionNegativesAreAllRejected() throws {
        for id in ["fx-ins-content-de-gefahrenwar", "fx-ins-content-de-dieseteile", "fx-ins-content-de-einanderes", "fx-ins-digit-de"] {
            let fixture = try requireFixture(id)
            let result = EditGuard.apply(rulesCleaned: fixture.baseline, llmOutput: fixture.candidate, language: fixture.language, lexicon: TestSpellLexicon.allKnown)
            XCTAssertEqual(result.text, fixture.expectedText, "[\(id)] the whole inserted run must revert together — a partial-survival Frankenstein fragment is the failure mode this pass exists to prevent")
        }
    }

    func testD06FunctionWordInsertionIsAccepted() throws {
        let fixture = try requireFixture("fx-ins-func-de")
        let result = EditGuard.apply(rulesCleaned: fixture.baseline, llmOutput: fixture.candidate, language: fixture.language, lexicon: TestSpellLexicon.allKnown)
        XCTAssertEqual(result.text, fixture.expectedText)
    }

    // MARK: - D-02a: derivation blocked, including the coupled article case

    func testDerivationalSuffixChangesAreBlocked() throws {
        for id in ["fx-sub-content-de-handhabe-handhabung", "fx-sub-content-de-krankheit-kraenkung"] {
            let fixture = try requireFixture(id)
            let result = EditGuard.apply(rulesCleaned: fixture.baseline, llmOutput: fixture.candidate, language: fixture.language, lexicon: TestSpellLexicon.allKnown)
            XCTAssertEqual(result.text, fixture.expectedText, "[\(id)] D-02a blocks derivation")
        }
    }

    /// The coupled case: an accepted article gender-flip ("Der"->"Die")
    /// riding alongside a rejected derivational noun change
    /// ("Beobachter"->"Beobachtung") must ALSO revert — otherwise the
    /// output is "Die Beobachter", grammatically broken and equal to
    /// neither baseline nor a coherent repair.
    func testArticleAgreementCouplingRevertsWithRejectedNoun() throws {
        let fixture = try requireFixture("fx-sub-content-de-beobachter-beobachtung")
        let result = EditGuard.apply(rulesCleaned: fixture.baseline, llmOutput: fixture.candidate, language: fixture.language, lexicon: TestSpellLexicon.allKnown)
        XCTAssertEqual(result.text, fixture.expectedText)
    }

    func testArticleGenderAgreementFixIsAcceptedWhenNounUnchanged() throws {
        let fixture = try requireFixture("fx-sub-func-de-der-das")
        let result = EditGuard.apply(rulesCleaned: fixture.baseline, llmOutput: fixture.candidate, language: fixture.language, lexicon: TestSpellLexicon.allKnown)
        XCTAssertEqual(result.text, fixture.expectedText, "der -> das must still accept when the noun itself is unchanged")
    }

    // MARK: - The Damerau-OSA leak fixture (introduced typo)

    func testIntroducedTypoIsBlockedNotAcceptedAsNearMissRespelling() throws {
        let fixture = try requireFixture("fx-sub-content-de-typo-introduced")
        let result = EditGuard.apply(rulesCleaned: fixture.baseline, llmOutput: fixture.candidate, language: fixture.language, lexicon: TestSpellLexicon.allKnown)
        XCTAssertEqual(result.text, fixture.expectedText, "Führungsrhythmus -> Führungsrythmus is an INTRODUCED typo the OSA-2 leniency clause used to pass")
    }

    /// Threat T-44-33: the confirmed leak (an UNCONDITIONAL Damerau-OSA
    /// transposition-leniency clause that let ANY introduced typo pass as
    /// a "near-miss respelling") must never re-enter this file.
    ///
    /// RECONCILED (quick task 260723-sx1): the blanket "never reference
    /// Levenshtein" assertion is now STALE, not the Damerau check. Criterion
    /// A's `nonWordRepair` exemption is a categorically different
    /// mechanism from the removed clause: it only ever fires when `old` is
    /// NOT a known word AND `new` IS a known word (via the injected
    /// `SpellLexicon`) — a real word can NEVER be "corrected" by this path,
    /// which is exactly the failure mode T-44-33 existed to block
    /// (Führungsrhythmus -> Führungsrythmus is a real-word-to-real-word
    /// typo; `isKnownForRepair` would find BOTH sides known and the
    /// exemption would never fire). The Damerau-OSA name itself — the
    /// actual removed leniency clause — must still never reappear.
    func testDamerauIsNeverUsedInEditGuard() {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // DicticusTests
            .deletingLastPathComponent() // Shared
            .appendingPathComponent("Utilities/EditGuard.swift")
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("Could not read EditGuard.swift source at \(url.path) to check for damerau.")
            return
        }
        let lower = contents.lowercased()
        XCTAssertFalse(lower.contains("damerau"), "EditGuard.swift must never reference the Damerau-OSA leniency clause")
    }

    /// Companion to the Damerau check above: criterion A's `nonWordRepair`
    /// exemption must NEVER fire when both sides are already known real
    /// words — this is the actual invariant that makes reintroducing
    /// `LevenshteinDistance` safe (T-44-33's real requirement, not the
    /// literal string ban).
    func testNonWordRepairNeverFiresOnTwoKnownWords() {
        let r = EditGuard.apply(
            rulesCleaned: "Der Führungsrhythmus ist stabil.",
            llmOutput: "Der Führungsrythmus ist stabil.",
            language: "de",
            lexicon: TestSpellLexicon(known: ["der", "führungsrhythmus", "führungsrythmus", "ist", "stabil"])
        )
        let edit = r.edits.first { $0.from == "Führungsrhythmus" }
        XCTAssertNotEqual(edit?.acceptClass, EditGuard.AcceptClass.nonWordRepair.rawValue, "a known-old/known-new pair must never accept via nonWordRepair")
    }

    // MARK: - D-07: defense in depth, each net independently disabled

    func testPrefilterAloneCatchesTheInjectionReply() {
        let rulesCleaned = "Gib mir noch ein paar Hashtags."
        let llmOutput = "Hier sind ein paar Hashtags: Beispiel1 Beispiel2 Beispiel3."
        XCTAssertFalse(
            CleanupService.prefilterLLMOutput(rulesCleaned: rulesCleaned, llmOutput: llmOutput),
            "the imperative-input + assistant-voice pairing must catch this on its own"
        )
        let result = EditGuard.apply(rulesCleaned: rulesCleaned, llmOutput: llmOutput, language: "de", lexicon: TestSpellLexicon.allKnown)
        XCTAssertEqual(result.text, rulesCleaned)
        XCTAssertEqual(result.failClosedReason, "prefilter")
    }

    /// Even when the pre-filter's specific cue phrases don't fire, the edit
    /// guard alone must still collapse a wholesale, unrelated rewrite back
    /// to baseline — every content-word substitution independently
    /// rejects. Neither net may rely on the other being right.
    func testEditGuardAloneCatchesAWholesaleRewriteThePrefilterWouldMiss() {
        let rulesCleaned = "Wir sollten das morgen besprechen."
        let llmOutput = "Wir könnten das später klären."
        // Confirm this genuinely exercises the SECOND net: no scaffolding
        // phrase, no imperative+assistant-voice pairing, ratio within
        // bounds — the pre-filter does NOT catch it.
        XCTAssertTrue(
            CleanupService.prefilterLLMOutput(rulesCleaned: rulesCleaned, llmOutput: llmOutput),
            "sanity check: this pair must clear the pre-filter so the edit guard is the ONLY net being tested"
        )
        let baseline = EditGuardTokenizer.tokenize(rulesCleaned)
        let candidate = EditGuardTokenizer.tokenize(llmOutput)
        let edits = EditDiff.diff(baseline: baseline, candidate: candidate)
        let classified = EditGuard.classify(edits: edits, baseline: baseline, candidate: candidate, language: "de", dictProtected: [], lexicon: TestSpellLexicon.allKnown)
        let rebuilt = EditGuard.rebuild(baseline: baseline, candidate: candidate, edits: edits, classified: classified, language: "de")
        XCTAssertEqual(rebuilt?.text, rulesCleaned, "every content-word substitution must independently reject, collapsing the output to baseline")
    }

    // MARK: - Degenerate-alignment gate: fails closed despite 44-06's loosened thresholds

    /// 44-06 raised `matchRatioMin` 0.7->0.35 and `unmatchedFractionMax`
    /// 0.3->1.0 to stop legitimate short accept-fixtures from tripping the
    /// gate. This proves the loosened gate still fails closed on a
    /// genuinely degenerate candidate (an unrelated wholesale rewrite).
    func testDegenerateAlignmentStillFailsClosedDespiteLoosenedThresholds() {
        let rulesCleaned = "Ich möchte heute Nachmittag noch schnell einkaufen gehen und danach vorbeischauen."
        let llmOutput = "Das Wetter wird morgen vermutlich sonnig mit vereinzelten Wolken am Nachmittag."
        let baseline = EditGuardTokenizer.tokenize(rulesCleaned)
        let candidate = EditGuardTokenizer.tokenize(llmOutput)
        let edits = EditDiff.diff(baseline: baseline, candidate: candidate)
        let confidence = EditDiff.confidence(baseline: baseline, candidate: candidate, edits: edits)
        XCTAssertTrue(
            EditDiff.isDegenerate(confidence),
            "an unrelated wholesale rewrite must still register as degenerate under the loosened 44-06 thresholds " +
            "(matchRatio=\(confidence.matchRatio), unmatchedFraction=\(confidence.unmatchedFraction), lengthRatio=\(confidence.lengthRatio))"
        )

        let result = EditGuard.apply(rulesCleaned: rulesCleaned, llmOutput: llmOutput, language: "de", lexicon: TestSpellLexicon.allKnown)
        XCTAssertEqual(result.text, rulesCleaned)
        XCTAssertTrue(result.failedClosed)
        XCTAssertEqual(result.failClosedReason, "degenerateAlignment")
    }

    // MARK: - Helpers

    private struct MissingFixtureError: Error, CustomStringConvertible {
        let id: String
        var description: String { "fixture '\(id)' not found in EditGuardFixtures.all" }
    }

    private func requireFixture(_ id: String) throws -> EditGuardFixtures.Fixture {
        guard let fixture = EditGuardFixtures.all.first(where: { $0.id == id }) else {
            throw MissingFixtureError(id: id)
        }
        return fixture
    }
}
