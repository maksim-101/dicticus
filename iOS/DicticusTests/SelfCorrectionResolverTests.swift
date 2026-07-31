import XCTest
@testable import Dicticus

/// SelfCorrectionResolver unit tests (Phase 20.01 — Wave 0 RED).
///
/// References `SelfCorrectionResolver` which does NOT exist yet —
/// the type lands in plan 20.03 at
/// `Shared/Utilities/SelfCorrectionResolver.swift`.
///
/// Contract being locked:
///   ```
///   public enum SelfCorrectionResolver {
///       public static func resolve(_ text: String, language: String) -> String
///   }
///   ```
///
/// Critical guards:
///   1. Connector must be preceded by `", "` to fire — defends against
///      "I mean it" / "Ich meine es ernst" false positives.
///   2. Backward window ≤ 3 tokens — never deletes more than the most
///      recent reparandum candidate.
///   3. Abort path: if no clear replacement candidate exists, leave the
///      text fully unchanged (do NOT strip the connector pair, do NOT
///      drop tokens past it).
///
/// Connector list (case-insensitive, German + English):
///   de: ich meine, besser gesagt, genauer gesagt, oder vielmehr, oder besser
///   en: I mean, I meant, or rather, or better, scratch that
final class SelfCorrectionResolverTests: XCTestCase {

    // MARK: - Positive German cases

    func testGermanIchMeineCurrencyCorrection() {
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(
                "Das kostet 110 Franken, ich meine 110 Euro.",
                language: "de"
            ),
            "Das kostet 110 Euro."
        )
    }

    func testGermanGenauerGesagt() {
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(
                "Ich gehe nach Bern, genauer gesagt nach Thun.",
                language: "de"
            ),
            "Ich gehe nach Thun."
        )
    }

    /// Phase 43 (43-02 Task 1, D-01/D-02): this fixture previously relied on
    /// the removed blind repair-count fallback (no backward-token alignment
    /// for "übermorgen" — the fallback guessed a 1-token drop). Under the
    /// abstain-unless-evidence discipline there is no exact alignment and no
    /// typed-value evidence, so the resolver now correctly ABSTAINS
    /// (byte-identical). D-02 explicitly accepts this net recall decrease in
    /// exchange for zero corruption.
    func testGermanBesserGesagt() {
        let input = "Wir treffen uns morgen, besser gesagt übermorgen."
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(input, language: "de"),
            input,
            "Phase 43/D-01: no alignment/typed-value evidence for 'übermorgen' — must abstain, not guess a drop count"
        )
    }

    /// Phase 43 (43-02 Task 1, D-01/D-02): same class as `testGermanBesserGesagt`
    /// — "Dienstag" has no backward alignment or typed-value evidence, so the
    /// removed fallback's 1-token guess is retired in favor of abstain.
    func testGermanOderVielmehr() {
        let input = "Es war Montag, oder vielmehr Dienstag."
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(input, language: "de"),
            input,
            "Phase 43/D-01: no alignment/typed-value evidence for 'Dienstag' — must abstain"
        )
    }

    /// Phase 43 (43-02 Task 1, D-01/D-02): same class — "fünf Stück" has no
    /// backward alignment or typed-value evidence (word quantities, not
    /// digits), so the removed fallback's 2-token guess is retired in favor
    /// of abstain.
    func testGermanOderBesser() {
        let input = "Drei Stück, oder besser fünf Stück."
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(input, language: "de"),
            input,
            "Phase 43/D-01: no alignment/typed-value evidence for 'fünf Stück' — must abstain"
        )
    }

    // MARK: - Comma-prefix guards (German)

    /// "Ich meine es ernst" — `ich meine` is content, not connector.
    /// Without preceding `", "`, the resolver MUST NOT fire.
    func testGermanIchMeineWithoutCommaUnchanged() {
        let input = "Ich meine es ernst"
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(input, language: "de"),
            input,
            "Comma-prefix guard: 'Ich meine' without preceding ', ' must remain content"
        )
    }

    // MARK: - Positive English cases

    func testEnglishIMeanCityCorrection() {
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(
                "Send to Boston, I mean to Denver.",
                language: "en"
            ),
            "Send to Denver."
        )
    }

    func testEnglishOrRather() {
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(
                "the red car, or rather the blue one",
                language: "en"
            ),
            "the blue one"
        )
    }

    /// Phase 43 (43-02 Task 1, D-01/D-02): this fixture previously relied on
    /// the removed blind repair-count fallback (no backward-token alignment
    /// for "Wednesday" — the fallback guessed a 1-token drop). Under the
    /// abstain-unless-evidence discipline there is no exact alignment and no
    /// typed-value evidence, so the resolver now correctly ABSTAINS
    /// (byte-identical). D-02 explicitly accepts this net recall decrease.
    func testEnglishIMeantPastTense() {
        let input = "Call him Tuesday, I meant Wednesday."
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(input, language: "en"),
            input,
            "Phase 43/D-01: no alignment/typed-value evidence for 'Wednesday' — must abstain, not guess a drop count"
        )
    }

    /// Phase 43 (43-02 Task 1, D-01/D-02): same class — "blue" has no
    /// backward alignment or typed-value evidence, so the removed fallback's
    /// 1-token guess is retired in favor of abstain.
    func testEnglishOrBetter() {
        let input = "Use red, or better blue."
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(input, language: "en"),
            input,
            "Phase 43/D-01: no alignment/typed-value evidence for 'blue' — must abstain"
        )
    }

    /// Phase 43 (43-02 Task 1, D-01/D-02): same class — "twelve dollars" is a
    /// word quantity (not a digit-typed value), so the exactly-one-candidate
    /// typed-value anchor does not apply and there is no backward alignment
    /// either; the removed fallback's 2-token guess is retired in favor of
    /// abstain.
    func testEnglishScratchThat() {
        let input = "ten dollars, scratch that twelve dollars"
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(input, language: "en"),
            input,
            "Phase 43/D-01: no alignment/typed-value evidence for 'twelve dollars' — must abstain"
        )
    }

    // MARK: - Comma-prefix guards (English) — false-positive defense

    /// Classic "I mean it" — `I mean` is content, not connector.
    func testEnglishIMeanItUnchanged() {
        let input = "I mean it"
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(input, language: "en"),
            input,
            "Comma-prefix guard: 'I mean it' is the canonical false-positive defense case"
        )
    }

    func testEnglishIMeanWhatISayUnchanged() {
        let input = "I mean what I say"
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(input, language: "en"),
            input
        )
    }

    // MARK: - Window-boundary semantics

    /// Phase 43 (43-02 Task 1, D-01/D-02): this fixture originally locked the
    /// removed blind fallback's synthetic "single-token repair + ≥6 backward
    /// tokens → cap-3 escalation" rule (`"X"` never aligns anywhere backward,
    /// so the old fallback guessed a 3-token drop). Under the abstain-
    /// unless-evidence discipline there is no exact alignment and no
    /// typed-value evidence for "X", so the resolver now correctly ABSTAINS
    /// (byte-identical) — the cap-3 fallback escalation this test named no
    /// longer exists. D-02 explicitly accepts this net recall decrease in
    /// exchange for zero corruption.
    func testGermanBackwardWindowCappedAtThree() {
        let input = "a b c d e f g h, ich meine X"
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(input, language: "de"),
            input,
            "Phase 43/D-01: no alignment/typed-value evidence for 'X' — must abstain, not escalate to a cap-3 guess"
        )
    }

    // MARK: - Abort-path semantics

    /// If the post-connector phrase is too long / ambiguous to be a clear
    /// replacement (e.g. clausal continuation), the resolver MUST leave
    /// the text fully unchanged. It MUST NOT strip the connector pair
    /// (would corrupt the sentence) and MUST NOT drop the trailing word.
    func testGermanAbortPathLeavesTextUnchanged() {
        let input = "Ich gehe heute ins Kino, ich meine, mit der ganzen Familie."
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(input, language: "de"),
            input,
            "Abort path: clausal continuation has no clear replacement candidate — leave fully unchanged, do not drop 'Familie'"
        )
    }

    // MARK: - Pure-correction connectors with post-connector comma
    //
    // 2026-05-06 fix: "no", "nein", "actually", "eigentlich", ... are pure
    // correction markers. A comma immediately after them is just punctuation
    // around the interjection ("..., No, it's at..."), NOT a clausal-
    // continuation signal. The resolver advances past the ", " and keeps
    // collapsing instead of aborting via guard 3a (which still applies to
    // parenthetical-eligible connectors like "I mean" / "ich meine").

    /// User UAT case: "8 o'clock. No, actually at 7 o'clock" should
    /// collapse to the corrected time without aborting on the comma
    /// after "No".
    /// Phase 43 (43-01 Task 2): tightened to an exact-string assertion —
    /// the boundary path resolves this via backward alignment on "at",
    /// so this stays GREEN. (Weak `contains`/`!contains` previously let a
    /// dangling-fragment corruption pass; exact-string closes that gap.)
    func testEnglishNoCommaTimeCorrection() {
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(
                "Today my workday started at 8 o'clock. No, actually at 7 o'clock.",
                language: "en"
            ),
            "Today my workday started at 7 o'clock."
        )
    }

    /// Parallel German case: ". Nein, eigentlich um 7 Uhr" — both the
    /// "Nein" and "eigentlich" matches should resolve cleanly because
    /// both connectors are pure correction.
    ///
    /// Phase 43 (43-01 Task 2): tightened to an exact-string assertion —
    /// resolves via backward alignment on "um"; stays GREEN.
    func testGermanNeinEigentlichTimeCorrection() {
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(
                "Heute hat mein Arbeitstag um 8 Uhr angefangen. Nein, eigentlich um 7 Uhr.",
                language: "de"
            ),
            "Heute hat mein Arbeitstag um 7 Uhr angefangen."
        )
    }

    /// Make sure the parenthetical guard still fires for `I mean`
    /// even after the pure-correction split — this is the existing
    /// `testGermanAbortPathLeavesTextUnchanged` analog in English.
    func testEnglishIMeanCommaContinuationStillAborts() {
        let input = "I went to the cinema, I mean, with the whole family."
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(input, language: "en"),
            input,
            "Parenthetical guard must still fire for 'I mean' (not pure correction); 'family' must not be dropped"
        )
    }

    // MARK: - JSONL regression fixtures (Phase 22)
    //
    // Captured 2026-05-08 by `Dicticus-Debug-Recorder` scheme. Each fixture
    // is a verbatim `raw` value from
    // `~/Library/Application Support/Dicticus/DebugRecordings/cleanup-2026-05-08.jsonl`.
    // Pre-fix, the SelfCorrectionResolver regex at line 75 ate substrings
    // (`no` inside `now`/`noticed`, `wait` inside `waitress`) and fired on
    // plain whitespace without a comma prefix. These fixtures lock the fix
    // in as a regression net (per memory `feedback_tests_as_regression_nets`).

    /// JSONL record 5 — `now` must not be eaten by the `no` connector (\b guard).
    func testEnglishNowNotConsumedAsNoSubstring() {
        let input = "Yes, please go ahead now."
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(input, language: "en"),
            input,
            "Regex fix: 'now' must pass through unchanged — 'no' connector must not substring-match inside 'now'"
        )
    }

    /// JSONL record 6 — `actually` mid-sentence without comma prefix must not fire.
    func testEnglishActuallyMidSentenceWithoutCommaUnchanged() {
        let input = "I want to explain what the SDK actually is"
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(input, language: "en"),
            input,
            "Regex fix: 'actually' without preceding comma must not trigger resolver"
        )
    }

    /// JSONL record 9 — same `now`/`no` substring guard as record 5.
    func testEnglishNowInHomeAssistantUnchanged() {
        let input = "I set this up in home assistant now."
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(input, language: "en"),
            input,
            "Regex fix: trailing 'now' must pass through unchanged"
        )
    }

    /// JSONL record 18 — `now` mid-sentence, no comma prefix.
    func testEnglishWillPersistNowUnchanged() {
        let input = "And what you did will persist now or will it not."
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(input, language: "en"),
            input,
            "Regex fix: 'now' mid-sentence must not be eaten as 'no' substring"
        )
    }

    /// JSONL record 19 — `now` followed by `but`, no comma prefix.
    func testEnglishPushBranchNowUnchanged() {
        let input = "Yes, you can push the branch now but check first."
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(input, language: "en"),
            input,
            "Regex fix: 'now' followed by 'but' must pass through unchanged"
        )
    }

    /// JSONL record 29 — `no` must not substring-match inside `noticed`.
    func testEnglishNoticedNotConsumedAsNoSubstring() {
        let input = "The findings you noticed as well should be considered."
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(input, language: "en"),
            input,
            "Regex fix: 'noticed' must pass through unchanged — '\\b' must block 'no' from matching inside 'noticed'"
        )
    }

    /// JSONL record 11 minimal — `wait` has no PRE-comma here (the comma is
    /// AFTER `wait`), so the resolver must no-op; `\b` also blocks `no` from
    /// eating `noticed`.
    func testEnglishWaitCommaPreservesNoticed() {
        let input = "oh wait, I just noticed"
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(input, language: "en"),
            input,
            "Regex fix: 'wait' without preceding comma is a no-op; 'noticed' must survive (\\b blocks 'no' substring match)"
        )
    }

    // MARK: - Phase 24 regressions

    /// "by the way, I meant one million" — alignment fails, so 'I meant'
    /// must not fall back to guessing a drop count.
    func testByTheWayIMeantIsPreserved() {
        let input = "And by the way, I meant one million."
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(input, language: "en"),
            input,
            "Ambiguous connector 'I meant' must not guess a drop when alignment fails."
        )
    }

    /// Ensure that 'I mean' still works when alignment IS found.
    func testEnglishIMeanValidAlignment() {
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(
                "The first meeting, I mean the second meeting.",
                language: "en"
            ),
            "the second meeting.",
            "Valid alignment must still work for ambiguous connectors."
        )
    }

    // MARK: - Phase 26 UAT regressions — doch/oder false positives

    /// UAT record 117: "eigentlich ganz gut, doch" — "doch" is a tag question /
    /// discourse particle here, not a self-correction connector. Resolver must NOT fire.
    func testGermanDochQualificationPreserved() {
        let input = "gefällt mir eigentlich ganz gut, doch dieser eine Teilsatz"
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(input, language: "de"),
            input,
            "Phase 26 UAT 117: ', doch' as tag question/confirmation must not trigger resolver"
        )
    }

    /// UAT record 132: "ankurbelt, doch wenn" — subordinate clause introduced
    /// by "doch wenn"; resolver must leave the clause intact.
    func testGermanDochWennClausePreserved() {
        let input = "das Ganze ankurbelt, doch wenn noch tun"
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(input, language: "de"),
            input,
            "Phase 26 UAT 132: ', doch wenn' subordinate clause must not be dropped"
        )
    }

    /// UAT record 102: "Stadt Zürich, oder wäre" — "oder" introduces a rhetorical
    /// question / tag question, not a self-correction. Resolver must leave unchanged.
    func testGermanOderTagQuestionPreserved() {
        let input = "wir sind in dieser Stadt Zürich, oder wäre das auch schon einschränkend"
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(input, language: "de"),
            input,
            "Phase 26 UAT 102: ', oder' as tag question must not trigger resolver"
        )
    }

    // MARK: - Phase 36.4 adversarial negative cases (Wave 0 GREEN guardrail)
    //
    // These fixtures pin the no-corruption invariant for Item 1 (D-04/D-05).
    // They PASS today because the comma-only resolver does not fire on content-word
    // sentences. Plan 36.4-05's non-comma expansion MUST preserve this invariant.
    // A failure here after Plan 05 ships would mean the expansion has a false positive.

    func testNonCommaContentWordsNotDropped() {
        // EN: "no" as content word — must not be treated as self-correction connector.
        let noNetworkCalls = "there are no network calls"
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(noNetworkCalls, language: "en"),
            noNetworkCalls,
            "Phase 36.4 Item 1 guardrail: 'no' as content word must not trigger self-correction resolver"
        )
        // EN: "actually" as content word — must not fire without a comma-preceded connector.
        let actuallyRunning = "it is actually running on time"
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(actuallyRunning, language: "en"),
            actuallyRunning,
            "Phase 36.4 Item 1 guardrail: 'actually' as content word must not trigger self-correction resolver"
        )
        // EN: "I mean it" — 'it' is abort pronoun; existing guard keeps this safe.
        // Verifies the abort-pronoun guard still fires when non-comma path is added.
        let iMeanIt = "I mean it when I say that"
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(iMeanIt, language: "en"),
            iMeanIt,
            "Phase 36.4 Item 1 guardrail: 'I mean it' (abort pronoun 'it') must not drop anything"
        )
        // DE: content sentence with 'keine' — unrelated to 'nein' connector.
        let keineNetzwerkaufrufe = "es gibt keine Netzwerkaufrufe"
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(keineNetzwerkaufrufe, language: "de"),
            keineNetzwerkaufrufe,
            "Phase 36.4 Item 1 guardrail (DE): 'keine Netzwerkaufrufe' is content, not a self-correction"
        )
    }

    // MARK: - Phase 42 Plan 03 (SELFCORR-01): production comma-path lock
    //
    // Confirms the shipped resolve() entry point (comma-prefix guard active,
    // non-comma path OFF — enableNonComma:false, enableVerbatimRestatements:
    // false) still: (a) resolves the comma-prefixed self-correction construct
    // cleanly, and (b) does NOT collapse a legitimate repeated clause — the
    // exact corruption class that Variant B (commit 6349e12) introduced and
    // that was reverted (c5f56fd, 2026-06-17). No production code changed by
    // this task; these assertions lock the already-correct behavior.

    /// "X, no actually Y" comma-path construct resolves to the corrected value.
    ///
    /// Phase 43 (43-01 Task 2): tightened to an exact-string assertion —
    /// this is the DIRECT unit-test analog of the SELFCORR-04 chained-connector
    /// defect (43-RESEARCH.md Finding 1). RED today: production drops "at" and
    /// leaves "actually" dangling ("The meeting is actually 9."). Goes GREEN
    /// at Wave 1 (plan 43-02) once the connector chain is stripped as a unit
    /// and typed-value evidence anchors the drop.
    func testProductionCommaPathResolvesMeetingTimeCorrection() {
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(
                "The meeting is at 8, no actually 9.",
                language: "en"
            ),
            "The meeting is at 9."
        )
    }

    /// SELFCORR-04: chained/multi-word connectors ("no actually" / "nein
    /// eigentlich") must be consumed as a single unit — no dangling connector
    /// token left in the output. RED until Wave 1 (plan 43-02).
    func testChainedConnectorEnglishResolvesNoDangling() {
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(
                "I have a meeting at 8, no actually 9.",
                language: "en"
            ),
            "I have a meeting at 9."
        )
    }

    /// SELFCORR-04, German: digit form. The number-WORD form
    /// ("um neun … um acht") is a separate D-06 fixture
    /// (`testNumberWordAnchorPositives`, gated to Wave 2).
    func testChainedConnectorGermanResolvesNoDangling() {
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(
                "Ich habe ein Meeting um 9, nein eigentlich um 8.",
                language: "de"
            ),
            "Ich habe ein Meeting um 8."
        )
    }

    /// Variant-B corruption class: a legitimate repeated clause ("you have to
    /// wait you have to be patient") must NOT be collapsed by the production
    /// resolver — verbatim-restatement collapse is flag-gated OFF in
    /// resolve()'s production entry and must stay that way.
    func testProductionResolverDoesNotCollapseLegitimateRepeatedClause() {
        let input = "you have to wait you have to be patient"
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(input, language: "en"),
            input,
            "SELFCORR-01: legitimate repeated clause must survive intact — verbatim-restatement collapse (Variant B) is OFF in production"
        )
    }

    // MARK: - Phase 42 Plan 07 (SELFCORR-02): spike-012 sentence-boundary port
    //
    // Full port of `.planning/spikes/012-german-selfcorrection-boundary/corpus.json`
    // (VALIDATED spike 012: 18/18 typed positives, 23/23 negatives byte-identical
    // at the isolated-algorithm level, 0 corruptions across 1408 real debug-log
    // texts). These tests exercise the production `resolve(_:language:)` entry
    // point (boundary path + comma path composed), NOT the isolated Python
    // algorithm, so 3 corpus fixtures that share ONE root cause are asserted
    // against their ACTUAL production output rather than a false byte-identity
    // claim — see `testKnownPreExistingCommaPathInteractionOnNonTypedBoundaryCases`.

    /// Typed-value sentence-boundary positives: 3 real UAT captures + 15
    /// designed cases (clock / time_uhr / ampm / price / plain, DE + EN,
    /// with/without copula, with/without prep, chained markers). Each MUST
    /// resolve to the corrected value with the reparandum sentence dropped.
    func testSentenceBoundaryTypedValuePositives() {
        let cases: [(id: String, text: String, expect: String, lang: String)] = [
            ("de-real-1030uhr", "Ich habe nämlich morgen ein Meeting um 10.30 Uhr. Ach nein, das ist um 11 Uhr.", "Ich habe nämlich morgen ein Meeting um 11 Uhr.", "de"),
            ("de-real-14uhr", "Ich habe morgen zudem um 14 Uhr ein Meeting. Nein, es ist um 15 Uhr.", "Ich habe morgen zudem um 15 Uhr ein Meeting.", "de"),
            ("en-real-800", "So today I have a meeting at 8:00. No, actually it's 9:00.", "So today I have a meeting at 9:00.", "en"),
            ("de-uhr-nein", "Das Treffen ist um 9 Uhr. Nein, es ist um 10 Uhr.", "Das Treffen ist um 10 Uhr.", "de"),
            ("de-price-franken", "Das kostet 50 Franken. Ach nein, es sind 60 Franken.", "Das kostet 60 Franken.", "de"),
            ("de-price-euro-ahnein", "Der Preis ist 20 Euro. Ah nein, das sind 25 Euro.", "Der Preis ist 25 Euro.", "de"),
            ("de-clock", "Der Zug fährt um 14:30. Nein, das ist um 15:45.", "Der Zug fährt um 15:45.", "de"),
            ("de-plain", "Die Antwort ist 42. Nein, es ist 43.", "Die Antwort ist 43.", "de"),
            ("de-nein-warte", "Das Meeting ist um 11 Uhr. Nein, warte, es ist um 12 Uhr.", "Das Meeting ist um 12 Uhr.", "de"),
            ("de-eigentlich-noprep-copula", "Das Treffen ist um 8 Uhr. Nein, eigentlich um 9 Uhr.", "Das Treffen ist um 9 Uhr.", "de"),
            ("de-price-nocopula-noprep", "Es kostet 100 Franken. Ach nein, 120 Franken.", "Es kostet 120 Franken.", "de"),
            ("en-nowait-clock", "The meeting is at 3:00. No wait, it's at 4:00.", "The meeting is at 4:00.", "en"),
            ("en-real-ampm", "Tomorrow I think I have a meeting at 9 a.m. No, actually it's 8 a.m.", "Tomorrow I think I have a meeting at 8 a.m.", "en"),
            ("en-pm", "Dinner is at 7pm. No, it's at 8pm.", "Dinner is at 8pm.", "en"),
            ("en-price-dollars", "It costs 50 dollars. No, actually it's 60 dollars.", "It costs 60 dollars.", "en"),
            ("en-plain", "The total is 5. No, it's 6.", "The total is 6.", "en"),
            ("en-clock-noactually", "Our call is at 10:00. No, actually it's at 11:00.", "Our call is at 11:00.", "en"),
            ("en-plain-noprep", "Let's meet at 2. No, at 3.", "Let's meet at 3.", "en"),
        ]
        for c in cases {
            XCTAssertEqual(
                SelfCorrectionResolver.resolve(c.text, language: c.lang),
                c.expect,
                "spike-012[\(c.id)]: typed-value sentence-boundary correction must resolve to the corrected value. Got: \(SelfCorrectionResolver.resolve(c.text, language: c.lang))"
            )
        }
    }

    /// Noun/name restatements MUST abstain (safe miss, accepted recall gap —
    /// spike 012 README §"What resolves safely vs. what must abstain"). The
    /// boundary path itself never fires on either of these (no typed value
    /// in S2).
    ///
    /// Phase 43 (43-01 Task 3): `enSingleNounName` INVERTED — previously
    /// pinned the pre-existing comma-path corruption
    /// ("So I'm meeting his name is Joe Smith.", dropping "Joe Miller") as
    /// expected production behavior. That pin is removed.
    ///
    /// Phase 43 (43-04, D-04 gate verdict: ENABLED at zero corruption):
    /// upgraded from the byte-identical safe-miss floor to the RESOLVED
    /// value. The restricted anchored proper-noun evidence source cleared
    /// its own scale-replay pass (`selfcorr43`: 18/1778, zero corruptions,
    /// exactly one new genuine resolution vs. the pre-43-04 baseline — see
    /// 43-04-SUMMARY.md) — this exact frame ("... No, actually his name is
    /// Y.") is the cross-sentence shape the anchored-noun source targets.
    /// It must NEVER again assert the dropped-noun corruption.
    func testSentenceBoundaryNounNameAbstains() {
        let deSingleNoun = "Wir treffen uns am Bahnhof. Nein, am Flughafen."
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(deSingleNoun, language: "de"),
            deSingleNoun,
            "spike-012[de-single-noun]: noun restatement must ABSTAIN (safe miss) — byte-identical (no anchored-noun frame present)"
        )
        let enSingleNounName = "So I'm meeting Joe Miller. No, actually his name is Joe Smith."
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(enSingleNounName, language: "en"),
            "So I'm meeting Joe Smith.",
            "spike-012[en-single-noun-name]: Phase 43-04/D-04 anchored-noun evidence source resolves this cleanly (gate verdict: ENABLED, zero corruption) — must never again assert the dropped-noun corruption"
        )
    }

    /// Full 23-case negative corpus: the boundary path must leave normal
    /// prose, legitimate `nein`/`no` answers, questions, idioms, and the
    /// two-clock ambiguity case byte-identical (D-03). Two of these 23 have
    /// a SEPARATE, pre-existing comma-path interaction and are exercised in
    /// `testKnownPreExistingCommaPathInteractionOnNonTypedBoundaryCases`
    /// instead, with a comment explaining why.
    func testSentenceBoundaryNegativesByteIdentical() {
        let cases: [(id: String, text: String, lang: String)] = [
            ("n-nein-danke", "Nein, danke.", "de"),
            ("n-no-thankyou", "No, thank you.", "en"),
            ("n-das-ist-gut", "Das ist gut.", "de"),
            ("n-es-ist-spaet", "Es ist schon spät.", "de"),
            ("n-its-fine", "It's fine.", "en"),
            ("n-das-ist-gut-oder", "Das ist gut, oder?", "de"),
            ("n-no-misunderstood", "No, you misunderstood me. I'm fine with the regular countdown.", "en"),
            ("n-no-leave-movies", "No, leave these two movies as they are for now.", "en"),
            ("n-no-idea", "I went home early. No idea why though.", "en"),
            ("n-nein-anders", "Nein, das sehe ich anders.", "de"),
            ("n-five-oclock", "It's 5 o'clock somewhere.", "en"),
            ("n-its-going", "The meeting is at 8:00. It's going to be great.", "en"),
            ("n-franken-euro-danke", "Das kostet 50 Franken und 20 Euro. Nein, danke.", "de"),
            ("n-question-restate", "Is it at 8:00? No, is it at 9:00?", "en"),
            ("n-nicht-moeglich", "Ich brauche das um 8 Uhr fertig. Nein, das ist nicht möglich.", "de"),
            ("n-prose-walk", "The weather is nice today. I think I'll go for a walk. Maybe to the park.", "en"),
            ("n-byway-idiom", "By the way, no worries about the time.", "en"),
            ("n-that-reminds", "No, actually that reminds me of something.", "en"),
            ("n-ambiguous-two-clocks", "The meeting is at 8:00 or at 9:00. No, it's at 10:00.", "en"),
            ("n-nein-solo", "Nein.", "de"),
            ("n-no-hover", "No only hover and hotkey because clicking might also trigger bartender six.", "en"),
        ]
        for c in cases {
            XCTAssertEqual(
                SelfCorrectionResolver.resolve(c.text, language: c.lang),
                c.text,
                "spike-012[\(c.id)]: must stay byte-identical (D-03 safe miss)"
            )
        }
    }

    /// Phase 43 (43-01 Task 3): INVERTED — this class previously pinned the
    /// pre-existing comma-path corruption (dropping real dictated content)
    /// as "expected"/"out of scope" behavior for Phase 42. Phase 43 re-opens
    /// exactly that scope (D-07 re-opens the SELFCORR-01 lock). Both
    /// assertions now name the phase's abstain CONTRACT, not a documented
    /// defect: once the evidence-free fallback is gone (D-01), the comma
    /// path must ABSTAIN on both — case 1 because the repair side leads with
    /// a copula ("it's"), not a bare typed value the comma matcher can
    /// cleanly anchor on (merging the boundary path's copula handling into
    /// the comma matcher is out of scope — 43-RESEARCH.md Finding 3); case 2
    /// because S1 holds TWO clock values ("8:00" and "9:00") → ambiguous →
    /// ABSTAIN per the exactly-one-candidate rule (Pitfall 3) — do NOT
    /// resolve to either time. Both RED until Wave 1 (plan 43-02).
    func testKnownPreExistingCommaPathInteractionOnNonTypedBoundaryCases() {
        let copulaLedRepair = "So today I have a meeting at 8:00, no actually it's 9:00 and I expect it to be quite fiery."
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(copulaLedRepair, language: "en"),
            copulaLedRepair,
            "n-comma-joined-real: copula-led repair has no bare typed value for the comma matcher to anchor on — ABSTAIN (safe miss), byte-identical"
        )
        let twoClockAmbiguity = "I have two meetings at 8:00 and at 9:00. No, actually let's reschedule."
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(twoClockAmbiguity, language: "en"),
            twoClockAmbiguity,
            "n-no-reschedule: S1 has TWO same-type clock values (8:00, 9:00) — ambiguous, exactly-one-candidate rule requires ABSTAIN, byte-identical"
        )
    }

    // MARK: - Phase 43 Wave-0 adversarial fixtures: D-06 number-word anchor
    //
    // D-06 extends the typed-value anchor to number WORDS (DE/EN: neun,
    // acht, nine, eight, …), not only digits — 43-RESEARCH.md Finding 2
    // confirms both languages' ITN deliberately leave 0–9 as words, so this
    // is a real, non-trivial extension, not a no-op. Positives are RED until
    // Wave 2 (plan 43-03, own scale-replay gate); negatives must be GREEN
    // now AND stay GREEN — they guard against the new source corrupting
    // ordinary prose/enumerations once it ships.

    /// D-06 positives: number-WORD self-corrections resolve to the
    /// human-readable corrected word (per D-05 — not digit form). RED until
    /// Wave 2.
    func testNumberWordAnchorPositives() {
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(
                "Ich habe ein Meeting um neun, nein eigentlich um acht.",
                language: "de"
            ),
            "Ich habe ein Meeting um acht."
        )
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(
                "I have a meeting at nine, no actually eight.",
                language: "en"
            ),
            "I have a meeting at eight."
        )
    }

    /// D-06 negatives: byte-identical, GREEN throughout (including today,
    /// against the untouched resolver — proving these fixtures don't rely
    /// on unimplemented code). Guards the two failure modes D-06 must never
    /// introduce: (a) an unmarked enumeration mistaken for a correction, and
    /// (b) an ambiguous two-number-word S1 resolved instead of abstained.
    func testNumberWordAnchorNegatives() {
        let unmarkedEnumeration = "Termine um neun, um acht."
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(unmarkedEnumeration, language: "de"),
            unmarkedEnumeration,
            "D-06 guardrail: no correction marker present — this is an enumeration, not a self-correction (D-05)"
        )
        let twoNumberWordAmbiguity = "Ich habe acht oder neun Meetings. Nein eigentlich zehn."
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(twoNumberWordAmbiguity, language: "de"),
            twoNumberWordAmbiguity,
            "D-06 guardrail: S1 has TWO number-word candidates (acht, neun) — ambiguous, must ABSTAIN, byte-identical"
        )
    }

    // MARK: - Phase 43 Wave-0 adversarial fixtures: D-04 anchored-noun evidence source
    //
    // D-04 is a RESTRICTED, gated attempt at proper-noun restatement
    // alignment (copula/possessive frame, exactly-one-same-shape-candidate
    // in S1). It ships DISABLED (abstain, fall back to the LLM) if it
    // produces even one prose corruption on its own scale-replay pass.
    // Positives are RED/CONTINGENT until Wave 3 (plan 43-04); negatives must
    // be GREEN now AND stay GREEN — they guard against the anchored-noun rule
    // ever corrupting ordinary prose.

    /// D-04 positives: the copula/possessive-frame proper-noun restatement
    /// resolves cleanly, in BOTH the comma-path and boundary-path frame
    /// shapes. RED until Wave 3; may relax to byte-identical (safe-miss) per
    /// plan 43-04 if the gated rule fails its own zero-corruption pass.
    func testAnchoredNounPositives() {
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(
                "His name is Joe Miller, no actually Joe Smith.",
                language: "en"
            ),
            "His name is Joe Smith."
        )
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(
                "So I'm meeting Joe Miller. No, actually his name is Joe Smith.",
                language: "en"
            ),
            "So I'm meeting Joe Smith."
        )
    }

    /// D-04 negatives: byte-identical, GREEN throughout (including today,
    /// against the untouched resolver). Guards the two failure modes the
    /// anchored-noun rule must never trigger on: (a) two same-shape proper
    /// nouns in S1 (ambiguous — must abstain, matching the typed-value
    /// exactly-one-candidate discipline), and (b) an ordinary comma+connector
    /// sentence with no proper-noun restatement frame at all.
    func testAnchoredNounNegatives() {
        let twoSameShapeNounsAmbiguous = "I'm meeting Joe Miller and Jane Doe. No, his name is Bob Smith."
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(twoSameShapeNounsAmbiguous, language: "en"),
            twoSameShapeNounsAmbiguous,
            "D-04 guardrail: S1 has TWO same-shape proper-noun candidates (Joe Miller, Jane Doe) — ambiguous, must ABSTAIN, byte-identical"
        )
        let plainCommaConnectorNoNounFrame = "I like the color, no that one is nice."
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(plainCommaConnectorNoNounFrame, language: "en"),
            plainCommaConnectorNoNounFrame,
            "D-04 guardrail: comma+connector present but no proper-noun restatement frame — must not fire, byte-identical"
        )
    }

    // MARK: - Phase 39: scratch-command delete operation (RED until 39-02)
    //
    // These fixtures pin the exact expected output of
    // `SelfCorrectionResolver.resolveScratchCommandPath`, the new sibling
    // pass that does not exist yet (lands in plan 39-02). They are the
    // SPECIFICATION of correctness for that plan, authored here as
    // source-of-truth rather than as a description of already-written code
    // — mirroring this file's own "Wave 0 RED" convention (see the header
    // comment at the top of this file). Every assertion is a full
    // `XCTAssertEqual` against an exact expected string — Phase 43 found
    // that `contains`/`!contains` assertions missed all 17 real
    // corruptions, and this phase's characteristic failure (a delete
    // truncated by the comma path's 6-token `actualDrop` cap) is invisible
    // to a substring check.

    // MARK: - 39-05 SECOND mitigation, 2026-07-11 (CR-02): enableScratchCommand
    // ships FULLY DISABLED — every scratch command phrase, in every span
    // shape, is now pasted literally. This is a whole-feature abstain, not
    // a narrowing to tail-only: the evidence source has failed its ship
    // gate TWICE in two successive review passes (CR-01 in `39-REVIEW.md`,
    // CR-02 in `39-VERIFICATION.md`), and per this project's non-negotiable
    // rule an evidence source that fails its gate ships DISABLED, not
    // shipped-and-monitored. Every fixture below that used to assert a
    // firing delete now asserts byte-identical passthrough. None are
    // deleted — each doc comment PRESERVES the original enabled-expectation
    // verbatim so gap closure is a mechanical fixture revert, not a
    // re-derivation of what each fixture ever meant.

    /// D-04 case 3 (bare command, no continuation, no named span): delete
    /// the preceding sentence. Period-prefixed, unpunctuated-command tail.
    ///
    /// DISABLED 2026-07-11 (enableScratchCommand = false; see CR-01/CR-02
    /// in the flag's doc comment in SelfCorrectionResolver.swift).
    /// Asserts passthrough because the gate is off.
    /// WHEN RE-ENABLED after gap closure, this MUST assert:
    ///   "The report is done."
    /// Do not re-enable the flag and leave this asserting passthrough.
    func testScratchBareCommandDeletesPrecedingSentenceEN() {
        let input = "The report is done. We ship on Friday. Scratch that."
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(input, language: "en"),
            input,
            "enableScratchCommand ships false (CR-01/CR-02) — must ABSTAIN, byte-identical"
        )
    }

    /// D-04 case 3, German. "Bitte" is the user's own canonical German
    /// exemplar's polite prefix.
    ///
    /// DISABLED 2026-07-11 (enableScratchCommand = false; see CR-01/CR-02).
    /// Asserts passthrough because the gate is off.
    /// WHEN RE-ENABLED after gap closure, this MUST assert:
    ///   "Wir treffen uns um zehn."
    /// Do not re-enable the flag and leave this asserting passthrough.
    func testScratchBareCommandDeletesPrecedingSentenceDE() {
        let input = "Wir treffen uns um zehn. Das Meeting ist am Montag. Bitte ignoriere den letzten Satz."
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(input, language: "de"),
            input,
            "enableScratchCommand ships false (CR-01/CR-02) — must ABSTAIN, byte-identical"
        )
    }

    /// D-04 case 3, comma-prefixed sub-case: bare command in the same
    /// sentence as the span it deletes, joined by a comma rather than a
    /// period.
    ///
    /// DISABLED 2026-07-11 (enableScratchCommand = false; see CR-01/CR-02).
    /// Asserts passthrough because the gate is off.
    /// WHEN RE-ENABLED after gap closure, this MUST assert:
    ///   "The report is done."
    /// Do not re-enable the flag and leave this asserting passthrough.
    func testScratchCommaPrefixedBareCommandDeletesPrecedingSentenceEN() {
        let input = "The report is done. We ship on Friday, scratch that."
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(input, language: "en"),
            input,
            "enableScratchCommand ships false (CR-01/CR-02) — must ABSTAIN, byte-identical"
        )
    }

    /// D-11 (amends D-04): command followed by a non-backward-aligning
    /// continuation. Originally asserted a firing delete (the command
    /// fires anywhere it sits, deleting the preceding sentence and
    /// keeping everything after).
    ///
    /// DISABLED 2026-07-11 (enableScratchCommand = false; see CR-01/CR-02
    /// — this fixture was already passthrough under the first,
    /// mid-utterance-only mitigation; it now stays passthrough for the
    /// stronger reason that the whole evidence source abstains).
    /// WHEN RE-ENABLED after both CR-01 and CR-02 are fixed and
    /// `enableScratchMidUtterance` is also restored, this MUST assert:
    ///   "Let's meet Friday at the office. Let's do a video call instead."
    /// Do not re-enable the flag and leave this asserting passthrough.
    func testScratchMidUtteranceKeepsContinuationEN() {
        let input = "Let's meet Friday at the office. Scratch that. Let's do a video call instead."
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(input, language: "en"),
            input,
            "enableScratchCommand ships false (CR-01/CR-02) — must ABSTAIN, byte-identical"
        )
    }

    /// D-11, German. See English sibling above for the corrected-verdict
    /// rationale.
    ///
    /// DISABLED 2026-07-11 (enableScratchCommand = false; see CR-01/CR-02).
    /// WHEN RE-ENABLED after both CR-01 and CR-02 are fixed and
    /// `enableScratchMidUtterance` is also restored, this MUST assert:
    ///   "Wir liefern am Freitag. Wir liefern am Montag."
    /// Do not re-enable the flag and leave this asserting passthrough.
    func testScratchMidUtteranceKeepsContinuationDE() {
        let input = "Wir liefern am Freitag. Streich das. Wir liefern am Montag."
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(input, language: "de"),
            input,
            "enableScratchCommand ships false (CR-01/CR-02) — must ABSTAIN, byte-identical"
        )
    }

    // MARK: - 39-REVIEW.md CR-01: blind-spot fixtures (.word span + trailing content)
    //
    // BLIND-SPOT FIXTURES (39-REVIEW.md CR-01). Every 39-01 positive
    // fixture placed the command at the end of the utterance — the one
    // shape that works — so the `.word`-span + trailing-content
    // corruption shipped undetected. These pin the DISABLED (passthrough)
    // behavior. When gap closure fixes the `.word` delete-range
    // arithmetic (both CR-01 AND CR-02) and restores both gate flags, these
    // MUST be flipped to assert the CORRECT delete (e.g. "The server is
    // called alpha. It ships Friday.") — NOT passthrough. Do not simply
    // re-enable the flags and leave these asserting passthrough.

    /// The exact corrupting case from `39-REVIEW.md` CR-01: `.word`-span
    /// command, period-boundary (`commandBeginsItsSpan == true`), with
    /// trailing content. Pre-mitigation this produced
    /// "The server is called alphaIt ships Friday." (fragments glued
    /// together, period silently dropped).
    ///
    /// DISABLED 2026-07-11 (enableScratchCommand = false; see CR-01/CR-02).
    /// WHEN RE-ENABLED after gap closure, this MUST assert:
    ///   "The server is called alpha. It ships Friday."
    /// Do not re-enable the flag and leave this asserting passthrough.
    func testScratchWordSpanTrailingContentPeriodBoundaryEN() {
        let input = "The server is called alpha beta. Scratch the last word. It ships Friday."
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(input, language: "en"),
            input,
            "enableScratchCommand ships false (CR-01/CR-02) — must ABSTAIN, byte-identical"
        )
    }

    /// `39-REVIEW.md` CR-01, comma-prefixed sub-case (same-sentence
    /// command, not period-terminated). Pre-mitigation this produced
    /// "The server is called alphaand we ship Friday.".
    ///
    /// DISABLED 2026-07-11 (enableScratchCommand = false; see CR-01/CR-02).
    /// WHEN RE-ENABLED after gap closure, this MUST assert:
    ///   "The server is called alpha and we ship Friday."
    /// Do not re-enable the flag and leave this asserting passthrough.
    func testScratchWordSpanTrailingContentCommaPrefixedEN() {
        let input = "The server is called alpha beta, scratch the last word, and we ship Friday."
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(input, language: "en"),
            input,
            "enableScratchCommand ships false (CR-01/CR-02) — must ABSTAIN, byte-identical"
        )
    }

    /// `39-REVIEW.md` CR-01, German. Pre-mitigation this produced
    /// "Der Server heisst AlphaWir liefern am Montag.".
    ///
    /// DISABLED 2026-07-11 (enableScratchCommand = false; see CR-01/CR-02).
    /// WHEN RE-ENABLED after gap closure, this MUST assert:
    ///   "Der Server heisst Alpha. Wir liefern am Montag."
    /// Do not re-enable the flag and leave this asserting passthrough.
    func testScratchWordSpanTrailingContentPeriodBoundaryDE() {
        let input = "Der Server heisst Alpha Beta. Vergiss das letzte Wort. Wir liefern am Montag."
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(input, language: "de"),
            input,
            "enableScratchCommand ships false (CR-01/CR-02) — must ABSTAIN, byte-identical"
        )
    }

    /// D-04 case 2 (command names its span explicitly): named span = last
    /// sentence.
    ///
    /// DISABLED 2026-07-11 (enableScratchCommand = false; see CR-01/CR-02).
    /// WHEN RE-ENABLED after gap closure, this MUST assert:
    ///   "We meet at noon."
    /// Do not re-enable the flag and leave this asserting passthrough.
    func testScratchNamedSpanLastSentenceEN() {
        let input = "We meet at noon. The vendor is Acme Corp. Ignore the last sentence."
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(input, language: "en"),
            input,
            "enableScratchCommand ships false (CR-01/CR-02) — must ABSTAIN, byte-identical"
        )
    }

    /// D-04 case 2: named span = last word, command in its own
    /// period-delimited sentence. This is the EXACT CR-02 control shape —
    /// the preceding sentence already ends in "." so this particular
    /// fixture would have been correct even under the CR-02 defect. It is
    /// precisely BECAUSE every `.word`-span fixture used only this shape
    /// that CR-02's "!"/"?" mutation shipped undetected — see the new
    /// blind-spot fixtures below.
    ///
    /// DISABLED 2026-07-11 (enableScratchCommand = false; see CR-01/CR-02).
    /// WHEN RE-ENABLED after gap closure, this MUST assert:
    ///   "The server is called alpha."
    /// Do not re-enable the flag and leave this asserting passthrough.
    func testScratchNamedSpanLastWordEN() {
        let input = "The server is called alpha beta. Scratch the last word."
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(input, language: "en"),
            input,
            "enableScratchCommand ships false (CR-01/CR-02) — must ABSTAIN, byte-identical"
        )
    }

    /// D-04 case 2: named span = last word, comma-prefixed command in the
    /// SAME sentence as the span it targets.
    ///
    /// DISABLED 2026-07-11 (enableScratchCommand = false; see CR-01/CR-02).
    /// WHEN RE-ENABLED after gap closure, this MUST assert:
    ///   "The server is called alpha."
    /// Do not re-enable the flag and leave this asserting passthrough.
    func testScratchNamedSpanLastWordSameSentenceEN() {
        let input = "The server is called alpha beta, scratch the last word."
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(input, language: "en"),
            input,
            "enableScratchCommand ships false (CR-01/CR-02) — must ABSTAIN, byte-identical"
        )
    }

    /// D-04 case 2, German: named span = last word.
    ///
    /// DISABLED 2026-07-11 (enableScratchCommand = false; see CR-01/CR-02).
    /// WHEN RE-ENABLED after gap closure, this MUST assert:
    ///   "Der Server heisst Alpha."
    /// Do not re-enable the flag and leave this asserting passthrough.
    func testScratchNamedSpanLastWordDE() {
        let input = "Der Server heisst Alpha Beta. Vergiss das letzte Wort."
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(input, language: "de"),
            input,
            "enableScratchCommand ships false (CR-01/CR-02) — must ABSTAIN, byte-identical"
        )
    }

    // MARK: - 39-VERIFICATION.md CR-02: blind-spot fixtures (.word span,
    // preceding-sentence terminator other than ".")
    //
    // BLIND-SPOT FIXTURES (CR-02, 39-VERIFICATION.md). Every `.word`-span
    // fixture above used a preceding "." — the one terminator that works —
    // so the punctuation-mutation bug shipped undetected in a surface that
    // was, at the time, ENABLED. When `.word` is rebuilt, these MUST
    // assert the ORIGINAL terminator survives ("?" stays "?", "!" stays
    // "!"), NOT a period.

    /// CR-02 EN, question mark. Pre-CR-02-discovery this silently produced
    /// "Is it alpha." — the "?" became a "." (question → statement).
    ///
    /// DISABLED 2026-07-11 (enableScratchCommand = false; see CR-02).
    /// WHEN RE-ENABLED after gap closure, this MUST assert:
    ///   "Is it alpha?"
    /// — note the "?" MUST survive, NOT become ".". Do not re-enable the
    /// flag and leave this asserting passthrough, and do not accept a
    /// "fix" that produces "Is it alpha." for this input.
    func testScratchWordSpanBlindSpotQuestionMarkBoundaryEN() {
        let input = "Is it alpha beta? Scratch the last word."
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(input, language: "en"),
            input,
            "enableScratchCommand ships false (CR-02 blind spot) — must ABSTAIN, byte-identical"
        )
    }

    /// CR-02 EN, exclamation mark, command has its own trailing period.
    /// Pre-CR-02-discovery this silently produced "This is amazing alpha."
    /// — the "!" became a ".".
    ///
    /// DISABLED 2026-07-11 (enableScratchCommand = false; see CR-02).
    /// WHEN RE-ENABLED after gap closure, this MUST assert:
    ///   "This is amazing alpha!"
    /// — note the "!" MUST survive, NOT become ".". Do not re-enable the
    /// flag and leave this asserting passthrough.
    func testScratchWordSpanBlindSpotExclamationBoundaryEN() {
        let input = "This is amazing alpha beta! Scratch the last word."
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(input, language: "en"),
            input,
            "enableScratchCommand ships false (CR-02 blind spot) — must ABSTAIN, byte-identical"
        )
    }

    /// CR-02 EN, exclamation mark, command has NO trailing punctuation of
    /// its own (raw/unpunctuated ASR tail). Pre-CR-02-discovery this
    /// silently produced "Alpha" — the "!" was dropped entirely, with no
    /// replacement at all.
    ///
    /// DISABLED 2026-07-11 (enableScratchCommand = false; see CR-02).
    /// WHEN RE-ENABLED after gap closure, this MUST assert:
    ///   "Alpha!"
    /// — note the "!" MUST survive, NOT be silently dropped. Do not
    /// re-enable the flag and leave this asserting passthrough.
    func testScratchWordSpanBlindSpotExclamationNoTrailingPunctuationEN() {
        let input = "Alpha beta! Scratch the last word"
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(input, language: "en"),
            input,
            "enableScratchCommand ships false (CR-02 blind spot) — must ABSTAIN, byte-identical"
        )
    }

    /// CR-02 DE, exclamation mark. Pre-CR-02-discovery this silently
    /// produced "Das ist super Alpha." — the "!" became a ".". German
    /// sibling confirming the defect is language-independent (same
    /// resolver code path, no language-specific punctuation handling).
    ///
    /// DISABLED 2026-07-11 (enableScratchCommand = false; see CR-02).
    /// WHEN RE-ENABLED after gap closure, this MUST assert:
    ///   "Das ist super Alpha!"
    /// — note the "!" MUST survive, NOT become ".". Do not re-enable the
    /// flag and leave this asserting passthrough.
    func testScratchWordSpanBlindSpotExclamationBoundaryDE() {
        let input = "Das ist super Alpha Beta! Vergiss das letzte Wort."
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(input, language: "de"),
            input,
            "enableScratchCommand ships false (CR-02 blind spot) — must ABSTAIN, byte-identical"
        )
    }

    /// Boundary: one sentence, command at the tail, nothing preceding
    /// survives the delete — the honest result is the empty string. Pinned
    /// so a later "helpfully restore the text" patch cannot slip in
    /// unnoticed.
    ///
    /// DISABLED 2026-07-11 (enableScratchCommand = false; see CR-01/CR-02).
    /// WHEN RE-ENABLED after gap closure, this MUST assert:
    ///   ""
    /// Do not re-enable the flag and leave this asserting passthrough.
    func testScratchWholeUtteranceScratchedYieldsEmptyString() {
        let input = "We ship on Friday, scratch that."
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(input, language: "en"),
            input,
            "enableScratchCommand ships false (CR-01/CR-02) — must ABSTAIN, byte-identical"
        )
    }

    /// Boundary: no preceding span exists, so the evidence licenses no
    /// deletion — ABSTAIN, phrase pasted literally. This is correct
    /// behavior, not a bug.
    func testScratchWithNothingPrecedingAbstains() {
        let input = "Scratch that."
        XCTAssertEqual(
            SelfCorrectionResolver.resolve(input, language: "en"),
            input,
            "No preceding span exists — must ABSTAIN, byte-identical"
        )
    }

    // MARK: - Phase 39: command-vs-literal discrimination (D-05 / VEDIT-02) — must stay byte-identical
    //
    // These fixtures pass TODAY (the resolver has no scratch-delete
    // operation yet) and must STILL pass after 39-02 — they are the
    // tripwire, and per memory feedback_spike_corpus_adversarial_breadth a
    // narrow corpus once produced a false "zero-corruption" pass that
    // shipped corrupting code. Every assertion is byte-identical passthrough.

    /// English negatives: boundary-anchor and verb-complement-exclusion
    /// (D-05) guardrails, plus content-word-follows-command cases.
    func testScratchCommandNegativesEnglishByteIdentical() {
        let cases: [(id: String, text: String, reason: String)] = [
            ("verb-complement", "I told him to scratch that idea.", "verb-complement exclusion (D-05b) — canonical negative"),
            ("verb-complement-2", "We should just scratch that plan and start over.", "verb-complement exclusion (D-05b)"),
            ("content-word-follows", "Scratch that idea, it will not work.", "content word follows the command — the command does not terminate its clause"),
            ("verb-complement-3", "He wanted to scratch that from the record.", "verb-complement exclusion (D-05b)"),
            ("verb-complement-4", "The cat likes to scratch that post.", "verb-complement exclusion (D-05b)"),
            ("polite-prefix-content-follows", "Please ignore the last word of the previous paragraph when you review it.", "allowed polite prefix + exact command phrase, but a content word follows"),
            ("content-word-follows-2", "You can ignore the last sentence if it is unclear.", "content word follows the command — the command does not terminate its clause"),
            ("verb-complement-blocker", "If you want, just scratch that.", "comma boundary, but the verb-complement blocker 'just' intervenes (D-05b)"),
            ("verb-complement-5", "Do not scratch that surface.", "verb-complement exclusion (D-05b)"),
            ("verb-complement-6", "The label says scratch that off the list.", "verb-complement exclusion (D-05b)"),
        ]
        for c in cases {
            XCTAssertEqual(
                SelfCorrectionResolver.resolve(c.text, language: "en"),
                c.text,
                "D-05[\(c.id)]: \(c.reason) — must stay byte-identical"
            )
        }
    }

    /// German negatives: the 5 REAL corpus collisions verbatim
    /// (39-RESEARCH.md Pitfall 3, grepped from this user's real debug-log
    /// corpus), plus hand-authored adversarial extensions each containing
    /// an EXACT D-06 command phrase that must not fire.
    func testScratchCommandNegativesGermanByteIdentical() {
        let cases: [(id: String, text: String, reason: String)] = [
            ("real-corpus-1", "Also streiche diesen Sprachentoggle komplett aus dem Admin Panel.", "real debug-log collision (39-RESEARCH.md Pitfall 3) — not an exact D-06 phrase"),
            ("real-corpus-2", "Ich denke, man kann die Zurückschaltfläche komplett streichen.", "real debug-log collision (39-RESEARCH.md Pitfall 3) — not an exact D-06 phrase"),
            ("real-corpus-3", "Es wäre gut, wenn man hier den Verlauf löschen kann.", "real debug-log collision (39-RESEARCH.md Pitfall 3) — not an exact D-06 phrase"),
            ("real-corpus-4", "Wir haben geprüft, ob wichtige Aspekte vergessen gingen.", "real debug-log collision (39-RESEARCH.md Pitfall 3) — not an exact D-06 phrase"),
            ("real-corpus-5", "Es gibt Abschnitte, die du inhaltlich ignorieren kannst.", "real debug-log collision (39-RESEARCH.md Pitfall 3) — not an exact D-06 phrase"),
            ("exact-phrase-content-follows", "Bitte streiche das Kapitel aus dem Bericht.", "allowed prefix + exact phrase 'streiche das' + a content word follows"),
            ("exact-phrase-content-follows-2", "Streiche das letzte Wort nicht, es ist wichtig.", "exact named-span phrase at string start + a content word follows — sharpest right-guard test in the corpus"),
            ("same-words-different-order", "Du kannst den letzten Satz ignorieren, wenn er unklar ist.", "same words, different order — must not match"),
            ("not-a-shipped-phrase", "Vergiss das nicht wieder.", "'vergiss das' is NOT a shipped phrase; only the named-span forms are"),
            ("verb-complement", "Ich musste den letzten Satz vergessen, weil er falsch war.", "verb-complement exclusion (D-05b)"),
            ("verb-complement-2", "Er sagte, ich solle das letzte Wort streichen.", "verb-complement exclusion (D-05b)"),
        ]
        for c in cases {
            XCTAssertEqual(
                SelfCorrectionResolver.resolve(c.text, language: "de"),
                c.text,
                "D-05[\(c.id)]: \(c.reason) — must stay byte-identical"
            )
        }
    }

    /// Pins that the new German command phrases were NOT injected into
    /// `germanConnectors` — doing so would silently change
    /// `resolveCommaPath`'s corruption-gated behavior (SELFCORR-01 lock)
    /// and the per-sentence gate's baseline switch. Easiest way for plan
    /// 39-02 to go wrong.
    func testScratchPhrasesAreNotCorrectionConnectors() {
        XCTAssertFalse(
            SelfCorrectionResolver.containsCorrectionMarker("Ignoriere den letzten Satz.", language: "de"),
            "The new D-06 scratch-command phrases must not be injected into germanConnectors"
        )
    }
}
