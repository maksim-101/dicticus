import XCTest
@testable import Dicticus

/// Phase 44 Plan 02 Task 2: the coverage-lock test. Reads ONLY
/// `EditGuardFixtures` — it calls no guard code and must therefore be GREEN
/// the moment Task 1 lands. It locks the fixture set; it does not test the
/// guard.
///
/// Mirrors the "ship-list lock" convention established by
/// `FillerWordRemover.swift`'s `testGermanFillerShipList` (asserts the exact
/// set so nobody widens it silently) — applied here to fixture coverage
/// instead of a filler list.
final class EditGuardFixtureCoverageTests: XCTestCase {

    // MARK: - Cell enumeration

    private static let allCells: [String] = {
        var cells: [String] = []
        for editKind in [EditGuard.EditKind.substitute, .delete, .insert, .move] {
            for tokenClass in EditGuardFixtures.TokenClass.allCases {
                for position in EditGuardFixtures.Position.allCases {
                    for language in ["de", "en"] {
                        cells.append("\(editKind.rawValue)|\(tokenClass.rawValue)|\(position.rawValue)|\(language)")
                    }
                }
            }
        }
        return cells
    }()

    // MARK: - testEveryCellIsCoveredOrPruned

    func testEveryCellIsCoveredOrPruned() {
        XCTAssertEqual(
            Self.allCells.count, 120,
            "Sanity check on the cross-product itself: 4 editKinds x 5 " +
            "tokenClasses x 3 positions x 2 languages must be 120."
        )

        let coveredCells = Set(EditGuardFixtures.all.map(\.cell))
        let prunedCellNames = Set(EditGuardFixtures.prunedCells.map(\.cell))

        // No cell may be BOTH covered and pruned — that would hide a real
        // fixture behind a false "pruned" claim.
        let overlap = coveredCells.intersection(prunedCellNames)
        XCTAssertTrue(
            overlap.isEmpty,
            "Cells claimed as both covered AND pruned (pick one): \(overlap.sorted())"
        )

        var missing: [String] = []
        for cell in Self.allCells {
            if !coveredCells.contains(cell) && !prunedCellNames.contains(cell) {
                missing.append(cell)
            }
        }
        XCTAssertTrue(
            missing.isEmpty,
            "The following shape cells are neither covered by a fixture nor " +
            "explicitly pruned with a reason — this is exactly the Phase 39 " +
            "monoculture failure mode: \(missing.sorted())"
        )
    }

    // MARK: - testNoDimensionIsMonocultural

    func testNoDimensionIsMonocultural() {
        func assertAtLeastTwoFixturesPerCase<T: Hashable>(
            _ extract: (EditGuardFixtures.Fixture) -> T,
            allCases: [T],
            dimensionName: String
        ) {
            var counts: [T: Int] = [:]
            for fixture in EditGuardFixtures.all {
                counts[extract(fixture), default: 0] += 1
            }
            for caseValue in allCases {
                let count = counts[caseValue, default: 0]
                XCTAssertGreaterThanOrEqual(
                    count, 2,
                    "Dimension '\(dimensionName)' case '\(caseValue)' appears " +
                    "in only \(count) fixture(s) — this is the exact Phase 39 " +
                    "monoculture shape (one fixture technically exists but the " +
                    "dimension is not genuinely exercised)."
                )
            }
        }

        assertAtLeastTwoFixturesPerCase(
            { $0.editKind }, allCases: [.substitute, .delete, .insert, .move],
            dimensionName: "editKind"
        )
        assertAtLeastTwoFixturesPerCase(
            { $0.tokenClass }, allCases: EditGuardFixtures.TokenClass.allCases,
            dimensionName: "tokenClass"
        )
        assertAtLeastTwoFixturesPerCase(
            { $0.position }, allCases: EditGuardFixtures.Position.allCases,
            dimensionName: "position"
        )
        assertAtLeastTwoFixturesPerCase(
            { $0.language }, allCases: ["de", "en"],
            dimensionName: "language"
        )
    }

    // MARK: - testBothVerdictsPresentPerEditKind

    func testBothVerdictsPresentPerEditKind() {
        for editKind in [EditGuard.EditKind.substitute, .delete, .insert, .move] {
            let fixturesForKind = EditGuardFixtures.all.filter { $0.editKind == editKind }
            let hasAccept = fixturesForKind.contains { $0.expectedVerdict == .accept }
            let hasReject = fixturesForKind.contains { $0.expectedVerdict == .reject }
            XCTAssertTrue(
                hasAccept,
                "editKind '\(editKind.rawValue)' has zero .accept fixtures — a " +
                "gate that only ever sees rejects for an edit kind cannot prove " +
                "it does not over-reject (the 36.6 failure mode)."
            )
            XCTAssertTrue(
                hasReject,
                "editKind '\(editKind.rawValue)' has zero .reject fixtures."
            )
        }
    }

    // MARK: - testRequiredFixturesPresent

    /// Hardcoded ids of fixtures the plan and its acceptance criteria name
    /// explicitly. A future agent cannot make this suite green by quietly
    /// deleting an inconvenient fixture — the id must exist.
    private static let requiredFixtureIDs: Set<String> = [
        // The five ROADMAP-named corruptions (plan acceptance criteria)
        "fx-sub-digit-en-value",
        "fx-sub-pronoun-de-personflip",
        "fx-mov-func-en-moodlock",
        "fx-del-pronoun-en-sentenceinitial",
        "fx-sub-content-de-typo-introduced",
        // D-04 core word-order-repair evidence
        "fx-mov-func-de-wordorder",
        "fx-mov-content-de-moodlock-falsepos",
        // D-02 / D-02a required fixtures
        "fx-sub-content-de-inflection-beinhalten",
        "fx-sub-func-de-der-das",
        "fx-sub-content-de-format-formats",
        "fx-ins-func-de",
        "fx-sub-content-de-handhabe-handhabung",
        "fx-sub-content-de-krankheit-kraenkung",
        "fx-sub-content-de-beobachter-beobachtung",
        // RESEARCH-named rule-defeating inputs
        "fx-sub-content-de-messer-messe",
        "fx-sub-content-de-wagen-wagt",
        "fx-sub-content-de-hunde-hund",
        "fx-sub-content-de-tolles-toll",
        "fx-sub-content-de-lauft-umlaut",
        "fx-sub-content-de-singen-ablaut",
        // D-05 required negative (particle) fixtures
        "fx-del-filler-en-interior-actually",
        "fx-del-filler-en-interior-like",
        "fx-del-filler-de-si-noch",
        "fx-del-filler-en-terminal-well",
        "fx-del-filler-en-interior-right",
        "fx-del-filler-de-si-doch",
        "fx-del-filler-en-interior-imean",
        // D-06 required negative (insertion) fixtures
        "fx-ins-content-de-gefahrenwar",
        "fx-ins-content-de-dieseteile",
        "fx-ins-content-de-einanderes",
        "fx-ins-digit-de",
        // Filler-deletion / repetition accepts
        "fx-del-filler-de-si-aehm",
        "fx-del-filler-en-interior-umuh",
        "fx-del-filler-de-interior-repetition",
        // Punctuation/casing + number-form-change
        "fx-req-punctcasing-de",
        "fx-req-punctcasing-en",
        "fx-sub-digit-de-numberform",
        "fx-sub-digit-en-numberform",
        // D-01 architecture proof
        "fx-d01-bundled-repair-and-corruption-de",
        // SC#3 gap-closure fixtures (44-FIDELITY-REPLAY.md §2/§3/§6 —
        // classifySubstitute rule #2 word-vs-punctuation hole + the
        // restoration-boundary glued-word defect)
        "fx-sub-punct-en-orphan-contraction",
        "fx-del-content-de-restoration-boundary-glue",
        // Live-user regression, corpus 2026-07-12T09:38:37.354Z — the exact
        // "goodshine" pause-dots -> em-dash repair the old inverted gate
        // reverted at the user's cursor. See EditGuardFixtures.swift's
        // goodshinePauseDotsFixture doc comment.
        "fx-sub-punct-en-goodshine-pausedots-emdash",
        // Punctuation-move corruption fix (classifyMove/pairMovesFirst,
        // SAME live corpus record's FULL two-sentence shape, plus its
        // flagship-class counter-proof): a rejected edit's stray
        // punctuation must never be mis-paired via EditDiff's unbounded
        // move-matching and injected elsewhere; a genuine long-distance
        // German word-order repair must still accept. See
        // EditGuardFixtures.swift's goodshineFullRecordSpuriousMoveFixture
        // / longDistanceGermanWordOrderRepairFixture doc comments.
        "fx-mov-punct-en-goodshine-fullrecord-spuriousmove",
        "fx-mov-content-de-longdistance-objectfronting",
        // DUAL-ROLE class fix (Plan 14 — 44-AUDIT-FRESH-CORRUPTION.md). The
        // live Qwen3.5 leak (copula 'sein' invented at a truncated seam), its
        // priced cost (a genuine auxiliary 'sein' is rejected too — fail
        // closed, no POS awareness), and the English twin ('after') of the
        // 'before' bug that was fixed as an instance. See FunctionWords.swift's
        // "THE DUAL-ROLE CRITERION".
        "fx-ins-func-de-sein-copula-invented",
        "fx-ins-func-de-sein-auxiliary-pricedcost",
        "fx-ins-func-en-after-adverb",
        // GAP CLOSURE (2026-07-13): Defect B fix proof (an accepted
        // substitute/insert adjacent to a rejected contentWordDeletion
        // reverts too — "In to Regarding the definition..." no longer
        // produced) + Defect A's known-open cross-clause move mispairing,
        // locked in as a regression net since no safe fix was found. See
        // 44-FIDELITY-REPLAY.md's gap-closure section.
        "fx-sub-content-en-inregardsto-couplingfix",
        "fx-mov-content-de-crossclause-manicht-knownopen"
    ]

    func testRequiredFixturesPresent() {
        XCTAssertGreaterThanOrEqual(
            Self.requiredFixtureIDs.count, 15,
            "This lock must hardcode at least 15 required fixture ids per " +
            "the plan's acceptance criteria."
        )
        let presentIDs = Set(EditGuardFixtures.all.map(\.id))
        let missing = Self.requiredFixtureIDs.subtracting(presentIDs)
        XCTAssertTrue(
            missing.isEmpty,
            "The following REQUIRED fixture ids are missing from " +
            "EditGuardFixtures.all — do not quietly drop an inconvenient " +
            "fixture: \(missing.sorted())"
        )
    }

    // MARK: - testExpectedTextIsSelfConsistent

    func testExpectedTextIsSelfConsistent() {
        // The D-01 bundled fixture is both accept and reject at the edit
        // level (that is the entire point of it existing) and is exempted
        // by id from this per-verdict check. fx-del-content-de-restoration-
        // boundary-glue is the same shape: a REJECTED content-word deletion
        // run riding alongside one independently-ACCEPTED cosmetic comma
        // deletion (see its own note for why) — see EditGuardFixtures.swift.
        // fx-mov-content-de-crossclause-manicht-knownopen (260723-rif):
        // `applyAtomicGroupCoupling` now reverts EVERY move in this record
        // (0 accepted wordOrderRepair, down from several — see its own
        // 260723-rif note), so its expectedText — still `.accept` by the
        // SAME "convention only" precedent d01Bundled established — now
        // happens to equal baseline byte-for-byte. Exempted for the same
        // reason d01Bundled is: the per-verdict check assumes `.accept`
        // always changes text, which is no longer true for this record.
        let exemptIDs: Set<String> = [
            "fx-d01-bundled-repair-and-corruption-de",
            "fx-del-content-de-restoration-boundary-glue",
            "fx-mov-content-de-crossclause-manicht-knownopen"
        ]

        for fixture in EditGuardFixtures.all where !exemptIDs.contains(fixture.id) {
            switch fixture.expectedVerdict {
            case .accept:
                XCTAssertNotEqual(
                    fixture.expectedText, fixture.baseline,
                    "[\(fixture.id)] .accept fixture's expectedText must " +
                    "differ from baseline — an accepted edit changes the text."
                )
            case .reject:
                XCTAssertEqual(
                    fixture.expectedText, fixture.baseline,
                    "[\(fixture.id)] .reject fixture's expectedText must " +
                    "equal baseline on a single-edit pair — a rejected edit " +
                    "leaves the baseline token in place."
                )
            }
        }
    }

    // MARK: - Sanity: the corpus itself is non-trivial

    func testFixtureCountMeetsMinimum() {
        XCTAssertGreaterThanOrEqual(
            EditGuardFixtures.all.count, 60,
            "Plan Task 1 acceptance criteria: EditGuardFixtures.all.count >= 60."
        )
    }
}
