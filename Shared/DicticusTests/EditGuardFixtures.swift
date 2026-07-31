import Foundation
@testable import Dicticus

/// Phase 44 Plan 02: the SHAPE cross-product fixture corpus that every
/// EditGuard unit test in this phase (44-03 through 44-10) scores itself
/// against. One corpus, many consumers — see `EditGuardFixtureCoverageTests`
/// for the compile-time-checked coverage lock.
///
/// WHY THIS FILE EXISTS: Phase 39 shipped two data-loss bugs because all 11
/// of its positive fixtures used ONE input shape (command at end of string,
/// preceded by a period). Both bugs lived in shapes no fixture tried. This
/// file enumerates the real cross-product — edit type (substitute / delete /
/// insert / move) x token class (digit / pronoun / contentWord /
/// functionWord / filler) x position (sentenceInitial / interior / terminal)
/// x language (de / en) = 120 cells — and either fills each cell with a real
/// fixture or explicitly prunes it with a documented reason in
/// `EditGuardFixtures.prunedCells`. A fixture set that varies only sentence
/// content while holding shape fixed is the exact monoculture this file
/// exists to prevent (see `EditGuardFixtureCoverageTests`, which fails the
/// build if a cell silently disappears).
///
/// PROVENANCE: every fixture's `note` cites either a real corpus timestamp
/// (from `44-CORPUS-AUDIT.md`), a `44-CONTEXT.md` decision ID (D-01..D-11),
/// a `44-RESEARCH.md` finding, or is marked `INVENTED` when it exists purely
/// to fill a cross-product cell with no direct real-world citation. Per the
/// plan's acceptance criteria, `INVENTED` fixtures are a minority of the
/// corpus.
enum EditGuardFixtures {

    // MARK: - Shape dimensions

    enum TokenClass: String, CaseIterable {
        case digit
        case pronoun
        case contentWord
        case functionWord
        case filler
    }

    enum Position: String, CaseIterable {
        case sentenceInitial
        case interior
        case terminal
    }

    enum Verdict: String {
        case accept
        case reject
    }

    // MARK: - Fixture record

    struct Fixture {
        /// Unique, kebab-case, human-readable.
        let id: String
        /// "de" / "en".
        let language: String
        /// The rules-cleaned baseline text (what the guard diffs FROM).
        let baseline: String
        /// The LLM candidate text (what the guard diffs TO).
        let candidate: String
        /// What the guard must REBUILD. Proves reconstruction, not merely
        /// accept/reject — see `EditGuardFixtureCoverageTests
        /// .testExpectedTextIsSelfConsistent`.
        let expectedText: String
        let editKind: EditGuard.EditKind
        let tokenClass: TokenClass
        let position: Position
        let expectedVerdict: Verdict
        /// `AcceptClass` or `RejectionClass` rawValue.
        let expectedClass: String
        /// Provenance: corpus timestamp, CONTEXT.md decision ID, RESEARCH.md
        /// finding, or literal `"INVENTED"`.
        let note: String

        /// Cross-product cell key, format `editKind|tokenClass|position|language`.
        /// Shared format with `EditGuardFixtures.prunedCells` and
        /// `EditGuardFixtureCoverageTests`'s cell enumeration.
        var cell: String {
            "\(editKind.rawValue)|\(tokenClass.rawValue)|\(position.rawValue)|\(language)"
        }
    }

    // MARK: - The D-01 proof fixture (exempted from single-cell semantics)

    /// The one fixture a sentence-level pass/fail gate cannot produce: a
    /// SINGLE German sentence containing both a genuine repair (kept) and a
    /// corruption (reverted) in the same candidate. Composed from two real
    /// logged edits per Task 1's instruction ("if none exists, compose one
    /// from two logged edits"): the D-04 word-order repair
    /// ("...werden ja gleich sofort ausgewertet" -> "...gleich sofort
    /// ausgewertet werden") and the D-04 pronoun-person corruption
    /// ("Du wohnst" -> "Ich wohne", corpus 2026-07-11T14:05:11.597Z).
    ///
    /// `expectedVerdict` is `.accept` by convention only (the guard's overall
    /// output changes) — the record is fundamentally BOTH accept and reject
    /// at the edit level, which is exactly the point. It is exempted BY ID
    /// from `testExpectedTextIsSelfConsistent`'s per-verdict expectedText
    /// check, and from the plain shape cross-product (its cell overlaps
    /// `move|contentWord|interior|de`, already covered by
    /// `fx-mov-content-de-moodlock-falsepos`).
    ///
    /// This fixture is unsatisfiable by any sentence-level pass/fail gate.
    /// It is the reason D-01 exists.
    static let d01BundledFixture = Fixture(
        id: "fx-d01-bundled-repair-and-corruption-de",
        language: "de",
        baseline: "Weil die Fragen werden ja gleich sofort ausgewertet und du wohnst dort.",
        candidate: "Weil die Fragen ja gleich sofort ausgewertet werden und ich wohne dort.",
        expectedText: "Weil die Fragen ja gleich sofort ausgewertet werden und du wohnst dort.",
        editKind: .move,
        tokenClass: .contentWord,
        position: .interior,
        expectedVerdict: .accept,
        expectedClass: "wordOrderRepair",
        note: "D-01 architecture proof: composed from a real word-order repair " +
            "(D-04, corpus-grounded) + a real pronoun-person corruption " +
            "(corpus 2026-07-11T14:05:11.597Z) bundled in one sentence. " +
            "expectedText keeps the repair and reverts the corruption — a " +
            "string no sentence-level pass/fail gate can produce. " +
            "[44-10 fix] 'ja' restored to the candidate (was accidentally " +
            "dropped when this fixture was composed in 44-02 — the cited " +
            "D-04 word-order repair only moves 'werden', it never removes " +
            "'ja', and 'ja' is not on D-05's zero-ambiguity deletion list, " +
            "so its disappearance was inconsistent with this fixture's own " +
            "citations, not an intentional test of 'ja' deletion)."
    )

    // MARK: - The live-user "goodshine" pause-dots -> em-dash proof fixture

    /// LIVE PRODUCTION BUG, corpus 2026-07-12T09:38:37.354Z
    /// (`~/Library/Application Support/Dicticus/DebugRecordings/
    /// cleanup-2026-07-12.jsonl`, model `qwen2.5-3b-instruct-q4_k_m.gguf`,
    /// prompt `v-transcriptionist`): the user dictated a sentence with three
    /// mid-utterance thinking pauses; Whisper transcribed each as a run of
    /// six literal `.` characters (`......`). The LLM CORRECTLY repaired all
    /// three into properly-punctuated prose — wrapping "goodshine" in
    /// quotes and replacing the pause-dot runs flanking the appositive
    /// clause with em-dashes. The OLD, INVERTED gate (the one this phase
    /// exists to replace) reverted the whole record back to the dotted raw
    /// text — exactly the D-01 problem statement, caught live.
    ///
    /// `baseline`/`candidate` are the EXACT substring of `post_rules`/
    /// `llm_raw` (stripped of the `<corrected_text>` scaffold tags, which
    /// `CleanupService.stripPreamble` always removes before the guard ever
    /// sees the text — see `CleanupService.stripPreamble`'s
    /// `scaffoldPatterns`) covering the second sentence only, where all
    /// three pause-dot repairs live. The first sentence of the same record
    /// contains an UNRELATED "of course" -> "However" rephrase that the
    /// guard correctly rejects (`contentWordIdentityChange`/
    /// `contentWordDeletion`) but whose rejected period, in the FULL
    /// two-sentence record, gets mis-paired by `EditDiff`'s global move
    /// pass against one of this sentence's many identical "." tokens,
    /// producing a spurious mid-sentence period elsewhere in the OTHER
    /// sentence — a real, separate, corpus-grounded finding (reported in
    /// `44-GOODSHINE-VERIFICATION.md`, NOT fixed here; deliberately
    /// excluded from this fixture by trimming to the single sentence so
    /// this fixture only locks in the punctuation-repair behavior it
    /// names, not that unrelated cross-sentence artifact).
    ///
    /// Bundles FIVE edit kinds in one sentence (three `.`-run ->
    /// quote/em-dash substitutes, several `.`-run cosmetic deletes, one
    /// em-dash insert) — like `d01BundledFixture`, this is a real-world
    /// proof composition, not a single-cell fixture; tagged onto the
    /// already-covered `substitute|contentWord|interior|en` cell (same
    /// convention `fx-sub-punct-en-orphan-contraction` uses for a
    /// punctuation-boundary shape with no cell of its own) rather than
    /// colliding with or hiding behind a pruned one.
    ///
    /// VERIFIED by direct execution (not read from code) via
    /// `EditGuard.apply` — `xcodebuild test`, 2026-07-12: rebuilt text is
    /// byte-identical to `expectedText` below; every one of the three
    /// `.`-run edits classifies `accepted=true acceptClass=punctuationOrCasing`
    /// (D-06's punctuation-insert branch for the inserted em-dash, D-04's
    /// classifySubstitute rule #2 both-sides-punctuation branch for the
    /// quote/dash substitutes and the `.`-run cosmetic deletes).
    static let goodshinePauseDotsFixture = Fixture(
        id: "fx-sub-punct-en-goodshine-pausedots-emdash",
        language: "en",
        baseline: "And I think some kind of......goodshine......that roughly covers a new iPhone would be......appropriate.",
        candidate: "And I think some kind of \"goodshine\" — that roughly covers a new iPhone — would be appropriate.",
        expectedText: "And I think some kind of \"goodshine\" — that roughly covers a new iPhone — would be appropriate.",
        editKind: .substitute,
        tokenClass: .contentWord,
        position: .interior,
        expectedVerdict: .accept,
        expectedClass: "punctuationOrCasing",
        note: "LIVE production bug, corpus 2026-07-12T09:38:37.354Z — the " +
            "old inverted gate reverted this exact LLM repair back to the " +
            "raw dotted text, which is what actually got pasted at the " +
            "user's cursor. EditGuard.apply preserves it: verified by " +
            "direct execution, rebuilt text byte-identical to candidate."
    )

    /// LIVE production bug (the SAME corpus record as
    /// `goodshinePauseDotsFixture`, but the FULL two-sentence record, not
    /// the trimmed second sentence) — the post-corruption-fix regression
    /// fixture. The candidate's first sentence contains a genuine rephrase
    /// ("of course, but then" -> "However") the guard correctly REJECTS
    /// (`contentWordIdentityChange`/`contentWordDeletion`). But the
    /// candidate's own new period (closing the rejected rephrase's
    /// sentence) has NO local baseline partner to pair against — so
    /// `EditDiff.pairMovesFirst`'s GLOBAL, unbounded-distance identical-
    /// text matching pairs it as a `.move` against one of the SECOND
    /// sentence's eighteen `.` tokens (three six-dot pause-dot runs), a
    /// textually-identical but semantically-unrelated punctuation token
    /// clause-boundaries away. Before the fix, `classifyMove` accepted ANY
    /// move unconditionally as `wordOrderRepair` — including this one —
    /// injecting a spurious mid-sentence period: `"...what we suspect. of
    /// course, but then..."`, a genuine corruption (a false sentence
    /// boundary followed by a lowercase continuation). This fixture proves
    /// BOTH halves of the fix at once: the spurious period must NOT appear
    /// (the rejected move's punctuation token is restored, not injected —
    /// `EditGuard.classifyMove`'s new `kind == .punctuation` reject arm)
    /// AND the SAME record's genuine pause-dots -> quote/em-dash repair
    /// (`goodshinePauseDotsFixture`'s own proof) must still SURVIVE
    /// untouched a few tokens later in the SAME sentence — proving the fix
    /// is edit-local, not a blanket rejection of every punctuation edit
    /// near a dot-run. `expectedText` is VERIFIED by direct execution
    /// (`harness debugEG`, 2026-07-12) — rebuilt text byte-identical.
    /// `editKind`/`tokenClass`/`position` describe the fixture's DOMINANT
    /// mechanism (a rejected `.move` of a `.punctuation` token) using the
    /// closest-fit cross-product labels; like `d01BundledFixture` and
    /// `goodshinePauseDotsFixture`, this record is fundamentally MULTI-EDIT
    /// (several independent accepts and rejects in one text) — marked
    /// `.accept` by convention only, per `d01BundledFixture`'s own
    /// documented convention. No exemption from
    /// `testExpectedTextIsSelfConsistent` is needed: `expectedText` differs
    /// from `baseline` (many edits DID change the text), which is all the
    /// `.accept` branch of that check requires.
    static let goodshineFullRecordSpuriousMoveFixture = Fixture(
        id: "fx-mov-punct-en-goodshine-fullrecord-spuriousmove",
        language: "en",
        baseline: "Because to be fair, as of now we're not 100% sure and we will be surfacing what we suspect of course, but then I would also argue it's not my job to fix Apple's problems, at least not at my own expense, which is what has happened here. And I think some kind of......goodshine......that roughly covers a new iPhone would be......appropriate.",
        candidate: "Because to be fair, as of now we're not 100% sure, and we will be surfacing what we suspect. However, I would also argue it's not my job to fix Apple's problems, at least not at my own expense, which is what has happened here. And I think some kind of \"goodshine\" — that roughly covers a new iPhone — would be appropriate.",
        expectedText: "Because to be fair, as of now we're not 100% sure, and we will be surfacing what we suspect of course, but then I would also argue it's not my job to fix Apple's problems, at least not at my own expense, which is what has happened here. And I think some kind of.\"goodshine\" — that roughly covers a new iPhone — would be appropriate.",
        editKind: .move,
        tokenClass: .contentWord,
        position: .interior,
        expectedVerdict: .accept,
        expectedClass: "punctuationOrCasing",
        note: "LIVE production bug, corpus 2026-07-12T09:38:37.354Z, FULL " +
            "record (see goodshinePauseDotsFixture for the trimmed " +
            "second-sentence-only proof of the em-dash repair alone). " +
            "44-GOODSHINE-VERIFICATION.md root-caused this exact mechanism; " +
            "44-FIDELITY-REPLAY.md's SC#3 Adjudication Records 6/7 " +
            "independently found the same EditDiff.pairMovesFirst " +
            "unbounded-distance defect via non-punctuation tokens. Fix: " +
            "EditGuard.classifyMove rejects every `kind == .punctuation` " +
            "move unconditionally (never a genuine word-order repair — " +
            "punctuation is fungible and the most repetitive token class in " +
            "any text). Previously a known residual, NOT a meaning " +
            "corruption: the rejected move's punctuation token restored " +
            "with a leading space (\"of .\\\"goodshine\\\"\" instead of the " +
            "exact baseline dot-run spacing). 2026-07-17: " +
            "EditGuard.bindPunctuationLeft closes this at the root — the " +
            "kept token immediately before a restored single-char mark no " +
            "longer keeps its candidate-calibrated trailing space, so the " +
            "residual space is gone (\"of.\\\"goodshine\\\"\")."
    )

    /// The flagship-class counter-proof this fix must NOT break: a genuine
    /// German long-distance word-order repair (object fronting / V2
    /// topicalization) where the moved tokens travel across a LONG
    /// intervening clause — the move DISTANCE here (`abs(baseline.index -
    /// candidate.index)`, `EditDiff.pairMovesFirst`'s own selection metric)
    /// is deliberately large (~30 tokens), well above the 9-16 token
    /// distance range where 44-FIDELITY-REPLAY.md's SC#3 Adjudication
    /// Records 6/7 exhibited the cross-clause mispairing defect. This
    /// fixture is WHY a token-distance bound on `pairMovesFirst` (the
    /// alternative "lever 2" fix considered and rejected for this task) is
    /// unsafe: measured against the real qwen-era corpus (44-FIDELITY-
    /// REPLAY.md's re-measurement section), legitimate accepted word moves
    /// range up to distance 89, overlapping entirely with the Records 6/7
    /// problem range — no fixed distance cutoff can separate the two
    /// populations without silently rejecting genuine repairs like this
    /// one. `das`/`neue`/`Auto` (object) and `Ich`/`ich` (subject,
    /// re-cased) all move; every move classifies `wordOrderRepair` and
    /// `EditGuard.apply`'s rebuilt text is byte-identical to `candidate`.
    static let longDistanceGermanWordOrderRepairFixture = Fixture(
        id: "fx-mov-content-de-longdistance-objectfronting",
        language: "de",
        baseline: "Ich habe gestern nach der Arbeit ganz spontan und ohne es vorher gross anzukündigen zusammen mit meinen alten Freunden aus der Schulzeit sowie ein paar Kollegen von der Universität bei sehr schönem und warmem Wetter das neue Auto ausführlich angeschaut.",
        candidate: "Das neue Auto habe ich gestern nach der Arbeit ganz spontan und ohne es vorher gross anzukündigen zusammen mit meinen alten Freunden aus der Schulzeit sowie ein paar Kollegen von der Universität bei sehr schönem und warmem Wetter ausführlich angeschaut.",
        expectedText: "Das neue Auto habe ich gestern nach der Arbeit ganz spontan und ohne es vorher gross anzukündigen zusammen mit meinen alten Freunden aus der Schulzeit sowie ein paar Kollegen von der Universität bei sehr schönem und warmem Wetter ausführlich angeschaut.",
        editKind: .move,
        tokenClass: .contentWord,
        position: .sentenceInitial,
        expectedVerdict: .accept,
        expectedClass: "wordOrderRepair",
        note: "INVENTED — a deliberately LONG-distance analogue of " +
            "fx-mov-content-de-fronting (same V2 topicalization shape, " +
            "short sentence there). Exists specifically to lock in that " +
            "the punctuation-move rejection fix (fx-mov-punct-en-" +
            "goodshine-fullrecord-spuriousmove) does not collapse the " +
            "wordOrderRepair flagship class for genuinely long moves — " +
            "verified by direct execution (harness debugEG, 2026-07-12): " +
            "all 4 moves (Ich/ich, das/Das, neue/neue, Auto/Auto) accept as " +
            "wordOrderRepair, rebuilt text byte-identical to candidate."
    )

    // MARK: - Gap closure (2026-07-13): Defect B fix proof + Defect A open-defect lock

    /// LIVE production bug, corpus `2026-07-04T06:01:35.827Z` (44-01
    /// hand-labeled `repair`; `44-FIDELITY-REPLAY.md` §3 named it "a genuine
    /// rebuild-quality defect independent of D-05 policy" and left it
    /// unfixed at the time). `substitute(regards->Regarding)` passes D-02's
    /// lemma lock in isolation (same lemma "regard" — legitimate
    /// `inflectionFix`), but its immediate baseline neighbours `"In"` and
    /// `"to"` are independently, correctly rejected as `contentWordDeletion`
    /// (D-05's zero-ambiguity policy has no way to know "regards"->
    /// "Regarding" makes them grammatically redundant). Pre-fix, both
    /// rejected deletes restored at the front of the output, landing
    /// directly in front of "Regarding" — `"In to Regarding the
    /// definition..."`, neither the baseline nor a coherent repair.
    ///
    /// Fix (`EditGuard.applyAdjacentDeletionSubstituteCoupling`): a
    /// rejected `contentWordDeletion` immediately adjacent to an accepted,
    /// non-cosmetic `.substitute`/`.insert` reverts that neighbour too —
    /// the full baseline phrase is restored verbatim instead of a
    /// Frankenstein mix. `expectedText == baseline` (a `.reject`-shaped
    /// outcome even though the fixture's dominant, most-informative
    /// mechanism is the coupling revert of an otherwise-`.accept`
    /// substitute — hence `expectedClass: "unclassified"`, the coupling
    /// pass's own reject-class marker, not `contentWordDeletion`).
    /// Verified by direct execution (`harness debugEG`, 2026-07-13):
    /// rebuilt text byte-identical to baseline; `wordOrderRepair` (125
    /// corpus / 94 audit) unaffected — this coupling is scoped to
    /// rejected-DELETE neighbours only, never a rejected-substitute
    /// neighbour (see the function's own doc comment for why that
    /// broader scope was deliberately rejected — it would also catch
    /// genuine `inflectionFix`/`functionWordSubstitution` accepts).
    static let adjacentDeletionSubstituteCouplingFixture = Fixture(
        id: "fx-sub-content-en-inregardsto-couplingfix",
        language: "en",
        baseline: "In regards to the definition of what AI Cleanup is supposed to be, also with the repair tier taxonomy, which I don't quite understand what this is supposed to be.",
        candidate: "Regarding the definition of what AI Cleanup is supposed to be, and the repair tier taxonomy, which I don't quite understand what this is supposed to be.",
        expectedText: "In regards to the definition of what AI Cleanup is supposed to be, also with the repair tier taxonomy, which I don't quite understand what this is supposed to be.",
        editKind: .substitute,
        tokenClass: .contentWord,
        position: .interior,
        expectedVerdict: .reject,
        expectedClass: "unclassified",
        note: "LIVE production bug, corpus 2026-07-04T06:01:35.827Z — the " +
            "phase's own SC#3 §3 flagged this as a genuine rebuild-quality " +
            "defect ('In to Regarding the definition...') and left it " +
            "unfixed. Gap-closure fix (2026-07-13): " +
            "EditGuard.applyAdjacentDeletionSubstituteCoupling reverts an " +
            "accepted substitute/insert immediately adjacent to a rejected " +
            "contentWordDeletion, restoring the baseline phrase verbatim. " +
            "Verified byte-identical wordOrderRepair (125/94) and SC#3 " +
            "recall (unchanged) on the real corpus before/after."
    )

    /// KNOWN OPEN DEFECT — locked in, NOT fixed, per the 2026-07-13 gap-
    /// closure investigation's explicit, evidence-based decision NOT to
    /// ship a regression. Real-corpus shape (`44-FIDELITY-REPLAY.md`'s SC#3
    /// Adjudication Record 7's "denn man nicht," finding; independently
    /// re-confirmed live in a SECOND, unrelated corpus record during this
    /// session's Task 3 adjudication of `44-BAKEOFF.md`'s "re-emerged
    /// German deletion" survivor): `EditDiff.pairMovesFirst`'s GLOBAL,
    /// unbounded-distance identical-normalized-text move matching can pair
    /// two textually-identical but semantically UNRELATED occurrences of a
    /// common word across clause boundaries when the connecting content
    /// between them was independently rejected — here baseline's `"man"`
    /// and `"nicht"` (from `"...das sieht man nicht auf den ersten
    /// Blick..."`) individually move to land adjacent to each other in the
    /// rebuild (`"denn man nicht was..."`), because candidate's `"kann"`,
    /// which should sit between them, is itself an independently-rejected
    /// `contentWordInsertion` and never renders.
    ///
    /// THREE distinct distance-bounding levers were measured against the
    /// real 618-record qwen-era corpus (`fidelity44 --ab`) and the 232-
    /// record fresh-Qwen3.5 audit population (`auditReplay44`) this
    /// session and ALL rejected as unsafe: (1) a sentence-index bound
    /// (already rejected pre-session, -32% `wordOrderRepair`); (2) a fixed
    /// move-distance cap (already rejected pre-session — legitimate moves
    /// range 0-89 tokens, fully overlapping the 9-16 token problem range);
    /// (3) a "local stable-anchor window" bound (measured THIS session,
    /// both OR- and AND-neighbour variants) — the ONLY window narrow
    /// enough to close this defect (<=12 candidate-index tokens) costs
    /// `wordOrderRepair` 125->98 (-21.6%) on the full corpus / 94->90
    /// (-4.3%) on the audit population, the SAME order of magnitude as
    /// the already-rejected sentence bound. Per this task's own explicit
    /// fallback instruction ("If you cannot find a fix that preserves
    /// wordOrderRepair... report that you could not, and leave it open"),
    /// NO fix ships. This fixture exists so a FUTURE attempt has a
    /// concrete, corpus-grounded regression net: if `guardedText` ever
    /// changes from `expectedText` below, re-verify `wordOrderRepair`
    /// (125 corpus / 94 audit) has not silently regressed as the price.
    static let crossClauseMoveMispairingOpenDefectFixture = Fixture(
        id: "fx-mov-content-de-crossclause-manicht-knownopen",
        language: "de",
        baseline: "Auch diese Frage ist erst einmal unübersichtlich, denn was muss sich wie zuordnen, was ist überhaupt das Thema, das sieht man nicht auf den ersten Blick. Das muss definitiv auch besser gelöst werden. Und dann schätze ich hier die Frage, kontinuierliche Führungsrhythmen, nach welchem Reglement geht es hier um die unternehmerischen Führungsrhythmen und Prozesse? geht es um die Führungsprozesse aus dem KODAL.",
        candidate: "Und das ist zunächst unübersichtlich, denn man kann nicht sofort erkennen, was sich zuordnen lässt und was das Thema ist. Das muss definitiv besser gelöst werden. Darüber hinaus schätze ich die Frage nach kontinuierlichen Führungsrhythmen. Welches Reglement geht hier konkret auf unternehmerische Führungsrhythmen und Prozesse zu? Gibt es KODAL-Prozesse, die hier in Betracht gezogen werden?",
        expectedText: "Auch diese Frage ist erst einmal unübersichtlich, denn was muss sich wie zuordnen, was ist überhaupt das Thema, das sieht man nicht auf den ersten Blick. Das muss definitiv auch besser gelöst werden. Und dann schätze ich hier die Frage, kontinuierliche Führungsrhythmen, nach welchem Reglement geht es hier um die unternehmerischen Führungsrhythmen und Prozesse? geht es um die Führungsprozesse aus dem KODAL.",
        editKind: .move,
        tokenClass: .contentWord,
        position: .interior,
        expectedVerdict: .accept,
        expectedClass: "wordOrderRepair",
        note: "260723-rif UPDATE: expectedText moved again (3rd time — see " +
            "the 2026-07-17 and 2026-07-19 updates below for precedent). " +
            "`applyAtomicGroupCoupling`'s atomic-revert-group principle " +
            "reverts EVERY accepted move in this record's several " +
            "keep-bounded clusters that also contain a rejected content " +
            "edit (the man/nicht cross-clause mispairing this fixture " +
            "exists to track is exactly such a cluster) — this fixture's " +
            "OWN accepted wordOrderRepair count goes from several to 0, " +
            "which is WHY testRepairYieldFloor_wordOrderRepairsPreserved's " +
            "pinned constant moves 23->17 (traced entirely to this one " +
            "fixture; every other move fixture, including all 3 named " +
            "German verb-order repairs sind/ist/werden, is UNCHANGED by " +
            "260723-rif once the punctuation-only-group exemption is " +
            "applied — see EditGuard.applyAtomicGroupCoupling's own doc " +
            "comment). This is expected, not a silent regression: the new " +
            "expectedText is now byte-closer to a clean baseline-or-" +
            "candidate mix and the known man/nicht mispairing NO LONGER " +
            "appears (the cluster containing it now fully reverts to " +
            "baseline instead of partially splicing) — an incidental " +
            "IMPROVEMENT of the open defect, not a fix (still tracked " +
            "open; the underlying EditDiff.pairMovesFirst mispairing this " +
            "fixture's id references is untouched by this quick task, out " +
            "of its locked scope). KNOWN OPEN DEFECT, NOT a corrected behavior — locked in " +
            "2026-07-13 to document the CURRENT (imperfect) output after " +
            "an extensive, measured investigation found no fix that " +
            "preserves the flagship wordOrderRepair class (125 corpus / " +
            "94 audit) — see EditDiff.pairMovesFirst's doc comment and " +
            "44-FIDELITY-REPLAY.md's gap-closure section for the full " +
            "three-lever rejection record. `.accept` by convention only " +
            "(per d01BundledFixture's own documented convention) — this " +
            "record is fundamentally multi-edit, most of it correctly " +
            "rejected/restored; only the man/nicht cross-clause mispairing " +
            "is the defect this fixture exists to track. 2026-07-17: " +
            "EditGuard.bindPunctuationLeft closed the UNRELATED space-" +
            "before-comma artifact this record's expectedText also " +
            "happened to carry (\"zuordnen , und\" -> \"zuordnen, und\", " +
            "\"Thema , sieht\" -> \"Thema, sieht\"); the cross-clause " +
            "mispairing defect itself remains open and untouched. " +
            "2026-07-19 (quick task 8am): EditDiff.pairMovesFirst's new " +
            "locality constraint (word/content tokens only, see its doc " +
            "comment) disqualified 2 of this fixture's move pairings as a " +
            "side effect of closing the cross-clause phantom-move class — " +
            "CONTENT-PRESERVING relocation only (same word multiset: " +
            "\"das\" moved from right after \"Frage\" to right before " +
            "\"sieht\"; \"hier\" moved from a glued sentence-final " +
            "\"KODAL.hier\" corruption to its correct mid-sentence position " +
            "\"schätze ich hier die Frage\" — an additional, incidental fix, " +
            "not a regression). Repair-yield floor 25->23 pre/post-fix, " +
            "entirely accounted for by this ONE fixture " +
            "(EditGuardGrammarRegressionTests.testRepairYieldFloor_" +
            "wordOrderRepairsPreserved); every other move fixture, " +
            "including all 3 named German verb-order repairs " +
            "(sind/ist/werden), is byte-identical before/after. The man/" +
            "nicht cross-clause mispairing itself remains open and " +
            "untouched — this fixture is NOT closed, only its expectedText " +
            "moved with the new, still-imperfect, rebuild."
    )

    // MARK: - substitute x digit

    static let substituteDigit: [Fixture] = [
        Fixture(
            id: "fx-sub-digit-en-value",
            language: "en",
            baseline: "...the latency was 10,011 milliseconds under load.",
            candidate: "...the latency was 10,111 milliseconds under load.",
            expectedText: "...the latency was 10,011 milliseconds under load.",
            editKind: .substitute, tokenClass: .digit, position: .interior,
            expectedVerdict: .reject, expectedClass: "digitValueChange",
            note: "Corpus 2026-07-11T08:05:55.432Z — D-03 blindspot fixture: " +
                "tokenizeForDialectGate splits '10,011' into ['10','011'], " +
                "both <4 chars, structurally invisible to the pre-Phase-44 gate."
        ),
        Fixture(
            id: "fx-sub-digit-de-value",
            language: "de",
            baseline: "Wir treffen uns um 14 Uhr.",
            candidate: "Wir treffen uns um 15 Uhr.",
            expectedText: "Wir treffen uns um 14 Uhr.",
            editKind: .substitute, tokenClass: .digit, position: .interior,
            expectedVerdict: .reject, expectedClass: "digitValueChange",
            note: "INVENTED — DE analogue of a digit-value-change corruption; " +
                "D-03 ('digits are a HARD LOCK') applies symmetrically to DE and EN."
        ),
        Fixture(
            id: "fx-sub-digit-de-numberform",
            language: "de",
            baseline: "Ich habe 10 Kunden angerufen.",
            candidate: "Ich habe zehn Kunden angerufen.",
            expectedText: "Ich habe zehn Kunden angerufen.",
            editKind: .substitute, tokenClass: .digit, position: .interior,
            expectedVerdict: .accept, expectedClass: "numberFormChange",
            note: "D-03: '10 -> zehn ... Expected: accept / numberFormChange. " +
                "Pins the D-03/NumberRevert ordering: the guard must NOT reject " +
                "same-value form changes, or NumberRevert becomes unreachable.'"
        ),
        Fixture(
            id: "fx-sub-digit-en-numberform",
            language: "en",
            baseline: "I called 10 customers.",
            candidate: "I called ten customers.",
            expectedText: "I called ten customers.",
            editKind: .substitute, tokenClass: .digit, position: .interior,
            expectedVerdict: .accept, expectedClass: "numberFormChange",
            note: "D-03: '(and ten for EN)' — same value, form only."
        )
    ]

    // MARK: - substitute x pronoun

    static let substitutePronoun: [Fixture] = [
        Fixture(
            id: "fx-sub-pronoun-de-personflip",
            language: "de",
            baseline: "Du wohnst ja in einem Block.",
            candidate: "Ich wohne ja in einem Block.",
            expectedText: "Du wohnst ja in einem Block.",
            editKind: .substitute, tokenClass: .pronoun, position: .sentenceInitial,
            expectedVerdict: .reject, expectedClass: "pronounPersonChange",
            note: "Corpus 2026-07-11T14:05:11.597Z (+ near-duplicate at " +
                "T14:05:21.029Z) — D-04 pronoun-lock: 'a pronoun may never be " +
                "deleted nor change person.'"
        ),
        Fixture(
            id: "fx-sub-pronoun-en-genderflip",
            language: "en",
            baseline: "You should ask him about the schedule.",
            candidate: "You should ask her about the schedule.",
            expectedText: "You should ask him about the schedule.",
            editKind: .substitute, tokenClass: .pronoun, position: .interior,
            expectedVerdict: .reject, expectedClass: "pronounPersonChange",
            note: "INVENTED — EN analogue proving D-04's pronoun-lock applies " +
                "symmetrically to EN, not just DE."
        )
    ]

    // MARK: - substitute x contentWord (de) — the D-02/RESEARCH adversarial cluster

    static let substituteContentWordDe: [Fixture] = [
        Fixture(
            id: "fx-sub-content-de-personflip-verb",
            language: "de",
            baseline: "Du wohnst ja in einem Block.",
            candidate: "Ich wohne ja in einem Block.",
            expectedText: "Du wohnst ja in einem Block.",
            editKind: .substitute, tokenClass: .contentWord, position: .interior,
            expectedVerdict: .reject, expectedClass: "contentWordIdentityChange",
            note: "Corpus 2026-07-11T14:05:11.597Z — Trap A person-ending flip " +
                "('wohnst'->'wohne'), NOT a legal inflection. Same sentence pair " +
                "as fx-sub-pronoun-de-personflip, tagged on the contentWord " +
                "dimension per plan Task 1 ('TWO fixtures')."
        ),
        Fixture(
            id: "fx-sub-content-de-typo-introduced",
            language: "de",
            baseline: "Ich frage mich, welchen Führungsrhythmus wir hier brauchen.",
            candidate: "Ich frage mich, welchen Führungsrythmus wir hier brauchen.",
            expectedText: "Ich frage mich, welchen Führungsrhythmus wir hier brauchen.",
            editKind: .substitute, tokenClass: .contentWord, position: .interior,
            expectedVerdict: .reject, expectedClass: "contentWordIdentityChange",
            note: "Corpus 2026-07-11T13:18:03.074Z — the Damerau-OSA leak fixture " +
                "(OSA distance 1); CleanupService.swift:1040's blanket-accept " +
                "clause passed an INTRODUCED typo. CONFIRMED to have PASSED the " +
                "pre-Phase-44 gate and survived to paste."
        ),
        Fixture(
            id: "fx-sub-content-de-inflection-beinhalten",
            language: "de",
            baseline: "Das Angebot beinhalten die Versicherung.",
            candidate: "Das Angebot beinhaltet die Versicherung.",
            expectedText: "Das Angebot beinhaltet die Versicherung.",
            editKind: .substitute, tokenClass: .contentWord, position: .interior,
            expectedVerdict: .accept, expectedClass: "inflectionFix",
            note: "D-02: 'Permitted: beinhalten -> beinhaltet ... INFLECTION " +
                "only (same lemma).'"
        ),
        Fixture(
            id: "fx-sub-content-de-format-formats",
            language: "de",
            baseline: "Bezüglich Format habe ich eine Frage.",
            candidate: "Bezüglich des Formats habe ich eine Frage.",
            expectedText: "Bezüglich des Formats habe ich eine Frage.",
            editKind: .substitute, tokenClass: .contentWord, position: .interior,
            expectedVerdict: .accept, expectedClass: "inflectionFix",
            note: "D-02/D-06 combined example: 'Bezüglich Format' -> 'Bezüglich " +
                "des Formats' — co-occurring insert(des) + substitute(Format-> " +
                "Formats). Shares this baseline/candidate with fx-ins-func-de."
        ),
        Fixture(
            id: "fx-sub-content-de-messer-messe",
            language: "de",
            baseline: "Ich brauche noch ein scharfes Messer für die Küche.",
            candidate: "Ich brauche noch ein scharfes Messe für die Küche.",
            expectedText: "Ich brauche noch ein scharfes Messer für die Küche.",
            editKind: .substitute, tokenClass: .contentWord, position: .interior,
            expectedVerdict: .reject, expectedClass: "contentWordIdentityChange",
            note: "44-RESEARCH.md 'KNOWN ADVERSARIAL DEFEATS' — Messer/Messe " +
                "spurious stem overlap via -r<->'' transition. If the inflection " +
                "rule cannot pass this fixture, the RULE fails closed (44-04), " +
                "not the fixture."
        ),
        Fixture(
            id: "fx-sub-content-de-wagen-wagt",
            language: "de",
            baseline: "Er hat den Wagen repariert.",
            candidate: "Er hat den wagt repariert.",
            expectedText: "Er hat den Wagen repariert.",
            editKind: .substitute, tokenClass: .contentWord, position: .interior,
            expectedVerdict: .reject, expectedClass: "contentWordIdentityChange",
            note: "44-RESEARCH.md known adversarial defeat — Wagen/wagt noun/" +
                "verb crossover via -en<->-t transition."
        ),
        Fixture(
            id: "fx-sub-content-de-hunde-hund",
            language: "de",
            baseline: "Wir haben zwei Hunde im Garten gesehen.",
            candidate: "Wir haben zwei Hund im Garten gesehen.",
            expectedText: "Wir haben zwei Hunde im Garten gesehen.",
            editKind: .substitute, tokenClass: .contentWord, position: .interior,
            expectedVerdict: .reject, expectedClass: "contentWordIdentityChange",
            note: "Trap B: plural->singular strip-to-empty-suffix; plan Task 1 " +
                "named defeat."
        ),
        Fixture(
            id: "fx-sub-content-de-tolles-toll",
            language: "de",
            baseline: "Das war etwas tolles heute.",
            candidate: "Das war etwas toll heute.",
            expectedText: "Das war etwas tolles heute.",
            editKind: .substitute, tokenClass: .contentWord, position: .interior,
            expectedVerdict: .reject, expectedClass: "contentWordIdentityChange",
            note: "Trap B: strip-to-empty-suffix; plan Task 1 named defeat."
        ),
        Fixture(
            id: "fx-sub-content-de-handhabe-handhabung",
            language: "de",
            baseline: "Ich brauche eine bessere Handhabe für dieses Problem.",
            candidate: "Ich brauche eine bessere Handhabung für dieses Problem.",
            expectedText: "Ich brauche eine bessere Handhabe für dieses Problem.",
            editKind: .substitute, tokenClass: .contentWord, position: .interior,
            expectedVerdict: .reject, expectedClass: "derivationalSuffixChange",
            note: "D-02a (amended 2026-07-12, user decision on research " +
                "evidence): DERIVATION IS BLOCKED. Handhabe->Handhabung is " +
                "SUPERSEDED from D-02's original 'permitted' table entry to " +
                "blocked. Do NOT 'correct' this fixture to accept."
        ),
        Fixture(
            id: "fx-sub-content-de-krankheit-kraenkung",
            language: "de",
            baseline: "Diese Krankheit hat ihn sehr geschwächt.",
            candidate: "Diese Kränkung hat ihn sehr geschwächt.",
            expectedText: "Diese Krankheit hat ihn sehr geschwächt.",
            editKind: .substitute, tokenClass: .contentWord, position: .interior,
            expectedVerdict: .reject, expectedClass: "derivationalSuffixChange",
            note: "D-02a: same morphological operation as Handhabe->Handhabung " +
                "— permitting one would license this meaning-change too."
        ),
        Fixture(
            id: "fx-sub-content-de-beobachter-beobachtung",
            language: "de",
            baseline: "Der Beobachter hat alles notiert.",
            candidate: "Die Beobachtung hat alles notiert.",
            expectedText: "Der Beobachter hat alles notiert.",
            editKind: .substitute, tokenClass: .contentWord, position: .interior,
            expectedVerdict: .reject, expectedClass: "derivationalSuffixChange",
            note: "D-02a: same class as Handhabe->Handhabung; why permitting " +
                "derivation is unsafe."
        ),
        Fixture(
            id: "fx-sub-content-de-lauft-umlaut",
            language: "de",
            baseline: "Er lauft jeden Morgen zur Arbeit.",
            candidate: "Er läuft jeden Morgen zur Arbeit.",
            expectedText: "Er lauft jeden Morgen zur Arbeit.",
            editKind: .substitute, tokenClass: .contentWord, position: .interior,
            expectedVerdict: .reject, expectedClass: "contentWordIdentityChange",
            note: "44-RESEARCH.md Pitfall 2: umlaut mutation breaks the exact-" +
                "stem hypothesis. DELIBERATE FALSE-REJECT — do not special-case " +
                "irregulars; asymmetric risk (a false reject costs a missed " +
                "repair, a false accept costs a corrupted meaning)."
        ),
        Fixture(
            id: "fx-sub-content-de-singen-ablaut",
            language: "de",
            baseline: "Die Kinder singen ein Lied im Park.",
            candidate: "Die Kinder sang ein Lied im Park.",
            expectedText: "Die Kinder singen ein Lied im Park.",
            editKind: .substitute, tokenClass: .contentWord, position: .interior,
            expectedVerdict: .reject, expectedClass: "contentWordIdentityChange",
            note: "44-RESEARCH.md Pitfall 2: ablaut mutation (singen->sang); " +
                "DELIBERATE FALSE-REJECT, same asymmetric-risk rationale as the " +
                "umlaut fixture."
        )
    ]

    // MARK: - substitute x contentWord (en)

    static let substituteContentWordEn: [Fixture] = [
        Fixture(
            id: "fx-sub-content-en-identity-reject",
            language: "en",
            baseline: "The meeting is scheduled for Friday.",
            candidate: "The meeting is planned for Friday.",
            expectedText: "The meeting is scheduled for Friday.",
            editKind: .substitute, tokenClass: .contentWord, position: .interior,
            expectedVerdict: .reject, expectedClass: "contentWordIdentityChange",
            note: "INVENTED — EN analogue proving D-02's lemma-lock applies " +
                "symmetrically to EN, not just DE."
        ),
        Fixture(
            id: "fx-sub-content-en-inflection-accept",
            language: "en",
            baseline: "He want to leave early today.",
            candidate: "He wants to leave early today.",
            expectedText: "He wants to leave early today.",
            editKind: .substitute, tokenClass: .contentWord, position: .interior,
            expectedVerdict: .accept, expectedClass: "inflectionFix",
            note: "INVENTED — EN inflection accept, symmetric with D-02's DE " +
                "examples (beinhalten -> beinhaltet)."
        )
    ]

    // MARK: - substitute x contentWord — SC#3 gap-closure (word-vs-punctuation
    // pairing hole). Deliberately kept OUT of substituteContentWordDe/En:
    // InflectionRulesTests.testSubstitutedWordPairCoversEveryContentWordSubstitutionFixture
    // requires every fixture in those two arrays to have a hand-mapped
    // single-word substitution pair for lemma/inflection calibration — this
    // fixture's "substitution" is a word-vs-punctuation diff-pairing artifact,
    // not a word-pair InflectionRules has any opinion on, so it does not
    // belong in that coupled test's sweep.

    static let substitutePunctuationBoundary: [Fixture] = [
        Fixture(
            id: "fx-sub-punct-en-orphan-contraction",
            language: "en",
            baseline: "This is also in proper grammar and style it's",
            candidate: "This is also in proper grammar and style.",
            expectedText: "This is also in proper grammar and style it's",
            editKind: .substitute, tokenClass: .contentWord, position: .interior,
            expectedVerdict: .reject, expectedClass: "contentWordIdentityChange",
            note: "SC#3 gap-closure fixture (44-FIDELITY-REPLAY.md §2/§6) — " +
                "corpus 2026-07-08T16:22:31.625Z: baseline ends in a " +
                "truncated, orphaned \"it's\"; the LLM (correctly) drops it " +
                "and closes the sentence with a period. EditDiff's " +
                "LCS+substitute-pairing has nothing else to pair the " +
                "trailing \"it's\" against, so it pairs it with the " +
                "candidate's trailing \".\" as a word-vs-punctuation " +
                "substitute — the SAME root cause found independently in " +
                "the §6 A/B legacy-gate retirement hole (identical " +
                "timestamp). Proves classifySubstitute rule #2 requires " +
                "BOTH sides punctuation, not either side: a real word " +
                "paired against punctuation must fall through to the " +
                "content-word checks, not blanket-accept as " +
                "punctuationOrCasing. Physically sentence-terminal in the " +
                "source, but per this file's own pruned-cell rationale " +
                "(\"substitute|contentWord|terminal|en COLLAPSES into " +
                "substitute|contentWord|interior|en — D-02 lemma-lock " +
                "classification is position-invariant\") this fixture is " +
                "tagged position: .interior to land in the already-covered " +
                "cell rather than collide with that pruned one."
        )
    ]

    // MARK: - substitute x functionWord

    static let substituteFunctionWord: [Fixture] = [
        Fixture(
            id: "fx-sub-func-de-der-das",
            language: "de",
            baseline: "Der Auto steht vor dem Haus.",
            candidate: "Das Auto steht vor dem Haus.",
            expectedText: "Das Auto steht vor dem Haus.",
            editKind: .substitute, tokenClass: .functionWord, position: .sentenceInitial,
            expectedVerdict: .accept, expectedClass: "functionWordSubstitution",
            note: "D-02: 'Permitted: der -> das.'"
        ),
        Fixture(
            id: "fx-sub-func-en-a-an",
            language: "en",
            baseline: "A apple fell from the tree.",
            candidate: "An apple fell from the tree.",
            expectedText: "An apple fell from the tree.",
            editKind: .substitute, tokenClass: .functionWord, position: .sentenceInitial,
            expectedVerdict: .accept, expectedClass: "functionWordSubstitution",
            note: "INVENTED — EN analogue of an article-agreement fix, " +
                "symmetric with D-02's der->das."
        ),
        Fixture(
            id: "fx-req-punctcasing-de",
            language: "de",
            baseline: "das ist gut",
            candidate: "Das ist gut.",
            expectedText: "Das ist gut.",
            editKind: .substitute, tokenClass: .functionWord, position: .sentenceInitial,
            expectedVerdict: .accept, expectedClass: "punctuationOrCasing",
            note: "Plan Task 1 required fixture: 'A pure punctuation + casing " +
                "edit — accept / punctuationOrCasing, both languages.'"
        ),
        Fixture(
            id: "fx-req-punctcasing-en",
            language: "en",
            baseline: "this is good",
            candidate: "This is good.",
            expectedText: "This is good.",
            editKind: .substitute, tokenClass: .functionWord, position: .sentenceInitial,
            expectedVerdict: .accept, expectedClass: "punctuationOrCasing",
            note: "Plan Task 1 required fixture, EN half of the punctuation + " +
                "casing pair."
        )
    ]

    // MARK: - substitute x filler

    static let substituteFiller: [Fixture] = [
        Fixture(
            id: "fx-sub-filler-de-reject",
            language: "de",
            baseline: "Das ist, äh, ziemlich gut.",
            candidate: "Das ist, ja, ziemlich gut.",
            expectedText: "Das ist, äh, ziemlich gut.",
            editKind: .substitute, tokenClass: .filler, position: .interior,
            expectedVerdict: .reject, expectedClass: "unclassified",
            note: "INVENTED — fillers may only be DELETED (D-05), never " +
                "substituted for another word; fail-closed default since no " +
                "accept class covers filler substitution."
        ),
        Fixture(
            id: "fx-sub-filler-en-reject",
            language: "en",
            baseline: "This is, um, quite good.",
            candidate: "This is, well, quite good.",
            expectedText: "This is, um, quite good.",
            editKind: .substitute, tokenClass: .filler, position: .interior,
            expectedVerdict: .reject, expectedClass: "unclassified",
            note: "INVENTED — EN analogue; same fail-closed rationale as " +
                "fx-sub-filler-de-reject."
        )
    ]

    // MARK: - delete x digit

    static let deleteDigit: [Fixture] = [
        Fixture(
            id: "fx-del-digit-de",
            language: "de",
            baseline: "Ich habe 5 Äpfel gekauft.",
            candidate: "Ich habe Äpfel gekauft.",
            expectedText: "Ich habe 5 Äpfel gekauft.",
            editKind: .delete, tokenClass: .digit, position: .interior,
            expectedVerdict: .reject, expectedClass: "contentWordDeletion",
            note: "INVENTED — 44-RESEARCH.md D-03 code example: '.delete(N1): " +
                "REJECT (numbers are never in the D-05 filler/repetition list, " +
                "except the verbatim-adjacent-repetition case).'"
        ),
        Fixture(
            id: "fx-del-digit-en",
            language: "en",
            baseline: "I bought 5 apples yesterday.",
            candidate: "I bought apples yesterday.",
            expectedText: "I bought 5 apples yesterday.",
            editKind: .delete, tokenClass: .digit, position: .interior,
            expectedVerdict: .reject, expectedClass: "contentWordDeletion",
            note: "INVENTED — EN analogue of fx-del-digit-de."
        )
    ]

    // MARK: - delete x pronoun

    static let deletePronoun: [Fixture] = [
        Fixture(
            id: "fx-del-pronoun-en-sentenceinitial",
            language: "en",
            baseline: "You can push the commits, but no PR.",
            candidate: "Push the commits, but no PR.",
            expectedText: "You can push the commits, but no PR.",
            editKind: .delete, tokenClass: .pronoun, position: .sentenceInitial,
            expectedVerdict: .reject, expectedClass: "pronounDeleted",
            note: "Corpus 2026-07-12T03:43:31.761Z — D-04 pronoun-lock: 'a " +
                "pronoun may never be deleted.'"
        ),
        Fixture(
            id: "fx-del-pronoun-de-interior",
            language: "de",
            baseline: "Ich denke, dass wir das schaffen können.",
            candidate: "Ich denke, dass das schaffen können.",
            expectedText: "Ich denke, dass wir das schaffen können.",
            editKind: .delete, tokenClass: .pronoun, position: .interior,
            expectedVerdict: .reject, expectedClass: "pronounDeleted",
            note: "INVENTED — DE analogue proving D-04's pronoun-lock applies " +
                "symmetrically to DE."
        )
    ]

    // MARK: - delete x contentWord

    static let deleteContentWord: [Fixture] = [
        Fixture(
            id: "fx-del-content-en-scratch",
            language: "en",
            baseline: "But the question remains: what kind of commands would " +
                "remain? Aside from scratch that. And also...",
            candidate: "But the question remains: what kind of commands would " +
                "remain? Aside from that. And also...",
            expectedText: "But the question remains: what kind of commands " +
                "would remain? Aside from scratch that. And also...",
            editKind: .delete, tokenClass: .contentWord, position: .interior,
            expectedVerdict: .reject, expectedClass: "contentWordDeletion",
            note: "Corpus 2026-07-11T05:06:57.921Z."
        ),
        Fixture(
            id: "fx-del-content-de-das",
            language: "de",
            baseline: "Ich habe das Auto gesehen, das rote.",
            candidate: "Ich habe Auto gesehen, das rote.",
            expectedText: "Ich habe das Auto gesehen, das rote.",
            editKind: .delete, tokenClass: .contentWord, position: .interior,
            expectedVerdict: .reject, expectedClass: "contentWordDeletion",
            note: "44-CORPUS-AUDIT.md / plan Task 1 alternative example: 'the " +
                "logged \"das\" deletion.'"
        ),
        Fixture(
            id: "fx-del-content-de-restoration-boundary-glue",
            language: "de",
            baseline: "Auch hier ist die Essensdarstellung nicht optimal, da " +
                "wir zum Beispiel unterschiedlich grosse Textboxen haben, " +
                "und dann ist alles richtig, wenn wir das anders machen.",
            candidate: "Auch hier ist die Essensdarstellung nicht optimal, " +
                "und dann ist alles richtig, wenn wir das anders machen.",
            expectedText: "Auch hier ist die Essensdarstellung nicht " +
                "optimal, da wir zum Beispiel unterschiedlich grosse " +
                "Textboxen haben, und dann ist alles richtig, wenn wir das " +
                "anders machen.",
            editKind: .delete, tokenClass: .contentWord, position: .interior,
            expectedVerdict: .reject, expectedClass: "contentWordDeletion",
            note: "260723-rif UPDATE: expectedText now keeps the comma " +
                "after 'haben' (byte-identical to baseline) instead of " +
                "dropping it. `applyAtomicGroupCoupling` correctly groups " +
                "the comma's delete into the SAME keep-bounded cluster as " +
                "the 8 rejected content-word deletes around it (all " +
                "consecutive non-keep edits between 'optimal,' and 'und') " +
                "and reverts it too, since the cluster has a non-punctuation " +
                "(content) member — this is the atomic-revert-group " +
                "principle working as designed, not a regression: keeping " +
                "the comma matches baseline exactly (zero tier-1/tier-2 " +
                "neither-source risk), where the old drop-the-comma output, " +
                "while not itself a tier-1 violation, WAS a tier-2 " +
                "violation (a fused 'haben und' bigram present in NEITHER " +
                "source verbatim, once the comma between them vanished) — " +
                "so the new behavior is strictly safer, not merely " +
                "different. " +
                "SC#3 gap-closure fixture (44-FIDELITY-REPLAY.md §2/§3) — " +
                "wording grounded in corpus 2026-07-12T04:00:34.093Z " +
                "('Essensdarstellung nicht optimal, da wir zum Beispiel " +
                "unterschiedlich grosse Textboxen haben'), reshaped into a " +
                "self-contained sentence pair so the degenerate-alignment " +
                "gate does not fail-closed the whole thing (the real " +
                "record's candidate replaces almost the entire baseline, " +
                "which trips isDegenerate on its own before this bug's " +
                "mechanism is ever exercised). The candidate deletes the " +
                "'da wir ... Textboxen haben' clause; every content word in " +
                "it is correctly rejected (contentWordDeletion) and " +
                "restored, but the COMMA immediately after 'haben' in the " +
                "baseline is, independently and correctly, an ACCEPTED " +
                "cosmetic deletion — so nothing restores it, and 'haben' " +
                "(whose own baseline trailing is \"\", since the comma was " +
                "its own separate token directly after it) ends up glued " +
                "to whatever candidate token survives next ('und'), " +
                "producing 'habenund' pre-fix. This is the general " +
                "mechanism behind the real corpus's 'habenUnd', 'etcDann', " +
                "'optimalda', 'RechtsprechungDatenschutzvorgaben' glued-word " +
                "artifacts: a restored token's trailing was calibrated " +
                "against a baseline neighbor that did not survive to sit " +
                "next to it in the rebuilt output. `expectedVerdict` is " +
                ".reject by CONVENTION ONLY (mirrors fx-d01-bundled-repair-" +
                "and-corruption-de) — the record is fundamentally a REJECT " +
                "(the content deletion) plus one small independently-" +
                "ACCEPTED cosmetic comma edit, so expectedText differs from " +
                "baseline by exactly that dropped comma; exempted BY ID " +
                "from testExpectedTextIsSelfConsistent's strict per-verdict " +
                "check for the same reason the D-01 bundled fixture is."
        )
    ]

    // MARK: - delete x functionWord

    static let deleteFunctionWord: [Fixture] = [
        Fixture(
            id: "fx-del-func-de",
            language: "de",
            baseline: "Er geht in die Schule.",
            candidate: "Er geht die Schule.",
            expectedText: "Er geht in die Schule.",
            editKind: .delete, tokenClass: .functionWord, position: .interior,
            expectedVerdict: .reject, expectedClass: "unclassified",
            note: "INVENTED — function-word deletion is not in D-05's zero-" +
                "ambiguity list (fillers + verbatim repetition only); fail-" +
                "closed default."
        ),
        Fixture(
            id: "fx-del-func-en",
            language: "en",
            baseline: "I go to the store every morning.",
            candidate: "I go the store every morning.",
            expectedText: "I go to the store every morning.",
            editKind: .delete, tokenClass: .functionWord, position: .interior,
            expectedVerdict: .reject, expectedClass: "unclassified",
            note: "INVENTED — EN analogue of fx-del-func-de."
        )
    ]

    // MARK: - delete x filler (all 6 cells covered — the D-05 evidence table)

    static let deleteFiller: [Fixture] = [
        Fixture(
            id: "fx-del-filler-de-si-aehm",
            language: "de",
            baseline: "Äh, das ist gut.",
            candidate: "Das ist gut.",
            expectedText: "Das ist gut.",
            editKind: .delete, tokenClass: .filler, position: .sentenceInitial,
            expectedVerdict: .accept, expectedClass: "fillerDeletion",
            note: "D-05: 'Deletable: acoustic fillers that are never content " +
                "(äh, ähm, uh, um, hm).'"
        ),
        Fixture(
            id: "fx-del-filler-de-si-noch",
            language: "de",
            baseline: "Noch nicht am Ziel, aber wir kommen voran.",
            candidate: "Nicht am Ziel, aber wir kommen voran.",
            expectedText: "Noch nicht am Ziel, aber wir kommen voran.",
            editKind: .delete, tokenClass: .filler, position: .sentenceInitial,
            expectedVerdict: .reject, expectedClass: "contentWordDeletion",
            note: "D-05 particle table: 'noch — 51 occurrences — deleting " +
                "flips \"not yet\" -> \"not\".' Required D-05 negative fixture."
        ),
        Fixture(
            id: "fx-del-filler-de-si-doch",
            language: "de",
            baseline: "Doch keiner stellt sich die Frage.",
            candidate: "Keiner stellt sich die Frage.",
            expectedText: "Doch keiner stellt sich die Frage.",
            editKind: .delete, tokenClass: .filler, position: .sentenceInitial,
            expectedVerdict: .reject, expectedClass: "contentWordDeletion",
            note: "D-05 particle table: 'doch — 12 occurrences — sentence-" +
                "initial adversative \"however\".' Required D-05 negative fixture."
        ),
        Fixture(
            id: "fx-del-filler-de-interior-repetition",
            language: "de",
            baseline: "Das ist auch auch ganz gut.",
            candidate: "Das ist auch ganz gut.",
            expectedText: "Das ist auch ganz gut.",
            editKind: .delete, tokenClass: .filler, position: .interior,
            expectedVerdict: .accept, expectedClass: "repetitionDeletion",
            note: "D-05: 'verbatim repetitions / false starts (\"auch auch\" " +
                "-> \"auch\").'"
        ),
        Fixture(
            id: "fx-del-filler-de-terminal",
            language: "de",
            baseline: "Das ist gut, ähm.",
            candidate: "Das ist gut.",
            expectedText: "Das ist gut.",
            editKind: .delete, tokenClass: .filler, position: .terminal,
            expectedVerdict: .accept, expectedClass: "fillerDeletion",
            note: "INVENTED — trailing-position filler deletion, DE."
        ),
        Fixture(
            id: "fx-del-filler-en-si",
            language: "en",
            baseline: "Um, I think we should leave now.",
            candidate: "I think we should leave now.",
            expectedText: "I think we should leave now.",
            editKind: .delete, tokenClass: .filler, position: .sentenceInitial,
            expectedVerdict: .accept, expectedClass: "fillerDeletion",
            note: "INVENTED — sentence-initial filler deletion, EN, D-05 " +
                "acoustic-filler class."
        ),
        Fixture(
            id: "fx-del-filler-en-interior-umuh",
            language: "en",
            baseline: "This is, um, quite good.",
            candidate: "This is quite good.",
            expectedText: "This is quite good.",
            editKind: .delete, tokenClass: .filler, position: .interior,
            expectedVerdict: .accept, expectedClass: "fillerDeletion",
            note: "D-05: 'Deletable: acoustic fillers ... (uh, um).'"
        ),
        Fixture(
            id: "fx-del-filler-en-interior-actually",
            language: "en",
            baseline: "It's actually nine a.m already.",
            candidate: "It's nine a.m already.",
            expectedText: "It's actually nine a.m already.",
            editKind: .delete, tokenClass: .filler, position: .interior,
            expectedVerdict: .reject, expectedClass: "contentWordDeletion",
            note: "D-05 particle table: 'actually — 88 occurrences — \"it's " +
                "actually nine a.m\" — meaningful.' Required D-05 negative fixture."
        ),
        Fixture(
            id: "fx-del-filler-en-interior-like",
            language: "en",
            baseline: "I would like your advice on this.",
            candidate: "I would your advice on this.",
            expectedText: "I would like your advice on this.",
            editKind: .delete, tokenClass: .filler, position: .interior,
            expectedVerdict: .reject, expectedClass: "contentWordDeletion",
            note: "D-05 particle table: 'like — 52 occurrences — \"I would " +
                "like your advice\" — almost never filler.' Required D-05 " +
                "negative fixture."
        ),
        Fixture(
            id: "fx-del-filler-en-interior-right",
            language: "en",
            baseline: "Please put it back in the right order.",
            candidate: "Please put it back in the order.",
            expectedText: "Please put it back in the right order.",
            editKind: .delete, tokenClass: .filler, position: .interior,
            expectedVerdict: .reject, expectedClass: "contentWordDeletion",
            note: "D-05 particle table: 'right — 28 occurrences — \"the right " +
                "order\" — content.' Required D-05 negative fixture."
        ),
        Fixture(
            id: "fx-del-filler-en-interior-imean",
            language: "en",
            baseline: "By it I mean the second option.",
            candidate: "By it the second option.",
            expectedText: "By it I mean the second option.",
            editKind: .delete, tokenClass: .filler, position: .interior,
            expectedVerdict: .reject, expectedClass: "contentWordDeletion",
            note: "D-05 particle table: '\"I mean\" — 10 occurrences — \"By " +
                "it I mean the…\" — definitional.' Required D-05 negative fixture."
        ),
        Fixture(
            id: "fx-del-filler-en-terminal-well",
            language: "en",
            baseline: "It shows up in your logs as well.",
            candidate: "It shows up in your logs.",
            expectedText: "It shows up in your logs as well.",
            editKind: .delete, tokenClass: .filler, position: .terminal,
            expectedVerdict: .reject, expectedClass: "contentWordDeletion",
            note: "D-05 particle table: 'well — 50 occurrences — \"in your " +
                "logs as well\" — \"as well\" = also.' Required D-05 negative fixture."
        )
    ]

    // MARK: - insert x digit

    static let insertDigit: [Fixture] = [
        Fixture(
            id: "fx-ins-digit-de",
            language: "de",
            baseline: "Wir treffen uns morgen im Büro.",
            candidate: "Wir treffen uns morgen um 15 im Büro.",
            expectedText: "Wir treffen uns morgen im Büro.",
            editKind: .insert, tokenClass: .digit, position: .interior,
            expectedVerdict: .reject, expectedClass: "numberInsertion",
            note: "D-06: 'It may never insert ... a number' — required " +
                "inserted-number negative fixture."
        ),
        Fixture(
            id: "fx-ins-digit-en",
            language: "en",
            baseline: "We will meet tomorrow at the office.",
            candidate: "We will meet tomorrow at 3 the office.",
            expectedText: "We will meet tomorrow at the office.",
            editKind: .insert, tokenClass: .digit, position: .interior,
            expectedVerdict: .reject, expectedClass: "numberInsertion",
            note: "INVENTED — EN analogue of fx-ins-digit-de, D-06 inserted-" +
                "number prohibition."
        )
    ]

    // MARK: - insert x pronoun

    static let insertPronoun: [Fixture] = [
        Fixture(
            id: "fx-ins-pronoun-de",
            language: "de",
            baseline: "Ich habe angerufen und gewartet.",
            candidate: "Ich habe ihn angerufen und gewartet.",
            expectedText: "Ich habe angerufen und gewartet.",
            editKind: .insert, tokenClass: .pronoun, position: .interior,
            expectedVerdict: .reject, expectedClass: "unclassified",
            note: "INVENTED — pronouns are not in D-06's permitted insertion " +
                "list (articles/prepositions/auxiliaries/conjunctions only); " +
                "fail-closed default."
        ),
        Fixture(
            id: "fx-ins-pronoun-en",
            language: "en",
            baseline: "I called and waited.",
            candidate: "I called him and waited.",
            expectedText: "I called and waited.",
            editKind: .insert, tokenClass: .pronoun, position: .interior,
            expectedVerdict: .reject, expectedClass: "unclassified",
            note: "INVENTED — EN analogue of fx-ins-pronoun-de."
        )
    ]

    // MARK: - insert x contentWord

    static let insertContentWord: [Fixture] = [
        Fixture(
            id: "fx-ins-content-de-gefahrenwar",
            language: "de",
            baseline: "Ich bin zur Arbeit, als es passierte.",
            candidate: "Ich bin zur Arbeit gefahren war, als es passierte.",
            expectedText: "Ich bin zur Arbeit, als es passierte.",
            editKind: .insert, tokenClass: .contentWord, position: .interior,
            expectedVerdict: .reject, expectedClass: "contentWordInsertion",
            note: "D-06: '2026-07-12 car record ... inserting gefahren war ... " +
                "expected reject / contentWordInsertion.' Required D-06 " +
                "negative fixture."
        ),
        Fixture(
            id: "fx-ins-content-de-dieseteile",
            language: "de",
            baseline: "Ich musste bestellen, weil sie fehlten.",
            candidate: "Ich musste diese Teile bestellen, weil sie fehlten.",
            expectedText: "Ich musste bestellen, weil sie fehlten.",
            editKind: .insert, tokenClass: .contentWord, position: .interior,
            expectedVerdict: .reject, expectedClass: "contentWordInsertion",
            note: "D-06: '2026-07-12 car record ... inserting ... diese " +
                "Teile.' Required D-06 negative fixture."
        ),
        Fixture(
            id: "fx-ins-content-de-einanderes",
            language: "de",
            baseline: "Ich brauche Ersatzteil für den Wagen.",
            candidate: "Ich brauche ein anderes Ersatzteil für den Wagen.",
            expectedText: "Ich brauche Ersatzteil für den Wagen.",
            editKind: .insert, tokenClass: .contentWord, position: .interior,
            expectedVerdict: .reject, expectedClass: "contentWordInsertion",
            note: "D-06: '2026-07-12 car record ... inserting ... ein " +
                "anderes.' Required D-06 negative fixture."
        ),
        Fixture(
            id: "fx-ins-content-en",
            language: "en",
            baseline: "The meeting starts at 9.",
            candidate: "The meeting officially starts at 9.",
            expectedText: "The meeting starts at 9.",
            editKind: .insert, tokenClass: .contentWord, position: .interior,
            expectedVerdict: .reject, expectedClass: "contentWordInsertion",
            note: "INVENTED — EN analogue proving D-06's insertion ban " +
                "applies symmetrically."
        )
    ]

    // MARK: - insert x functionWord

    static let insertFunctionWord: [Fixture] = [
        Fixture(
            id: "fx-ins-func-de",
            language: "de",
            baseline: "Bezüglich Format habe ich eine Frage.",
            candidate: "Bezüglich des Formats habe ich eine Frage.",
            expectedText: "Bezüglich des Formats habe ich eine Frage.",
            editKind: .insert, tokenClass: .functionWord, position: .interior,
            expectedVerdict: .accept, expectedClass: "functionWordInsertion",
            note: "D-06: 'permits \"Bezüglich Format\" -> \"Bezüglich des " +
                "Formats\".' Co-occurs with fx-sub-content-de-format-formats " +
                "(same baseline/candidate pair, substitute dimension)."
        ),
        Fixture(
            id: "fx-ins-func-en",
            language: "en",
            baseline: "I want go to the store.",
            candidate: "I want to go to the store.",
            expectedText: "I want to go to the store.",
            editKind: .insert, tokenClass: .functionWord, position: .interior,
            expectedVerdict: .accept, expectedClass: "functionWordInsertion",
            note: "INVENTED — EN analogue of a missing-preposition repair, " +
                "symmetric with D-06's DE example."
        ),

        // MARK: - DUAL-ROLE insertion fixtures (Phase 44 Plan 14 class fix)
        //
        // See FunctionWords.swift's "THE DUAL-ROLE CRITERION" doc comment. A
        // token that has ANY productive lexical-content reading may not be
        // blanket-insertable, because this closed list has no POS awareness
        // and cannot tell the two roles apart. These three fixtures pin the
        // class — the corpus-evidenced leak, its priced cost, and the English
        // twin of the already-fixed `before` bug.

        Fixture(
            id: "fx-ins-func-de-sein-copula-invented",
            language: "de",
            baseline: "Das ist zu prüfen. Es muss wahrscheinlich nicht",
            candidate: "Das ist zu prüfen. Es muss wahrscheinlich nicht sein.",
            expectedText: "Das ist zu prüfen. Es muss wahrscheinlich nicht",
            editKind: .insert, tokenClass: .contentWord, position: .terminal,
            expectedVerdict: .reject, expectedClass: "contentWordInsertion",
            note: "THE LIVE LEAK, corpus 2026-07-09T17:56:47.797Z " +
                "(44-AUDIT-FRESH-CORRUPTION.md §4). Baseline's trailing " +
                "'muss wahrscheinlich nicht' is an ambiguous, orphaned " +
                "self-correction seam. Qwen3.5-4B completed the thought by " +
                "INVENTING the copula 'sein' ('...doesn't have to BE') — the " +
                "entire asserted predicate, since the complement is elided — " +
                "and the guard accepted it as a harmless functionWordInsertion " +
                "because 'sein' sat in germanInsertable among the auxiliaries. " +
                "'sein' is DUAL-ROLE (auxiliary AND full lexical copula; also " +
                "the possessive 'his'), so it must never be blanket-insertable. " +
                "This is the exact structural twin of the earlier 'before' bug."
        ),
        Fixture(
            id: "fx-ins-func-de-sein-auxiliary-pricedcost",
            language: "de",
            baseline: "Er muss schon gegangen.",
            candidate: "Er muss schon gegangen sein.",
            expectedText: "Er muss schon gegangen.",
            editKind: .insert, tokenClass: .contentWord, position: .terminal,
            expectedVerdict: .reject, expectedClass: "contentWordInsertion",
            note: "THE PRICED COST, stated as a fixture rather than buried in " +
                "a comment. Here 'sein' is a GENUINE perfect-tense auxiliary " +
                "('muss gegangen sein' = 'must have left') — a legitimate " +
                "repair D-06 would like to permit. It is REJECTED anyway, " +
                "because the closed list is string-only (no POS) and cannot " +
                "distinguish this from the copula insertion in " +
                "fx-ins-func-de-sein-copula-invented above. FAIL CLOSED: a " +
                "missed repair costs an under-correction; an invented copula " +
                "costs a corruption. That asymmetry is this phase's premise. " +
                "If a future plan adds real POS awareness (PosTagger, currently " +
                "dead code), THIS is the fixture whose verdict should flip — " +
                "not the one above."
        ),
        Fixture(
            id: "fx-ins-func-en-after-adverb",
            language: "en",
            baseline: "I have seen that GitHub project, though I haven't started.",
            candidate: "I have seen that GitHub project after, though I haven't started.",
            expectedText: "I have seen that GitHub project, though I haven't started.",
            editKind: .insert, tokenClass: .contentWord, position: .interior,
            expectedVerdict: .reject, expectedClass: "contentWordInsertion",
            note: "The English twin of the 'before' bug (44-FIDELITY-REPLAY.md " +
                "SC#3 adjudication, record 2026-07-04T05:52:54.137Z), which was " +
                "fixed as an INSTANCE — leaving 'after', its identical " +
                "preposition/adverb dual, in the list, explicitly 'pending " +
                "corpus evidence'. The Plan 14 CLASS audit is that evidence. " +
                "Here 'after' has no object (a comma follows), so it can only " +
                "be a bare temporal ADVERB — content D-06 forbids inserting."
        )
    ]

    // MARK: - insert x filler

    static let insertFiller: [Fixture] = [
        Fixture(
            id: "fx-ins-filler-de",
            language: "de",
            baseline: "Das ist gut.",
            candidate: "Das ist, äh, gut.",
            expectedText: "Das ist gut.",
            editKind: .insert, tokenClass: .filler, position: .interior,
            expectedVerdict: .reject, expectedClass: "unclassified",
            note: "INVENTED — fillers are not in D-06's permitted insertion " +
                "list; a hallucinated filler insertion must fail closed."
        ),
        Fixture(
            id: "fx-ins-filler-en",
            language: "en",
            baseline: "This is good.",
            candidate: "This is, um, good.",
            expectedText: "This is good.",
            editKind: .insert, tokenClass: .filler, position: .interior,
            expectedVerdict: .reject, expectedClass: "unclassified",
            note: "INVENTED — EN analogue of fx-ins-filler-de."
        )
    ]

    // MARK: - move x digit

    static let moveDigit: [Fixture] = [
        Fixture(
            id: "fx-mov-digit-de",
            language: "de",
            baseline: "Wir treffen morgen uns um 15 Uhr.",
            candidate: "Wir treffen uns um 15 Uhr morgen.",
            expectedText: "Wir treffen uns um 15 Uhr morgen.",
            editKind: .move, tokenClass: .digit, position: .interior,
            expectedVerdict: .accept, expectedClass: "wordOrderRepair",
            note: "INVENTED — 44-RESEARCH.md D-03 code example: '.move(N1): " +
                "ACCEPT (a move by construction pairs IDENTICAL tokens, so " +
                "value cannot change).' Post-merge gate fix (2026-07-12, " +
                "Rule 1 test-data fix): the ORIGINAL wording ('Wir treffen " +
                "uns um 15 Uhr morgen.' -> 'Morgen treffen wir uns um 15 " +
                "Uhr.') fronted 'morgen' to sentence-initial position. That " +
                "collided with FiniteVerbCues' DELIBERATELY over-inclusive " +
                "German suffix heuristic (germanFiniteSuffixes includes " +
                "'-en', and 'morgen' ends in '-en') — see FiniteVerbCues.swift's " +
                "own doc comment: over-inclusion is INTENTIONAL and 'this " +
                "file deliberately does NOT attempt to disambiguate it.' The " +
                "mood-lock therefore correctly (per its own documented, " +
                "priced design) rejected this move as a suspected verb-" +
                "fronting, which is orthogonal to what this fixture's own " +
                "'position: .interior' metadata claims to test — the " +
                "ORIGINAL wording never actually exercised an interior move " +
                "at all, only an accidental sentence-initial one. Reworded " +
                "so 'Wir' stays sentence-initial in BOTH baseline and " +
                "candidate (mood-lock cannot fire — baselineFirst == " +
                "rebuiltFirst == 'wir' always) and only 'morgen' relocates " +
                "within the sentence interior, alongside an untouched 'um " +
                "15 Uhr' digit phrase (kept verbatim) proving the move " +
                "mechanism doesn't disturb digit value. Do NOT 'fix' this " +
                "by loosening FiniteVerbCues — that file's over-inclusion is " +
                "load-bearing (blocks the 'You can push'->'Can you push' " +
                "corruption) and explicitly forbids disambiguation heuristics."
        ),
        Fixture(
            id: "fx-mov-digit-en",
            language: "en",
            baseline: "We meet at 3pm tomorrow.",
            candidate: "Tomorrow we meet at 3pm.",
            expectedText: "Tomorrow we meet at 3pm.",
            editKind: .move, tokenClass: .digit, position: .interior,
            expectedVerdict: .accept, expectedClass: "wordOrderRepair",
            note: "INVENTED — EN analogue of fx-mov-digit-de."
        )
    ]

    // MARK: - move x pronoun

    static let movePronoun: [Fixture] = [
        Fixture(
            id: "fx-mov-pronoun-de",
            language: "de",
            baseline: "Morgen kommt er vorbei.",
            candidate: "Er kommt morgen vorbei.",
            expectedText: "Er kommt morgen vorbei.",
            editKind: .move, tokenClass: .pronoun, position: .interior,
            expectedVerdict: .accept, expectedClass: "wordOrderRepair",
            note: "INVENTED — pure position move of a pronoun with NO person " +
                "change; D-04's pronoun-lock only blocks deletion/person-" +
                "change, not position."
        ),
        Fixture(
            id: "fx-mov-pronoun-en",
            language: "en",
            baseline: "Tomorrow he arrives at noon.",
            candidate: "He arrives tomorrow at noon.",
            expectedText: "He arrives tomorrow at noon.",
            editKind: .move, tokenClass: .pronoun, position: .interior,
            expectedVerdict: .accept, expectedClass: "wordOrderRepair",
            note: "INVENTED — EN analogue of fx-mov-pronoun-de."
        )
    ]

    // MARK: - move x contentWord

    static let moveContentWord: [Fixture] = [
        Fixture(
            id: "fx-mov-content-de-moodlock-falsepos",
            language: "de",
            baseline: "Also ich möchte das gerne besprechen.",
            candidate: "Also möchte ich das gerne besprechen.",
            expectedText: "Also möchte ich das gerne besprechen.",
            editKind: .move, tokenClass: .contentWord, position: .interior,
            expectedVerdict: .accept, expectedClass: "wordOrderRepair",
            note: "D-04: '\"Also ich möchte…\" -> \"Also möchte ich…\" ... the " +
                "mood-lock must NOT fire here (the sentence still starts with " +
                "\"Also\") — the mood-lock's false-positive guard.'"
        ),
        Fixture(
            id: "fx-mov-content-de-fronting",
            language: "de",
            baseline: "Ich habe das Auto gestern gesehen.",
            candidate: "Das Auto habe ich gestern gesehen.",
            expectedText: "Das Auto habe ich gestern gesehen.",
            editKind: .move, tokenClass: .contentWord, position: .sentenceInitial,
            expectedVerdict: .accept, expectedClass: "wordOrderRepair",
            note: "INVENTED — German V2 topicalization (fronting a content-" +
                "word object); still legal word order, not a mood-lock " +
                "violation since no finite verb/modal is fronted."
        ),
        Fixture(
            id: "fx-mov-content-en",
            language: "en",
            baseline: "I think, honestly, we should go.",
            candidate: "Honestly, I think we should go.",
            expectedText: "Honestly, I think we should go.",
            editKind: .move, tokenClass: .contentWord, position: .interior,
            expectedVerdict: .accept, expectedClass: "wordOrderRepair",
            note: "INVENTED — EN analogue of a content-word (adverb) reorder " +
                "repair."
        )
    ]

    // MARK: - move x functionWord (D-04's core evidence: mood-lock + word-order repair)

    static let moveFunctionWord: [Fixture] = [
        Fixture(
            id: "fx-mov-func-en-moodlock",
            language: "en",
            baseline: "You can push the commits and then I'm wondering where " +
                "do we stand.",
            candidate: "Can you push the commits and then I'm wondering " +
                "where we stand.",
            expectedText: "You can push the commits and then I'm wondering " +
                "where do we stand.",
            editKind: .move, tokenClass: .functionWord, position: .sentenceInitial,
            expectedVerdict: .reject, expectedClass: "moodLockSentenceInitialVerb",
            note: "Corpus 2026-07-11T04:26:02.697Z — the mood-lock signature; " +
                "NEITHER version adds '?' — a terminal-punctuation check would " +
                "NOT catch this."
        ),
        Fixture(
            id: "fx-mov-func-de-wordorder",
            language: "de",
            baseline: "Weil die Fragen werden ja gleich sofort ausgewertet.",
            candidate: "Weil die Fragen ja gleich sofort ausgewertet werden.",
            expectedText: "Weil die Fragen ja gleich sofort ausgewertet werden.",
            editKind: .move, tokenClass: .functionWord, position: .terminal,
            expectedVerdict: .accept, expectedClass: "wordOrderRepair",
            note: "D-04: broken V2-in-a-weil-clause -> correct verb-final; " +
                "currently gate=rejected by the pre-Phase-44 gate — this " +
                "fixture is the proof the inversion is fixed."
        ),
        Fixture(
            id: "fx-mov-func-en-interior",
            language: "en",
            baseline: "Can we finish this today.",
            candidate: "We can finish this today.",
            expectedText: "We can finish this today.",
            editKind: .move, tokenClass: .functionWord, position: .interior,
            expectedVerdict: .accept, expectedClass: "wordOrderRepair",
            note: "INVENTED — un-fronting a mistakenly-fronted modal back to " +
                "normal statement order; the reverse repair direction of " +
                "fx-mov-func-en-moodlock."
        ),
        Fixture(
            id: "fx-mov-func-de-moodlock",
            language: "de",
            baseline: "Er kommt morgen.",
            candidate: "Kommt er morgen?",
            expectedText: "Er kommt morgen.",
            editKind: .move, tokenClass: .functionWord, position: .sentenceInitial,
            expectedVerdict: .reject, expectedClass: "moodLockSentenceInitialVerb",
            note: "INVENTED — DE analogue of the mood-lock: statement -> " +
                "question via verb-fronting, mirroring the EN 'You can push' " +
                "-> 'Can you push' corruption."
        )
    ]

    // MARK: - move x filler

    static let moveFiller: [Fixture] = [
        Fixture(
            id: "fx-mov-filler-de",
            language: "de",
            baseline: "Das ist, glaube ich, äh, gut.",
            candidate: "Das ist, äh, glaube ich, gut.",
            expectedText: "Das ist, glaube ich, äh, gut.",
            editKind: .move, tokenClass: .filler, position: .interior,
            expectedVerdict: .reject, expectedClass: "unclassified",
            note: "INVENTED — a filler should be deleted (D-05), not " +
                "relocated; moving a filler token is not a defined permitted " +
                "class, fail-closed default."
        ),
        Fixture(
            id: "fx-mov-filler-en",
            language: "en",
            baseline: "This is, I think, um, good.",
            candidate: "This is, um, I think, good.",
            expectedText: "This is, I think, um, good.",
            editKind: .move, tokenClass: .filler, position: .interior,
            expectedVerdict: .reject, expectedClass: "unclassified",
            note: "INVENTED — EN analogue of fx-mov-filler-de."
        )
    ]

    // MARK: - The full corpus

    static let all: [Fixture] =
        substituteDigit + substitutePronoun + substituteContentWordDe +
        substituteContentWordEn + substitutePunctuationBoundary +
        substituteFunctionWord + substituteFiller +
        deleteDigit + deletePronoun + deleteContentWord + deleteFunctionWord +
        deleteFiller +
        insertDigit + insertPronoun + insertContentWord + insertFunctionWord +
        insertFiller +
        moveDigit + movePronoun + moveContentWord + moveFunctionWord +
        moveFiller +
        [d01BundledFixture, goodshinePauseDotsFixture,
         goodshineFullRecordSpuriousMoveFixture, longDistanceGermanWordOrderRepairFixture,
         adjacentDeletionSubstituteCouplingFixture, crossClauseMoveMispairingOpenDefectFixture]

    // MARK: - Pruned cells

    /// Every uncovered cell of the 120-cell cross product
    /// (editKind x tokenClass x position x language), with a reason.
    /// A cell may only be pruned for one of two reasons:
    ///   - COLLAPSES: behaviourally identical to an already-covered cell.
    ///   - IMPOSSIBLE: the shape cannot be produced by the diff, or (for
    ///     `insert`, which has no baseline `from` token so position is a
    ///     candidate-stream-only property) the position dimension cannot be
    ///     distinguished from another position for that (class, language).
    static let prunedCells: [(cell: String, reason: String)] = [
        // substitute x digit — value/form classification is position-invariant
        ("substitute|digit|sentenceInitial|de", "COLLAPSES into substitute|digit|interior|de — digit value-identity classification is position-invariant."),
        ("substitute|digit|terminal|de", "COLLAPSES into substitute|digit|interior|de — digit value-identity classification is position-invariant."),
        ("substitute|digit|sentenceInitial|en", "COLLAPSES into substitute|digit|interior|en — digit value-identity classification is position-invariant."),
        ("substitute|digit|terminal|en", "COLLAPSES into substitute|digit|interior|en — digit value-identity classification is position-invariant."),
        // substitute x pronoun — person-change classification is position-invariant
        ("substitute|pronoun|interior|de", "COLLAPSES into substitute|pronoun|sentenceInitial|de — pronoun person-change classification is position-invariant."),
        ("substitute|pronoun|terminal|de", "COLLAPSES into substitute|pronoun|sentenceInitial|de — pronoun person-change classification is position-invariant."),
        ("substitute|pronoun|sentenceInitial|en", "COLLAPSES into substitute|pronoun|interior|en — pronoun person-change classification is position-invariant."),
        ("substitute|pronoun|terminal|en", "COLLAPSES into substitute|pronoun|interior|en — pronoun person-change classification is position-invariant."),
        // substitute x contentWord — lemma-lock classification is position-invariant
        ("substitute|contentWord|sentenceInitial|de", "COLLAPSES into substitute|contentWord|interior|de — D-02 lemma-lock classification is position-invariant."),
        ("substitute|contentWord|terminal|de", "COLLAPSES into substitute|contentWord|interior|de — D-02 lemma-lock classification is position-invariant."),
        ("substitute|contentWord|sentenceInitial|en", "COLLAPSES into substitute|contentWord|interior|en — D-02 lemma-lock classification is position-invariant."),
        ("substitute|contentWord|terminal|en", "COLLAPSES into substitute|contentWord|interior|en — D-02 lemma-lock classification is position-invariant."),
        // substitute x functionWord — position-invariant once lemma-locked
        ("substitute|functionWord|interior|de", "COLLAPSES into substitute|functionWord|sentenceInitial|de — functionWordSubstitution classification is position-invariant."),
        ("substitute|functionWord|terminal|de", "COLLAPSES into substitute|functionWord|sentenceInitial|de — functionWordSubstitution classification is position-invariant."),
        ("substitute|functionWord|interior|en", "COLLAPSES into substitute|functionWord|sentenceInitial|en — functionWordSubstitution classification is position-invariant."),
        ("substitute|functionWord|terminal|en", "COLLAPSES into substitute|functionWord|sentenceInitial|en — functionWordSubstitution classification is position-invariant."),
        // substitute x filler — always fail-closed regardless of position
        ("substitute|filler|sentenceInitial|de", "COLLAPSES into substitute|filler|interior|de — filler substitution is fail-closed regardless of position."),
        ("substitute|filler|terminal|de", "COLLAPSES into substitute|filler|interior|de — filler substitution is fail-closed regardless of position."),
        ("substitute|filler|sentenceInitial|en", "COLLAPSES into substitute|filler|interior|en — filler substitution is fail-closed regardless of position."),
        ("substitute|filler|terminal|en", "COLLAPSES into substitute|filler|interior|en — filler substitution is fail-closed regardless of position."),

        // delete x digit — always rejected regardless of position
        ("delete|digit|sentenceInitial|de", "COLLAPSES into delete|digit|interior|de — digit deletion is rejected regardless of position."),
        ("delete|digit|terminal|de", "COLLAPSES into delete|digit|interior|de — digit deletion is rejected regardless of position."),
        ("delete|digit|sentenceInitial|en", "COLLAPSES into delete|digit|interior|en — digit deletion is rejected regardless of position."),
        ("delete|digit|terminal|en", "COLLAPSES into delete|digit|interior|en — digit deletion is rejected regardless of position."),
        // delete x pronoun — always rejected regardless of position
        ("delete|pronoun|sentenceInitial|de", "COLLAPSES into delete|pronoun|interior|de — pronoun deletion is rejected regardless of position."),
        ("delete|pronoun|terminal|de", "COLLAPSES into delete|pronoun|interior|de — pronoun deletion is rejected regardless of position."),
        ("delete|pronoun|interior|en", "COLLAPSES into delete|pronoun|sentenceInitial|en — pronoun deletion is rejected regardless of position."),
        ("delete|pronoun|terminal|en", "COLLAPSES into delete|pronoun|sentenceInitial|en — pronoun deletion is rejected regardless of position."),
        // delete x contentWord — always rejected regardless of position
        ("delete|contentWord|sentenceInitial|de", "COLLAPSES into delete|contentWord|interior|de — content-word deletion is rejected regardless of position."),
        ("delete|contentWord|terminal|de", "COLLAPSES into delete|contentWord|interior|de — content-word deletion is rejected regardless of position."),
        ("delete|contentWord|sentenceInitial|en", "COLLAPSES into delete|contentWord|interior|en — content-word deletion is rejected regardless of position."),
        ("delete|contentWord|terminal|en", "COLLAPSES into delete|contentWord|interior|en — content-word deletion is rejected regardless of position."),
        // delete x functionWord — always rejected regardless of position
        ("delete|functionWord|sentenceInitial|de", "COLLAPSES into delete|functionWord|interior|de — function-word deletion is rejected regardless of position."),
        ("delete|functionWord|terminal|de", "COLLAPSES into delete|functionWord|interior|de — function-word deletion is rejected regardless of position."),
        ("delete|functionWord|sentenceInitial|en", "COLLAPSES into delete|functionWord|interior|en — function-word deletion is rejected regardless of position."),
        ("delete|functionWord|terminal|en", "COLLAPSES into delete|functionWord|interior|en — function-word deletion is rejected regardless of position."),
        // delete x filler — no prunes, all 6 covered by the D-05 evidence table

        // insert x * — position is a candidate-stream-only property; one
        // representative position per (class, language), rest indistinguishable.
        ("insert|digit|sentenceInitial|de", "IMPOSSIBLE-TO-DISTINGUISH — insert has no baseline `from` token, so position is a candidate-stream property; interior chosen as representative for (digit, de)."),
        ("insert|digit|terminal|de", "IMPOSSIBLE-TO-DISTINGUISH — see insert|digit|sentenceInitial|de."),
        ("insert|digit|sentenceInitial|en", "IMPOSSIBLE-TO-DISTINGUISH — interior chosen as representative for (digit, en)."),
        ("insert|digit|terminal|en", "IMPOSSIBLE-TO-DISTINGUISH — see insert|digit|sentenceInitial|en."),
        ("insert|pronoun|sentenceInitial|de", "IMPOSSIBLE-TO-DISTINGUISH — interior chosen as representative for (pronoun, de)."),
        ("insert|pronoun|terminal|de", "IMPOSSIBLE-TO-DISTINGUISH — see insert|pronoun|sentenceInitial|de."),
        ("insert|pronoun|sentenceInitial|en", "IMPOSSIBLE-TO-DISTINGUISH — interior chosen as representative for (pronoun, en)."),
        ("insert|pronoun|terminal|en", "IMPOSSIBLE-TO-DISTINGUISH — see insert|pronoun|sentenceInitial|en."),
        ("insert|contentWord|sentenceInitial|de", "IMPOSSIBLE-TO-DISTINGUISH — interior chosen as representative for (contentWord, de)."),
        // insert|contentWord|terminal|de was PRUNED here as
        // "IMPOSSIBLE-TO-DISTINGUISH". Plan 14's fresh-corruption audit
        // FALSIFIED that claim with real corpus evidence: TERMINAL position is
        // exactly what makes a dual-role insertion dangerous — a copula/
        // particle/adverb inserted with no complement after it ("...muss
        // wahrscheinlich nicht **sein**.") is the content-asserting reading,
        // while the same token before an object is merely functional. The cell
        // is now genuinely covered by fx-ins-func-de-sein-copula-invented and
        // fx-ins-func-de-sein-auxiliary-pricedcost, so the prune is removed
        // rather than the fixtures being retagged to fit a stale claim.
        ("insert|contentWord|sentenceInitial|en", "IMPOSSIBLE-TO-DISTINGUISH — interior chosen as representative for (contentWord, en)."),
        ("insert|contentWord|terminal|en", "IMPOSSIBLE-TO-DISTINGUISH — see insert|contentWord|sentenceInitial|en."),
        ("insert|functionWord|sentenceInitial|de", "IMPOSSIBLE-TO-DISTINGUISH — interior chosen as representative for (functionWord, de)."),
        ("insert|functionWord|terminal|de", "IMPOSSIBLE-TO-DISTINGUISH — see insert|functionWord|sentenceInitial|de."),
        ("insert|functionWord|sentenceInitial|en", "IMPOSSIBLE-TO-DISTINGUISH — interior chosen as representative for (functionWord, en)."),
        ("insert|functionWord|terminal|en", "IMPOSSIBLE-TO-DISTINGUISH — see insert|functionWord|sentenceInitial|en."),
        ("insert|filler|sentenceInitial|de", "IMPOSSIBLE-TO-DISTINGUISH — interior chosen as representative for (filler, de)."),
        ("insert|filler|terminal|de", "IMPOSSIBLE-TO-DISTINGUISH — see insert|filler|sentenceInitial|de."),
        ("insert|filler|sentenceInitial|en", "IMPOSSIBLE-TO-DISTINGUISH — interior chosen as representative for (filler, en)."),
        ("insert|filler|terminal|en", "IMPOSSIBLE-TO-DISTINGUISH — see insert|filler|sentenceInitial|en."),

        // move x digit — accept-by-construction, position-invariant
        ("move|digit|sentenceInitial|de", "COLLAPSES into move|digit|interior|de — a digit move is accept-by-construction (identical tokens) regardless of position."),
        ("move|digit|terminal|de", "COLLAPSES into move|digit|interior|de — see above."),
        ("move|digit|sentenceInitial|en", "COLLAPSES into move|digit|interior|en — see above."),
        ("move|digit|terminal|en", "COLLAPSES into move|digit|interior|en — see above."),
        // move x pronoun — position-invariant (identity/deletion is what pronoun-lock checks, not position)
        ("move|pronoun|sentenceInitial|de", "COLLAPSES into move|pronoun|interior|de — pronoun-lock cares about identity/deletion, not the destination position of a move."),
        ("move|pronoun|terminal|de", "COLLAPSES into move|pronoun|interior|de — see above."),
        ("move|pronoun|sentenceInitial|en", "COLLAPSES into move|pronoun|interior|en — see above."),
        ("move|pronoun|terminal|en", "COLLAPSES into move|pronoun|interior|en — see above."),
        // move x contentWord
        ("move|contentWord|terminal|de", "COLLAPSES into move|contentWord|interior|de — a content-word move landing at the sentence end behaves identically to one landing mid-clause."),
        ("move|contentWord|sentenceInitial|en", "COLLAPSES into move|contentWord|interior|en — EN topicalization is rarer than DE V2 fronting and is scored the same as the general move-permission case already covered."),
        ("move|contentWord|terminal|en", "COLLAPSES into move|contentWord|interior|en — see above."),
        // move x functionWord — the plan's own worked example: terminal collapses interior for DE, interior collapses terminal for EN
        ("move|functionWord|interior|de", "COLLAPSES into move|functionWord|terminal|de — a functionWord move mid-clause that doesn't reach sentence-final position is scored the same as the German verb-position repair already covered."),
        ("move|functionWord|terminal|en", "COLLAPSES into move|functionWord|interior|en — English lacks the German verb-final clause structure that motivates a distinct terminal-position functionWord move; the shape collapses into the interior cell already covered."),
        // move x filler — plan's own worked COLLAPSES example
        ("move|filler|sentenceInitial|de", "COLLAPSES into move|filler|interior|de — per plan Task 1: 'a filler's position does not change how a move is classified.'"),
        ("move|filler|terminal|de", "COLLAPSES into move|filler|interior|de — see above."),
        ("move|filler|sentenceInitial|en", "COLLAPSES into move|filler|interior|en — see above."),
        ("move|filler|terminal|en", "COLLAPSES into move|filler|interior|en — see above.")
    ]
}
