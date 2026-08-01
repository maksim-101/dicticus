import Foundation
import NaturalLanguage

/// Phase 44 Plan 01 (D-01, the phase's load-bearing architectural decision):
/// the shared vocabulary + entry point for the edit-level fidelity guard.
///
/// EditGuard owns content and numeric VALUE identity. `NumberRevert` (Step
/// 3a.5) owns number FORM. The guard never rewrites a digit — it only
/// accepts or rejects the LLM's edit — so the two layers cannot
/// double-revert.
///
/// This plan (44-01) declares ONLY the public vocabulary + a fail-closed
/// stub. No diff logic (plan 44-06 `EditDiff`), no per-edit classification
/// (plan 44-10) lives here yet — every later plan in this phase (44-02
/// through 44-11) compiles against these exact types, so the surface is
/// frozen first.
///
/// `@MainActor`: matches `SentenceAligner`'s precedent (it reuses
/// `CleanupService.tokenizeForDialectGate`, which is `@MainActor`-isolated)
/// and the `@MainActor` call sites (`TextProcessingService`, the spike-004
/// harness) that will invoke `EditGuard.apply(...)` — avoids Swift 6
/// strict-concurrency churn later.
///
/// INVARIANT: until plan 44-10 lands the classifier, `apply(...)` returns
/// the rules-cleaned baseline. A half-built guard that passes the LLM
/// candidate through is strictly worse than no guard.
@MainActor
public enum EditGuard {

    // MARK: - Token vocabulary

    /// A single token from either the baseline or candidate stream.
    ///
    /// `trailing` is the whitespace/punctuation that followed this token in
    /// the source string, so a token array rebuilds losslessly (mirrors the
    /// lossless-reconstruction contract `SentenceAligner.splitSentences`
    /// already guarantees at the sentence level).
    public struct Token: Equatable, Sendable {
        /// Surface form, original casing.
        public let text: String
        /// Lowercased form, used for classification lookups.
        public let normalized: String
        public let kind: TokenKind
        /// Position in its own stream (baseline stream or candidate stream).
        public let index: Int
        public let sentenceIndex: Int
        /// Whitespace/punctuation that followed this token in the source text.
        public let trailing: String

        public init(
            text: String,
            normalized: String,
            kind: TokenKind,
            index: Int,
            sentenceIndex: Int,
            trailing: String
        ) {
            self.text = text
            self.normalized = normalized
            self.kind = kind
            self.index = index
            self.sentenceIndex = sentenceIndex
            self.trailing = trailing
        }
    }

    public enum TokenKind: String, Sendable {
        case word
        case numeric
        case punctuation
    }

    // MARK: - Edit vocabulary

    public enum EditKind: String, Sendable {
        case keep
        case substitute
        case insert
        case delete
        case move
    }

    /// A single typed edit between the baseline and candidate token streams.
    /// `from` is the baseline-side token (nil for `.insert`); `to` is the
    /// candidate-side token (nil for `.delete`).
    public struct Edit: Sendable {
        public let kind: EditKind
        public let from: Token?
        public let to: Token?

        public init(kind: EditKind, from: Token?, to: Token?) {
            self.kind = kind
            self.from = from
            self.to = to
        }
    }

    // MARK: - Classification vocabulary (D-10 / D-11 wire format)

    /// D-10's scoring vocabulary — the classes of edit this guard ACCEPTS.
    /// `rawValue` strings are the wire format later plans (and the D-09
    /// bake-off's surviving-yield scoring) depend on; do not rename cases
    /// without updating every consumer.
    public enum AcceptClass: String, Sendable {
        case punctuationOrCasing
        case inflectionFix
        case functionWordSubstitution
        case functionWordInsertion
        case wordOrderRepair
        case fillerDeletion
        case repetitionDeletion
        case numberFormChange
        /// Quick task 260723-sx1, criterion A: a `.substitute` where `old`
        /// is NOT a known word, `new` IS a known word, and the pair is
        /// phonetically/orthographically close (the guard's own
        /// content-word similarity gate, not `NumberRevert`'s). Additive in
        /// this commit (Task 1) — no classification logic assigns it yet;
        /// wired in Task 2.
        case nonWordRepair
        /// Quick task 260723-sx1, criterion B: a `.delete` (or, per the
        /// pronoun-pair arm, a pronoun-old `.substitute` paired against
        /// unrelated punctuation by `EditDiff`) that collapses two ADJACENT
        /// aligned near-duplicate blocks (stutter/restart) down to one
        /// copy. Additive in this commit (Task 1); wired in Task 2.
        case disfluencyCollapse
    }

    /// D-11's forensics vocabulary — the classes of edit this guard REJECTS.
    /// `rawValue` strings are the wire format `DebugCleanupRecord.GateEntry`
    /// (plan 44-11) serializes; do not rename cases without updating every
    /// consumer.
    ///
    /// `derivationalSuffixChange` is its OWN case, distinct from
    /// `contentWordIdentityChange`, per D-02a: the user blocked derivation
    /// (`Handhabe`→`Handhabung`) on research evidence and requires the cost
    /// of that block to be separately visible in D-10's scoring — merging it
    /// into `contentWordIdentityChange` would hide exactly the number this
    /// decision needs to stay accountable to.
    public enum RejectionClass: String, Sendable {
        case digitValueChange
        case pronounDeleted
        case pronounPersonChange
        case moodLockSentenceInitialVerb
        case contentWordIdentityChange
        case derivationalSuffixChange
        case contentWordDeletion
        case contentWordInsertion
        case numberInsertion
        case unclassified
        /// Quick task 260723-rif: assigned by `applyAtomicGroupCoupling` when
        /// an otherwise-accepted edit is flipped to rejected because it
        /// shares an atomic revert group (a keep-bounded run of interacting
        /// edits, or a `.move`-bridged pair of such runs) with another edit
        /// that was independently rejected. See that function's doc comment.
        case atomicGroupRevert
    }

    /// The log-shaped record: one classified edit, ready to serialize
    /// straight into `DebugCleanupRecord.GateEntry` (plan 44-11).
    public struct ClassifiedEdit: Codable, Sendable {
        public let kind: String
        public let from: String?
        public let to: String?
        public let accepted: Bool
        public let acceptClass: String?
        public let rejectClass: String?

        public init(
            kind: String,
            from: String?,
            to: String?,
            accepted: Bool,
            acceptClass: String?,
            rejectClass: String?
        ) {
            self.kind = kind
            self.from = from
            self.to = to
            self.accepted = accepted
            self.acceptClass = acceptClass
            self.rejectClass = rejectClass
        }
    }

    /// The guard's result: the reconstructed text, every classified edit
    /// (for D-11 forensics), and whether the degenerate-alignment fail-closed
    /// path fired.
    public struct GuardResult: Sendable {
        public let text: String
        public let edits: [ClassifiedEdit]
        public let failedClosed: Bool
        public let failClosedReason: String?

        public init(
            text: String,
            edits: [ClassifiedEdit],
            failedClosed: Bool,
            failClosedReason: String?
        ) {
            self.text = text
            self.edits = edits
            self.failedClosed = failedClosed
            self.failClosedReason = failClosedReason
        }
    }

    // MARK: - Public entry point

    /// Diffs `llmOutput` against `rulesCleaned`, classifies each edit, and
    /// rebuilds the output from the baseline plus only the accepted edits
    /// (D-01). Parameter shape is byte-comparable to
    /// `CleanupService.gatePerSentence` so plan 44-11's call-site swap is
    /// mechanical.
    ///
    /// - Parameters:
    ///   - rawText: raw ASR dictation, before dictionary/ITN/Swiss/rules/
    ///     self-correction processing. Accepted for parity with
    ///     `gatePerSentence`'s signature but deliberately UNUSED — see the
    ///     "T-42-06 decision" doc comment on `classify(...)` below. Kept as
    ///     a parameter (not removed) so 44-11's call-site swap stays
    ///     mechanical and so a future plan can wire it without another
    ///     signature change.
    ///   - rulesCleaned: deterministic Swift-side cleanup output (rules pass)
    ///     — the fallback text on every fail-closed path.
    ///   - llmOutput: post-strip/leak-guard LLM output (the candidate).
    ///   - language: BCP-47-ish language tag ("de"/"en"/...).
    ///   - dictProtected: dictionary-replacement values that must survive
    ///     verbatim.
    /// - Returns: a `GuardResult`. Every untrusted path returns
    ///   `rulesCleaned` verbatim (`failedClosed == true`); the trusted path
    ///   returns the baseline rebuilt with only the individually-approved
    ///   edits applied. MUST NOT return `llmOutput` wholesale — construct,
    ///   never merely accept-or-reject the LLM's whole text (D-01).
    public static func apply(
        rawText: String = "",
        rulesCleaned: String,
        llmOutput: String,
        language: String,
        dictProtected: Set<String> = [],
        lexicon: any SpellLexicon = PlatformSpellLexicon.shared
    ) -> GuardResult {
        let safe = GuardResult(
            text: rulesCleaned,
            edits: [],
            failedClosed: true,
            failClosedReason: "notApplicable"
        )

        guard !rulesCleaned.isEmpty, !llmOutput.isEmpty else {
            return GuardResult(text: rulesCleaned.isEmpty ? llmOutput : rulesCleaned, edits: [], failedClosed: true, failClosedReason: "emptyInput")
        }

        guard CleanupService.prefilterLLMOutput(rulesCleaned: rulesCleaned, llmOutput: llmOutput) else {
            return GuardResult(text: safe.text, edits: [], failedClosed: true, failClosedReason: "prefilter")
        }

        let baselineTokens = EditGuardTokenizer.tokenize(rulesCleaned)
        let candidateTokens = EditGuardTokenizer.tokenize(llmOutput)
        let edits = EditDiff.diff(baseline: baselineTokens, candidate: candidateTokens)
        let confidence = EditDiff.confidence(baseline: baselineTokens, candidate: candidateTokens, edits: edits)
        guard !EditDiff.isDegenerate(confidence) else {
            return GuardResult(text: safe.text, edits: [], failedClosed: true, failClosedReason: "degenerateAlignment")
        }

        let classified = classify(
            edits: edits,
            baseline: baselineTokens,
            candidate: candidateTokens,
            language: language,
            dictProtected: dictProtected,
            lexicon: lexicon
        )

        guard let rebuilt = rebuild(
            baseline: baselineTokens,
            candidate: candidateTokens,
            edits: edits,
            classified: classified,
            language: language
        ) else {
            return GuardResult(text: safe.text, edits: [], failedClosed: true, failClosedReason: "rebuildInvariant")
        }

        return GuardResult(text: collapseDanglingPunctuation(rebuilt.text), edits: rebuilt.classified, failedClosed: false, failClosedReason: nil)
    }

    /// Collapse two punctuation marks separated ONLY by whitespace (e.g. `worked , . So`) into a
    /// single mark. Such a sequence is never valid prose, so this is always a repair, never a
    /// meaning change — no content token is touched.
    ///
    /// Root cause it backstops (documented, not fixed here): when the LLM splits a run-on sentence
    /// (comma→period) AND adds a comma elsewhere, `EditDiff`'s LCS pairs the two IDENTICAL comma
    /// tokens across the clause boundary, so `rebuild` keeps the baseline comma and inserts the new
    /// period as a separate spaced token → ` , .`. Fixing the LCS pairing itself is deep and
    /// high-regression; collapsing the provably-invalid output is the safe, targeted fix.
    /// Reproduced on the real corpus (`worked, so`→`worked. So,`; `connected, otherwise`→
    /// `connected. Otherwise,`) — 4 occurrences across the debug logs, both models.
    ///
    /// Winner: a sentence-terminal mark (`.!?`) beats a non-terminal (`,;:`); otherwise the later
    /// mark wins. The required whitespace BETWEEN the marks is what makes this precise — legitimate
    /// runs like `...`, `?!`, or `etc.,` have no interior space and never match.
    static func collapseDanglingPunctuation(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: " *([.,;:!?]) +([.,;:!?])") else { return text }
        let terminals: Set<Character> = [".", "!", "?"]
        var current = text
        // Loop so a run of 3+ (e.g. ` , . ;`) fully collapses.
        while true {
            let range = NSRange(current.startIndex..., in: current)
            guard let m = regex.firstMatch(in: current, range: range),
                  let r1 = Range(m.range(at: 1), in: current),
                  let r2 = Range(m.range(at: 2), in: current),
                  let full = Range(m.range, in: current) else { break }
            let p1 = current[r1.lowerBound], p2 = current[r2.lowerBound]
            let winner = (terminals.contains(p1) && !terminals.contains(p2)) ? p1 : p2
            current.replaceSubrange(full, with: String(winner))
        }
        return current
    }

    // MARK: - D-04 pronoun family (identity beyond grammatical person)

    /// `PronounPersonMap` only tracks grammatical PERSON (1st/2nd/3rd).
    /// Two pronouns can share a person yet refer to a DIFFERENT subject —
    /// "him" -> "her" are both third person, but the substitution changes
    /// WHO is being talked about, which is a meaning change, not a repair
    /// (44-10's pronoun gender-flip gap, raised by 44-03's
    /// `fx-sub-pronoun-en-genderflip` fixture). This table adds a coarser
    /// "family" identity beneath person: two pronouns are interchangeable
    /// (a case-declension of the SAME referent, e.g. German `ihn`->`ihm`,
    /// English `him`->`his`) only when they share a family. A substitution
    /// across families is rejected even when `PronounPersonMap` reports the
    /// same person — this is a STRICTER predicate than person-equality
    /// alone (family-equal implies person-equal), so it can only reject
    /// MORE than the person-only check, never accept something the
    /// person-only check would have rejected. That is the safe direction
    /// per this file's asymmetric-risk framing (a false reject costs a
    /// missed repair; a false accept pastes a corrupted meaning).
    ///
    /// Deliberately conservative: German `sie`/`ihnen` are each given their
    /// OWN family rather than grouped with a plural sibling, mirroring
    /// `PronounPersonMap`'s own documented KNOWN GAP (that ambiguity is
    /// already accepted there) — a genuine case-declension repair between
    /// them becomes a missed repair (safe) rather than a risked false
    /// accept. `sich` (invariant reflexive across all 3rd-person genders)
    /// gets its own family for the same reason.
    private static let germanPronounFamily: [String: String] = [
        "ich": "1sg", "mich": "1sg", "mir": "1sg",
        "wir": "1pl", "uns": "1pl", "unser": "1pl",
        "du": "2sg", "dich": "2sg", "dir": "2sg",
        "ihr": "2pl", "euch": "2pl",
        "er": "3sg.m", "ihn": "3sg.m", "ihm": "3sg.m",
        "sie": "3.sie", "ihnen": "3.ihnen",
        "es": "3sg.n",
        "sich": "3.reflexive"
    ]

    /// English half of the pronoun-family table — see `germanPronounFamily`.
    private static let englishPronounFamily: [String: String] = [
        "i": "1sg", "me": "1sg", "my": "1sg",
        "we": "1pl", "us": "1pl", "our": "1pl",
        "you": "2", "your": "2", "yours": "2",
        "he": "3sg.m", "him": "3sg.m", "his": "3sg.m",
        "she": "3sg.f", "her": "3sg.f",
        "it": "3sg.n", "its": "3sg.n",
        "they": "3pl", "them": "3pl", "their": "3pl"
    ]

    private static func pronounFamily(_ token: String, language: String) -> String? {
        let lower = token.lowercased()
        let prefix = language.prefix(2).lowercased()
        return prefix == "en" ? englishPronounFamily[lower] : germanPronounFamily[lower]
    }

    // MARK: - Filler predicate (dispatches to the closed D-05 lists)

    private static func isFillerToken(_ normalized: String, language: String) -> Bool {
        let prefix = language.prefix(2).lowercased()
        return prefix == "en"
            ? FillerWordRemover.englishFillers.contains(normalized)
            : FillerWordRemover.germanFillers.contains(normalized)
    }

    // MARK: - Part B: classify

    /// Classifies every edit in `edits` against D-02..D-06, in the fixed
    /// order documented on each branch below (first match wins). Returns a
    /// `[ClassifiedEdit]` in the SAME order/count as `edits` — `rebuild`
    /// zips them back together positionally, so callers must never reorder
    /// or filter either array independently.
    ///
    /// **T-42-06 decision (recorded here, not implemented):** `rawText` is
    /// NOT threaded into classification. Verified against the Phase 42
    /// self-correction fixtures during 44-10 development
    /// (`testSelfCorrectionKeepsLLMResolutionOverDegradedRulesBaseline`'s
    /// scenario, replayed through this classifier by hand): D-05's
    /// deletion predicate rejects the degraded rules-cleaned baseline's
    /// stray self-correction artifacts (`"actually"`, `"it's"`, `"think"`)
    /// as `contentWordDeletion`, so the guard falls back toward the
    /// degraded-but-safe baseline rather than the LLM's cleaner resolution
    /// — a REGRESSION relative to `gatePerSentence`'s T-42-06 raw-window
    /// switch on that one scenario. The regression is in the SAFE
    /// direction (a missed repair — clunkier text survives, not a
    /// corrupted one) and is documented in `44-10-SUMMARY.md` rather than
    /// implemented, because implementing the raw-window switch faithfully
    /// requires per-sentence window classification (mirroring
    /// `gateSentenceWindow`'s architecture) that this edit-level guard does
    /// not otherwise need — out of scope for this plan. `rawText` stays a
    /// parameter so a follow-up plan can wire it without another signature
    /// change.
    public static func classify(
        edits: [Edit],
        baseline: [Token],
        candidate: [Token],
        language: String,
        dictProtected: Set<String>,
        lexicon: any SpellLexicon = PlatformSpellLexicon.shared
    ) -> [ClassifiedEdit] {
        let dictProtectedLower = Set(dictProtected.map { $0.lowercased() })
        let disfluencyIndices = disfluencyAcceptedIndices(edits: edits, baseline: baseline, language: language)
        var result: [ClassifiedEdit] = []
        result.reserveCapacity(edits.count)

        for edit in edits {
            let (accepted, acceptClass, rejectClass) = classifyOne(
                edit, baseline: baseline, language: language, dictProtectedLower: dictProtectedLower,
                candidate: candidate, lexicon: lexicon, disfluencyIndices: disfluencyIndices
            )
            result.append(ClassifiedEdit(
                kind: edit.kind.rawValue,
                from: edit.from?.text,
                to: edit.to?.text,
                accepted: accepted,
                acceptClass: acceptClass?.rawValue,
                rejectClass: rejectClass?.rawValue
            ))
        }
        return result
    }

    private static func classifyOne(
        _ edit: Edit,
        baseline: [Token],
        language: String,
        dictProtectedLower: Set<String>,
        candidate: [Token],
        lexicon: any SpellLexicon,
        disfluencyIndices: Set<Int>
    ) -> (accepted: Bool, acceptClass: AcceptClass?, rejectClass: RejectionClass?) {
        switch edit.kind {
        case .keep:
            guard let a = edit.from else { return (true, nil, nil) }
            return a.kind == .punctuation ? (true, .punctuationOrCasing, nil) : (true, nil, nil)

        case .substitute:
            return classifySubstitute(edit, language: language, dictProtectedLower: dictProtectedLower, lexicon: lexicon, disfluencyIndices: disfluencyIndices)

        case .insert:
            return classifyInsert(edit, language: language, candidate: candidate)

        case .delete:
            return classifyDelete(edit, baseline: baseline, language: language, disfluencyIndices: disfluencyIndices)

        case .move:
            return classifyMove(edit, language: language)
        }
    }

    // MARK: - substitute

    private static func classifySubstitute(
        _ edit: Edit,
        language: String,
        dictProtectedLower: Set<String>,
        lexicon: any SpellLexicon = PlatformSpellLexicon.shared,
        disfluencyIndices: Set<Int> = []
    ) -> (accepted: Bool, acceptClass: AcceptClass?, rejectClass: RejectionClass?) {
        guard let a = edit.from, let b = edit.to else { return (false, nil, .unclassified) }

        // 1. Casing-only fix.
        if a.normalized == b.normalized, a.text != b.text {
            return (true, .punctuationOrCasing, nil)
        }
        // 1.5. Quick task 260723-sx1, criterion B (defensive second path):
        // `EditDiff` can pair a disfluency-block's leftover baseline WORD
        // (a pronoun, per the pronoun-pair arm) against a leftover
        // candidate PUNCTUATION token instead of emitting a clean `.delete`
        // — the live "you they will analyze" evidence case (replay-HEAD-
        // evidence.txt case 6b). Checked BEFORE the pronoun lock (step 4
        // below) for the same D-04 reason `classifyDelete` checks this set
        // first: the sentence keeps its subject via the ADJACENT surviving
        // pronoun, so this is not the agent-erasing deletion D-04 exists to
        // block.
        if a.kind == .word, b.kind == .punctuation, disfluencyIndices.contains(a.index) {
            return (true, .disfluencyCollapse, nil)
        }
        // 2. BOTH sides punctuation (SC#3 gap closure, 44-FIDELITY-REPLAY.md
        //    §2/§6): the ORIGINAL rule accepted whenever EITHER side was
        //    punctuation. `EditDiff`'s LCS+substitute-pairing can pair a real
        //    WORD against trailing/adjacent punctuation when nothing else is
        //    left to pair it with in a local gap (root-caused case:
        //    baseline's orphaned "it's" at a truncated sentence boundary
        //    paired against candidate's closing "."). That let a genuine
        //    content word vanish, misclassified as a "punctuation-only" edit
        //    — bypassing every digit/pronoun/content-word check below. A
        //    word-vs-punctuation pairing must FALL THROUGH to those checks
        //    instead of blanket-accepting; only a punctuation<->punctuation
        //    substitute (e.g. "."->",") is a genuine punctuation-only edit.
        //
        //    Quick task 260723-sx1, criterion C: further restricted to
        //    PROSODIC punctuation on BOTH sides (`prosodicPunctuation`) —
        //    a symbol substitute (e.g. "#"->"+") is SYMBOL content, not
        //    prosody, and must fall through to the content checks below
        //    instead of blanket-accepting.
        if a.kind == .punctuation, b.kind == .punctuation,
           prosodicPunctuation.contains(a.text), prosodicPunctuation.contains(b.text) {
            return (true, .punctuationOrCasing, nil)
        }
        // 3. Digit lock (D-03).
        if EditGuardTokenizer.isDigitBearing(a.text) || EditGuardTokenizer.isDigitBearing(b.text) {
            if let va = EditGuardTokenizer.numericValue(a, language: language),
               let vb = EditGuardTokenizer.numericValue(b, language: language),
               va == vb {
                return (true, .numberFormChange, nil)
            }
            return (false, nil, .digitValueChange)
        }
        // 4. Pronoun lock (D-04) — person AND family (see `pronounFamily`).
        let aIsPronoun = PronounPersonMap.isPronoun(a.normalized, language: language)
        let bIsPronoun = PronounPersonMap.isPronoun(b.normalized, language: language)
        if aIsPronoun || bIsPronoun {
            if aIsPronoun, bIsPronoun,
               let famA = pronounFamily(a.normalized, language: language),
               let famB = pronounFamily(b.normalized, language: language),
               famA == famB {
                return (true, .functionWordSubstitution, nil)
            }
            return (false, nil, .pronounPersonChange)
        }
        // 5. dictProtect — the user's dictionary spelling must survive verbatim.
        if dictProtectedLower.contains(a.normalized) {
            return (false, nil, .contentWordIdentityChange)
        }
        // Fillers may only be DELETED (D-05), never substituted for another
        // word — no accept class covers filler substitution.
        if isFillerToken(a.normalized, language: language) || isFillerToken(b.normalized, language: language) {
            return (false, nil, .unclassified)
        }
        // 6. Function<->function (D-02 article/agreement repair).
        if FunctionWords.isSubstitutable(a.normalized, language: language),
           FunctionWords.isSubstitutable(b.normalized, language: language) {
            return (true, .functionWordSubstitution, nil)
        }
        // 6.5. Quick task 260723-sx1, criterion A: non-word repair
        // exemption. Accept iff `a` is NOT a known word, `b` IS a known
        // word (dictProtect counts as known for BOTH arms — a dictionary
        // term is never "repairable" in either direction), and the pair is
        // orthographically/phonetically close. Placed BEFORE step 7's
        // derivational lock (not after): the derivational lock was
        // evidenced on real-word pairs (Handhabe->Handhabung);
        // derivational analysis of a NON-word is meaningless, and
        // eingänglicher->eingängiger would otherwise die at step 7 (-lich/
        // -ig read as a derivational suffix pair) before this exemption is
        // ever consulted. Real-word pairs (both known) never reach this
        // branch — they still fall through to steps 7/8/9 unchanged.
        if a.kind == .word, b.kind == .word,
           !isKnownForRepair(a, language: language, dictProtectedLower: dictProtectedLower, lexicon: lexicon),
           isKnownForRepair(b, language: language, dictProtectedLower: dictProtectedLower, lexicon: lexicon),
           isNonWordRepairClose(a.normalized, b.normalized, language: language) {
            return (true, .nonWordRepair, nil)
        }
        // 7. Derivation (D-02a) — checked BEFORE the lemma-lock accept path.
        if InflectionRules.isDerivational(a.normalized, b.normalized, language: language) {
            return (false, nil, .derivationalSuffixChange)
        }
        // 8. Lemma lock (D-02).
        if InflectionRules.isAllowedInflection(a.normalized, b.normalized, language: language) {
            return (true, .inflectionFix, nil)
        }
        // 9. Fail closed.
        return (false, nil, .contentWordIdentityChange)
    }

    // MARK: - insert (D-06)

    private static func classifyInsert(
        _ edit: Edit,
        language: String,
        candidate: [Token]
    ) -> (accepted: Bool, acceptClass: AcceptClass?, rejectClass: RejectionClass?) {
        guard let b = edit.to else { return (false, nil, .unclassified) }

        // Quick task 260723-sx1, criterion C: only PROSODIC/typographic
        // marks are freely insertable. Every other punctuation-kind token
        // (`+ * = < > | ^ ~ # $ % @ & _ §` …) is SYMBOL content — it
        // changes meaning ("C" -> "C++"), so it is classed like any other
        // invented content, not blanket-accepted.
        if b.kind == .punctuation {
            if prosodicPunctuation.contains(b.text) {
                return (true, .punctuationOrCasing, nil)
            }
            return (false, nil, .contentWordInsertion)
        }
        if b.kind == .numeric {
            return (false, nil, .numberInsertion)
        }
        // A pronoun the user did not say invents an agent. Not on D-06's
        // permitted list; classed `unclassified` rather than
        // `contentWordInsertion` — pronoun insertion is a DIFFERENT failure
        // shape (inventing a referent) from inventing a noun/verb/
        // adjective/adverb, and D-11's forensics keep them distinguishable.
        if PronounPersonMap.isPronoun(b.normalized, language: language) {
            return (false, nil, .unclassified)
        }
        // A hallucinated filler insertion — not on D-06's permitted list
        // either; same "not really a content word" shape as the pronoun
        // case above.
        if isFillerToken(b.normalized, language: language) {
            return (false, nil, .unclassified)
        }
        if FunctionWords.isInsertable(b.normalized, language: language) {
            return (true, .functionWordInsertion, nil)
        }
        // PosTagger widener — dead code while `enableNLTaggerFunctionWidening`
        // ships `false` (44-07). A `nil` verdict is NEVER coerced to accept.
        if PosTagger.enableNLTaggerFunctionWidening {
            let sentenceText = EditGuardTokenizer.rebuild(
                candidate.filter { $0.sentenceIndex == b.sentenceIndex }
            )
            if PosTagger.isFunctionWord(b.text, in: sentenceText, language: language) == true {
                return (true, .functionWordInsertion, nil)
            }
        }
        return (false, nil, .contentWordInsertion)
    }

    // MARK: - delete (D-05 — ZERO-AMBIGUITY ONLY)

    private static func classifyDelete(
        _ edit: Edit,
        baseline: [Token],
        language: String,
        disfluencyIndices: Set<Int> = []
    ) -> (accepted: Bool, acceptClass: AcceptClass?, rejectClass: RejectionClass?) {
        guard let a = edit.from else { return (false, nil, .unclassified) }

        if a.kind == .punctuation {
            return (true, .punctuationOrCasing, nil)
        }
        // Quick task 260723-sx1, criterion B: consulted BEFORE the
        // pronounDeleted lock (and before filler/repetition below) — the
        // D-04 lock exists to prevent agent ERASURE, but in an adjacent-
        // duplicate stutter/restart the agent (or the repeated content)
        // survives via the adjacent surviving copy, so the sentence's
        // meaning is unchanged, not erased.
        if disfluencyIndices.contains(a.index) {
            return (true, .disfluencyCollapse, nil)
        }
        // D-04: a pronoun may NEVER be deleted — checked before the filler
        // test so a pronoun that somehow collides with a filler token still
        // dies here.
        if PronounPersonMap.isPronoun(a.normalized, language: language) {
            return (false, nil, .pronounDeleted)
        }
        if isFillerToken(a.normalized, language: language) {
            return (true, .fillerDeletion, nil)
        }
        // Verbatim repetition: the immediately preceding OR following
        // BASELINE token has the same normalized value ("auch auch" ->
        // "auch"). Adjacency is on the baseline stream via `Token.index`
        // (baseline[i].index == i by construction — EditGuardTokenizer
        // assigns indices sequentially).
        let idx = a.index
        let prevNormalized = idx > 0 ? baseline[idx - 1].normalized : nil
        let nextNormalized = idx + 1 < baseline.count ? baseline[idx + 1].normalized : nil
        if prevNormalized == a.normalized || nextNormalized == a.normalized {
            return (true, .repetitionDeletion, nil)
        }
        // Everything else — `noch`, `doch`, `actually`, `like`, `well`,
        // `right`, `I mean`, digits, content words, function words — dies
        // here. No exception list; D-05 measured every one of these and
        // the filler reading is the MINORITY reading for nearly all of
        // them.
        return (false, nil, .contentWordDeletion)
    }

    // MARK: - move (D-04 — MOVES ARE PERMITTED)

    private static func classifyMove(
        _ edit: Edit,
        language: String
    ) -> (accepted: Bool, acceptClass: AcceptClass?, rejectClass: RejectionClass?) {
        guard let a = edit.from, let b = edit.to else { return (false, nil, .unclassified) }

        // Punctuation is never a genuine "move" (44-GOODSHINE-VERIFICATION.md
        // / 44-FIDELITY-REPLAY.md SC#3 Adjudication Records 6/7): a moved `.`
        // / `,` / `—` is not a repositioning of the SAME mark the user
        // dictated — punctuation is the most repetitive token class in any
        // text (a single utterance can carry a dozen `.` tokens from pause-
        // dot runs alone), so `EditDiff.pairMovesFirst`'s global identical-
        // normalized-text matching pairs a rejected edit's stray punctuation
        // token against a textually-identical but semantically-unrelated
        // punctuation token anywhere else in the stream. Treating that as a
        // `wordOrderRepair` injects a spurious mark at the mismatched
        // target position — a genuine corruption (the live "goodshine"
        // "...we suspect. of course, but then..." spurious mid-sentence
        // period). Reject unconditionally: the rejected move restores the
        // baseline token at its own position and drops the unmatched
        // candidate token, exactly like two independently-rejected
        // delete/insert edits would — never a blanket accept.
        if a.kind == .punctuation {
            return (false, nil, .unclassified)
        }
        // A filler should be deleted (D-05), not relocated — moving a
        // filler token is not a defined permitted class.
        if isFillerToken(a.normalized, language: language) {
            return (false, nil, .unclassified)
        }
        // A pure positional move of a pronoun with UNCHANGED person is
        // fine; a move by construction pairs tokens with identical
        // `.normalized` text, so person cannot actually differ here — this
        // check is defensive symmetry with the substitute path, not a
        // reachable branch in practice.
        if PronounPersonMap.isPronoun(a.normalized, language: language) {
            let personA = PronounPersonMap.person(of: a.normalized, language: language)
            let personB = PronounPersonMap.person(of: b.normalized, language: language)
            if personA != personB {
                return (false, nil, .pronounPersonChange)
            }
        }
        // The mood-lock is a SENTENCE-level property, applied in the
        // rebuild's second pass — NOT here, per edit. Do not re-implement
        // that comparison in this function.
        return (true, .wordOrderRepair, nil)
    }

    // MARK: - Quick task 260723-sx1, criterion A: non-word repair

    /// Orthographic-arm threshold (`nlev <= 0.35`): "old" and "new" are
    /// close enough that `old` reads as ASR garble of `new`. R3-pinned spot
    /// values: clawd/claude 0.333, claudco/claude 0.286, geträgt(folded)/
    /// getragen 0.25, eingänglicher(folded)/eingängiger 0.23 — all accept.
    /// gisela/gazelle 0.57 — rejects. Tuning rule: may only move in the
    /// direction that keeps every R6 negative rejecting; any loosening
    /// requires a NEW negative fixture pinning the new boundary first.
    private static let nonWordRepairOrthographicThreshold = 0.35
    /// Phonetic backstop (`phonetic keys equal AND nlev <= 0.50`): a wider
    /// orthographic allowance when the two tokens also SOUND alike (per the
    /// language-routed phonetic encoder below), covering ASR mishearings
    /// that a pure edit-distance threshold would miss. gisela/gazelle
    /// (0.57) still rejects even under this backstop.
    private static let nonWordRepairPhoneticBackstopThreshold = 0.50

    /// "Known" for criterion A purposes: `dictProtected` counts as known
    /// for BOTH arms of the substitute (a dictionary term is never
    /// "repairable" in either direction — mirrors step 5's existing
    /// dictProtect-on-`a` rule, extended here to `b` since criterion A can
    /// evaluate either side), OR the injected `lexicon`'s platform/
    /// augmentation-backed verdict.
    private static func isKnownForRepair(
        _ token: Token, language: String, dictProtectedLower: Set<String>, lexicon: any SpellLexicon
    ) -> Bool {
        if dictProtectedLower.contains(token.normalized) { return true }
        return lexicon.isKnownWord(token.text, language: language)
    }

    /// Diacritic-fold + lowercase, then normalized Levenshtein distance;
    /// close iff the orthographic threshold is met, OR the language-routed
    /// phonetic keys collide AND the (still folded/lowercased) distance
    /// meets the wider phonetic backstop. English uses `DoubleMetaphone`,
    /// German uses `ColognePhonetic` (36.5 convention — English Metaphone
    /// rules are wrong for German).
    private static func isNonWordRepairClose(_ a: String, _ b: String, language: String) -> Bool {
        let foldedA = foldForSimilarity(a)
        let foldedB = foldForSimilarity(b)
        let nlev = LevenshteinDistance.normalizedDistance(foldedA, foldedB)
        if nlev <= nonWordRepairOrthographicThreshold { return true }
        let isGerman = language.hasPrefix("de")
        let keyA = isGerman ? ColognePhonetic.encode(a) : DoubleMetaphone.encode(a)
        let keyB = isGerman ? ColognePhonetic.encode(b) : DoubleMetaphone.encode(b)
        if !keyA.isEmpty, keyA == keyB, nlev <= nonWordRepairPhoneticBackstopThreshold {
            return true
        }
        return false
    }

    private static func foldForSimilarity(_ s: String) -> String {
        s.lowercased().folding(options: .diacriticInsensitive, locale: nil)
    }

    // MARK: - Quick task 260723-sx1, criterion C: prosodic-punctuation allowlist

    /// PROSODIC/typographic marks, freely insertable/substitutable
    /// (criterion C). Every OTHER `.punctuation`-kind token (`+ * = < > |
    /// ^ ~ # $ % @ & _ §` …) is SYMBOL content — inserting or substituting
    /// one changes meaning (`"C"` -> `"C++"`) and must NOT blanket-accept.
    private static let prosodicPunctuation: Set<String> = [
        ".", ",", ";", ":", "!", "?", "…",
        "'", "’", "‘", "\"", "“", "”", "„", "«", "»",
        "(", ")", "[", "]", "{", "}",
        "-", "–", "—"
    ]

    // MARK: - Quick task 260723-sx1, criterion B: adjacent-duplicate disfluency collapse

    /// Baseline token indices belonging to an ACCEPTED adjacent-duplicate
    /// disfluency collapse (a stutter/restart the candidate correctly
    /// resolved down to one copy). Consulted by `classifyDelete` (the
    /// `.delete` shape) and `classifySubstitute` (the pronoun-old-paired-
    /// against-punctuation shape `EditDiff` sometimes produces instead —
    /// replay-HEAD-evidence.txt case 6b).
    ///
    /// Algorithm (criterion B, verbatim): for every candidate block length
    /// 1-3 and every position, take two STRICTLY ADJACENT baseline blocks A
    /// then B of that length. They qualify iff, position-wise, EVERY pair
    /// (A[k], B[k]) either has equal `normalized` text, is a same-lemma
    /// near-duplicate (`InflectionRules.isAllowedInflection` OR shared
    /// prefix >= 4 chars AND raw Levenshtein distance <= 2 — covers
    /// furtherly/further), or is a pair of pronouns (the adjacent-pronoun-
    /// stutter arm) — AND exactly one of {A[k], B[k]} was actually dropped
    /// by the candidate (a `.delete`, or a `.substitute` pairing a WORD
    /// against PUNCTUATION). A qualifying pair contributes its dropped
    /// index. This is deliberately pairing-agnostic — whichever side
    /// `EditDiff` happened to attribute the drop to, the same block
    /// collapse qualifies (mirrors the "to furtherly"/"to further"
    /// evidence case, where the SECOND "to" — not the first — is the one
    /// actually dropped).
    private static func disfluencyAcceptedIndices(
        edits: [Edit], baseline: [Token], language: String
    ) -> Set<Int> {
        var dropped: Set<Int> = []
        for edit in edits {
            guard let a = edit.from, a.kind == .word else { continue }
            switch edit.kind {
            case .delete:
                dropped.insert(a.index)
            case .substitute:
                if let b = edit.to, b.kind == .punctuation {
                    dropped.insert(a.index)
                }
            default:
                break
            }
        }
        guard !dropped.isEmpty else { return [] }

        var accepted: Set<Int> = []
        let n = baseline.count
        for length in 1...3 {
            guard n >= 2 * length else { continue }
            for i in 0...(n - 2 * length) {
                let blockA = Array(baseline[i..<(i + length)])
                let blockB = Array(baseline[(i + length)..<(i + 2 * length)])
                guard blockA.allSatisfy({ $0.kind == .word }), blockB.allSatisfy({ $0.kind == .word }) else { continue }

                var qualifies = true
                var pairDrops: [Int] = []
                for k in 0..<length {
                    let x = blockA[k], y = blockB[k]
                    guard disfluencyBlockAligns(x, y, language: language) else { qualifies = false; break }
                    let xDropped = dropped.contains(x.index)
                    let yDropped = dropped.contains(y.index)
                    guard xDropped != yDropped else { qualifies = false; break } // exactly one dropped
                    pairDrops.append(xDropped ? x.index : y.index)
                }
                if qualifies {
                    accepted.formUnion(pairDrops)
                }
            }
        }
        return accepted
    }

    /// Position-wise alignment predicate for criterion B's block pairs —
    /// (a) equal normalized text, (b) same-lemma near-duplicate, or (c)
    /// both pronouns (the adjacent-pronoun-stutter arm — the surviving
    /// adjacent pronoun keeps the sentence's subject, so this is not the
    /// agent-erasing deletion D-04's `pronounDeleted` lock exists for).
    private static func disfluencyBlockAligns(_ x: Token, _ y: Token, language: String) -> Bool {
        if x.normalized == y.normalized { return true }
        if InflectionRules.isAllowedInflection(x.normalized, y.normalized, language: language) { return true }
        if x.normalized.count >= 4, y.normalized.count >= 4,
           x.normalized.prefix(4) == y.normalized.prefix(4),
           LevenshteinDistance.distance(x.normalized, y.normalized) <= 2 {
            return true
        }
        if PronounPersonMap.isPronoun(x.normalized, language: language),
           PronounPersonMap.isPronoun(y.normalized, language: language) {
            return true
        }
        return false
    }

    // MARK: - Part C: rebuild + apply

    /// An emitted token in the rebuilt output — a lightweight projection of
    /// `Token` (no `index`, since restored/rebuilt tokens don't occupy a
    /// stable position in either source stream).
    private struct WorkToken {
        let text: String
        let normalized: String
        let kind: TokenKind
        let trailing: String
        let sentenceIndex: Int
        /// Set only when `text` was accepted via the casing-only substitute
        /// path (`AcceptClass.punctuationOrCasing`, `a.normalized ==
        /// b.normalized`) AND the candidate token was itself its sentence's
        /// FIRST word (`materialize`'s `candidateFirstWordIndex` check) —
        /// the token's ORIGINAL baseline spelling, kept so a later
        /// restoration in front of this token (which changes whether it is
        /// STILL genuinely sentence-initial after rebuild) can revert a
        /// capitalization the LLM only applied because THIS token looked
        /// sentence-initial in the candidate. Phase 44 Plan 11 fix: without
        /// the candidate-sentence-initial gate, this flag was set for EVERY
        /// accepted mid-sentence casing-only fix too (e.g. a legitimate
        /// German mid-sentence noun capitalization, "welt"->"Welt"),
        /// causing `revertSpuriousSentenceInitialCapitalization` to strip
        /// it back to lowercase even though nothing was ever restored in
        /// front of it — surfaced by `TextProcessingServiceTests
        /// .testCleanupPath` once the guard was wired into the real
        /// pipeline (Task 1). See `revertSpuriousSentenceInitialCapitalization`.
        let baselineCasingAlternative: String?
    }

    private static let germanArticleTokens: Set<String> = [
        "der", "die", "das", "den", "dem", "des",
        "ein", "eine", "einen", "einem", "einer", "eines"
    ]
    private static let englishArticleTokens: Set<String> = ["a", "an", "the"]

    private static func isArticleToken(_ normalized: String, language: String) -> Bool {
        let prefix = language.prefix(2).lowercased()
        return prefix == "en" ? englishArticleTokens.contains(normalized) : germanArticleTokens.contains(normalized)
    }

    /// Consistency pass (Rule 2 — critical for correctness, not in the
    /// plan's literal Part B algorithm): a maximal run of consecutive
    /// `.insert` edits is either ALL applied or ALL reverted. Without this,
    /// the classifier's per-token independence lets a coherent inserted
    /// phrase split — e.g. `"gefahren war"` (D-06 negative fixture
    /// `fx-ins-content-de-gefahrenwar`) has `"war"` independently accept
    /// (it's on the D-06 auxiliary allowlist) while `"gefahren"` rejects,
    /// producing `"...zur Arbeit war, als..."` — a Frankenstein fragment
    /// that is neither the baseline nor a coherent repair. Required by
    /// `fx-ins-content-de-gefahrenwar`, `fx-ins-content-de-einanderes`, and
    /// `fx-ins-digit-de` (all in `EditGuardFixtureCoverageTests`'s required
    /// set).
    private static func applyInsertRunCoupling(edits: [Edit], verdicts: inout [ClassifiedEdit]) {
        var i = 0
        while i < edits.count {
            guard edits[i].kind == .insert else { i += 1; continue }
            var j = i
            while j < edits.count, edits[j].kind == .insert { j += 1 }
            let run = i..<j
            let anyRejected = run.contains { !verdicts[$0].accepted }
            if anyRejected {
                for k in run where verdicts[k].accepted {
                    verdicts[k] = ClassifiedEdit(
                        kind: verdicts[k].kind, from: verdicts[k].from, to: verdicts[k].to,
                        accepted: false, acceptClass: nil,
                        rejectClass: RejectionClass.contentWordInsertion.rawValue
                    )
                }
            }
            i = j
        }
    }

    /// Post-merge gate fix (bug 2): consistency pass, same shape as
    /// `applyInsertRunCoupling` — a maximal run of consecutive `.move`
    /// edits whose tokens are CONTIGUOUS in both the baseline stream and
    /// the candidate stream (i.e. a genuine multi-token chunk that moved
    /// together, not two unrelated moves that merely landed next to each
    /// other in the edit list) is applied or reverted as a UNIT. Without
    /// this, a filler token's rejected move (D-05: fillers are deleted, not
    /// relocated) can leave its immediately-adjacent punctuation's move
    /// independently ACCEPTED — the two halves of one bundle then land in
    /// completely different places during restoration (the filler restores
    /// near its baseline anchor; the punctuation, having "moved" to
    /// wherever the candidate put it, stays there), producing malformed
    /// output like a doubled comma or two words glued together with no
    /// space (`fx-mov-filler-de`/`fx-mov-filler-en`).
    private static func applyMoveRunCoupling(edits: [Edit], verdicts: inout [ClassifiedEdit]) {
        var i = 0
        while i < edits.count {
            guard edits[i].kind == .move else { i += 1; continue }
            var j = i
            while j + 1 < edits.count,
                  edits[j + 1].kind == .move,
                  let prevFrom = edits[j].from, let nextFrom = edits[j + 1].from,
                  nextFrom.index == prevFrom.index + 1,
                  let prevTo = edits[j].to, let nextTo = edits[j + 1].to,
                  nextTo.index == prevTo.index + 1
            {
                j += 1
            }
            let run = i...j
            if run.count > 1 {
                let anyRejected = run.contains { !verdicts[$0].accepted }
                if anyRejected {
                    for k in run where verdicts[k].accepted {
                        verdicts[k] = ClassifiedEdit(
                            kind: verdicts[k].kind, from: verdicts[k].from, to: verdicts[k].to,
                            accepted: false, acceptClass: nil,
                            rejectClass: RejectionClass.unclassified.rawValue
                        )
                    }
                }
            }
            i = j + 1
        }
    }

    /// Consistency pass (Rule 2): an accepted article/determiner
    /// `functionWordSubstitution` immediately adjacent to a REJECTED
    /// content-word substitution (`contentWordIdentityChange` or
    /// `derivationalSuffixChange`) is reverted too. German articles carry
    /// grammatical gender; when a noun's identity change is rejected (D-02a
    /// blocks `Beobachter`->`Beobachtung`, masc->fem), keeping an
    /// independently-accepted `Der`->`Die` gender flip would produce
    /// `"Die Beobachter"` — grammatically broken AND not equal to either
    /// the baseline or a coherent repair. Required by
    /// `fx-sub-content-de-beobachter-beobachtung`.
    private static func applyArticleAgreementCoupling(edits: [Edit], verdicts: inout [ClassifiedEdit], language: String) {
        for i in edits.indices {
            guard edits[i].kind == .substitute, verdicts[i].accepted,
                  verdicts[i].acceptClass == AcceptClass.functionWordSubstitution.rawValue,
                  let a = edits[i].from, let b = edits[i].to,
                  isArticleToken(a.normalized, language: language),
                  isArticleToken(b.normalized, language: language)
            else { continue }

            let neighborRejectsNounIdentity: Bool = [i - 1, i + 1].contains { neighbor in
                guard edits.indices.contains(neighbor), edits[neighbor].kind == .substitute,
                      !verdicts[neighbor].accepted else { return false }
                return verdicts[neighbor].rejectClass == RejectionClass.contentWordIdentityChange.rawValue
                    || verdicts[neighbor].rejectClass == RejectionClass.derivationalSuffixChange.rawValue
            }

            if neighborRejectsNounIdentity {
                verdicts[i] = ClassifiedEdit(
                    kind: verdicts[i].kind, from: verdicts[i].from, to: verdicts[i].to,
                    accepted: false, acceptClass: nil,
                    rejectClass: RejectionClass.contentWordIdentityChange.rawValue
                )
            }
        }
    }

    /// Defect B fix (2026-07-13 gap closure — the disfluency-not-corruption
    /// class named in `44-FIDELITY-REPLAY.md`'s "New findings" #2 and
    /// `44-BAKEOFF.md`'s adjudicated Records 3/4/6-of-11, plus a distinct,
    /// FULLY REPRODUCED real-corpus instance this fix directly closes):
    /// corpus `2026-07-04T06:01:35.827Z` — baseline "In regards to the
    /// definition..." / candidate "Regarding the definition..." —
    /// `substitute(regards->Regarding)` passes D-02's lemma lock in
    /// isolation (same lemma "regard", legitimate `inflectionFix`), but its
    /// immediate baseline neighbours `"In"` and `"to"` are independently,
    /// correctly REJECTED as `contentWordDeletion` (D-05's zero-ambiguity
    /// policy has no reason to know "regards"->"Regarding" makes them
    /// grammatically redundant). `materialize`'s restoration anchor chains
    /// both rejected deletes to the FRONT of the output (each restored
    /// token becomes a valid anchor for the next), landing directly in
    /// front of "Regarding" — producing "In to Regarding the definition...",
    /// neither the baseline nor a coherent repair.
    ///
    /// Fix: when a REJECTED `contentWordDeletion` sits immediately adjacent
    /// (in edit-stream order — the same edits-array adjacency
    /// `applyArticleAgreementCoupling` already uses) to an ACCEPTED
    /// `.substitute`/`.insert` that is NOT itself
    /// `punctuationOrCasing`/`numberFormChange` (a cosmetic edit never
    /// causes this shape), revert that neighbour too — restoring the FULL
    /// baseline phrase verbatim instead of a Frankenstein mix of restored
    /// and rewritten fragments. Deliberately scoped to REJECTED-DELETE
    /// neighbours only (not rejected-substitute neighbours, which is the
    /// shape `44-BAKEOFF.md`'s milder Records 3/4 exhibit) — reverting on a
    /// rejected-substitute neighbour too would ALSO catch genuine,
    /// desirable `inflectionFix`/`functionWordSubstitution` accepts sitting
    /// beside an unrelated rejected substitute elsewhere in the same
    /// multi-edit sentence (e.g. Record 4's `überschneiden`->
    /// `überschneidet`, a flagship D-02 case, sits directly beside the
    /// independently-rejected `Texte`->`Text`) — costing real yield to fix
    /// a defect this file's own SC#3 adjudication already classified as
    /// disfluent-but-not-meaning-corrupting and explicitly left open. This
    /// narrower scope closes the FULLY REPRODUCED, corpus-grounded "In to
    /// Regarding" shape without that yield cost — verified byte-identical
    /// `wordOrderRepair`/`inflectionFix`/`functionWordSubstitution` counts
    /// on both the 618-record corpus replay and the 232-record fresh-
    /// Qwen3.5 audit population (see `44-FIDELITY-REPLAY.md`'s gap-closure
    /// section for both numbers, before and after this fix).
    private static func applyAdjacentDeletionSubstituteCoupling(edits: [Edit], verdicts: inout [ClassifiedEdit]) {
        for i in edits.indices {
            guard edits[i].kind == .delete, !verdicts[i].accepted,
                  verdicts[i].rejectClass == RejectionClass.contentWordDeletion.rawValue
            else { continue }

            for neighbor in [i - 1, i + 1] where edits.indices.contains(neighbor) {
                guard verdicts[neighbor].accepted,
                      edits[neighbor].kind == .substitute || edits[neighbor].kind == .insert,
                      verdicts[neighbor].acceptClass != AcceptClass.punctuationOrCasing.rawValue,
                      verdicts[neighbor].acceptClass != AcceptClass.numberFormChange.rawValue
                else { continue }
                verdicts[neighbor] = ClassifiedEdit(
                    kind: verdicts[neighbor].kind, from: verdicts[neighbor].from, to: verdicts[neighbor].to,
                    accepted: false, acceptClass: nil,
                    rejectClass: RejectionClass.unclassified.rawValue
                )
            }
        }
    }

    /// Quick task 260723-rif (defect class A, log-analysis 2026-07-23):
    /// atomic revert groups. Fixes the general shape the four narrow
    /// couplings above each patch ONE instance of: a keep-bounded run of
    /// interacting edits where partial acceptance splices baseline and
    /// candidate fragments into text that appears in NEITHER source
    /// ("wanna to", "of for heartrate instance", a lost "?" leaving "right
    /// So", a dangling "Es" before "Und zwar").
    ///
    /// **Grouping.** A group is a connected component over: (a) each
    /// maximal run of consecutive non-`.keep` edits in the FINAL `edits`
    /// array (order-preserving, as `EditDiff.diff` returns it) — one
    /// cluster per run; (b) every `.move` edit additionally bridges its own
    /// cluster to whichever cluster's CANDIDATE-index interval contains
    /// `move.to.index` — the move's second half, which `EditDiff
    /// .pairMovesFirst` consumed from the ops stream, so the destination
    /// gap has no edit of its own sitting there to make the connection
    /// visible without this explicit bridge. A cluster's candidate-index
    /// interval is derived from the `to.index` of its bounding `.keep`
    /// edits (sentinels `-1`/`Int.max` at the string's own edges) — pure
    /// interval containment, not a lookup, so it works whether or not any
    /// edit actually sits at that destination index.
    ///
    /// **Reversion.** For every resulting group: if ANY member has
    /// `accepted == false`, flip every ACCEPTED member to rejected
    /// (`atomicGroupRevert`). Idempotent and monotone (accept -> reject
    /// only, never the reverse) by construction — the cluster/group
    /// structure is derived purely from `edits` (immutable within one
    /// `rebuild` call), never from `verdicts`, so re-running after a later
    /// verdict mutation (the mood-lock loop) is always safe and can only
    /// discover MORE reasons to revert, never un-revert a prior flip.
    ///
    /// **Punctuation-only-group exemption (found via the golden-fixture
    /// regression sweep, `fx-mov-punct-en-goodshine-fullrecord-
    /// spuriousmove`):** a group whose members are ALL punctuation-only (no
    /// member has a non-nil `from`/`to` token with `kind != .punctuation`)
    /// is NEVER reverted, even when it contains a rejection. `classifyMove`
    /// already rejects EVERY punctuation `.move` unconditionally (comments,
    /// `EditGuard.swift`) precisely because commas/dots/dashes are the most
    /// repetitive token class in any text — a rejected punctuation move
    /// sitting in the same keep-bounded gap as several UNRELATED, correctly
    /// ACCEPTED punctuation edits (e.g. an ellipsis run "......" legitimately
    /// collapsing to a quote mark + em-dash) is a coincidence of position,
    /// not a genuine content interaction — the four described mechanisms
    /// above ALL have at least one non-punctuation (word) member whose
    /// rejection is the reason the group must not be spliced. Reverting a
    /// punctuation-only group throws away independently-good punctuation
    /// cleanup and reintroduces the exact ellipsis-glued-onto-a-quote defect
    /// `44-GOODSHINE-VERIFICATION.md` fixed. This exemption is why `.move`
    /// bridging in Step 2 still matters even for a punctuation-only move: it
    /// can bridge INTO a content-bearing group (as `Es`/`Und zwar` does) —
    /// eligibility is evaluated on the FINAL merged group, not the
    /// originating cluster.
    ///
    /// **Crossed multi-pair substitute rendering — FIXED by 260724-j96
    /// (formerly a documented residual of this fix, out of THIS function's
    /// scope):** when a single keep-bounded gap contains TWO OR MORE
    /// `.substitute` pairs produced by `EditDiff.pairAdjacentSubstitutes`'
    /// STEM-PLAUSIBILITY ranking (not position), that ranking can cross the
    /// pairs' relative order versus their baseline order (e.g. baseline
    /// "fact check" / candidate "let's fact-check" pairs baseline "fact" to
    /// candidate "fact-check" — the higher stem-overlap pair — leaving
    /// "check" paired against "let's"). `materialize` renders a rejected
    /// `.substitute` inline, at the CANDIDATE index of its own `to` token
    /// (unlike a rejected `.delete`/`.move`, which restores via the
    /// baseline-anchored `restorationTargets` mechanism and is therefore
    /// order-safe) — so reverting BOTH crossed substitutes to rejected used
    /// to still splice them out of baseline order ("check fact" instead of
    /// "fact check"). This was NOT a partial-acceptance defect this
    /// function's verdict propagation could fix — it required a rendering-
    /// level fix. 260724-j96 fixes it with a gap-local rejected-substitute
    /// remap inside `materialize` itself (its own doc comment, above
    /// `byCandidateIndex`): within each gap, the i-th baseline-index-ordered
    /// rejected substitute is reassigned to render at the i-th candidate-
    /// index-ordered rejected-substitute slot, an identity remap when the
    /// pairing was never crossed. `EditDiff.pairAdjacentSubstitutes` itself
    /// remains byte-untouched — the fix is purely in how `materialize`
    /// renders an already-rejected substitute pair.
    private static func applyAtomicGroupCoupling(edits: [Edit], verdicts: inout [ClassifiedEdit]) {
        guard !edits.isEmpty else { return }

        // Step 1: assign a cluster id to each maximal run of consecutive
        // non-keep edits, and record each cluster's candidate-index
        // interval (exclusive bounds), derived from the bounding `.keep`
        // edits' `to.index` values — sentinels at the string's own edges.
        var clusterID = [Int](repeating: -1, count: edits.count) // -1 == keep, no cluster
        var clusterLo: [Int] = []
        var clusterHi: [Int] = []

        var currentID: Int?
        var lastKeepCandidateIndex = -1
        for i in edits.indices {
            if edits[i].kind == .keep {
                if let cid = currentID {
                    clusterHi[cid] = edits[i].to?.index ?? Int.max
                    currentID = nil
                }
                lastKeepCandidateIndex = edits[i].to?.index ?? lastKeepCandidateIndex
            } else {
                if currentID == nil {
                    let newID = clusterLo.count
                    clusterLo.append(lastKeepCandidateIndex)
                    clusterHi.append(Int.max) // patched when the cluster closes, or left open at string end
                    currentID = newID
                }
                clusterID[i] = currentID!
            }
        }

        guard !clusterLo.isEmpty else { return } // every edit was a keep — nothing to group

        // Step 2: union-find over clusters, bridged by `.move` destinations.
        var parent = Array(clusterLo.indices)
        func find(_ x: Int) -> Int {
            var x = x
            while parent[x] != x { parent[x] = parent[parent[x]]; x = parent[x] }
            return x
        }
        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[ra] = rb }
        }
        func clusterContaining(candidateIndex x: Int) -> Int? {
            for cid in clusterLo.indices where clusterLo[cid] < x && x < clusterHi[cid] {
                return cid
            }
            return nil
        }

        for i in edits.indices {
            guard edits[i].kind == .move, let from = edits[i].from, let to = edits[i].to,
                  // A punctuation move never bridges clusters: `classifyMove`
                  // already rejects EVERY punctuation move unconditionally
                  // (it is never a genuine content interaction — see this
                  // function's "punctuation-only-group exemption" doc
                  // comment), and identical punctuation marks recur so often
                  // in ordinary prose (ellipsis runs especially) that a
                  // punctuation move's destination landing inside some
                  // UNRELATED content-bearing cluster is a coincidence of
                  // matching text, not a genuine interaction — bridging on
                  // it would let that unrelated cluster's rejection sweep up
                  // this move's own, otherwise-independent punctuation
                  // neighbours (confirmed via the golden-fixture regression
                  // sweep on `fx-mov-punct-en-goodshine-fullrecord-
                  // spuriousmove`).
                  from.kind != .punctuation
            else { continue }
            let ownCluster = clusterID[i]
            guard ownCluster != -1,
                  let destCluster = clusterContaining(candidateIndex: to.index),
                  destCluster != ownCluster
            else { continue } // destination inside the move's own cluster (or no cluster there) — no-op
            union(ownCluster, destCluster)
        }

        // Step 3: for every resulting group, if ANY member is rejected AND
        // the group has at least one non-punctuation-only member (the
        // "punctuation-only-group exemption" above), flip every accepted
        // member to rejected.
        func isPunctuationOnly(_ edit: Edit) -> Bool {
            let fromIsPunctOrNil = edit.from.map { $0.kind == .punctuation } ?? true
            let toIsPunctOrNil = edit.to.map { $0.kind == .punctuation } ?? true
            return fromIsPunctOrNil && toIsPunctOrNil
        }
        var groupHasRejection = Set<Int>()
        var groupHasContentMember = Set<Int>()
        for i in edits.indices where clusterID[i] != -1 {
            let root = find(clusterID[i])
            if !verdicts[i].accepted { groupHasRejection.insert(root) }
            if !isPunctuationOnly(edits[i]) { groupHasContentMember.insert(root) }
        }
        let groupsToRevert = groupHasRejection.intersection(groupHasContentMember)
        guard !groupsToRevert.isEmpty else { return }
        for i in edits.indices {
            let cid = clusterID[i]
            guard cid != -1, verdicts[i].accepted, groupsToRevert.contains(find(cid)) else { continue }
            verdicts[i] = ClassifiedEdit(
                kind: verdicts[i].kind, from: verdicts[i].from, to: verdicts[i].to,
                accepted: false, acceptClass: nil,
                rejectClass: RejectionClass.atomicGroupRevert.rawValue
            )
        }
    }

    /// The candidate-stream walk (Part C step 1-5, 7): emits accepted
    /// candidate-side tokens in candidate order, restores rejected
    /// delete/move tokens near their nearest surviving baseline anchor, and
    /// never mutates `verdicts` itself.
    private static func materialize(
        baseline: [Token],
        candidate: [Token],
        edits: [Edit],
        verdicts: [ClassifiedEdit]
    ) -> [WorkToken] {
        var byCandidateIndex: [Int: (Edit, ClassifiedEdit)] = [:]
        for (i, edit) in edits.enumerated() {
            if let to = edit.to {
                byCandidateIndex[to.index] = (edit, verdicts[i])
            }
        }

        // Gap-local rejected-substitute remap (260724-j96): a rejected
        // `.substitute` renders inline at the CANDIDATE index of its own
        // `to` token — unlike a rejected `.delete`/`.move`, which restores
        // via the baseline-anchored `restorationTargets` mechanism below and
        // is therefore order-safe regardless of pairing. When a single
        // keep-bounded gap holds 2+ `.substitute` pairs,
        // `EditDiff.pairAdjacentSubstitutes`' STEM-PLAUSIBILITY ranking can
        // cross the pairs' relative order versus their baseline order (e.g.
        // baseline "fact check" / candidate "let's fact-check" pairs
        // baseline "fact" to candidate "fact-check" — the higher stem-
        // overlap pair — leaving "check" paired against "let's"). If both
        // are then rejected, rendering each at its OWN candidate slot
        // reproduces the crossed (candidate) order instead of baseline
        // order — a neither-source splice ("check fact" instead of "fact
        // check"). Crossing is GAP-LOCAL: `pairAdjacentSubstitutes` only
        // forms pairs within one keep-bounded delete/insert run, and keeps
        // (the LCS backbone) are monotonic in both streams, so a rejected
        // substitute can only be order-crossed against another rejected
        // substitute in the SAME gap.
        //
        // Fix: within each gap, collect the REJECTED `.substitute` edits
        // only (accepted ones emit real candidate text and need no
        // baseline-order constraint). Sort their baseline `from` tokens by
        // `from.index` ascending and their candidate slots by `to.index`
        // ascending, then assign the i-th baseline token to the i-th slot.
        // When the pairing was never crossed this is the identity
        // assignment (each token maps back to its own slot) — output
        // byte-identical, which is what keeps the blast radius exactly the
        // crossed-gap records. The resulting map is threaded through all
        // three consumers of a rejected substitute below: the candidate
        // walk (renders the reassigned token, not `edit.from`),
        // `baselineAnchorCandidateIndex`/`baselineSurvives` (a restored
        // baseline index must anchor at the slot where its token NOW
        // renders, or a stale entry misplaces `.delete`/`.move`
        // restorations), and `emittedKindAt` (reports the reassigned
        // token's kind).
        var gapID = [Int](repeating: -1, count: edits.count)
        do {
            var currentGap: Int?
            var gapCount = 0
            for i in edits.indices {
                if edits[i].kind == .keep {
                    currentGap = nil
                } else {
                    if currentGap == nil {
                        currentGap = gapCount
                        gapCount += 1
                    }
                    gapID[i] = currentGap!
                }
            }
        }
        var gapRejectedSubstitutes: [Int: [(from: Token, to: Token)]] = [:]
        for i in edits.indices {
            guard edits[i].kind == .substitute, !verdicts[i].accepted,
                  let from = edits[i].from, let to = edits[i].to,
                  gapID[i] != -1
            else { continue }
            gapRejectedSubstitutes[gapID[i], default: []].append((from, to))
        }
        var substituteRestoreToken: [Int: Token] = [:] // candidate to.index -> reassigned baseline token
        for (_, group) in gapRejectedSubstitutes {
            let byBaseline = group.sorted { $0.from.index < $1.from.index }
            let bySlot = group.sorted { $0.to.index < $1.to.index }
            for k in bySlot.indices {
                substituteRestoreToken[bySlot[k].to.index] = byBaseline[k].from
            }
        }

        // Which candidate index is each sentence's FIRST word, in the
        // ORIGINAL (pre-rebuild) candidate stream — used below to scope
        // `baselineCasingAlternative` to tokens that genuinely LOOKED
        // sentence-initial to the LLM, not to every mid-sentence
        // casing-only accept (a legitimate German mid-sentence noun
        // capitalization repair, e.g. "welt"->"Welt", is never candidate-
        // sentence-initial and must never be a spurious-capitalization
        // revert candidate — see `revertSpuriousSentenceInitialCapitalization`).
        var candidateFirstWordIndex: [Int: Int] = [:]
        for t in candidate where t.kind == .word {
            if candidateFirstWordIndex[t.sentenceIndex] == nil {
                candidateFirstWordIndex[t.sentenceIndex] = t.index
            }
        }

        // Which baseline indices "survive" verbatim (keep, or a rejected
        // substitute restoring the baseline token in place), and which
        // candidate index anchors them for restoration purposes.
        var baselineSurvives = [Bool](repeating: false, count: baseline.count)
        var baselineAnchorCandidateIndex: [Int: Int] = [:] // -1 == front-of-output
        for (i, edit) in edits.enumerated() {
            guard edit.kind == .keep, let a = edit.from, let b = edit.to else { continue }
            baselineSurvives[a.index] = true
            baselineAnchorCandidateIndex[a.index] = b.index
        }
        // Rejected substitutes: anchor the token that ACTUALLY renders at
        // each slot per the gap-local remap above (identity when the
        // pairing wasn't crossed) — see the remap's doc comment for why
        // this must use the reassigned token, not `edit.from`.
        for (slotIndex, token) in substituteRestoreToken {
            baselineSurvives[token.index] = true
            baselineAnchorCandidateIndex[token.index] = slotIndex
        }

        var restorationsAfter: [Int: [WorkToken]] = [:]
        var restorationsAtFront: [WorkToken] = []

        let restorationTargets: [(bIdx: Int, token: Token)] = edits.enumerated().compactMap { i, edit in
            let v = verdicts[i]
            guard !v.accepted, let a = edit.from else { return nil }
            switch edit.kind {
            case .delete, .move: return (a.index, a)
            default: return nil
            }
        }.sorted { $0.bIdx < $1.bIdx }

        for (bIdx, a) in restorationTargets {
            let restored = WorkToken(text: a.text, normalized: a.normalized, kind: a.kind, trailing: a.trailing, sentenceIndex: a.sentenceIndex, baselineCasingAlternative: nil)

            var anchor: Int?
            var scan = bIdx - 1
            while scan >= 0 {
                if baselineSurvives[scan] { anchor = scan; break }
                scan -= 1
            }

            let targetCandidateIndex: Int
            if let anchorIdx = anchor, let candIdx = baselineAnchorCandidateIndex[anchorIdx] {
                targetCandidateIndex = candIdx
            } else {
                targetCandidateIndex = -1
            }

            if targetCandidateIndex == -1 {
                restorationsAtFront.append(restored)
            } else {
                restorationsAfter[targetCandidateIndex, default: []].append(restored)
            }
            baselineAnchorCandidateIndex[bIdx] = targetCandidateIndex
            baselineSurvives[bIdx] = true
        }

        // Precompute what each candidate index actually EMITS (nothing for
        // a rejected insert/move — those are true "drops"). Used by
        // `trailingFor` below to decide, for every emitted token, whether
        // the position immediately following it in candidate is UNCHANGED
        // (in which case candidate's own trailing is already correct and
        // must be preserved verbatim — this is what protects abbreviations
        // like "a.m" and a leading "..." from a fabricated space) or was
        // DROPPED (in which case the gap needs bridging: no space before
        // whatever punctuation now follows, one space before a word).
        var emittedKindAt: [Int: TokenKind] = [:]
        for (i, edit) in edits.enumerated() {
            guard let to = edit.to else { continue }
            let v = verdicts[i]
            switch edit.kind {
            case .keep:
                emittedKindAt[to.index] = to.kind
            case .substitute:
                emittedKindAt[to.index] = v.accepted ? to.kind : (substituteRestoreToken[to.index]?.kind ?? edit.from?.kind ?? to.kind)
            case .insert, .move:
                if v.accepted { emittedKindAt[to.index] = to.kind }
            case .delete:
                break
            }
        }

        func trailingFor(candidateIndex i: Int, ownTrailing: String) -> String {
            // A restoration queued right after this position needs a
            // leading separator. Originally documented "restored content is
            // virtually always a word, never punctuation" — TRUE only until
            // the punctuation-move lever-1 fix (44-FIDELITY-REPLAY.md SC#3
            // Adjudication / GOODSHINE-VERIFICATION.md): a rejected
            // `.delete` of punctuation never reaches this path (D-05 accepts
            // ALL punctuation deletes unconditionally, so they are never
            // restored), but a rejected `.move` of punctuation NOW can be
            // (classifyMove rejects every punctuation move as of this fix,
            // where it previously always accepted). Root-caused via the live
            // full-record replay of the 2026-07-12T09:38:37.354Z "goodshine"
            // corpus record: forcing `""` here glued the restored `.` onto
            // the immediately-following candidate token with ZERO separator
            // ("of.\"goodshine\"" — no space anywhere), a genuine rendering
            // corruption `bridgeGluedWordTokens`/`renderingInvariantHolds`
            // cannot catch (both deliberately skip punctuation-adjacent
            // seams, to protect abbreviations like "a.m" — see their own doc
            // comments). Restored punctuation now takes the SAME
            // separator-guaranteeing path as restored words: never glue,
            // worst case one extra space (cosmetic, never a correctness
            // issue) instead of a fused token.
            if let after = restorationsAfter[i], after.first != nil {
                return ownTrailing.isEmpty ? " " : ownTrailing
            }
            // Nothing dropped immediately after `i` — candidate's own
            // structure at this seam is unchanged, so its own trailing is
            // already correct. Preserve it verbatim.
            if i + 1 >= candidate.count || emittedKindAt[i + 1] != nil {
                return ownTrailing
            }
            // A drop occurred — find the next position that will actually
            // emit something and bridge the gap: no space before
            // punctuation, one space before a word/number.
            var next = i + 1
            while next < candidate.count, emittedKindAt[next] == nil {
                next += 1
            }
            guard next < candidate.count, let kind = emittedKindAt[next] else { return "" }
            return kind == .punctuation ? "" : " "
        }

        var output: [WorkToken] = []
        output.append(contentsOf: restorationsAtFront)

        for i in 0..<candidate.count {
            if let (edit, v) = byCandidateIndex[i] {
                switch edit.kind {
                case .keep:
                    if let b = edit.to {
                        output.append(WorkToken(text: b.text, normalized: b.normalized, kind: b.kind, trailing: trailingFor(candidateIndex: i, ownTrailing: b.trailing), sentenceIndex: b.sentenceIndex, baselineCasingAlternative: nil))
                    }
                case .substitute:
                    if v.accepted, let a = edit.from, let b = edit.to {
                        let isCasingOnly = v.acceptClass == AcceptClass.punctuationOrCasing.rawValue
                            && a.kind != .punctuation && a.normalized == b.normalized && a.text != b.text
                            && candidateFirstWordIndex[b.sentenceIndex] == b.index
                        output.append(WorkToken(
                            text: b.text, normalized: b.normalized, kind: b.kind, trailing: trailingFor(candidateIndex: i, ownTrailing: b.trailing), sentenceIndex: b.sentenceIndex,
                            baselineCasingAlternative: isCasingOnly ? a.text : nil
                        ))
                    } else if let a = edit.from, let b = edit.to {
                        // Gap-local remap (260724-j96): render the token
                        // reassigned to THIS slot, not necessarily this
                        // edit's own `a` — see `substituteRestoreToken`'s
                        // doc comment above. Falls back to `a` when no
                        // remap entry exists (defensive; every rejected
                        // substitute's own slot is always populated).
                        let renderToken = substituteRestoreToken[i] ?? a
                        // Whitespace-provenance fix (quick task 260801-9n7,
                        // evidence record 2026-07-29T03:47:35.149Z): this
                        // branch restores the BASELINE token's `text` (via
                        // `renderToken`) but was, unconditionally, taking the
                        // CANDIDATE token's whitespace via `trailingFor`. A
                        // baseline mark that carried a genuine inter-sentence
                        // separator (the "." in "...labeled. So...", baseline
                        // trailing " ") silently inherited a candidate glue
                        // (the LLM's "labeled—to", trailing "") whenever the
                        // candidate-derived trailing came back empty — gluing
                        // two sentences together ("labeled.So"). Falling back
                        // to the restored token's OWN baseline trailing in
                        // that situation is source-faithful BY CONSTRUCTION:
                        // it can never fabricate a separator the baseline
                        // didn't have, which is exactly what protects
                        // legitimate punct-glued-to-word source text like
                        // "a.m"/"z.B"/"(word" (their own baseline trailing is
                        // ALSO empty, so the fallback is a no-op there).
                        // Scoped to `.punctuation` only — the sibling restore
                        // paths (`restorationTargets`, front-of-output) are
                        // already baseline-anchored and deliberately
                        // untouched; a restored WORD's candidate-derived
                        // trailing is not this defect's shape.
                        let candidateDerivedTrailing = trailingFor(candidateIndex: i, ownTrailing: b.trailing)
                        let restoredTrailing = (candidateDerivedTrailing.isEmpty && renderToken.kind == .punctuation)
                            ? renderToken.trailing
                            : candidateDerivedTrailing
                        output.append(WorkToken(text: renderToken.text, normalized: renderToken.normalized, kind: renderToken.kind, trailing: restoredTrailing, sentenceIndex: b.sentenceIndex, baselineCasingAlternative: nil))
                    }
                case .insert:
                    if v.accepted, let b = edit.to {
                        output.append(WorkToken(text: b.text, normalized: b.normalized, kind: b.kind, trailing: trailingFor(candidateIndex: i, ownTrailing: b.trailing), sentenceIndex: b.sentenceIndex, baselineCasingAlternative: nil))
                    }
                    // rejected insert -> omit entirely; `trailingFor` on
                    // the PRECEDING emitted token already bridges this gap.
                case .move:
                    if v.accepted, let b = edit.to {
                        output.append(WorkToken(text: b.text, normalized: b.normalized, kind: b.kind, trailing: trailingFor(candidateIndex: i, ownTrailing: b.trailing), sentenceIndex: b.sentenceIndex, baselineCasingAlternative: nil))
                    }
                    // rejected move -> omit here; restored separately at
                    // its baseline anchor, and the gap this leaves is
                    // bridged the same way as a rejected insert.
                case .delete:
                    break // deletes never populate byCandidateIndex (no `to`)
                }
            }
            if let after = restorationsAfter[i] {
                output.append(contentsOf: after)
            }
        }

        return revertSpuriousSentenceInitialCapitalization(bindPunctuationLeft(bridgeGluedWordTokens(output)))
    }

    /// Post-process (SC#3 gap closure, bug 2 — 44-FIDELITY-REPLAY.md §2/§3):
    /// a restored token (a rejected `.delete`/`.move`, or a rejected
    /// `.substitute` restoring the baseline token) carries its ORIGINAL
    /// baseline `trailing`, calibrated against whatever followed it in the
    /// SOURCE baseline text — not necessarily what ends up next to it in the
    /// REBUILT output. Root-caused via the real-corpus "habenUnd" artifact:
    /// baseline "...Textboxen haben, und dann..." — "haben"'s own baseline
    /// trailing is `""` (a comma, its own separate token, followed
    /// immediately with no space). The clause "da wir ... Textboxen haben"
    /// was rejected and restored, but the comma immediately after "haben"
    /// was, independently and correctly, an ACCEPTED punctuation deletion
    /// (a legitimate cosmetic edit) — so it never made it into the output.
    /// "haben" ends up directly adjacent to whatever candidate token
    /// actually followed ("und"), with no bridging separator, producing
    /// "habenund". This is a general OUTPUT-adjacency defect (any token
    /// whose trailing was calibrated against a neighbor that didn't survive
    /// to sit next to it), not a defect specific to this one shape (the same
    /// mechanism produced "RechtsprechungDatenschutzvorgaben", "etcDann",
    /// "optimalda" in the same replay).
    ///
    /// Rather than special-casing every code path that can produce this
    /// (the restoration-insertion loop above, `trailingFor`'s candidate-walk
    /// bridging, front-of-output restorations), this pass repairs the FINAL
    /// adjacency directly, once, over the fully-assembled output: any
    /// WORD/NUMERIC token immediately followed (empty `trailing`) by another
    /// WORD/NUMERIC token gets a bridging space inserted. The tokenizer's
    /// lossless contract (`EditGuardTokenizer`) guarantees a word token's
    /// trailing is empty ONLY when the source text had it immediately
    /// followed by punctuation (its own separate token) or by nothing (end
    /// of string) — never by another word — so this condition can only ever
    /// fire on a genuine restoration/bridging defect, never on untouched
    /// candidate structure. Punctuation-adjacent trailing is left
    /// untouched: the tokenizer's contract already gets that case right
    /// wherever nothing was dropped, and touching it risks breaking
    /// abbreviations like "a.m" (see `trailingFor`'s own doc comment).
    private static func bridgeGluedWordTokens(_ tokens: [WorkToken]) -> [WorkToken] {
        guard tokens.count > 1 else { return tokens }
        var result = tokens
        for i in 0..<(result.count - 1) {
            guard result[i].trailing.isEmpty,
                  result[i].kind != .punctuation,
                  result[i + 1].kind != .punctuation
            else { continue }
            result[i] = WorkToken(
                text: result[i].text, normalized: result[i].normalized, kind: result[i].kind,
                trailing: " ", sentenceIndex: result[i].sentenceIndex,
                baselineCasingAlternative: result[i].baselineCasingAlternative
            )
        }
        return result
    }

    /// Post-process, sibling to `bridgeGluedWordTokens` (2026-07-17 root-
    /// cause fix): a KEPT/restored token's `trailing` is calibrated against
    /// its SOURCE neighbor. When the guard rejects a punctuation-for-word
    /// substitute and restores the mark in place, the preceding word keeps
    /// the space it had before the LLM's word — not before the mark that
    /// now actually follows it — producing "Excel , PowerPoint". This pass
    /// binds a single-char terminal/separator mark leftward by clearing any
    /// purely-horizontal-whitespace trailing immediately before it.
    ///
    /// Invariant-safety: this only ever CLEARS a trailing when the NEXT
    /// token is punctuation, so `renderingInvariantHolds` (which fails only
    /// between two NON-punctuation tokens) can never trip from this pass,
    /// and the token multiset is unchanged (only whitespace changes) so
    /// `multisetInvariantHolds` is unaffected — the chain's output still
    /// passes through BOTH checks at `rebuild`'s call sites as a backstop.
    private static let horizontalWhitespace: Set<Character> = [" ", "\t", "\u{00A0}"]
    private static let singleCharBindableMarks: Set<String> = [",", ".", ";", ":", "!", "?"]

    private static func bindPunctuationLeft(_ tokens: [WorkToken]) -> [WorkToken] {
        guard tokens.count > 1 else { return tokens }
        var result = tokens
        for i in 0..<(result.count - 1) {
            guard result[i + 1].kind == .punctuation,
                  singleCharBindableMarks.contains(result[i + 1].text),
                  // Bind a mark ONLY to a preceding word/numeric token, never
                  // to a preceding punctuation token: stripping the interior
                  // space of a doubled mark ("guide . ," -> "guide.,") would
                  // defeat collapseDanglingPunctuation, which needs that space
                  // to detect and collapse the dangling pair (it runs AFTER
                  // this pass, on the joined string). Leaving the space lets
                  // "guide . , explaining" collapse to "guide. explaining".
                  result[i].kind != .punctuation,
                  !result[i].trailing.isEmpty,
                  result[i].trailing.allSatisfy({ horizontalWhitespace.contains($0) })
            else { continue }

            // Ellipsis guard: "word ..." is three genuine "." tokens by
            // construction (renderingInvariantHolds' doc comment) — never
            // bind the first dot leftward and strip the space in front of it.
            if result[i + 1].text == ".", i + 2 < result.count,
               result[i + 2].kind == .punctuation, result[i + 2].text == "." {
                continue
            }

            result[i] = WorkToken(
                text: result[i].text, normalized: result[i].normalized, kind: result[i].kind,
                trailing: "", sentenceIndex: result[i].sentenceIndex,
                baselineCasingAlternative: result[i].baselineCasingAlternative
            )
        }
        return result
    }

    /// Fail-closed safety net (bug 2, belt-and-suspenders alongside
    /// `bridgeGluedWordTokens`): the rebuilt output must never glue two
    /// word/numeric tokens together with no separator.
    /// `bridgeGluedWordTokens` repairs the identified general mechanism for
    /// this; this check exists for defense in depth — any residual case
    /// (this one, or one a future change reintroduces) is safer to fail the
    /// WHOLE guard result closed on (falling back to `rulesCleaned`, same as
    /// `multisetInvariantHolds`) than to risk pasting malformed text at the
    /// user's cursor. Never used to loosen or bypass any other check.
    ///
    /// Deliberately does NOT also check for "doubled punctuation" (two
    /// identical adjacent punctuation marks with empty trailing between
    /// them) — that shape is indistinguishable from a legitimate literal
    /// ellipsis ("...", three genuine "." tokens by construction) or a
    /// repeated "!!"/"??" the user actually said; a first version of this
    /// check flagged the ROADMAP-named "scratch" and "10,011" corruption
    /// fixtures as false positives purely because their sentences end in
    /// "...". The doubled-comma failure mode this phase already knows about
    /// (44-10's `fx-mov-filler-de/en`) is handled by `applyMoveRunCoupling`,
    /// not this general net.
    private static func renderingInvariantHolds(_ tokens: [WorkToken]) -> Bool {
        guard tokens.count > 1 else { return true }
        for i in 0..<(tokens.count - 1) {
            if tokens[i].trailing.isEmpty, tokens[i].kind != .punctuation, tokens[i + 1].kind != .punctuation {
                return false
            }
        }
        return true
    }

    /// Post-process: a token accepted via the casing-only substitute path
    /// (`baselineCasingAlternative != nil`) may have been capitalized by
    /// the LLM only because it LOOKED sentence-initial in the candidate.
    /// Once restoration puts a rejected delete/move back in front of it,
    /// it is no longer genuinely sentence-initial — revert to its baseline
    /// spelling. Never touches the ACTUAL first word of a sentence.
    ///
    /// **Linear-adjacency fix (quick task 260719-8am):** this pass runs
    /// LAST, over the fully-assembled `bindPunctuationLeft(bridgeGluedWordTokens(output))`
    /// array — the true rendered structure, after every restoration,
    /// rejection, and rebuild decision has already been applied. The OLD
    /// test asked "is `t.sentenceIndex` the candidate's first-word-of-
    /// sentence?", a question keyed on the CANDIDATE's own sentence
    /// structure — which can disagree with what actually ends up adjacent
    /// to a token in the REBUILT output once a rejected move/delete/insert
    /// shifts what precedes it. Root cause of the "and Now" corruption: a
    /// rejected sentence split left "now" immediately after "interesting
    /// and" in the output, but "now" still carried its candidate
    /// `sentenceIndex` from the (rejected) split, so the OLD test still
    /// treated it as sentence-initial and let it keep the capital. The
    /// FIXED test asks the only question that matters for casing: is this
    /// token genuinely sentence-initial in the OUTPUT, i.e. is it the
    /// first emitted token, or does a sentence-terminal mark (".", "!",
    /// "?") immediately precede it in the output array? Otherwise revert.
    private static let sentenceTerminalMarks: Set<String> = [".", "!", "?"]

    private static func revertSpuriousSentenceInitialCapitalization(_ tokens: [WorkToken]) -> [WorkToken] {
        guard !tokens.isEmpty else { return tokens }
        return tokens.enumerated().map { i, t in
            guard t.kind == .word, let alt = t.baselineCasingAlternative,
                  let firstChar = t.text.first, firstChar.isUppercase,
                  let altFirst = alt.first, altFirst.isLowercase
            else { return t }
            let isGenuinelySentenceInitial = i == 0 ||
                (tokens[i - 1].kind == .punctuation && sentenceTerminalMarks.contains(tokens[i - 1].text))
            guard !isGenuinelySentenceInitial else { return t }
            return WorkToken(text: alt, normalized: t.normalized, kind: t.kind, trailing: t.trailing, sentenceIndex: t.sentenceIndex, baselineCasingAlternative: nil)
        }
    }


    /// Part C step 6: the rebuilt token multiset must equal
    /// `baselineMultiset - acceptedDeletions + acceptedInsertions`, with
    /// accepted substitutions swapped. Punctuation is excluded — this
    /// invariant is about WORDS, not formatting. `.move` always
    /// contributes exactly one occurrence regardless of verdict (accepted
    /// -> lands at the target; rejected -> restored at the origin) since a
    /// move never changes token count.
    private static func multisetInvariantHolds(edits: [Edit], verdicts: [ClassifiedEdit], output: [WorkToken]) -> Bool {
        var expected: [String: Int] = [:]
        for (i, edit) in edits.enumerated() {
            let v = verdicts[i]
            switch edit.kind {
            case .keep:
                if let t = edit.to, t.kind != .punctuation { expected[t.normalized, default: 0] += 1 }
            case .substitute:
                let t = v.accepted ? edit.to : edit.from
                if let t, t.kind != .punctuation { expected[t.normalized, default: 0] += 1 }
            case .insert:
                if v.accepted, let t = edit.to, t.kind != .punctuation { expected[t.normalized, default: 0] += 1 }
            case .delete:
                if !v.accepted, let t = edit.from, t.kind != .punctuation { expected[t.normalized, default: 0] += 1 }
            case .move:
                let t = v.accepted ? edit.to : edit.from
                if let t, t.kind != .punctuation { expected[t.normalized, default: 0] += 1 }
            }
        }
        var actual: [String: Int] = [:]
        for t in output where t.kind != .punctuation {
            actual[t.normalized, default: 0] += 1
        }
        return expected == actual
    }

    /// Post-merge gate fix (bug 3): true iff exactly one of `from`/`to` is a
    /// mood-indicating terminal mark (`?`/`!`) — i.e. the substitute
    /// introduces OR removes a question/exclamation mark, as opposed to a
    /// mood-neutral punctuation change (e.g. `.`->`,`, which is unrelated to
    /// D-04's mood-lock and must NOT be swept up by this pass).
    private static let moodMarks: Set<String> = ["?", "!"]

    private static func isMoodMarkChange(from: String, to: String) -> Bool {
        moodMarks.contains(from) != moodMarks.contains(to)
    }

    private static func firstWordToken(_ tokens: [Token], sentenceIndex: Int) -> Token? {
        tokens.first { $0.sentenceIndex == sentenceIndex && $0.kind == .word }
    }

    private static func firstWordToken(_ tokens: [WorkToken], sentenceIndex: Int) -> WorkToken? {
        tokens.first { $0.sentenceIndex == sentenceIndex && $0.kind == .word }
    }

    /// Diffs already computed (`edits`) and classified (`classified`)
    /// elsewhere — `rebuild` reconstructs the final text from the baseline
    /// plus only the approved edits, and runs the mood-lock second pass
    /// (D-04 exception 1).
    ///
    /// Extends the plan's documented `-> String?` shape to `(text:
    /// classified:)?` — the mood-lock pass can flip a `.move` from
    /// accepted to `moodLockSentenceInitialVerb` reject AFTER `classify`
    /// runs, and D-11's forensics log needs the FINAL verdict, not the
    /// stale pre-mood-lock one. Also takes `language`, absent from the
    /// plan's literal signature but required by the mood-lock's
    /// `FiniteVerbCues` lookup and the article-agreement coupling pass —
    /// both necessary for correctness, documented as a deviation in
    /// `44-10-SUMMARY.md`.
    ///
    /// - Returns: `nil` when the multiset invariant fails to hold after
    ///   every pass — `apply` treats `nil` as fail-closed
    ///   (`failClosedReason == "rebuildInvariant"`).
    public static func rebuild(
        baseline: [Token],
        candidate: [Token],
        edits: [Edit],
        classified: [ClassifiedEdit],
        language: String
    ) -> (text: String, classified: [ClassifiedEdit])? {
        guard edits.count == classified.count else { return nil }

        var verdicts = classified
        applyInsertRunCoupling(edits: edits, verdicts: &verdicts)
        applyMoveRunCoupling(edits: edits, verdicts: &verdicts)
        applyArticleAgreementCoupling(edits: edits, verdicts: &verdicts, language: language)
        applyAdjacentDeletionSubstituteCoupling(edits: edits, verdicts: &verdicts)
        applyAtomicGroupCoupling(edits: edits, verdicts: &verdicts)

        var tokens = materialize(baseline: baseline, candidate: candidate, edits: edits, verdicts: verdicts)

        // Mood-lock second pass (D-04 exception 1). Bounded to 2 attempts
        // per sentence: first drop only this sentence's accepted MOVEs,
        // then (if still violating) drop every non-keep edit in the
        // sentence. NOT a terminal-punctuation check — see FiniteVerbCues'
        // and D-04's doc comments for why that would miss both observed
        // reorder corruptions.
        let sentenceIndices = Set(baseline.map(\.sentenceIndex)).union(candidate.map(\.sentenceIndex))
        for sentenceIndex in sentenceIndices.sorted() {
            guard let baselineFirst = firstWordToken(baseline, sentenceIndex: sentenceIndex) else { continue }
            let baselineIsFiniteOrModal = FiniteVerbCues.isFiniteOrModal(baselineFirst.normalized, language: language)
            var moodLockFiredForSentence = false

            for attempt in 0..<2 {
                guard let rebuiltFirst = firstWordToken(tokens, sentenceIndex: sentenceIndex) else { break }
                let violates = FiniteVerbCues.isFiniteOrModal(rebuiltFirst.normalized, language: language) && !baselineIsFiniteOrModal
                guard violates else { break }
                moodLockFiredForSentence = true

                for i in edits.indices {
                    let touchesSentence = edits[i].from?.sentenceIndex == sentenceIndex || edits[i].to?.sentenceIndex == sentenceIndex
                    guard touchesSentence, verdicts[i].accepted else { continue }
                    if attempt == 0 {
                        guard edits[i].kind == .move else { continue }
                    } else {
                        guard edits[i].kind != .keep else { continue }
                    }
                    verdicts[i] = ClassifiedEdit(
                        kind: verdicts[i].kind, from: verdicts[i].from, to: verdicts[i].to,
                        accepted: false, acceptClass: nil,
                        rejectClass: RejectionClass.moodLockSentenceInitialVerb.rawValue
                    )
                }
                applyAtomicGroupCoupling(edits: edits, verdicts: &verdicts)
                tokens = materialize(baseline: baseline, candidate: candidate, edits: edits, verdicts: verdicts)
            }

            // Post-merge gate fix (bug 3): attempt 0 dropping only the
            // sentence's accepted MOVEs is often sufficient to fix the
            // sentence-initial violation on its own — the loop then breaks
            // WITHOUT ever reaching attempt 1, which is the only place that
            // would also revert a co-occurring accepted terminal-punctuation
            // substitute. But a verb-fronting reorder and a "."->"?"/"!"
            // punctuation change are the SAME mood-flip corruption's two
            // halves (D-04's "You can push" -> "Can you push" / "Er kommt
            // morgen." -> "Kommt er morgen?" both retarget mood); once the
            // move that caused the violation is reverted, an accepted
            // punctuation substitute that INTRODUCED a question/exclamation
            // mark in this sentence is now orphaned — it "repairs" a mood
            // flip that no longer exists post-revert — and must revert too,
            // regardless of which attempt actually fixed the violation.
            if moodLockFiredForSentence {
                var punctuationReverted = false
                for i in edits.indices {
                    guard edits[i].kind == .substitute, verdicts[i].accepted,
                          let a = edits[i].from, let b = edits[i].to,
                          a.kind == .punctuation, b.kind == .punctuation,
                          a.sentenceIndex == sentenceIndex || b.sentenceIndex == sentenceIndex,
                          isMoodMarkChange(from: a.text, to: b.text)
                    else { continue }
                    verdicts[i] = ClassifiedEdit(
                        kind: verdicts[i].kind, from: verdicts[i].from, to: verdicts[i].to,
                        accepted: false, acceptClass: nil,
                        rejectClass: RejectionClass.moodLockSentenceInitialVerb.rawValue
                    )
                    punctuationReverted = true
                }
                if punctuationReverted {
                    applyAtomicGroupCoupling(edits: edits, verdicts: &verdicts)
                    tokens = materialize(baseline: baseline, candidate: candidate, edits: edits, verdicts: verdicts)
                }
            }
        }

        guard multisetInvariantHolds(edits: edits, verdicts: verdicts, output: tokens) else {
            return nil
        }
        guard renderingInvariantHolds(tokens) else {
            return nil
        }

        let text = tokens.map { $0.text + $0.trailing }.joined()
        return (text, verdicts)
    }
}
