import Foundation

/// Phase 44 Plan 03 (D-06): the closed DE/EN function-word allowlist behind
/// the insertion test. Mirrors the `contentWordStopWords` /
/// `scaffoldingBlacklist` closed-list shape already established in
/// `CleanupService.swift` — one reviewable constant, one place to edit.
///
/// RISK DIRECTION (D-06's own framing): an omitted legitimate function word
/// costs a MISSED article-insertion repair. An erroneously-included content
/// word costs a CORRUPTION — the LLM inserting a noun/verb/adjective/adverb
/// dressed up as a "function word" pastes invented meaning at the user's
/// cursor (the 2026-07-12 car-record `"gefahren war"` / `"diese Teile"` /
/// `"ein anderes"` insertions). Under-inclusion is the safe error; keep the
/// list tight and do not widen it to reduce false rejects.
///
/// ## THE DUAL-ROLE CRITERION (Phase 44 Plan 14 — the class fix)
///
/// The audit that gates the Qwen3.5-4B swap
/// (`44-AUDIT-FRESH-CORRUPTION.md`) found a REAL, structural leak: German
/// `"sein"` sat in `germanInsertable` grouped with the auxiliaries, but
/// `"sein"` is DUAL-ROLE — it is both a tense-forming auxiliary ("ist
/// gegangen sein") AND the full lexical copula ("to be", the predicate
/// itself). Qwen3.5 used it in its CONTENT role to invent a completion for
/// a truncated fragment ("...muss wahrscheinlich nicht" -> "...muss
/// wahrscheinlich nicht **sein**.") and the guard waved it through as a
/// harmless `functionWordInsertion`. That is meaning the speaker never said,
/// pasted at their cursor — exactly the corruption class this phase exists
/// to make structurally impossible.
///
/// `"before"` (removed earlier, see `englishDualRole`) was the SAME bug,
/// fixed as an INSTANCE — so the rest of both lists was never checked. This
/// is that check. The criterion, stated BEFORE the removals were chosen and
/// BEFORE the yield cost was measured (so the line cannot have been drawn to
/// flatter a number):
///
/// > A token may be **blanket-insertable** ONLY if it has **no productive
/// > reading in which it carries lexical content** — i.e. it is never a full
/// > lexical verb, a separable verb particle, a predicate or bare adverb, a
/// > modal particle, a wh-adverb, or a noun. If ANY such reading is
/// > productive in the language, the token is **DUAL-ROLE**: inserting it can
/// > ASSERT content, and this string-only lookup (no POS awareness —
/// > `PosTagger.enableNLTaggerFunctionWidening` ships `false`, dead code, see
/// > `EditGuard.classifyInsert`) cannot tell the two roles apart.
///
/// **Fail closed.** Where the judgment is genuinely close, the token is
/// treated as dual-role and removed. A missed repair costs a
/// under-correction; an invented content word costs a corruption. That
/// asymmetry is the entire premise of this phase.
///
/// **Deliberate line, stated so it is auditable and contestable:** ARTICLES
/// and demonstratives (`der`/`das`/`that`) are KEPT even though they have
/// pronoun readings, because those readings are **anaphoric** — they point at
/// something already in the text; they cannot introduce a new lexical
/// meaning. D-06's own flagship repair ("Bezüglich Format" -> "Bezüglich
/// **des** Formats") depends on them. Contracted German prepositions
/// (`zum`/`beim`/`vom`...) are likewise KEPT: a preposition fused with an
/// article can never be a separable particle or a bare adverb — it is
/// structurally unambiguous.
///
/// **Scope: INSERTION ONLY.** The dual-role tokens are moved into
/// `germanDualRole` / `englishDualRole` and unioned straight back into the
/// SUBSTITUTION sets, which are therefore byte-for-byte UNCHANGED. A
/// function<->function substitution replaces a token that the speaker
/// already said; it cannot invent an assertion out of nothing. The corruption
/// vector found is specific to insertion, so the fix is confined to
/// insertion — and `functionWordSubstitution`'s measured yield must come out
/// of the replay IDENTICAL, which is a hard cross-check on this change (see
/// `ClosedListTests.testSubstitutableSetsAreUnchangedByTheDualRoleSplit`).
///
/// Pure lookup — no state, no actor isolation, no `NaturalLanguage` import.
public enum FunctionWords {

    // MARK: - Dual-role tokens (NOT insertable — see the criterion above)

    /// German dual-role tokens: removed from `germanInsertable`, retained in
    /// `germanSubstitutable`. Each entry names the CONTENT reading that makes
    /// a blanket insertion unsafe.
    ///
    /// **Lexical-verb duals** — every German "auxiliary" here is also a full
    /// lexical verb, so an inserted one can assert a proposition:
    /// - `sein` / `ist` / `sind` / `war` / `waren` / `bin` / `bist` / `seid`
    ///   — the COPULA is the predicate. With an elided complement it carries
    ///   the entire assertion ("Das muss nicht **sein**." = "it doesn't have
    ///   to BE [that way]"). This is the live leak found by the audit.
    ///   (`sein` is additionally the possessive pronoun "his".)
    /// - `hat` / `haben` / `hatte` / `hatten` — full lexical verb "to
    ///   have/possess" ("Ich **habe** ein Auto"). An inserted `hat` asserts
    ///   possession.
    /// - `wird` / `werden` / `wurde` / `wurden` — full lexical verb "to
    ///   become" ("Er **wird** Arzt"). An inserted `wird` asserts a change of
    ///   state.
    ///
    /// **Separable-particle / predicate-adverb duals** — German prepositions
    /// that are also productive separable verb particles. Inserting one
    /// adjacent to a verb CHANGES THE VERB'S LEMMA ("geht" -> "geht ... **zu**"
    /// = *zugehen auf*, "pertains to"), which is a content change wearing a
    /// preposition's clothes. Corpus evidence: the audit's own
    /// `2026-07-12T03:59:05.106Z` record, where an inserted `"zu"` completed
    /// exactly such a construction.
    /// - `auf`, `an`, `aus`, `vor`, `über`, `unter`, `durch`, `um`, `nach`,
    ///   `mit`, `zu`, `bei`
    ///
    /// **Adverb / modal-particle duals** among the conjunctions — D-06
    /// explicitly forbids inserting adverbs and modal particles:
    /// - `da` — locative adverb "there" (extremely common in this corpus)
    /// - `denn` — modal particle ("Was ist **denn** los?")
    /// - `wie` — wh-adverb "how"
    /// - `damit` — pronominal adverb "with that"
    public static let germanDualRole: Set<String> = [
        // Lexical-verb duals (copula / possess / become)
        "sein", "ist", "sind", "war", "waren", "bin", "bist", "seid",
        "hat", "haben", "hatte", "hatten",
        "wird", "werden", "wurde", "wurden",
        // Separable-particle / predicate-adverb duals
        "auf", "an", "aus", "vor", "über", "unter", "durch", "um", "nach",
        "mit", "zu", "bei",
        // Adverb / modal-particle duals
        "da", "denn", "wie", "damit"
    ]

    /// English dual-role tokens: removed from `englishInsertable`, retained
    /// in `englishSubstitutable`. Same criterion.
    ///
    /// - `before` — REMOVED EARLIER, as an instance
    ///   (44-FIDELITY-REPLAY.md "SC#3 adjudication", record
    ///   `2026-07-04T05:52:54.137Z`): preposition ("before the meeting") vs.
    ///   bare temporal ADVERB ("I've seen it **before**"). It is recorded here
    ///   as the first member of the class it turned out to belong to. **It is
    ///   deliberately NOT restored to `englishSubstitutable`** — that removal
    ///   already shipped and was already measured (44-FIDELITY-REPLAY.md:
    ///   `functionWordSubstitution` 36 -> 35); silently re-adding it would
    ///   reverse a closed decision.
    /// - `after` — the identical preposition/adverb dual to `before`. The
    ///   old doc comment left it in place for want of a corpus false
    ///   negative; the CLASS audit is that evidence.
    /// - `over`, `under`, `through`, `on`, `in`, `by` — all productive
    ///   adverbs / verb particles ("it's **over**", "get **through**", "the
    ///   light is **on**", "come **in**", "stop **by**").
    /// - `about` — adverb AND, worse, the numeric approximator ("**about**
    ///   10"), which hedges a value the speaker stated precisely.
    /// - `so` — intensifier adverb ("**so** good").
    /// - `when` — wh-adverb (same class as German `wie`).
    /// - `be` / `is` / `are` / `was` / `were` / `am` / `been` — copula; see
    ///   the German entry, same reasoning.
    /// - `has` / `have` / `had` — full lexical verb "to possess".
    /// - `do` / `does` / `did` — full lexical verb "to perform".
    /// - `being` — also a NOUN ("a human **being**").
    /// - `will` — also a noun ("a **will**") and a lexical verb ("to will").
    ///   `would` is KEPT: it has no lexical or nominal reading.
    ///
    /// KEPT (no productive content reading): `a`/`an`/`the`; `at`, `from`,
    /// `for`, `with`, `of`, `into`, `between`; `to` (infinitive marker — the
    /// adverbial "push the door **to**" is archaic, not productive);
    /// `and`, `or`, `but`, `because`, `if`, `while`, `although`; `that`
    /// (demonstrative = anaphoric, per the class doc above); `would`.
    public static let englishDualRole: Set<String> = [
        // Preposition <-> adverb/particle duals
        "after", "over", "under", "through", "about", "on", "in", "by",
        // Adverb duals among the conjunctions
        "so", "when",
        // Lexical-verb / noun duals
        "is", "are", "was", "were", "am", "be", "been", "being",
        "has", "have", "had", "do", "does", "did", "will"
    ]

    /// `"before"`: removed from BOTH the insertable and substitutable English
    /// sets by the earlier instance fix, and kept out of both here. Named as
    /// its own constant so the class audit's provenance is explicit and the
    /// omission cannot be mistaken for an oversight.
    public static let englishDualRoleAlsoNotSubstitutable: Set<String> = ["before"]

    // MARK: - D-06 insertion allowlist

    /// D-06's insertion allowlist, German: articles, prepositions
    /// (including contracted forms), coordinating + subordinating
    /// conjunctions. MUST NOT contain pronouns, adverbs, or modal particles
    /// — see `ClosedListTests.testFunctionWordsContainNoPronouns` — and, per
    /// the DUAL-ROLE CRITERION above, MUST NOT contain any token with a
    /// productive lexical-content reading. **All auxiliaries were removed by
    /// the Plan 14 class audit**: German has no verb form that is purely
    /// auxiliary (`sein`/`haben`/`werden` are all also full lexical verbs),
    /// so under the criterion none of them is blanket-insertable. Note this
    /// is what D-06's own text already demanded — *"It may never insert a
    /// noun, **verb**, adjective, adverb, or number"* — the original list's
    /// "auxiliaries" bullet contradicted it.
    public static let germanInsertable: Set<String> = [
        // Articles (kept: pronoun readings are anaphoric, never lexical)
        "der", "die", "das", "den", "dem", "des",
        "ein", "eine", "einen", "einem", "einer", "eines",
        // Prepositions with NO productive particle/adverb reading
        "in", "für", "von", "seit", "gegen", "ohne", "bis", "zwischen",
        // Contracted prepositions (preposition+article — structurally
        // incapable of being a particle or a bare adverb)
        "im", "am", "zum", "zur", "ins", "ans", "beim", "vom",
        // Conjunctions with NO productive adverb/particle reading
        "und", "oder", "aber", "sondern", "dass", "weil",
        "wenn", "ob", "als", "während", "obwohl"
    ]

    /// D-06's insertion allowlist, English: articles, prepositions,
    /// conjunctions. Same prohibition and same DUAL-ROLE CRITERION as
    /// `germanInsertable`; the removed tokens and their content readings are
    /// enumerated in `englishDualRole`.
    public static let englishInsertable: Set<String> = [
        "a", "an", "the",
        "at", "for", "with", "from", "to", "of", "into", "between",
        "and", "or", "but", "because", "that", "if", "while", "although",
        "would"
    ]

    // MARK: - D-02 function<->function substitution allowlist

    /// D-02's function<->function substitution allowlist, German:
    /// `germanInsertable` plus the DUAL-ROLE tokens plus finite modal verbs
    /// and negation. A function<->function substitution (`der`->`das`,
    /// article-gender agreement) is D-02's explicitly permitted repair; it is
    /// a strictly narrower operation than an insertion — it REPLACES a token
    /// the speaker actually said, so it cannot invent an assertion out of
    /// nothing. That is why the dual-role tokens are unioned back in here:
    /// the corruption vector the Plan 14 audit found is specific to
    /// INSERTION, and this set's contents are therefore **unchanged** by that
    /// fix (locked by
    /// `ClosedListTests.testSubstitutableSetsAreUnchangedByTheDualRoleSplit`).
    ///
    /// Negation is included so that `nicht`->`kein` reads as a function
    /// substitution — this does NOT authorize DELETING a negation; D-05 owns
    /// deletions and permits only acoustic fillers and verbatim repetitions,
    /// never negation.
    public static let germanSubstitutable: Set<String> =
        germanInsertable.union(germanDualRole).union([
            "kann", "können", "könnte", "muss", "müssen", "soll", "sollen",
            "will", "wollen", "darf", "dürfen", "mag", "mögen",
            "nicht", "kein", "keine", "keinen"
        ])

    /// D-02's function<->function substitution allowlist, English:
    /// `englishInsertable` plus the DUAL-ROLE tokens plus modal verbs and
    /// negation. Same rationale as `germanSubstitutable`. `"before"` is
    /// deliberately absent (see `englishDualRoleAlsoNotSubstitutable`).
    public static let englishSubstitutable: Set<String> =
        englishInsertable.union(englishDualRole).union([
            "can", "could", "must", "should", "will", "would", "may", "might",
            "not", "no"
        ])

    // MARK: - Public API

    /// Is `token` a member of the closed D-06 insertion allowlist (articles,
    /// prepositions, auxiliaries, conjunctions ONLY)?
    ///
    /// - Parameters:
    ///   - token: surface-form token; lowercased internally.
    ///   - language: BCP-47-ish tag; first 2 letters used, `"en"` -> English,
    ///     anything else -> German (mirrors `FillerWordRemover.fillerSet(for:)`).
    public static func isInsertable(_ token: String, language: String) -> Bool {
        let lower = token.lowercased()
        let prefix = language.prefix(2).lowercased()
        return prefix == "en" ? englishInsertable.contains(lower) : germanInsertable.contains(lower)
    }

    /// Is `token` a member of the closed D-02 function-word substitution
    /// allowlist (the insertion set plus modals and negation)?
    public static func isSubstitutable(_ token: String, language: String) -> Bool {
        let lower = token.lowercased()
        let prefix = language.prefix(2).lowercased()
        return prefix == "en" ? englishSubstitutable.contains(lower) : germanSubstitutable.contains(lower)
    }
}
