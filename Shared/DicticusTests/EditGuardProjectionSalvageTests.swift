import XCTest
@testable import Dicticus

/// Quick task 260830-fp4: tests for item 1 (the `projectFormatting` salvage
/// path) and item 2 (`applySegmented`'s sub-utterance revert granularity).
///
/// Both mechanisms are wired as a FALLBACK, reached only after the existing
/// whole-window `classify`/`rebuild` pipeline (unmodified by this quick
/// task) has already fail-closed (`degenerateAlignment`/`rebuildInvariant`).
/// `EditGuardFixtures.all`'s 87 fixtures are deliberately shaped to NEVER
/// trip that condition (see `EditGuardFixtures.swift`'s own note on the
/// `fx-del-content-de-restoration-boundary-glue` fixture, and
/// `EditGuardTests.testRebuildNeverReturnsNilOnAnyFixture`) — so this file's
/// own fixtures are the only place these two mechanisms are exercised. See
/// `testNonVacuityAcrossFixtureCorpus` below for the direct proof of that
/// claim, and the quick task's SUMMARY.md for the full non-vacuity report.
@MainActor
final class EditGuardProjectionSalvageTests: XCTestCase {

    // MARK: - projectFormatting: direct unit tests

    /// Pure-casing rewrite ("all words normalized-equal, only case
    /// differs") is exactly the shape that trips `EditDiff.isDegenerate`
    /// (its `matchRatio` only counts EXACT-text `.keep` edits — a
    /// casing-only `.substitute` never counts, so a fully re-cased sentence
    /// can score near-zero matchRatio) while still being 100%
    /// content-identical. `projectFormatting` must salvage it, keeping the
    /// candidate's own casing for every word (none differ in `normalized`,
    /// so there is nothing to substitute back).
    func testProjectFormattingSalvagesPureCasingRewrite() {
        let source = "wir haben das Angebot heute Nachmittag noch einmal besprochen."
        let candidate = "WIR HABEN DAS ANGEBOT HEUTE NACHMITTAG NOCH EINMAL BESPROCHEN."
        XCTAssertEqual(EditGuard.projectFormatting(source: source, candidate: candidate), candidate)
    }

    /// Mixed case: 8/9 content words match (89% >= 80% threshold), one word
    /// ("heute" -> "MORGEN") is a genuine value change. The salvage must
    /// keep the candidate's casing for every MATCHING word, but substitute
    /// the SOURCE's original word (lowercased, exactly as dictated) back at
    /// the one position that changed — proving this is a safe word-level
    /// revert, not a blanket "keep everything" pass.
    func testProjectFormattingRevertsChangedWordButKeepsCandidateCasingElsewhere() {
        let source = "wir haben das Angebot heute Nachmittag noch einmal besprochen."
        let candidate = "WIR HABEN DAS ANGEBOT MORGEN NACHMITTAG NOCH EINMAL BESPROCHEN."
        let expected = "WIR HABEN DAS ANGEBOT heute NACHMITTAG NOCH EINMAL BESPROCHEN."
        XCTAssertEqual(EditGuard.projectFormatting(source: source, candidate: candidate), expected)
    }

    /// Safety proof (evidence gate): an INSERTION changes the content-token
    /// count, so it must be UNCONDITIONALLY excluded from the projection
    /// path — never salvaged, always falls through to the existing
    /// reject-to-baseline route.
    func testProjectFormattingReturnsNilOnInsertion() {
        let source = "wir haben das Angebot heute Nachmittag noch einmal besprochen."
        let candidateWithInsertedWord = "WIR HABEN DAS NEUE ANGEBOT HEUTE NACHMITTAG NOCH EINMAL BESPROCHEN."
        XCTAssertNil(EditGuard.projectFormatting(source: source, candidate: candidateWithInsertedWord))
    }

    /// Safety proof (evidence gate): a DELETION changes the content-token
    /// count, so it must be UNCONDITIONALLY excluded from the projection
    /// path — never salvaged, always falls through to the existing
    /// reject-to-baseline route.
    func testProjectFormattingReturnsNilOnDeletion() {
        let source = "wir haben das Angebot heute Nachmittag noch einmal besprochen."
        let candidateWithDroppedWord = "WIR HABEN DAS ANGEBOT HEUTE NACHMITTAG EINMAL BESPROCHEN."
        XCTAssertNil(EditGuard.projectFormatting(source: source, candidate: candidateWithDroppedWord))
    }

    /// Match-ratio gate, isolated from the count gate: EQUAL content-token
    /// count (8 words on each side) but only 3/8 (37.5%) match normalized —
    /// below the 80% threshold, so the two streams are too dissimilar to
    /// trust a positional word-for-word pairing at all.
    func testProjectFormattingReturnsNilOnLowMatchRatio() {
        let source = "der Kunde hat heute Nachmittag angerufen und gefragt."
        let candidate = "DER MITARBEITER WAR GESTERN VORMITTAG ANGEKOMMEN und GEFRAGT."
        XCTAssertNil(EditGuard.projectFormatting(source: source, candidate: candidate))
    }

    // MARK: - EditGuard.apply: end-to-end wiring through the fail-closed path

    /// The whole-window `classify`/`rebuild` pipeline fails closed
    /// (`degenerateAlignment`, per the casing-rewrite shape above); `apply`
    /// must salvage via `projectFormatting` instead of discarding the
    /// candidate's casing/punctuation wholesale.
    func testApplySalvagesWholeUtteranceViaProjectionWhenPipelineFailsClosed() {
        let rulesCleaned = "wir haben das Angebot heute Nachmittag noch einmal besprochen."
        let llmOutput = "WIR HABEN DAS ANGEBOT MORGEN NACHMITTAG NOCH EINMAL BESPROCHEN."
        let result = EditGuard.apply(rulesCleaned: rulesCleaned, llmOutput: llmOutput, language: "de", lexicon: TestSpellLexicon.allKnown)
        XCTAssertEqual(result.text, "WIR HABEN DAS ANGEBOT heute NACHMITTAG NOCH EINMAL BESPROCHEN.")
        XCTAssertFalse(result.failedClosed, "a successful salvage must not report failedClosed")
        XCTAssertNil(result.failClosedReason)
        XCTAssertEqual(result.edits.count, 1)
        XCTAssertEqual(result.edits.first?.acceptClass, "formattingProjection")
    }

    /// Regression net for the PRE-existing behavior (unchanged by this
    /// quick task): a genuinely degenerate pair with an insertion has NO
    /// salvage available (equal-count gate fails) and no eligible
    /// segmentation (single sentence on both sides) — `apply` must still
    /// fail closed to `rulesCleaned` exactly as it did before this task.
    func testApplyStillFailsClosedWhenNeitherSalvageNorSegmentationApply() {
        let rulesCleaned = "wir haben das Angebot heute Nachmittag noch einmal besprochen."
        let llmOutput = "WIR HABEN DAS NEUE ANGEBOT HEUTE NACHMITTAG NOCH EINMAL BESPROCHEN."
        let result = EditGuard.apply(rulesCleaned: rulesCleaned, llmOutput: llmOutput, language: "de", lexicon: TestSpellLexicon.allKnown)
        XCTAssertEqual(result.text, rulesCleaned)
        XCTAssertTrue(result.failedClosed)
        XCTAssertEqual(result.failClosedReason, "degenerateAlignment")
        XCTAssertTrue(result.edits.isEmpty)
    }

    // MARK: - applySegmented: sub-utterance revert granularity

    /// Two-sentence utterance: sentence 1 is the salvageable casing-rewrite
    /// shape above; sentence 2 is a wholesale unrelated rewrite (the exact
    /// pair `EditGuardTests.testDegenerateAlignmentStillFailsClosedDespiteLoosenedThresholds`
    /// pins as genuinely degenerate with no salvage possible). The WHOLE
    /// utterance is degenerate too (diluted matchRatio) and whole-text
    /// projection cannot salvage it either (sentence 2's content shares
    /// almost no words with its candidate). `apply` must revert ONLY
    /// sentence 2 to its own baseline while sentence 1 keeps its
    /// LLM-approved casing polish — proving the fallback grants revert
    /// granularity BELOW the whole utterance, not just an all-or-nothing
    /// binary switch to a smaller all-or-nothing binary.
    func testApplyRevertsOnlyTheFailingSegmentNotTheWholeUtterance() {
        let sentence1Baseline = "wir haben das Angebot heute Nachmittag noch einmal besprochen."
        let sentence1Candidate = "WIR HABEN DAS ANGEBOT MORGEN NACHMITTAG NOCH EINMAL BESPROCHEN."
        let sentence2Baseline = "Ich möchte heute Nachmittag noch schnell einkaufen gehen und danach vorbeischauen."
        let sentence2Candidate = "Das Wetter wird morgen vermutlich sonnig mit vereinzelten Wolken am Nachmittag."

        let rulesCleaned = sentence1Baseline + " " + sentence2Baseline
        let llmOutput = sentence1Candidate + " " + sentence2Candidate

        // Sanity check pinning this fixture's own shape, so a future change
        // to EditDiff's thresholds fails LOUDLY here instead of silently
        // making this test vacuous.
        let wholeBaseline = EditGuardTokenizer.tokenize(rulesCleaned)
        let wholeCandidate = EditGuardTokenizer.tokenize(llmOutput)
        let wholeEdits = EditDiff.diff(baseline: wholeBaseline, candidate: wholeCandidate)
        let wholeConfidence = EditDiff.confidence(baseline: wholeBaseline, candidate: wholeCandidate, edits: wholeEdits)
        XCTAssertTrue(EditDiff.isDegenerate(wholeConfidence), "sanity: the WHOLE utterance must be degenerate for this test to exercise applySegmented at all")
        XCTAssertNil(EditGuard.projectFormatting(source: rulesCleaned, candidate: llmOutput), "sanity: whole-text projection must NOT be able to salvage this pair, or applySegmented is never reached")

        let result = EditGuard.apply(rulesCleaned: rulesCleaned, llmOutput: llmOutput, language: "de", lexicon: TestSpellLexicon.allKnown)

        let expected = "WIR HABEN DAS ANGEBOT heute NACHMITTAG NOCH EINMAL BESPROCHEN. " + sentence2Baseline
        XCTAssertEqual(result.text, expected)
        XCTAssertFalse(result.failedClosed, "at least one segment succeeded, so the aggregate must not report failedClosed")
        // Sentence 1 contributes the salvage marker; sentence 2 fails closed
        // and contributes no edits (matching the single-window fail-closed
        // convention of edits: []).
        XCTAssertEqual(result.edits.count, 1)
        XCTAssertEqual(result.edits.first?.acceptClass, "formattingProjection")
    }

    /// When the two sides split into a DIFFERENT number of sentences (the
    /// LLM restructured a boundary), `applySegmented` must decline (return
    /// nil) rather than guess a cross-stream pairing — `apply` falls
    /// through to the existing whole-text fail-closed behavior, unchanged.
    func testApplyFallsBackToWholeUtteranceOnSentenceCountMismatch() {
        let sentence1Baseline = "wir haben das Angebot heute Nachmittag noch einmal besprochen."
        let sentence2Baseline = "Ich möchte heute Nachmittag noch schnell einkaufen gehen und danach vorbeischauen."
        let rulesCleaned = sentence1Baseline + " " + sentence2Baseline
        // Lowercase continuation after the first period collapses this to
        // ONE sentence under boundarySentenceSpans (no uppercase opener) —
        // a genuine count mismatch (2 vs 1) against `rulesCleaned` above.
        let llmOutput = "Das Wetter wird morgen vermutlich sonnig. mit vereinzelten Wolken am Nachmittag und einem kuehlen Abend spaeter."

        XCTAssertEqual(SelfCorrectionResolver.boundarySentenceSpans(rulesCleaned).count, 2, "sanity: baseline must split into 2 sentences")
        XCTAssertEqual(SelfCorrectionResolver.boundarySentenceSpans(llmOutput).count, 1, "sanity: candidate must collapse to 1 sentence, for a genuine count mismatch")

        let result = EditGuard.apply(rulesCleaned: rulesCleaned, llmOutput: llmOutput, language: "de", lexicon: TestSpellLexicon.allKnown)
        XCTAssertEqual(result.text, rulesCleaned, "count mismatch must fall through to the plain whole-utterance fail-closed revert")
        XCTAssertTrue(result.failedClosed)
        XCTAssertEqual(result.failClosedReason, "degenerateAlignment")
    }

    // MARK: - Non-vacuity: does the frozen fixture corpus exercise this at all?

    /// Direct proof of the claim in this file's header comment: sweeps
    /// every fixture in `EditGuardFixtures.all` and counts how many would
    /// even REACH the salvage/segment fallback (i.e., trip
    /// `EditDiff.isDegenerate` at the whole-utterance level — the only
    /// realistic trigger in this corpus, since
    /// `EditGuardTests.testRebuildNeverReturnsNilOnAnyFixture` already
    /// proves `rebuildInvariant` never fires on it). Per the evidence
    /// gate: if this count is 0, that is reported as a finding in
    /// SUMMARY.md, not hidden — the corpus was deliberately shaped
    /// (`EditGuardFixtures.swift`'s own note on
    /// `fx-del-content-de-restoration-boundary-glue`) to keep every
    /// fixture on the classify/rebuild path, so 0 is the EXPECTED count,
    /// not a bug.
    func testNonVacuityAcrossFixtureCorpus() {
        var degenerateCount = 0
        for fixture in EditGuardFixtures.all {
            let baseline = EditGuardTokenizer.tokenize(fixture.baseline)
            let candidate = EditGuardTokenizer.tokenize(fixture.candidate)
            let edits = EditDiff.diff(baseline: baseline, candidate: candidate)
            let confidence = EditDiff.confidence(baseline: baseline, candidate: candidate, edits: edits)
            if EditDiff.isDegenerate(confidence) {
                degenerateCount += 1
            }
        }
        XCTAssertEqual(
            degenerateCount, 0,
            "EditGuardFixtures.all is deliberately shaped so no fixture trips isDegenerate — " +
            "if this changes, the projection/segment fallback paths are now exercised by the " +
            "frozen corpus and this quick task's non-vacuity report in SUMMARY.md needs updating."
        )
    }

    // MARK: - Item 3: the em-dash-at-restart-boundary todo

    /// `.planning/todos/pending/llm-inserts-em-dash-at-restart-boundary.md`
    /// reproduction, run through the ACTUAL pipeline. The em-dash insertion
    /// is classified and ACCEPTED by the existing (unmodified)
    /// `classifyInsert` — it is on the prosodic-punctuation allowlist
    /// (D-06) — so the whole-window `classify`/`rebuild` pipeline SUCCEEDS
    /// normally and never reaches `failedClosed`. Neither
    /// `salvageWithProjection` nor `applySegmented` is ever invoked for
    /// this input, because `apply` only tries them after
    /// `whole.failedClosed` is true (see `apply`'s own doc comment on why
    /// that ordering is deliberate). This test locks in that finding: the
    /// em-dash is asserted PRESENT, documenting that items 1+2 do NOT
    /// resolve this bug — see the quick task's SUMMARY.md for the full
    /// verdict. This is NOT a fix-verification test; flip it only once a
    /// future change actually addresses `classifyInsert`'s D-06 allowlist
    /// (out of scope for this quick task per its own constraints).
    func testEmDashBugIsNotResolvedByProjectionOrSegmentFallback() {
        let rulesCleaned = "you know, Assembly AI, WhisperKit and Parakeet Assembly AI in my opinion performed the best overall."
        let llmOutput = "you know, Assembly AI, WhisperKit, and Parakeet—Assembly AI, in my opinion, performed the best overall."
        let result = EditGuard.apply(rulesCleaned: rulesCleaned, llmOutput: llmOutput, language: "en", lexicon: TestSpellLexicon.allKnown)
        XCTAssertFalse(result.failedClosed, "sanity: this pair must classify/rebuild normally — it never reaches the fallback ladder this quick task adds")
        XCTAssertTrue(result.text.contains("—"), "documents the OPEN todo: the em-dash insertion is accepted by classifyInsert's existing D-06 prosodic-punctuation allowlist, unaffected by items 1+2")
    }
}
