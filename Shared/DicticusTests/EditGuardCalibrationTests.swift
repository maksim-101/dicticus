import XCTest
@testable import Dicticus

/// Quick task 260723-sx1 (EditGuard rejection-class calibration): the
/// deterministic `SpellLexicon` double + the exact-string RED/GREEN
/// fixtures for the three R3 criteria (A: non-word repair exemption, B:
/// adjacent-duplicate disfluency collapse, C: prosodic-punctuation
/// allowlist).
///
/// RED fixtures (Task 1) assert the criteria's FINAL, post-fix expected
/// behavior and FAIL until Task 2 lands (they document what SHOULD happen,
/// not what currently does). GREEN fixtures pin CURRENT rejection behavior
/// so Task 2 cannot loosen it unnoticed (R6 adversarial negatives) or
/// pin a designed residual (a case this calibration deliberately does NOT
/// fix).
///
/// Every fixture is built from the REAL replayed 07-19..23 evidence pair
/// (verbatim or a minimal faithful reduction, noted per fixture) — see
/// `replay-HEAD-evidence.txt` in this quick task's directory for the full
/// R7 reproduction record each RED fixture is grounded in.
struct TestSpellLexicon: SpellLexicon {
    private let known: Set<String>
    private let allKnownFlag: Bool

    init(known: Set<String>) {
        self.known = Set(known.map { $0.lowercased() })
        self.allKnownFlag = false
    }

    private init(allKnown: Bool) {
        self.known = []
        self.allKnownFlag = allKnown
    }

    /// Behavior-neutral double for every PRE-EXISTING EditGuard suite
    /// (`EditGuardTests`, `EditGuardGrammarRegressionTests`,
    /// `EditGuardDanglingPunctuationTests`, `EditGuardMergeAtomicityTests`):
    /// every word is "known", so criterion A's `known(a) == false` gate can
    /// never be satisfied for those suites' fixtures. Those suites predate
    /// criterion A and were never constructed to exercise its boundary —
    /// this guarantees zero interaction and zero dependency on the
    /// machine's system dictionary for any of them.
    static let allKnown = TestSpellLexicon(allKnown: true)

    func isKnownWord(_ text: String, language: String) -> Bool {
        if allKnownFlag { return true }
        return known.contains(text.lowercased())
    }
}

@MainActor
final class EditGuardCalibrationTests: XCTestCase {

    private func guardResult(
        _ baseline: String, _ candidate: String, lang: String = "en",
        known: Set<String>, dictProtected: Set<String> = []
    ) -> EditGuard.GuardResult {
        EditGuard.apply(
            rulesCleaned: baseline, llmOutput: candidate, language: lang,
            dictProtected: dictProtected, lexicon: TestSpellLexicon(known: known)
        )
    }

    // MARK: - A. Non-word repair — RED (currently rejected, must ACCEPT post-fix)

    /// Evidence: cleanup-2026-07-21.jsonl:6. R3 spot value: nlev(clawd,
    /// claude) = 0.333 (orthographic arm, <= 0.35).
    func testA_clawdToClaude_acceptsNonWordRepair() {
        let r = guardResult(
            "I use Clawd Max today.", "I use Claude Max today.",
            known: ["claude", "max", "today", "i", "use"]
        )
        XCTAssertEqual(r.text, "I use Claude Max today.")
        let edit = r.edits.first { $0.from == "Clawd" }
        XCTAssertEqual(edit?.accepted, true)
        XCTAssertEqual(edit?.acceptClass, EditGuard.AcceptClass.nonWordRepair.rawValue)
    }

    /// Evidence: cleanup-2026-07-19.jsonl:83. R3 spot value: nlev(claudco,
    /// claude) = 0.286 (orthographic arm).
    func testA_claudcoToClaude_acceptsNonWordRepair() {
        let r = guardResult(
            "Check claudco today.", "Check Claude today.",
            known: ["claude", "today", "check"]
        )
        XCTAssertEqual(r.text, "Check Claude today.")
        let edit = r.edits.first { $0.from == "claudco" }
        XCTAssertEqual(edit?.accepted, true)
        XCTAssertEqual(edit?.acceptClass, EditGuard.AcceptClass.nonWordRepair.rawValue)
    }

    /// Evidence: cleanup-2026-07-23.jsonl:7. R3 spot value: nlev(getragt
    /// [folded], getragen) = 0.25 (folded orthographic arm).
    func testA_getraegtToGetragen_de_acceptsNonWordRepair() {
        let r = guardResult(
            "Das würde geträgt werden.", "Das würde getragen werden.",
            lang: "de", known: ["das", "würde", "werden", "getragen"]
        )
        XCTAssertEqual(r.text, "Das würde getragen werden.")
        let edit = r.edits.first { $0.from == "geträgt" }
        XCTAssertEqual(edit?.accepted, true)
        XCTAssertEqual(edit?.acceptClass, EditGuard.AcceptClass.nonWordRepair.rawValue)
    }

    /// Evidence: cleanup-2026-07-21.jsonl:18. R3 spot value: nlev
    /// (einganglicher [folded], eingangiger [folded]) = 0.23. Step-6.5
    /// placement (BEFORE step 7's derivational lock) is what makes this
    /// fire — a naive placement after step 7 would die on the -lich/-ig
    /// derivational-suffix check first.
    func testA_eingaenglicherToEingaengiger_de_acceptsNonWordRepair() {
        let r = guardResult(
            "Der Titel sollte eingänglicher sein.", "Der Titel sollte eingängiger sein.",
            lang: "de", known: ["der", "titel", "sollte", "sein", "eingängiger"]
        )
        XCTAssertEqual(r.text, "Der Titel sollte eingängiger sein.")
        let edit = r.edits.first { $0.from == "eingänglicher" }
        XCTAssertEqual(edit?.accepted, true)
        XCTAssertEqual(edit?.acceptClass, EditGuard.AcceptClass.nonWordRepair.rawValue)
    }

    // MARK: - B. Disfluency collapse — RED (currently rejected, must ACCEPT post-fix)

    /// Evidence: cleanup-2026-07-23.jsonl:1 (minimal reduction of the
    /// "Garmin fitness band" record's tail clause). Baseline blocks
    /// "to furtherly" / "to further": position 0 to~to (equal), position 1
    /// furtherly~further (shared prefix "furth" >= 4 chars, raw Levenshtein
    /// distance 2).
    func testB_furtherlyRestartCollapse_acceptsDisfluencyCollapse() {
        let r = guardResult(
            "your data to furtherly to further improve their products.",
            "your data to further improve their products.",
            known: []
        )
        XCTAssertEqual(r.text, "your data to further improve their products.")
        let furtherlyEdit = r.edits.first { $0.from == "furtherly" }
        XCTAssertEqual(furtherlyEdit?.accepted, true)
        XCTAssertEqual(furtherlyEdit?.acceptClass, EditGuard.AcceptClass.disfluencyCollapse.rawValue)
    }

    /// Evidence: cleanup-2026-07-23.jsonl:1 (same record, "you they will
    /// analyze" clause). DEVIATION FROM THE OBJECTIVE'S PREDICTED SHAPE
    /// (documented in replay-HEAD-evidence.txt case 6b): `EditDiff` pairs
    /// this as a `.substitute` (from=you, to=",") rather than a clean
    /// `.delete` — `classifySubstitute`, not `classifyDelete`, must consult
    /// the disfluency-accepted set for the pronoun-pair arm (c) to catch
    /// this exact evidence case.
    func testB_youTheyStutter_acceptsDisfluencyCollapse() {
        let r = guardResult(
            "But if you opt for this you they will analyze and process your data.",
            "But if you opt for this, they will analyze and process your data.",
            known: []
        )
        XCTAssertEqual(r.text, "But if you opt for this, they will analyze and process your data.")
        let youEdit = r.edits.first { $0.from == "you" && $0.kind == "substitute" }
        XCTAssertEqual(youEdit?.accepted, true)
        XCTAssertEqual(youEdit?.acceptClass, EditGuard.AcceptClass.disfluencyCollapse.rawValue)
    }

    // MARK: - C. Symbol-invention gap — RED (currently accepted, must REJECT post-fix)

    /// Evidence-shape (NOT the literal 07-20:5 record — that record's
    /// baseline already contains "C++" before EditGuard runs; see
    /// replay-HEAD-evidence.txt case 8 for the full root-cause). This
    /// synthetic pair exercises the EXACT mechanism the objective predicted
    /// for 07-20:5 (verified via `harness debugEG` before Task 2: two
    /// `.insert` edits for "+","+", both currently accepted
    /// `punctuationOrCasing` via classifyInsert's blanket punctuation rule).
    func testC_plusPlusInsertion_rejectsAsContentWordInsertion() {
        let r = guardResult(
            "How do I get from A to C", "How do I get from A to C++",
            known: []
        )
        XCTAssertEqual(r.text, "How do I get from A to C")
        for e in r.edits where e.kind == "insert" && e.to == "+" {
            XCTAssertEqual(e.accepted, false)
            XCTAssertEqual(e.rejectClass, EditGuard.RejectionClass.contentWordInsertion.rawValue)
        }
    }

    /// Same closure, different shape: `EditDiff` pairs a baseline symbol
    /// ("#") against a candidate symbol ("+") as a `.substitute` (verified
    /// via `harness debugEG` before Task 2) — classifySubstitute step 2's
    /// allowlist restriction must ALSO close this path, not just
    /// classifyInsert's.
    func testC_symbolSubstitute_rejectsAsContentWordIdentityChange() {
        let r = guardResult(
            "Use C# today.", "Use C+ today.",
            known: []
        )
        XCTAssertEqual(r.text, "Use C# today.")
        let edit = r.edits.first { $0.from == "#" }
        XCTAssertEqual(edit?.accepted, false)
        XCTAssertEqual(edit?.rejectClass, EditGuard.RejectionClass.contentWordIdentityChange.rawValue)
    }

    // MARK: - R6 adversarial negatives (GREEN — pin CURRENT rejection; Task 2 must not loosen)

    /// R3 spot value: nlev(gisela, gazelle) = 0.57, rejected even if
    /// phonetic keys happen to collide — the orthographic-far / phonetic-
    /// backstop boundary.
    func testR6_giselaToGazelle_staysRejected() {
        let r = guardResult(
            "I met Gisela yesterday.", "I met Gazelle yesterday.",
            known: ["gazelle", "yesterday", "i", "met"]
        )
        XCTAssertEqual(r.text, "I met Gisela yesterday.")
        let edit = r.edits.first { $0.from == "Gisela" }
        XCTAssertEqual(edit?.accepted, false)
    }

    /// Orthographically-far nonsense old vs. a totally unrelated real word
    /// — never close enough to qualify as a repair.
    func testR6_vaspirdToHazard_staysRejected() {
        let r = guardResult(
            "The VASPIRD report is due.", "The hazard report is due.",
            known: ["hazard", "report", "due", "the"]
        )
        XCTAssertEqual(r.text, "The VASPIRD report is due.")
        let edit = r.edits.first { $0.from == "VASPIRD" }
        XCTAssertEqual(edit?.accepted, false)
    }

    /// A dictionary term is NEVER "repairable" — dictProtect (step 5) fires
    /// before criterion A's step 6.5 is ever consulted, unaffected by Task 2.
    func testR6_dictProtectedTerm_staysRejected() {
        let r = guardResult(
            "I opened Dicticus today.", "I opened dictation today.",
            known: ["dictation", "today", "i", "opened"],
            dictProtected: ["Dicticus"]
        )
        XCTAssertEqual(r.text, "I opened Dicticus today.")
        let edit = r.edits.first { $0.from == "Dicticus" }
        XCTAssertEqual(edit?.accepted, false)
    }

    /// Criterion A requires `new` to be KNOWN — an unknown-to-unknown
    /// substitute never qualifies, regardless of similarity.
    func testR6_clawdToKlawd_unknownNew_staysRejected() {
        let r = guardResult(
            "I use Clawd today.", "I use Klawd today.",
            known: ["today", "i", "use"]
        )
        XCTAssertEqual(r.text, "I use Clawd today.")
        let edit = r.edits.first { $0.from == "Clawd" }
        XCTAssertEqual(edit?.accepted, false)
    }

    /// A single deleted pronoun with no ADJACENT second block stays locked
    /// — criterion B never fires on a lone deletion.
    func testR6_lonePronounDelete_staysPronounDeleted() {
        let r = guardResult(
            "I think they will go.", "Think they will go.",
            known: []
        )
        let edit = r.edits.first { $0.from == "I" }
        XCTAssertEqual(edit?.accepted, false)
        XCTAssertEqual(edit?.rejectClass, EditGuard.RejectionClass.pronounDeleted.rawValue)
    }

    /// Two deleted tokens ("You", "and") with no adjacent aligned second
    /// block — criterion B's pronoun-pair arm requires a SURVIVING adjacent
    /// pronoun forming a block-pair, not merely "some pronoun somewhere
    /// later in the sentence".
    func testR6_youAndTheyNotAdjacentBlocks_staysRejected() {
        let r = guardResult(
            "You and they will decide.", "They will decide.",
            known: []
        )
        let youEdit = r.edits.first { $0.from == "You" }
        XCTAssertEqual(youEdit?.accepted, false)
    }

    /// A real content word with no near-duplicate anywhere adjacent — plain
    /// content deletion, never a disfluency collapse.
    func testR6_redCarDeletion_staysContentWordDeletion() {
        let r = guardResult(
            "I saw a red car yesterday.", "I saw a car yesterday.",
            known: []
        )
        let edit = r.edits.first { $0.from == "red" }
        XCTAssertEqual(edit?.accepted, false)
        XCTAssertEqual(edit?.rejectClass, EditGuard.RejectionClass.contentWordDeletion.rawValue)
    }

    /// Two adjacent baseline blocks exist ("to really" / "to improve") but
    /// FAIL to align position-wise at index 1 (really/improve share no
    /// prefix, far Levenshtein distance) — the WHOLE block match fails, not
    /// a partial accept.
    func testR6_toReallyToImprove_blocksDoNotAlign_staysRejected() {
        let r = guardResult(
            "I want to really to improve this.", "I want to improve this.",
            known: []
        )
        let edit = r.edits.first { $0.from == "really" }
        XCTAssertEqual(edit?.accepted, false)
        XCTAssertEqual(edit?.rejectClass, EditGuard.RejectionClass.contentWordDeletion.rawValue)
    }

    /// Prosodic-allowlist members stay accepted — the closure targets
    /// SYMBOL content, never legitimate punctuation.
    func testR6_prosodicPunctuationInserts_stayAccepted() {
        let r = guardResult(
            "Wait really for real", "Wait, really—for real?",
            known: []
        )
        for e in r.edits where e.kind == "insert" {
            XCTAssertEqual(e.accepted, true, "prosodic insert '\(e.to ?? "")' unexpectedly rejected")
            XCTAssertEqual(e.acceptClass, EditGuard.AcceptClass.punctuationOrCasing.rawValue)
        }
    }

    // MARK: - Designed residual (GREEN — pin CURRENT rejection, NOT attempted by this calibration)

    /// Evidence: cleanup-2026-07-22.jsonl:19. "aufgefahren" IS a real
    /// German word (past participle of "auffahren") — criterion A's
    /// "old is NOT known" gate correctly, deliberately excludes real-word
    /// olds. This is a LOCKED residual, not a bug: the criterion covers
    /// non-word ASR garble only.
    func testResidual_aufgefahrenToAufgefallen_de_staysRejected() {
        let r = guardResult(
            "Dann sollte dir auch aufgefahren sein, dass es einen Fehler gibt.",
            "Dann sollte dir auch aufgefallen sein, dass es einen Fehler gibt.",
            lang: "de",
            known: ["dann", "sollte", "dir", "auch", "aufgefahren", "aufgefallen", "sein", "dass", "es", "einen", "fehler", "gibt"]
        )
        XCTAssertEqual(r.text, "Dann sollte dir auch aufgefahren sein, dass es einen Fehler gibt.")
        let edit = r.edits.first { $0.from == "aufgefahren" }
        XCTAssertEqual(edit?.accepted, false)
    }

    // MARK: - Follow-up fix: R6 closure — dictionary/PersonalLexicon terms (and compounds built from them) must never be repairable

    /// Confirmed corruption from the live-corpus replay
    /// (`cleanup-2026-07-22.jsonl:24`): "MüraX" is the user's OWN brand
    /// (a `PersonalLexicon` replacement VALUE), but the hyphenated compound
    /// `"MüraX-Verhalten"` was not ITSELF in the augmentation set, so the
    /// spell checker correctly called the compound "unknown" and criterion
    /// A wrongly treated it as repairable, delivering "Mora-Verhalten".
    /// `PlatformSpellLexicon.hasAugmentedConstituent` closes this: a
    /// hyphenated compound counts as known when ANY hyphen-separated
    /// constituent is itself an augmented term. Uses the REAL
    /// `PlatformSpellLexicon` (not the deterministic double) via its
    /// `extraAugmentation` init, so this exercises the actual production
    /// augmentation-check code path end-to-end — exact-string assertion
    /// per the follow-up's requirement.
    func testFollowup_compoundConstituentProtection_deZueriAVerhalten() {
        let lexicon = PlatformSpellLexicon(extraAugmentation: ["MüraX"])
        let result = EditGuard.apply(
            rulesCleaned: "Das könnte natürlich schon ein MüraX-Verhalten sein.",
            llmOutput: "Das könnte natürlich schon ein Mora-Verhalten sein.",
            language: "de",
            lexicon: lexicon
        )
        XCTAssertEqual(result.text, "Das könnte natürlich schon ein MüraX-Verhalten sein.")
        let edit = result.edits.first { $0.from == "MüraX-Verhalten" }
        XCTAssertEqual(edit?.accepted, false, "a compound built from a known augmented term must never be treated as an unknown non-word")
    }

    /// Direct unit-level proof of the augmentation-only scoping requirement
    /// ("apply to the augmentation check only, not the platform
    /// spell-checker call"): the compound-constituent rule fires for a
    /// term actually IN the augmentation set, and does NOT spuriously fire
    /// for an unrelated hyphenated compound with no augmented constituent.
    func testFollowup_compoundConstituentProtection_isKnownWordUnitLevel() {
        let lexicon = PlatformSpellLexicon(extraAugmentation: ["MüraX"])
        XCTAssertTrue(lexicon.isKnownWord("MüraX-Verhalten", language: "de"))
        XCTAssertTrue(lexicon.isKnownWord("mürax-verhalten", language: "de"), "constituent match is case-insensitive")
        XCTAssertFalse(lexicon.isKnownWord("Vaspird-Verhalten", language: "de"), "a compound with NO augmented constituent must not be spuriously protected")
    }

    /// Confirmed corruption from the live-corpus replay
    /// (`cleanup-2026-06-29.jsonl:10`): "iterm" (iTerm2, a well-known
    /// terminal app) was misread as a non-word and "repaired" to the
    /// generic word "Item". Fixed via the `PersonalLexicon.swift` entry
    /// `"iterm": "iTerm"` (gitignored, dev-only — mirrors the 260723-qtb
    /// pattern; DictionaryService corrects the casing UPSTREAM of
    /// `EditGuard`, and the augmentation set gains "iterm" as a side
    /// effect of the replacement VALUE). This test simulates the
    /// augmentation-set effect directly (does not depend on the gitignored
    /// file being present) via `extraAugmentation: ["iTerm"]` — once
    /// "iterm" is known, criterion A's "old NOT known" gate excludes it,
    /// same mechanism as the `aufgefahren` residual.
    func testFollowup_iterm_protectedFromNonWordRepair() {
        let lexicon = PlatformSpellLexicon(extraAugmentation: ["iTerm"])
        let result = EditGuard.apply(
            rulesCleaned: "Zudem kann ich ja dann in iterm 2 mit Tabs arbeiten.",
            llmOutput: "Zudem kann ich ja dann in Item 2 mit Tabs arbeiten.",
            language: "de",
            lexicon: lexicon
        )
        let edit = result.edits.first { $0.from == "iterm" }
        XCTAssertEqual(edit?.accepted, false, "iterm must be protected from nonWordRepair once augmented")
        XCTAssertNotEqual(edit?.acceptClass, EditGuard.AcceptClass.nonWordRepair.rawValue)
    }

    /// Explicitly documents the compound-guard's scope boundary for
    /// "iterm 2": `EditGuardTokenizer` tokenizes digits as their OWN
    /// `.numeric`-kind token (mirrors the tokenizer's number-word/digit
    /// handling elsewhere), so baseline "iterm 2" is TWO separate tokens —
    /// word "iterm" + numeric "2" — with NO hyphen between them. The
    /// hyphen-constituent guard added by this follow-up is therefore
    /// irrelevant here (there is no hyphenated compound to split); what
    /// actually protects "iterm" in this context is the DIRECT
    /// augmentation-set membership check ("iterm" itself is augmented),
    /// proven by the test above. This test pins that observation so a
    /// future reader does not assume the hyphen-guard is doing the work
    /// for space-separated contexts too.
    func testFollowup_iterm2_tokenizesAsSeparateWordAndNumericTokens() {
        let tokens = EditGuardTokenizer.tokenize("iterm 2")
        XCTAssertEqual(tokens.map { $0.text }, ["iterm", "2"])
        XCTAssertEqual(tokens.map { $0.kind }, [.word, .numeric])
    }

    // MARK: - Follow-up fix: assert-current residuals (accepted, user decision pending)

    /// Evidence: cleanup-2026-07-10.jsonl:26. "puncto" is a standard
    /// (Latin-derived) German idiom ("in puncto X" = "regarding X") — old
    /// was arguably NOT a non-word, just apparently absent from the spell
    /// checker's dictionary. FIXED (260724-iw4, flagged case #3): "puncto"
    /// is now in `PlatformSpellLexicon.idiomKnownWords`, so criterion A's
    /// `known(a) == false` gate can never be satisfied for it — the edit
    /// falls through to the fail-closed default (step 9) instead of the
    /// non-word-repair exemption. This fixture now pins the FIXED behavior
    /// (rejected, not nonWordRepair) so any future regression is visible in
    /// a diff, not silent. Simulates the production augmentation via the
    /// test double by adding "puncto" to the `known:` set (mirroring what
    /// `PlatformSpellLexicon.idiomKnownWords` does for the real lexicon).
    func testFollowup_punctoToPunkt_de_rejectedNotNonWordRepair() {
        let r = guardResult(
            "Dann ist ebenfalls anzufügen, dass Handlungsbedarf in puncto Schulungsmaterial besteht.",
            "Dann ist ebenfalls anzufügen, dass Handlungsbedarf in Punkt Schulungsmaterial besteht.",
            lang: "de",
            known: ["dann", "ist", "ebenfalls", "anzufügen", "dass", "handlungsbedarf", "in", "puncto", "punkt", "schulungsmaterial", "besteht"]
        )
        let edit = r.edits.first { $0.from == "puncto" }
        XCTAssertEqual(edit?.accepted, false, "puncto is now a known idiom — must NOT be repaired via nonWordRepair")
        XCTAssertNotEqual(edit?.acceptClass, EditGuard.AcceptClass.nonWordRepair.rawValue)
    }

    /// Evidence: cleanup-2026-07-11.jsonl:18. "Pitte" and "Piete" are BOTH
    /// plausible ASR mishearings of the intended "Bitte" (please) — this
    /// edit swaps one garble for a differently-wrong garble rather than a
    /// genuine repair. Left AS-IS pending a user decision; this fixture
    /// pins the CURRENT behavior so any future change is visible.
    func testFollowup_assertCurrent_pitteToPiete_de_acceptsViaNonWordRepair() {
        let r = guardResult(
            "So etwas wie, Pitte ignoriere den letzten Satz, sollte auch erkannt werden.",
            "So etwas wie, Piete ignoriere den letzten Satz, sollte auch erkannt werden.",
            lang: "de",
            known: ["so", "etwas", "wie", "piete", "ignoriere", "den", "letzten", "satz", "sollte", "auch", "erkannt", "werden"]
        )
        let edit = r.edits.first { $0.from == "Pitte" }
        XCTAssertEqual(edit?.accepted, true, "documents CURRENT (residual, not attempted) behavior — see SUMMARY Follow-up section")
        XCTAssertEqual(edit?.acceptClass, EditGuard.AcceptClass.nonWordRepair.rawValue)
    }
}
