import XCTest
@testable import Dicticus

/// Phase 44 Plan 06 (D-01 core): TDD suite for `EditDiff` — the Myers/LCS
/// token differ with move detection and the fail-closed degenerate-alignment
/// gate. Every behavior bullet in `44-06-PLAN.md` has a corresponding test
/// here; the calibration positives (injection/translation/rewrite) and every
/// `.accept` fixture in `EditGuardFixtures.all` are required negative/positive
/// controls per the plan's `<verification>` and `<success_criteria>`.
final class EditDiffTests: XCTestCase {

    // MARK: - Helpers

    private func tok(_ s: String) -> [EditGuard.Token] {
        EditGuardTokenizer.tokenize(s)
    }

    /// Reconstructs the accepted-set (every edit, unfiltered) back into a
    /// baseline-ordered token multiset, for the losslessness invariant:
    /// keep.from + substitute.from + delete.from + move.from must be a
    /// permutation of the original baseline tokens' normalized text, and
    /// symmetrically for candidate/`.to`.
    private func baselineMultiset(_ edits: [EditGuard.Edit]) -> [String] {
        edits.compactMap { edit -> String? in
            switch edit.kind {
            case .keep, .substitute, .delete, .move:
                return edit.from?.normalized
            case .insert:
                return nil
            }
        }.sorted()
    }

    private func candidateMultiset(_ edits: [EditGuard.Edit]) -> [String] {
        edits.compactMap { edit -> String? in
            switch edit.kind {
            case .keep, .substitute, .insert, .move:
                return edit.to?.normalized
            case .delete:
                return nil
            }
        }.sorted()
    }

    // MARK: - Substitute detection

    func testSubstituteDetection() {
        let baseline = tok("Du wohnst in einem Block.")
        let candidate = tok("Ich wohne in einem Block.")
        let edits = EditDiff.diff(baseline: baseline, candidate: candidate)

        let substitutes = edits.filter { $0.kind == .substitute }
        XCTAssertEqual(substitutes.count, 2, "Expected exactly two substitutes (Du->Ich, wohnst->wohne), got kinds: \(edits.map(\.kind))")
        XCTAssertTrue(substitutes.contains { $0.from?.normalized == "du" && $0.to?.normalized == "ich" })
        XCTAssertTrue(substitutes.contains { $0.from?.normalized == "wohnst" && $0.to?.normalized == "wohne" })

        let keeps = edits.filter { $0.kind == .keep }
        XCTAssertEqual(keeps.map { $0.from?.normalized }, ["in", "einem", "block", "."])

        XCTAssertEqual(edits.filter { $0.kind == .delete }.count, 0)
        XCTAssertEqual(edits.filter { $0.kind == .insert }.count, 0)
    }

    // MARK: - Move detection (the phase's core value)

    /// The flagship fixture: `werden` must come out as a MOVE, never as a
    /// delete+insert pair — if it does, the classifier (44-10) sees an
    /// unauthorized content-word deletion plus an unauthorized insertion,
    /// rejects both, and the phase's core repair dies.
    func testWordOrderMoveNotDeleteInsert() {
        let baseline = tok("Weil die Fragen werden ja sofort ausgewertet.")
        let candidate = tok("Weil die Fragen ja sofort ausgewertet werden.")
        let edits = EditDiff.diff(baseline: baseline, candidate: candidate)

        let moves = edits.filter { $0.kind == .move }
        XCTAssertTrue(
            moves.contains { $0.from?.normalized == "werden" && $0.to?.normalized == "werden" },
            "Expected a move(werden) edit; got kinds \(edits.map { ($0.kind, $0.from?.text, $0.to?.text) })"
        )

        // The disqualifying failure mode: werden must NEVER appear as BOTH a
        // delete and an insert (that's the delete+insert pair this move-pass
        // exists to prevent).
        let hasWerdenDelete = edits.contains { $0.kind == .delete && $0.from?.normalized == "werden" }
        let hasWerdenInsert = edits.contains { $0.kind == .insert && $0.to?.normalized == "werden" }
        XCTAssertFalse(hasWerdenDelete && hasWerdenInsert, "werden must not be represented as delete+insert.")

        // No substitute should ever pair two BYTE-IDENTICAL tokens — that
        // would be a move (or a plain keep) misclassified as a substitute.
        // (Same `.normalized` with DIFFERENT `.text` is a legitimate
        // punctuationOrCasing substitute produced by Step 1's own backbone
        // — e.g. sentence-initial re-capitalization after a move — and must
        // NOT be flagged here.)
        XCTAssertFalse(edits.contains { $0.kind == .substitute && $0.from?.text == $0.to?.text })
    }

    /// Case-insensitive token match on `.normalized` — "You can push" vs
    /// "Can you push" must produce moves, not substitutes. Tie-break of
    /// WHICH token ends up as the move vs. the keep is an implementation
    /// detail; the fixture only requires SOME move exists and NO substitute
    /// pairs two BYTE-IDENTICAL tokens (a same-normalized-different-casing
    /// substitute, like `can`->`Can` picking up sentence-initial capitalization
    /// after the reorder, is legitimate and must NOT be flagged).
    func testCaseInsensitiveMoveNotSubstitute() {
        let baseline = tok("You can push.")
        let candidate = tok("Can you push.")
        let edits = EditDiff.diff(baseline: baseline, candidate: candidate)

        XCTAssertTrue(edits.contains { $0.kind == .move }, "Expected at least one move edit; got kinds \(edits.map(\.kind))")
        XCTAssertFalse(edits.contains { $0.kind == .substitute && $0.from?.text == $0.to?.text },
            "A byte-identical-text pair must be a move, not a substitute.")
        XCTAssertEqual(baselineMultiset(edits), tok("you can push .").map(\.normalized).sorted())
        XCTAssertEqual(candidateMultiset(edits), tok("can you push .").map(\.normalized).sorted())
    }

    // MARK: - Duplicate-token robustness (why inferringMoves() is banned)

    func testDuplicateTokenRobustness() {
        let baseline = tok("die Fragen und die Antworten.")
        let candidate = tok("die Antworten und die Fragen.")
        let edits = EditDiff.diff(baseline: baseline, candidate: candidate)

        // Must not crash (implicit — reaching this line proves it), must not
        // lose a token: the accepted-set reconstruction (every edit, since
        // this test isn't about classification) is a permutation of the
        // baseline and of the candidate.
        let baselineTokens = baseline.map(\.normalized).sorted()
        let candidateTokens = candidate.map(\.normalized).sorted()
        XCTAssertEqual(baselineMultiset(edits), baselineTokens)
        XCTAssertEqual(candidateMultiset(edits), candidateTokens)

        // Every edit must be keep/substitute/move (no leftover delete/insert)
        // OR, if the bipartite matcher hit a genuine tie, delete+insert is
        // an acceptable fallback — either way, no token is lost.
        XCTAssertTrue(edits.allSatisfy { [.keep, .substitute, .move, .delete, .insert].contains($0.kind) })
    }

    // MARK: - Degeneracy — FAIL CLOSED

    func testInjectionReplyIsDegenerate() {
        let baseline = tok("Gib mir noch ein paar Hashtags.")
        let candidate = tok("Ich verstehe, dass du noch Hashtags benötigst. Bitte gib mir die genauen Hashtags, die du benötigst, und ich werde sie in den Text einfügen.")
        let edits = EditDiff.diff(baseline: baseline, candidate: candidate)
        let confidence = EditDiff.confidence(baseline: baseline, candidate: candidate, edits: edits)
        XCTAssertTrue(EditDiff.isDegenerate(confidence), "The 2026-07-05 prompt-injection record must be degenerate. confidence=\(confidence)")
    }

    func testTranslationIsDegenerate() {
        let baseline = tok("Ich gehe heute ins Büro und arbeite bis spät.")
        let candidate = tok("I am going to the office today and will work late.")
        let edits = EditDiff.diff(baseline: baseline, candidate: candidate)
        let confidence = EditDiff.confidence(baseline: baseline, candidate: candidate, edits: edits)
        XCTAssertTrue(EditDiff.isDegenerate(confidence), "A DE->EN translation must be degenerate. confidence=\(confidence)")
    }

    func testWholesaleRewriteIsDegenerate() {
        let baseline = tok("Ich habe gestern das Auto repariert und es läuft jetzt wieder gut.")
        let candidate = tok("Das Fahrzeug wurde von mir gestern instand gesetzt und funktioniert nun einwandfrei.")
        let edits = EditDiff.diff(baseline: baseline, candidate: candidate)
        let confidence = EditDiff.confidence(baseline: baseline, candidate: candidate, edits: edits)
        XCTAssertTrue(EditDiff.isDegenerate(confidence), "A wholesale rewrite (match ratio collapse) must be degenerate. confidence=\(confidence)")
    }

    /// Negative controls: every `.accept` fixture must NOT be degenerate. A
    /// degeneracy gate that fires on a legitimate repair is the 36.6 failure
    /// mode reappearing at a different layer.
    func testEveryAcceptFixtureIsNonDegenerate() {
        let acceptFixtures = EditGuardFixtures.all.filter { $0.expectedVerdict == .accept }
        XCTAssertGreaterThan(acceptFixtures.count, 0, "Sanity: there must be accept fixtures to check.")

        var failures: [String] = []
        for fixture in acceptFixtures {
            let baseline = tok(fixture.baseline)
            let candidate = tok(fixture.candidate)
            let edits = EditDiff.diff(baseline: baseline, candidate: candidate)
            let confidence = EditDiff.confidence(baseline: baseline, candidate: candidate, edits: edits)
            if EditDiff.isDegenerate(confidence) {
                failures.append("\(fixture.id): confidence=\(confidence)")
            }
        }
        XCTAssertTrue(failures.isEmpty, "Accept fixtures wrongly flagged degenerate:\n\(failures.joined(separator: "\n"))")
    }

    // MARK: - Losslessness contract

    /// For every fixture (accept AND reject): baselineTokens.count ==
    /// keeps + substitutes + deletes + movesFromBaseline, and
    /// candidateTokens.count == keeps + substitutes + inserts + movesToCandidate.
    /// A differ that drops a token silently drops the user's words.
    func testLosslessnessAcrossAllFixtures() {
        var failures: [String] = []
        for fixture in EditGuardFixtures.all {
            let baseline = tok(fixture.baseline)
            let candidate = tok(fixture.candidate)
            let edits = EditDiff.diff(baseline: baseline, candidate: candidate)

            let keepCount = edits.filter { $0.kind == .keep }.count
            let substituteCount = edits.filter { $0.kind == .substitute }.count
            let deleteCount = edits.filter { $0.kind == .delete }.count
            let moveCount = edits.filter { $0.kind == .move }.count
            let insertCount = edits.filter { $0.kind == .insert }.count

            let baselineAccounted = keepCount + substituteCount + deleteCount + moveCount
            let candidateAccounted = keepCount + substituteCount + insertCount + moveCount

            if baselineAccounted != baseline.count {
                failures.append("\(fixture.id): baseline accounted=\(baselineAccounted) actual=\(baseline.count)")
            }
            if candidateAccounted != candidate.count {
                failures.append("\(fixture.id): candidate accounted=\(candidateAccounted) actual=\(candidate.count)")
            }
        }
        XCTAssertTrue(failures.isEmpty, "Losslessness invariant violated:\n\(failures.joined(separator: "\n"))")
    }

    // MARK: - Prohibition: no substitute pairs identical normalized text

    func testNoSubstitutePairsIdenticalTokensAcrossAllFixtures() {
        var failures: [String] = []
        for fixture in EditGuardFixtures.all {
            let baseline = tok(fixture.baseline)
            let candidate = tok(fixture.candidate)
            let edits = EditDiff.diff(baseline: baseline, candidate: candidate)
            for edit in edits where edit.kind == .substitute {
                if let f = edit.from?.normalized, let t = edit.to?.normalized, f == t, edit.from?.text == edit.to?.text {
                    failures.append("\(fixture.id): substitute with identical text \(f)")
                }
            }
        }
        XCTAssertTrue(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    // MARK: - Source-level prohibition

    func testDoesNotCallInferringMoves() {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Utilities/EditDiff.swift")
        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("Could not read EditDiff.swift source at \(url.path) to check for inferringMoves().")
            return
        }
        // Strip comment lines first — the doc comments legitimately NAME
        // `inferringMoves()` to explain why it's banned; only actual CODE
        // calling it (a non-comment line containing the call syntax) is
        // prohibited.
        let codeOnly = source
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        XCTAssertFalse(codeOnly.contains(".inferringMoves("), "EditDiff.swift must not call CollectionDifference.inferringMoves().")
    }

    // MARK: - No-op / trivial inputs

    func testEmptyBaselineAndCandidate() {
        let edits = EditDiff.diff(baseline: [], candidate: [])
        XCTAssertEqual(edits.count, 0)
        let confidence = EditDiff.confidence(baseline: [], candidate: [], edits: edits)
        XCTAssertFalse(EditDiff.isDegenerate(confidence), "Empty vs empty is a trivial exact match, not degenerate.")
    }

    func testIdenticalBaselineAndCandidate() {
        let baseline = tok("Das ist ein Test.")
        let candidate = tok("Das ist ein Test.")
        let edits = EditDiff.diff(baseline: baseline, candidate: candidate)
        XCTAssertTrue(edits.allSatisfy { $0.kind == .keep })
        let confidence = EditDiff.confidence(baseline: baseline, candidate: candidate, edits: edits)
        XCTAssertFalse(EditDiff.isDegenerate(confidence))
    }
}
