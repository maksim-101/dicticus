import XCTest
@testable import Dicticus

/// Quick task 260901-8m3: post-`materialize` invariant property suite.
///
/// Six separate quick tasks (260723-rif, 260724-j96, 260801-9n7, 260830-dc4,
/// 260831-ad8, 260831-gd9) each closed ONE instance of the same recurring
/// defect class — `EditGuard.apply(...)`'s output containing text that
/// appears in NEITHER the rules baseline NOR the LLM candidate — after a user
/// hit it live. This file turns the axes that class can occupy into
/// properties asserted across the whole corpus (`EditGuardFixtures.all` +
/// `EditGuardFixtures.productionRecords`), so the NEXT member of this class
/// fails a test here instead of shipping to a user first.
///
/// PROPERTY MAP — one row per axis of the known defect taxonomy, naming the
/// test/in-code check that OWNS it, the file it lives in, and the quick task
/// that motivated it. Finalized in Task 3 with the printed non-vacuity counts
/// from each property's passing run.
///
/// | Axis | Owner | File | Motivating quick task |
/// |---|---|---|---|
/// | WORD multiset (accepted inserts/deletes/substitutes/moves balance) | `EditGuard.multisetInvariantHolds` (in-code, fail-closed on every call) | `EditGuard.swift` | Phase 44 (pre-dates the quick-task series; punctuation deliberately excluded — this invariant is about words, not formatting) |
/// | WORD-bigram order / neither-source splice (word-only) | `EditGuardMergeAtomicityTests.testAggregate_allGoldenFixturesNeitherSourceClean` (tier 1, zero allowances, all of `EditGuardFixtures.all`) + this file's `testTier1NeitherSourceClean_productionRecords_P3Extension` (same tier-1 checker, widened to `productionRecords`) | `EditGuardMergeAtomicityTests.swift` / this file | 260723-rif (`applyAtomicGroupCoupling`), extended here (P3) |
/// | Punctuation RUNS of length >= 2 (character-level interleaving of both sources) | `EditGuardDanglingPunctuationTests.testPunctuationRunsAreSingleSourced_acrossFixtureCorpus` | `EditGuardDanglingPunctuationTests.swift` | 260830-dc4 |
/// | Full-token adjacency including punctuation ("tier 2") | `testFullTokenAdjacencyProvenance_P5` below — promotes the tier-2 result `EditGuardMergeAtomicityTests.neitherSourceViolations` already computed and discarded at every prior call site | this file | 260830-dc4 / 260831-ad8 (promoted here) |
/// | WHITESPACE / separator provenance (a restored/rebuilt adjacency's spacing must match SOME input occurrence of that adjacency) | `testAdjacencySpacingFidelity_P4` below — the hole nothing owned before this quick task | this file | 260801-9n7 (dropped-space direction) / 260831-gd9 (fabricated-space direction) |
///
/// The order and multiset axes are DELIBERATELY NOT re-implemented here:
/// `testAggregate_allGoldenFixturesNeitherSourceClean` and
/// `multisetInvariantHolds` already own them, and duplicating either would
/// only create a second copy to keep in sync for no new coverage.
///
/// Each property prints its own non-vacuity counters on every run.
///
/// One genuine, previously-unnoticed low-severity residual was FOUND by P4
/// (and independently re-surfaced by P3-extension/P5 under their own coarser
/// tokenizer) while measuring these counts — a stray space rendered before a
/// surviving em-dash in `record-2026-08-24T04-00-00-733Z`
/// (`EditGuard.collapseMixedProvenancePunctuationRuns` correctly fixes the
/// ORIGINAL 260831-ad8 comma-touching-dash defect but leaves a forced
/// bridging space, meant for the comma it drops, stranded in front of the
/// dash that survives in its place). NOT fixed here (test-only scope; see
/// `.planning/todos/pending/editguard-stray-space-before-surviving-emdash.md`)
/// — each affected property carries a single, exact-match, per-entry-cited
/// exemption for this one case, never a threshold or a whole-case skip.
@MainActor
final class EditGuardMaterializeInvariantTests: XCTestCase {

    // MARK: - Shared corpus

    /// Common projection of `EditGuardFixtures.Fixture` and
    /// `EditGuardFixtures.ProductionRecord` — the two source types this
    /// suite's sweeps need no other field from.
    struct Case {
        let id: String
        let language: String
        let baseline: String
        let candidate: String
    }

    private var corpus: [Case] {
        EditGuardFixtures.all.map {
            Case(id: $0.id, language: $0.language, baseline: $0.baseline, candidate: $0.candidate)
        }
        + EditGuardFixtures.productionRecords.map {
            Case(id: $0.id, language: $0.language, baseline: $0.baseline, candidate: $0.candidate)
        }
    }

    private func guardOut(_ baseline: String, _ candidate: String, _ language: String) -> String {
        EditGuard.apply(rulesCleaned: baseline, llmOutput: candidate, language: language, lexicon: TestSpellLexicon.allKnown).text
    }

    // MARK: - P4: adjacency spacing fidelity (whitespace provenance)

    /// Every adjacent OUTPUT token pair's spacing (spaced vs. glued) must
    /// match the spacing that SAME normalized token pair actually had in AT
    /// LEAST ONE of the two inputs. A pair the guard's output places
    /// adjacent that occurs in NEITHER input at all is not this property's
    /// concern (D-01 construction legitimately produces adjacencies absent
    /// from both inputs) — it ABSTAINS on those, counted separately, never
    /// silently treated as a pass.
    ///
    /// Catches, with `EditGuard.swift`'s rejected-`.substitute` render
    /// branch reverted to its pre-260801-9n7 form (candidate-derived trailing
    /// taken unconditionally):
    /// - 260831-gd9: "in.clawed" -> "in. clawed" (a fabricated space present
    ///   in neither input — baseline glues "." to "clawed" with empty
    ///   trailing; the candidate has no mark there at all).
    /// - 260801-9n7: "labeled. So" -> "labeled.So" (a needed space dropped —
    ///   baseline separates "." from "So" with a genuine space; the
    ///   candidate's competing em-dash token has no trailing there).
    ///
    /// Pre-registered allowance (one-directional, stated up front rather than
    /// discovered as a false positive): a non-punctuation token gluing
    /// directly to a FOLLOWING punctuation mark in the output is never
    /// flagged, even when every input occurrence of that pair was spaced —
    /// `EditGuard.bindPunctuationLeft` binding a mark leftward is a
    /// sanctioned normalization (protects against "Excel , PowerPoint"-STYLE
    /// dangling space, not producing it). The OPPOSITE direction — output
    /// SPACED where every input occurrence of that exact pair is glued,
    /// which is the actual "Excel , PowerPoint" defect shape — is NOT
    /// exempted and is fully checked below.
    /// Exemptions are EXACT case id + adjacency pair — never a threshold, a
    /// percentage, or a whole-case skip — so every OTHER occurrence of these
    /// shapes still fails:
    /// - `municipal|—`: the stray-space-before-surviving-em-dash residual
    ///   described in this file's header, filed as
    ///   `.planning/todos/pending/editguard-stray-space-before-surviving-emdash.md`.
    /// - `.|points`: the lone-restored-ellipsis-remnant glue filed as
    ///   `.planning/todos/pending/editguard-ellipsis-remnant-glue.md`.
    private static let p4KnownExemptions: Set<String> = [
        "record-2026-08-24T04-00-00-733Z|municipal|—",
        "record-2026-09-01T17-17-59-197Z|.|points",
    ]

    func testAdjacencySpacingFidelity_P4() {
        var checkedCount = 0
        var abstainCount = 0
        var contestedCount = 0
        var casesExercising = 0
        var exemptedCount = 0

        func recordAdjacencies(_ tokens: [EditGuard.Token], into observed: inout [String: Set<Bool>]) {
            guard tokens.count > 1 else { return }
            for i in 0..<(tokens.count - 1) {
                let key = tokens[i].normalized + "\u{0}" + tokens[i + 1].normalized
                observed[key, default: []].insert(!tokens[i].trailing.isEmpty)
            }
        }

        for c in corpus {
            let out = guardOut(c.baseline, c.candidate, c.language)
            let outTokens = EditGuardTokenizer.tokenize(out)
            guard outTokens.count > 1 else { continue }

            var observed: [String: Set<Bool>] = [:]
            recordAdjacencies(EditGuardTokenizer.tokenize(c.baseline), into: &observed)
            recordAdjacencies(EditGuardTokenizer.tokenize(c.candidate), into: &observed)

            var caseChecked = false
            for i in 0..<(outTokens.count - 1) {
                let left = outTokens[i]
                let right = outTokens[i + 1]
                let hasSeparator = !left.trailing.isEmpty

                // Pre-registered allowance — see doc comment above.
                if right.kind == .punctuation, left.kind != .punctuation, !hasSeparator {
                    continue
                }

                let exemptionKey = "\(c.id)|\(left.normalized)|\(right.normalized)"
                if Self.p4KnownExemptions.contains(exemptionKey) {
                    exemptedCount += 1
                    continue
                }

                let key = left.normalized + "\u{0}" + right.normalized
                guard let observedSet = observed[key] else {
                    abstainCount += 1
                    continue
                }
                checkedCount += 1
                caseChecked = true
                if observedSet.count > 1 { contestedCount += 1 }
                XCTAssertTrue(
                    observedSet.contains(hasSeparator),
                    "[\(c.id)] output adjacency '\(left.text)|\(right.text)' is " +
                    "\(hasSeparator ? "SPACED" : "GLUED") in the guard's output, but every " +
                    "occurrence of this pair across BOTH inputs was " +
                    "\(observedSet) (true=spaced, false=glued) — a fabricated-or-dropped " +
                    "separator present in neither input. Full output: \(out)"
                )
            }
            if caseChecked { casesExercising += 1 }
        }

        print("[P4 non-vacuity] checkedCount=\(checkedCount) casesExercising=\(casesExercising) " +
              "abstainCount=\(abstainCount) contestedCount=\(contestedCount) exemptedCount=\(exemptedCount) " +
              "(of \(corpus.count) total cases)")
        XCTAssertGreaterThan(
            checkedCount, 0,
            "P4 checked ZERO adjacencies across the whole corpus — the property never fired " +
            "on anything and is VACUOUS (memory feedback_gate_blind_to_firing_path). Widen the " +
            "corpus before trusting this test."
        )
        XCTAssertGreaterThan(
            casesExercising, 0,
            "P4 exercised ZERO cases across the whole corpus — see checkedCount's failure " +
            "message; the same vacuity risk applies per-case."
        )
    }

    /// Shared by P3-extension and P5: both run the same coarse-tokenizer
    /// checker, so both see the em-dash residual as the identical two pairs.
    /// Exact record id + pair only — never a threshold or a whole-record skip.
    private static let emDashResidualExemptions: Set<String> = [
        "record-2026-08-24T04-00-00-733Z|municipal —as",
        "record-2026-08-24T04-00-00-733Z|—as well"
    ]

    // MARK: - P3-extension: tier-1 word-bigram check, widened to production records

    /// The EXISTING tier-1 word-bigram neither-source checker
    /// (`EditGuardMergeAtomicityTests.neitherSourceViolations`), already run
    /// over all of `EditGuardFixtures.all` by
    /// `testAggregate_allGoldenFixturesNeitherSourceClean` — this test does
    /// NOT duplicate that sweep. It runs the SAME checker over
    /// `EditGuardFixtures.productionRecords` only, closing the gap that the
    /// word-level neither-source splice invariant was, until this quick
    /// task, checked only across the 87 synthetic fixtures and never against
    /// a live record.
    ///
    /// The em-dash residual surfaces here as a WORD bigram because this
    /// checker's tokenizer splits only on whitespace and 6 ASCII marks, so
    /// "—as" reads as one word — the same single root cause, not a second
    /// defect. Ledgered in `emDashResidualExemptions` below.
    func testTier1NeitherSourceClean_productionRecords_P3Extension() {
        var unledgered: [String] = []
        var ledgeredCount = 0
        for record in EditGuardFixtures.productionRecords {
            let out = guardOut(record.baseline, record.candidate, record.language)
            let v = EditGuardMergeAtomicityTests.neitherSourceViolations(
                output: out, sourceA: record.baseline, sourceB: record.candidate
            )
            for pair in v.tier1 {
                let key = "\(record.id)|\(pair)"
                if Self.emDashResidualExemptions.contains(key) {
                    ledgeredCount += 1
                } else {
                    unledgered.append(key)
                }
            }
        }
        print("[P3-extension] swept \(EditGuardFixtures.productionRecords.count) production records for " +
              "tier-1 neither-source violations; ledgeredCount=\(ledgeredCount)")
        XCTAssertTrue(
            unledgered.isEmpty,
            "tier-1 neither-source violation(s) outside the exemption ledger in production " +
            "records — a NEW word-level splice defect: \(unledgered)"
        )
    }

    // MARK: - P5: full-token adjacency provenance (tier 2), promoted to a corpus-wide ratchet

    /// Promotes `EditGuardMergeAtomicityTests.neitherSourceViolations`'s
    /// tier-2 result — computed at every prior call site and discarded,
    /// because `assertNeitherSourceClean` only asserts `.tier1` — to an
    /// actual assertion, run over the WHOLE corpus (fixtures + production
    /// records). Tier 2 additionally catches full-token (word-OR-punctuation)
    /// adjacencies absent from both inputs, e.g. the 260830-dc4 "und.," and
    /// 260831-ad8 comma-dash mixed-provenance shapes — see this checker's own
    /// doc comment for the exact spec (byte-for-byte port of the harness's
    /// `Atomicity.check`, including its sanctioned single-mark-after-word
    /// allowance).
    ///
    /// The assertion form below (a hard, per-entry-justified exemption
    /// ledger) was chosen AFTER measuring the real violation list on this
    /// corpus — not written first and fitted to a guess: the only tier-2
    /// violations are the same em-dash residual P4 found and filed
    /// (`.planning/todos/pending/editguard-stray-space-before-surviving-emdash.md`),
    /// ledgered in `emDashResidualExemptions` below.

    func testFullTokenAdjacencyProvenance_P5() {
        struct Violation { let caseID: String; let pair: String }
        var violations: [Violation] = []
        var adjacenciesEvaluated = 0
        var casesExercising = 0

        for c in corpus {
            let out = guardOut(c.baseline, c.candidate, c.language)
            let v = EditGuardMergeAtomicityTests.neitherSourceViolations(
                output: out, sourceA: c.baseline, sourceB: c.candidate
            )
            adjacenciesEvaluated += v.tier2Evaluated
            if v.tier2Evaluated > 0 { casesExercising += 1 }
            for pair in v.tier2 {
                violations.append(Violation(caseID: c.id, pair: pair))
            }
        }

        print("[P5 non-vacuity] adjacenciesEvaluated=\(adjacenciesEvaluated) " +
              "casesExercising=\(casesExercising) totalTier2Violations=\(violations.count) " +
              "(of \(corpus.count) total cases)")
        XCTAssertGreaterThan(
            adjacenciesEvaluated, 0,
            "P5 evaluated ZERO full-token adjacencies across the whole corpus — the property " +
            "never inspected anything and is VACUOUS (memory feedback_gate_blind_to_firing_path). " +
            "Widen the corpus before trusting this test."
        )
        XCTAssertGreaterThan(
            casesExercising, 0,
            "P5 exercised ZERO cases across the whole corpus — see adjacenciesEvaluated's " +
            "failure message; the same vacuity risk applies per-case."
        )

        var unledgered: [String] = []
        for v in violations {
            let key = "\(v.caseID)|\(v.pair)"
            if !Self.emDashResidualExemptions.contains(key) {
                unledgered.append(key)
            }
        }
        XCTAssertTrue(
            unledgered.isEmpty,
            "tier-2 neither-source violation(s) outside the exemption ledger — a NEW " +
            "full-token adjacency defect: \(unledgered)"
        )
    }

    // MARK: - P6: mark conservation (quick task 260901-qyi)

    /// Both `1751bc1` and `ff118d1` (reverted by 260901-qyi, this quick task)
    /// passed the FULL suite (1140-1143 tests, including P4/P5 above) while
    /// each independently DELETING a sentence-terminal mark outright — P4/P5
    /// check adjacency/spacing and neither-source SPLICES, but nothing in
    /// either green suite ever counted whether a mark disappeared entirely.
    /// That is the blind spot this property closes: a raw census of
    /// sentence-terminal marks (`.`, `!`, `?`) — not their position, not
    /// their spacing, just their COUNT — asserting the guard's output never
    /// carries FEWER such marks than the weaker of its two inputs already
    /// agreed on. A "possible.points"-shaped glue (mark present, just
    /// mis-spaced) passes this property; `ff118d1`'s narrowed drop arm
    /// (which literally deletes the lone mark) does not — see this quick
    /// task's SUMMARY for the empirical RED-capability proof (the arm
    /// re-applied, this property re-run, the failure captured, then
    /// reverted).
    ///
    /// MEASURED (not guessed): sweeping the whole corpus (`EditGuardFixtures
    /// .all` + `.productionRecords`, same 99-case `corpus` this file's other
    /// properties use) at the REVERTED (correct) `EditGuard.swift` surfaces
    /// exactly 2 pre-existing violations, NEITHER belonging to the
    /// 260901-qyi "neither source" defect family:
    /// - `fx-mov-punct-en-goodshine-fullrecord-spuriousmove`: baseline=20 /
    ///   candidate=3 / out=2. Baseline's 20 marks are almost entirely
    ///   pause-dot noise (`......goodshine......`) both sides correctly
    ///   strip; `out`'s 2 marks match this fixture's OWN `expectedText`
    ///   exactly (verified by inspection) — the guard correctly reverts
    ///   candidate's rejected sentence-split ("suspect. However" ->
    ///   "suspect of course, but then"), which legitimately drops the
    ///   output below candidate's own count because baseline's local
    ///   structure at that span never had a mark there either. A global
    ///   min-of-both-counts floor cannot distinguish this from a real
    ///   defect without edit-level analysis; investigated directly rather
    ///   than assumed.
    /// - `record-2026-08-30T04-54-30-157Z` (dc4's "langweilig und" record,
    ///   already owned by `testNoSplicedPunctuation_langweiligUnd_2026_08_30`,
    ///   which explicitly accepts EITHER the baseline's ellipsis form or the
    ///   candidate's comma form as valid): baseline=8 / candidate=6 / out=5.
    ///   Same mechanism — a rejected candidate sentence-split
    ///   ("machen. Normalerweise" -> "machen, normalerweise") correctly
    ///   reverts to baseline's non-split form, legitimately below
    ///   candidate's own count.
    /// Both exempted below by EXACT case id only, each independently
    /// investigated and cited — never widened to a threshold. Every OTHER
    /// case in the corpus (97 of 99) is P6-clean with zero exemption.
    private static let p6KnownExemptions: Set<String> = [
        "fx-mov-punct-en-goodshine-fullrecord-spuriousmove",
        "record-2026-08-30T04-54-30-157Z",
    ]

    private static let sentenceTerminalMarksForP6: Set<String> = [".", "!", "?"]

    /// Counts sentence-terminal mark CHARACTERS, not tokens whose whole
    /// `.text` is one mark. Since the same-mark run tokenizer change, a
    /// "......" hesitation is ONE `.punctuation` token whose `.text` is the
    /// six-character string "......" — matching whole token text against a
    /// set of single characters would score that run as 0 instead of 6, and
    /// (because both inputs and the output are counted the same way) the
    /// floor would collapse instead of staying put, silently hiding the
    /// mark-DELETION regression this property exists to catch.
    private func terminalMarkCount(_ text: String) -> Int {
        EditGuardTokenizer.tokenize(text).reduce(0) {
            $0 + ($1.kind == .punctuation
                  ? $1.text.filter { Self.sentenceTerminalMarksForP6.contains(String($0)) }.count
                  : 0)
        }
    }

    func testMarkConservation_P6() {
        var checkedCount = 0
        var casesExercising = 0
        var unledgered: [String] = []

        for c in corpus {
            let out = guardOut(c.baseline, c.candidate, c.language)
            let baselineCount = terminalMarkCount(c.baseline)
            let candidateCount = terminalMarkCount(c.candidate)
            let outCount = terminalMarkCount(out)
            let floor = min(baselineCount, candidateCount)

            checkedCount += 1
            if floor > 0 { casesExercising += 1 }

            if outCount < floor {
                if Self.p6KnownExemptions.contains(c.id) {
                    continue
                }
                unledgered.append(
                    "\(c.id) baseline=\(baselineCount) candidate=\(candidateCount) out=\(outCount)"
                )
            }
        }

        print("[P6 non-vacuity] checkedCount=\(checkedCount) casesExercising=\(casesExercising) " +
              "(of \(corpus.count) total cases)")
        XCTAssertGreaterThan(
            checkedCount, 0,
            "P6 checked ZERO cases across the whole corpus — the property never fired and is " +
            "VACUOUS (memory feedback_gate_blind_to_firing_path). Widen the corpus before " +
            "trusting this test."
        )
        XCTAssertGreaterThan(
            casesExercising, 0,
            "P6 exercised ZERO cases with a non-zero mark floor — see checkedCount's failure " +
            "message; the same vacuity risk applies per-case."
        )
        XCTAssertTrue(
            unledgered.isEmpty,
            "sentence-terminal mark count DROPPED below min(baseline, candidate) outside the " +
            "exemption ledger — a mark was silently deleted, the exact 260901-qyi defect shape: " +
            "\(unledgered)"
        )
    }
}
