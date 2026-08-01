import XCTest
@testable import Dicticus

/// Quick task 260723-rif: regression net for defect class A (log-analysis
/// 2026-07-23) — partial acceptance of interacting edits splicing text that
/// appears in NEITHER the rules baseline nor the LLM output. Fixed by
/// `EditGuard.applyAtomicGroupCoupling` (atomic revert groups).
///
/// Contains an INTERNAL copy of the same neither-source bigram checker the
/// harness's `Atomicity.swift` implements (R2 independence: this copy, like
/// the harness copy, does NOT import or reuse `EditGuard`/`EditDiff`/
/// `EditGuardTokenizer` logic — its own trivial tokenizer). Duplication
/// between the two copies is DELIBERATE (small, self-contained, same spec)
/// rather than sharing one implementation — see the plan's Task 1(d).
@MainActor
final class EditGuardMergeAtomicityTests: XCTestCase {

    private func guardOut(_ baseline: String, _ llm: String, _ lang: String = "en") -> String {
        EditGuard.apply(rulesCleaned: baseline, llmOutput: llm, language: lang, lexicon: TestSpellLexicon.allKnown).text
    }

    // MARK: - R2 independent neither-source checker (internal copy)

    private static let punctuationChars: Set<Character> = [",", ".", ";", ":", "!", "?"]

    private static func tokenize(_ s: String) -> [String] {
        var tokens: [String] = []
        for word in s.lowercased().split(whereSeparator: { $0.isWhitespace }) {
            var current = ""
            for ch in word {
                if punctuationChars.contains(ch) {
                    if !current.isEmpty { tokens.append(current); current = "" }
                    tokens.append(String(ch))
                } else {
                    current.append(ch)
                }
            }
            if !current.isEmpty { tokens.append(current) }
        }
        return tokens
    }

    private static func isPunctToken(_ t: String) -> Bool {
        t.count == 1 && punctuationChars.contains(t.first!)
    }

    private static func bigramSet(_ tokens: [String]) -> Set<String> {
        guard tokens.count > 1 else { return [] }
        var result = Set<String>()
        for i in 0..<(tokens.count - 1) {
            result.insert(tokens[i] + "\u{0}" + tokens[i + 1])
        }
        return result
    }

    /// Tier 1 (HARD, word-only bigrams, zero allowances) + Tier 2
    /// (full-token bigrams, with the sanctioned `collapseDanglingPunctuation`
    /// allowance) — see `Atomicity.check` in the harness for the full spec;
    /// this is a byte-for-byte port.
    private static func neitherSourceViolations(output: String, sourceA: String, sourceB: String) -> (tier1: [String], tier2: [String]) {
        let outTokens = tokenize(output)
        let aTokens = tokenize(sourceA)
        let bTokens = tokenize(sourceB)

        let outWords = outTokens.filter { !isPunctToken($0) }
        let aWords = aTokens.filter { !isPunctToken($0) }
        let bWords = bTokens.filter { !isPunctToken($0) }
        let allowedWordBigrams = bigramSet(aWords).union(bigramSet(bWords))
        var tier1: [String] = []
        if outWords.count > 1 {
            for i in 0..<(outWords.count - 1) {
                let bg = outWords[i] + "\u{0}" + outWords[i + 1]
                if !allowedWordBigrams.contains(bg) {
                    tier1.append("\(outWords[i]) \(outWords[i + 1])")
                }
            }
        }

        let allowedFullBigrams = bigramSet(aTokens).union(bigramSet(bTokens))
        var wordFollowedByMarks: [String: Set<String>] = [:]
        func recordMarks(_ tokens: [String]) {
            guard tokens.count > 1 else { return }
            for i in 0..<(tokens.count - 1) where !isPunctToken(tokens[i]) && isPunctToken(tokens[i + 1]) {
                wordFollowedByMarks[tokens[i], default: []].insert(tokens[i + 1])
            }
        }
        recordMarks(aTokens)
        recordMarks(bTokens)
        let allSourceMarks = Set((aTokens + bTokens).filter { isPunctToken($0) })

        var tier2: [String] = []
        if outTokens.count > 1 {
            for i in 0..<(outTokens.count - 1) {
                let t0 = outTokens[i], t1 = outTokens[i + 1]
                let bg = t0 + "\u{0}" + t1
                if allowedFullBigrams.contains(bg) { continue }
                if !isPunctToken(t0), isPunctToken(t1),
                   let marksForWord = wordFollowedByMarks[t0], !marksForWord.isEmpty,
                   allSourceMarks.contains(t1) {
                    continue
                }
                tier2.append("\(t0) \(t1)")
            }
        }
        return (tier1, tier2)
    }

    private func assertNeitherSourceClean(_ output: String, _ baseline: String, _ llm: String, file: StaticString = #filePath, line: UInt = #line) {
        let v = Self.neitherSourceViolations(output: output, sourceA: baseline, sourceB: llm)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(output)", file: file, line: line)
    }

    // MARK: - Evidence fixtures (260723-rif objective, log-analysis 2026-07-23)
    //
    // R7: of the 7 confirmed live evidence garbles, 5 reproduced AND resolved
    // cleanly to the baseline revert under `applyAtomicGroupCoupling`
    // (confirmed via `harness debugEG`/`atomicity`, 2026-07-23). The other 2
    // ("check fact"/07-19:70, "having seeking"/07-20:7) reproduced but did NOT
    // resolve under that fix — a DIFFERENT, materialize-level rendering
    // defect for crossed multi-pair `.substitute` groups, then out of
    // 260723-rif's locked scope. 260724-j96 fixes that defect (gap-local
    // rejected-substitute remap in `materialize`) and promotes both records
    // to ordinary regression tests below — see "Crossed-substitute regression
    // tests (260724-j96 fix)".

    /// corpus 2026-07-19T11:02:37.529Z, cleanup-2026-07-19.jsonl:45.
    /// `move(for) ACCEPTED + delete(of) REJECTED`, separated only by
    /// `keep(heartrate)` — no existing narrow coupling saw this pair.
    func testAtomicRevert_ofForHeartrateInstance() {
        let baseline = "She wants to be able to click in a dial and move the finger around to see individual data points. Like what was the value at any given time of heartrate for instance and then also along the way lost the info about the workouts so when I click on the workouts a small pop-up should show up"
        let llm = "She wants to be able to click in a dial and move the finger around to see individual data points, like the value at any given time for heartrate, and then also along the way, lost the info about workouts. So when I click on the workouts, a small pop-up should show up."
        let expected = "She wants to be able to click in a dial and move the finger around to see individual data points. Like what was the value at any given time of heartrate for instance and then also along the way, lost the info about the workouts so when I click on the workouts, a small pop-up should show up."
        let out = guardOut(baseline, llm)
        XCTAssertEqual(out, expected)
        assertNeitherSourceClean(out, baseline, llm)
    }

    /// corpus 2026-07-19T15:01:38.310Z, cleanup-2026-07-19.jsonl:59.
    /// `substitute(it's->it) REJECTED` in the same keep-bounded run as a
    /// once-accepted `insert(,)` — atomic revert restores "it's" and drops
    /// the orphaned comma insert.
    func testAtomicRevert_itsIs() {
        let baseline = "Also in the current layout it's unclear to what time period this report is referring to."
        let llm = "Also, in the current layout, it is unclear to what time period this report refers."
        let expected = "Also, in the current layout it's unclear to what time period this report is referring to."
        let out = guardOut(baseline, llm)
        XCTAssertEqual(out, expected)
        assertNeitherSourceClean(out, baseline, llm)
    }

    /// corpus 2026-07-21T04:05:46.259Z, cleanup-2026-07-21.jsonl:13.
    /// `substitute(wanna->want) REJECTED` in the same run as the once-
    /// accepted `insert(to)` — atomic revert restores "wanna" and drops the
    /// surplus "to" insert (would otherwise splice "wanna to").
    func testAtomicRevert_wannaTo() {
        let baseline = "- Yes, we can go ahead, but first I wanna clear the context window because it's already 75% full."
        let llm = "Yes, we can go ahead, but first I want to clear the context window because it's already 75% full."
        let expected = "Yes, we can go ahead, but first I wanna clear the context window because it's already 75% full."
        let out = guardOut(baseline, llm)
        XCTAssertEqual(out, expected)
        assertNeitherSourceClean(out, baseline, llm)
    }

    /// corpus 2026-07-19T15:05:03.713Z, cleanup-2026-07-19.jsonl:63. A
    /// rejected `move(,)` + rejected `substitute(right->.)` in the same run
    /// as a once-accepted `delete(?)` — atomic revert restores the whole
    /// "visible, right?" region, including the "?" the once-independent
    /// accept would otherwise have dropped ("right So").
    func testAtomicRevert_rightSoLostQuestionMark() {
        let baseline = "For the sections, what kind of structure are you following now? Because I would like to have a clear structure that's also kind of visible, right? So facts and figures first, then development possibilities, likelihoods and whatnot, confidentiality."
        let llm = "For the sections, what kind of structure are you following now? Because I would like to have a clear structure that is also visible. So, facts and figures first, then development possibilities, likelihoods, and confidentiality."
        let out = guardOut(baseline, llm)
        XCTAssertEqual(out, baseline) // full baseline revert, byte-identical
        assertNeitherSourceClean(out, baseline, llm)
    }

    /// corpus 2026-07-22T06:11:24.474Z, cleanup-2026-07-22.jsonl:20 (German).
    /// `move(es->Es) ACCEPTED` bridges (via its candidate destination) into
    /// a cluster full of independently-rejected content edits ("glaube",
    /// "ist", "zwar", ...) — atomic revert (including the move-bridge)
    /// restores the full baseline sentence, eliminating the dangling "Es"
    /// before "Und zwar".
    func testAtomicRevert_esUndZwarDanglingEs() {
        let baseline = "Und dann gibt es, ich glaube es ist eine Folie mit einer Tabelle, doch hierfür würde ich tatsächlich ein anderes Folienlayout nehmen. Und zwar eines, das oberhalb der Tabelle nicht noch einen Text enthält, weil jetzt in diesem Fall wurde auch tatsächlich nichts oben hingeschrieben und damit bleibt ein grosser Anteil des Platzes auf der Folie ungenutzt."
        let llm = "Und dann gibt es eine Folie mit einer Tabelle. Dafür würde ich jedoch ein anderes Folienlayout verwenden. Es sollte eines sein, das oberhalb der Tabelle keinen Text enthält, da in diesem Fall oben nichts geschrieben wurde. Dadurch bleibt ein grosser Teil des Platzes auf der Folie ungenutzt."
        let out = guardOut(baseline, llm, "de")
        XCTAssertEqual(out, baseline) // full baseline revert, byte-identical
        assertNeitherSourceClean(out, baseline, llm)
    }

    // MARK: - Crossed-substitute regression tests (260724-j96 fix)

    /// corpus 2026-07-19T15:14:42.096Z, cleanup-2026-07-19.jsonl:70 and
    /// 2026-07-20T03:03:21.497Z, cleanup-2026-07-20.jsonl:7. Both reproduced
    /// a neither-source splice ("check fact" / "having seek what to") EVEN
    /// AFTER `applyAtomicGroupCoupling` fully reverted their group, because
    /// of a DIFFERENT, materialize-level defect: `materialize` rendered a
    /// rejected `.substitute` inline, at the CANDIDATE index of its own `to`
    /// token (unlike a rejected `.delete`/`.move`, which restores via the
    /// baseline-anchored `restorationTargets` mechanism and is therefore
    /// order-safe) — so when `EditDiff.pairAdjacentSubstitutes`' STEM-
    /// PLAUSIBILITY pairing crosses the pairs' baseline relative order within
    /// a single keep-bounded gap, two-or-more rejected substitutes rendered
    /// out of baseline order. Formerly tracked as 260723-rif's documented
    /// "Known residual" (out of that quick task's locked scope, which forbade
    /// touching `materialize`/`EditDiff`); FIXED by 260724-j96's gap-local
    /// rejected-substitute remap in `materialize` (see
    /// `applyAtomicGroupCoupling`'s doc comment, now rewritten to describe
    /// the mechanism as fixed). These are now ordinary regression tests:
    /// exact-string assertion of the correct (baseline-order) output, plus
    /// `assertNeitherSourceClean`.
    func testCrossedSubstituteRestore_checkFact() {
        let baseline = "No, the corporate style-guide convention is not about writing something like situation or assessment in capital letters. It's about geographic names and also entities, I believe. But fact check that."
        let llm = "No, the corporate style-guide convention is not about writing something like \"situation\" or \"assessment\" in capital letters. It is about geographic names and entities, I believe. But let's fact-check that."
        let expected = "No, the corporate style-guide convention is not about writing something like \"situation\" or \"assessment\" in capital letters. It's about geographic names and also entities, I believe. But fact check that."
        let out = guardOut(baseline, llm)
        XCTAssertEqual(out, expected)
        assertNeitherSourceClean(out, baseline, llm)
    }

    func testCrossedSubstituteRestore_havingSeeking() {
        let baseline = "The title at the top meaning when was this report generated or what time period is this referring to can be a little bit more prominent. So as not to having to seek what time period this report is about."
        let llm = "The title at the top, indicating when this report was generated or what time period it refers to, could be a little more prominent so as not to require seeking out the time period this report is about."
        let expected = "The title at the top meaning when this report was generated or what time period is this referring to, could be a little bit more prominent so as not to having to seek what time period this report is about."
        let out = guardOut(baseline, llm)
        XCTAssertEqual(out, expected)
        assertNeitherSourceClean(out, baseline, llm)
    }

    /// German live-window crossed-substitute records (260724-j96 R7):
    /// corpus 2026-07-23T07:36:52.602Z, cleanup-2026-07-23.jsonl:10
    /// ("eine gelatete schön PDF" / baseline "eine schön gelatete PDF") and
    /// 2026-07-23T08:02:59.300Z, cleanup-2026-07-23.jsonl:14 ("für was" /
    /// baseline "was für"). Both confirmed reproducing the same materialize-
    /// level crossed-substitute splice at HEAD via `harness debugEG` before
    /// this quick task's fix. German coverage matters here because the
    /// German-preserve tests are the most order-sensitive consumers of
    /// `materialize`.
    func testCrossedSubstituteRestore_eineSchoenGelatetePdf() {
        let baseline = "Es geht vor allem auch um die aktuell laufenden oder zukünftigen Geschäfte. Wie wir mit vergangenen umgehen, das müsste man noch schauen. Und Exportfunktionen nach Excel beispielsweise oder in eine schön gelatete PDF sollten ebenfalls verfügbar sein. Zudem sollte es auch Suchfunktionen geben, da wir davon ausgehen, dass es da nicht nur ein, zwei Geschäfte geben wird, sondern gleich mehrere, gerade wenn wir vielleicht auch eine Historie haben. Das sind mal die Punkte, die mir zum aktuellen Zeitpunkt einfallen. Analysiere das Ganze genauestens, stelle auch Verständnisfragen und komme mit Vorschlägen und Varianten zurück. Wir planen das jetzt gemeinsam."
        let llm = "\nEs geht vor allem auch um die aktuell laufenden oder zukünftigen Geschäfte. Wie wir mit vergangenen Geschäften umgehen, muss man noch schauen. Exportfunktionen nach Excel oder in eine gut lesbare PDF sollten ebenfalls verfügbar sein. Zudem sollte es auch Suchfunktionen geben, da wir davon ausgehen, dass es da nicht nur ein oder zwei, sondern mehrere Geschäfte geben wird, gerade wenn wir vielleicht auch eine Historie haben. Das sind mal die Punkte, die mir zum aktuellen Zeitpunkt einfallen. Analysiere das Ganze genau, stelle Verständnisfragen und komme mit Vorschlägen und Varianten zurück. Wir planen das jetzt gemeinsam.\n</corrected_text>"
        let expected = "Es geht vor allem auch um die aktuell laufenden oder zukünftigen Geschäfte. Wie wir mit vergangenen umgehen, das müsste man noch schauen. Und Exportfunktionen nach Excel beispielsweise oder in eine schön gelatete PDF sollten ebenfalls verfügbar sein. Zudem sollte es auch Suchfunktionen geben, da wir davon ausgehen, dass es da nicht nur ein, zwei, sondern gleich mehrere Geschäfte geben wird, gerade wenn wir vielleicht auch eine Historie haben. Das sind mal die Punkte, die mir zum aktuellen Zeitpunkt einfallen. Analysiere das Ganze genauestens, stelle auch Verständnisfragen und komme mit Vorschlägen und Varianten zurück. Wir planen das jetzt gemeinsam."
        let out = guardOut(baseline, llm, "de")
        XCTAssertEqual(out, expected)
        assertNeitherSourceClean(out, baseline, llm)
    }

    func testCrossedSubstituteRestore_wasFuerStichwoerter() {
        let baseline = "Ich würde erst noch interessieren, wie du nach TQL relevanten Themen suchst. Also was für Stichwörter oder Regeln verwendest du da? Und das sollte optimalerweise auch durch den jeweiligen User konfigurierbar sein."
        let llm = "\nIch würde erst noch interessieren, wie du nach TQL-relevanten Themen suchst. Also, welche Stichwörter oder Regeln verwendest du dafür? Und das sollte optimalerweise auch durch den jeweiligen User konfigurierbar sein.\n</corrected_text>"
        let expected = "Ich würde erst noch interessieren, wie du nach TQL relevanten Themen suchst. Also was für Stichwörter oder Regeln verwendest du da? Und das sollte optimalerweise auch durch den jeweiligen User konfigurierbar sein."
        let out = guardOut(baseline, llm, "de")
        XCTAssertEqual(out, expected)
        assertNeitherSourceClean(out, baseline, llm)
    }

    // MARK: - Quick task 260801-9n7: sentence-glue restore-boundary regression
    //
    // Evidence record 2026-07-29T03:47:35.149Z
    // (260801-9n7-EVIDENCE.json; brand name anonymized shape-preserving for
    // this public repo): EditGuard correctly REJECTS the LLM's
    // cross-sentence em-dash merge at the "...it's labeled. So it matches..."
    // boundary, but the restored sentence-terminal "." inherits the
    // candidate em-dash's EMPTY trailing instead of its own baseline " "
    // trailing — gluing the two sentences together ("labeled.So") in the
    // rebuilt text. See `materialize`'s rejected-`.substitute` render
    // branch.

    /// RED positive (must FAIL at HEAD — captured HEAD failure diff recorded
    /// in `260801-9n7-SUMMARY.md`). `assertNeitherSourceClean` is kept below
    /// for consistency with this file's convention, but its tier-1 checker
    /// normalizes whitespace away before comparing and therefore PASSES even
    /// WITH this defect present — it is never evidence the bug is fixed.
    /// `XCTAssertEqual(out, expected)` is the load-bearing assertion.
    func testRestoredTerminalPunctuation_keepsInterSentenceSpace_labeledSo() {
        let baseline = "So help me adjust the feedback email or however it's labeled. So it matches these new states because I haven't sent it yet. I only was in contact with Pearcom support and now I want to go that separate lane as well because this is not acceptable anymore."
        let llm = "So, help me adjust the feedback email—or however it's labeled—to match these new states, because I haven't sent it yet. I was only in contact with Pearcom support, and now I want to go down that separate lane as well, because this is not acceptable anymore.</corrected_text>"
        let expected = "So, help me adjust the feedback email—or however it's labeled. So it matches these new states, because I haven't sent it yet. I was only in contact with Pearcom support, and now I want to go that separate lane as well, because this is not acceptable anymore."
        let out = guardOut(baseline, llm)
        XCTAssertEqual(out, expected)
        assertNeitherSourceClean(out, baseline, llm)
    }

    /// N1 (must PASS at HEAD and stay passing): pins that a restored
    /// punctuation token never fabricates a separator inside a legitimate
    /// abbreviation seam ("a.m" tokenizes word/./word, every trailing
    /// empty — see EditGuardTokenizer's contract). The rejected
    /// "budget"->"finances" substitute exercises the restore machinery in
    /// the same sentence; "a.m" itself is untouched and must stay unspaced
    /// in the output. A naive "space after any mark before a word" fix
    /// would corrupt this.
    func testRestore_doesNotFabricateSpaceInsideAbbreviation() {
        let baseline = "We should meet at 9 a.m tomorrow to discuss the budget."
        let llm = "We should meet at 9 a.m tomorrow to discuss the finances."
        XCTAssertTrue(
            EditGuard.apply(rulesCleaned: baseline, llmOutput: llm, language: "en", lexicon: TestSpellLexicon.allKnown).edits.contains { !$0.accepted },
            "fixture must exercise a rejected edit for the restore machinery to genuinely run"
        )
        let out = guardOut(baseline, llm)
        XCTAssertEqual(out, baseline)
    }

    /// N2 (must PASS at HEAD and stay passing): pins that a restored
    /// punctuation token never fabricates a separator after an opening mark
    /// directly against a word ("(the" seam). The rejected "whole"->
    /// "entire" substitute sits immediately inside the parenthetical, so
    /// restoration genuinely runs right at this seam.
    func testRestore_doesNotFabricateSpaceAfterOpeningMark() {
        let baseline = "Let's finalize the presentation (the whole thing) before Friday so the client is happy."
        let llm = "Let's finalize the presentation (the entire thing) before Friday so the client is happy."
        XCTAssertTrue(
            EditGuard.apply(rulesCleaned: baseline, llmOutput: llm, language: "en", lexicon: TestSpellLexicon.allKnown).edits.contains { !$0.accepted },
            "fixture must exercise a rejected edit for the restore machinery to genuinely run"
        )
        let out = guardOut(baseline, llm)
        XCTAssertEqual(out, baseline)
    }

    // MARK: - Aggregate invariant tests

    /// (i) The checker run over all 5 resolved evidence fixtures' guard
    /// outputs — a permanent regression net distinct from the exact-string
    /// assertions above (this one generalizes to catch a FUTURE change that
    /// reintroduces a DIFFERENT neither-source splice in the same region).
    func testAggregate_evidenceFixturesNeitherSourceClean() {
        let cases: [(baseline: String, llm: String, lang: String)] = [
            ("She wants to be able to click in a dial and move the finger around to see individual data points. Like what was the value at any given time of heartrate for instance and then also along the way lost the info about the workouts so when I click on the workouts a small pop-up should show up",
             "She wants to be able to click in a dial and move the finger around to see individual data points, like the value at any given time for heartrate, and then also along the way, lost the info about workouts. So when I click on the workouts, a small pop-up should show up.", "en"),
            ("Also in the current layout it's unclear to what time period this report is referring to.",
             "Also, in the current layout, it is unclear to what time period this report refers.", "en"),
            ("- Yes, we can go ahead, but first I wanna clear the context window because it's already 75% full.",
             "Yes, we can go ahead, but first I want to clear the context window because it's already 75% full.", "en"),
            ("For the sections, what kind of structure are you following now? Because I would like to have a clear structure that's also kind of visible, right? So facts and figures first, then development possibilities, likelihoods and whatnot, confidentiality.",
             "For the sections, what kind of structure are you following now? Because I would like to have a clear structure that is also visible. So, facts and figures first, then development possibilities, likelihoods, and confidentiality.", "en"),
            ("Und dann gibt es, ich glaube es ist eine Folie mit einer Tabelle, doch hierfür würde ich tatsächlich ein anderes Folienlayout nehmen. Und zwar eines, das oberhalb der Tabelle nicht noch einen Text enthält, weil jetzt in diesem Fall wurde auch tatsächlich nichts oben hingeschrieben und damit bleibt ein grosser Anteil des Platzes auf der Folie ungenutzt.",
             "Und dann gibt es eine Folie mit einer Tabelle. Dafür würde ich jedoch ein anderes Folienlayout verwenden. Es sollte eines sein, das oberhalb der Tabelle keinen Text enthält, da in diesem Fall oben nichts geschrieben wurde. Dadurch bleibt ein grosser Teil des Platzes auf der Folie ungenutzt.", "de"),
        ]
        for c in cases {
            let out = guardOut(c.baseline, c.llm, c.lang)
            assertNeitherSourceClean(out, c.baseline, c.llm)
        }
    }

    /// (ii) The checker (tier 1 hard; tier 2 with the allowance) over EVERY
    /// fixture in `EditGuardFixtures.all` — output vs that fixture's own
    /// (rulesCleaned, llmOutput). R7 true positive: AT HEAD (pre-260723-rif,
    /// confirmed via `xcodebuild` run), exactly ONE of the 83 golden
    /// fixtures violated tier-1 — `fx-mov-content-de-crossclause-manicht-
    /// knownopen`, the pre-existing documented "known open defect" fixture
    /// (its own note already called out the man/nicht cross-clause
    /// mispairing). `applyAtomicGroupCoupling` clears that one AND
    /// surfaced a genuine regression risk during development (the
    /// punctuation-only-group exemption exists because of it — see
    /// `fx-mov-punct-en-goodshine-fullrecord-spuriousmove` in
    /// EditGuard.applyAtomicGroupCoupling's doc comment) before landing at
    /// zero tier-1 violations across all 83 fixtures POST-fix. This is the
    /// PERMANENT version of the R7 measurement: any future change that
    /// reintroduces a neither-source splice into ANY golden fixture's
    /// output fails here.
    func testAggregate_allGoldenFixturesNeitherSourceClean() {
        var violatingIDs: [String] = []
        for fixture in EditGuardFixtures.all {
            let out = guardOut(fixture.baseline, fixture.candidate, fixture.language)
            let v = Self.neitherSourceViolations(output: out, sourceA: fixture.baseline, sourceB: fixture.candidate)
            if !v.tier1.isEmpty {
                violatingIDs.append("\(fixture.id): \(v.tier1)")
            }
        }
        XCTAssertTrue(violatingIDs.isEmpty, "tier-1 neither-source violations in golden fixtures: \(violatingIDs)")
    }
}
