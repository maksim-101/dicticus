import Foundation
import NaturalLanguage

/// Phase 44 Plan 07 (D-06's optional widener): measures Apple `NLTagger`'s
/// German `.lexicalClass` accuracy against this project's own dictation
/// corpus, and ships the result behind a compile-time gate.
///
/// **Design decision, recorded in `44-07-PLAN.md`'s objective (a deliberate
/// deviation from `44-RESEARCH.md`'s Standard Stack):** RESEARCH proposed
/// `NLTagger.lexicalClass` as the PRIMARY mechanism for D-06's
/// content-vs-function split, while flagging its German accuracy as
/// unmeasured, unbenchmarked, and load-bearing (Pitfall 4). Betting the
/// guard's correctness on an unmeasured closed-source classifier is exactly
/// the class of decision Phase 44 exists to undo.
///
/// D-06's real mechanism is the closed `FunctionWords.isInsertable`
/// allowlist (44-03) — precise by construction; its only failure mode is a
/// MISSED insertion repair, the safe direction under this project's
/// standing rule ("acceptable failure mode = miss, never corrupt or
/// invent"). `PosTagger` is never consulted by `EditGuard` as a
/// replacement for that allowlist — only (in 44-10, NOT this plan) as an
/// optional WIDENER on top of it. A widener can only ever cause an
/// insertion to be ACCEPTED that the closed list would have rejected, so it
/// can only ADD corruption risk, never remove it. It therefore ships
/// DISABLED unless `measureAgreement` reports its DANGEROUS-direction error
/// rate (`contentMisclassifiedAsFunction`) at EXACTLY ZERO.
///
/// `isFunctionWord` returns `Bool?`. `nil` means "no opinion" (tagger
/// unavailable for this language, or the token could not be located in the
/// sentence) and MUST be treated by every caller as "fall through to the
/// closed list" — `nil` must never be coerced to `true`.
///
/// NLTagger's base-form-reduction API is NOT used anywhere in this file
/// (pinned by an acceptance grep in `44-07-PLAN.md`) — two independently
/// evaluated stemmers already false-accept the exact corruptions D-02
/// blocks; a closed-source base-form reducer with no published German
/// benchmark is not a better oracle. `InflectionRules` (44-04) owns
/// word-identity ownership across inflected forms.
///
/// `@MainActor`: matches `SentenceAligner`'s precedent — `NaturalLanguage`
/// usage in this codebase is isolated to `@MainActor` call sites.
@MainActor
public enum PosTagger {

    // MARK: - Compile-time ship gate

    /// Whether `isFunctionWord`'s verdict may WIDEN the closed
    /// `FunctionWords.isInsertable` allowlist (D-06) in `EditGuard`. Copies
    /// the `SelfCorrectionResolver.enableScratchCommand` pattern
    /// (`SelfCorrectionResolver.swift:1450`): a `private(set)` — actually
    /// `public` here since 44-10 reads it from `EditGuard` — compile-time
    /// flag gates a call site that stays fully in place,
    /// reachable-but-disabled.
    ///
    /// DEFAULT / SHIPPED VALUE: `false`.
    ///
    /// **Measured 2026-07-12** (see `44-NLTAGGER-PROBE.md` for the full
    /// report): `PosTagger.measureAgreement(GermanPosProbeFixtures.sentences,
    /// language: "de")` on 200 real German dictation sentences from this
    /// project's own qwen-era corpus reported
    /// `contentMisclassifiedAsFunction == 54` (of 948 known-content tokens,
    /// a 5.70% dangerous-direction error rate) — NOT zero. Manually
    /// confirmed genuine (not merely a ground-truth-heuristic artifact):
    /// `NLTagger` tags the plain attributive adjective `"vielversprechende"`
    /// ("promising") as `.pronoun`, which would let `EditGuard` accept it as
    /// an inserted function word. This is exactly the corruption class D-06
    /// exists to block.
    ///
    /// Re-enabling this flag requires re-running the probe (adding fresh
    /// corpus records is fine; do not hand-edit the fixture to remove
    /// failing cases) and observing `contentMisclassifiedAsFunction == 0`.
    /// `PosTaggerProbeTests.testNLTaggerWideningFlagIsBoundToTheEvidence`
    /// pins this flag to the measurement in BOTH directions — it cannot be
    /// flipped to `true` without that evidence, and it cannot silently
    /// drift stale if a future OS update changes NLTagger's German model
    /// (the test goes red first, forcing a decision).
    ///
    /// Flipping this to `true` can only ever ADD accepted insertions to
    /// D-06 (never remove any) — `functionMisclassifiedAsContent` (the
    /// SAFE direction, a missed repair) does NOT gate this flag; only the
    /// dangerous direction does.
    public static let enableNLTaggerFunctionWidening = false

    // MARK: - Widener predicate

    /// NLTagger's per-token function/content verdict for `token` within
    /// `sentence`.
    ///
    /// - Returns: `true` for `.determiner`, `.preposition`, `.conjunction`,
    ///   `.particle`, `.pronoun` (function classes); `false` for `.noun`,
    ///   `.verb`, `.adjective`, `.adverb`, `.number` (content classes);
    ///   `nil` when the German `.lexicalClass` asset is unavailable
    ///   (`NLTagger.availableTagSchemes(for:language:)` does not list
    ///   `.lexicalClass`), the token cannot be located in `sentence`, or the
    ///   resolved tag is outside both lists (`.interjection`, `.otherWord`,
    ///   `.idiom`, punctuation/whitespace tags) — ambiguous tags are "no
    ///   opinion", never coerced toward either verdict.
    ///
    /// - Parameters:
    ///   - token: surface-form token to classify (case-insensitive match
    ///     against the sentence).
    ///   - sentence: the full sentence `token` occurs in — `NLTagger`
    ///     classifies in context, so the token cannot be tagged in
    ///     isolation.
    ///   - language: BCP-47-ish tag; first 2 letters used, `"en"` ->
    ///     `.english`, anything else -> `.german` (mirrors
    ///     `FillerWordRemover.fillerSet(for:)`).
    public static func isFunctionWord(_ token: String, in sentence: String, language: String) -> Bool? {
        let nlLanguage = self.nlLanguage(for: language)
        guard NLTagger.availableTagSchemes(for: .word, language: nlLanguage).contains(.lexicalClass) else {
            return nil
        }
        guard !sentence.isEmpty else { return nil }

        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = sentence
        tagger.setLanguage(nlLanguage, range: sentence.startIndex..<sentence.endIndex)

        let lowerToken = token.lowercased()
        var foundTag: NLTag?
        tagger.enumerateTags(
            in: sentence.startIndex..<sentence.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, range in
            if sentence[range].lowercased() == lowerToken {
                foundTag = tag
                return false // stop — first occurrence wins
            }
            return true
        }

        guard let tag = foundTag else { return nil }
        if functionTags.contains(tag) { return true }
        if contentTags.contains(tag) { return false }
        return nil
    }

    private static let functionTags: Set<NLTag> = [.determiner, .preposition, .conjunction, .particle, .pronoun]
    private static let contentTags: Set<NLTag> = [.noun, .verb, .adjective, .adverb, .number]

    private static func nlLanguage(for language: String) -> NLLanguage {
        language.prefix(2).lowercased() == "en" ? .english : .german
    }

    // MARK: - Probe

    /// The measurement this plan exists to produce. Counts are ONE bucket
    /// each — `functionMisclassifiedAsContent`/`contentMisclassifiedAsFunction`
    /// are only incremented when `isFunctionWord` returns a non-`nil`
    /// verdict; `taggerUnavailable` counts the `nil` ("no opinion") cases
    /// separately, since abstention is not an error.
    public struct ProbeResult: Sendable {
        /// `knownFunctionWords + knownContentWords` — tokens for which this
        /// probe has a ground-truth answer AND the tagger gave an opinion.
        public let total: Int
        /// Tokens with closed-list-backed FUNCTION ground truth
        /// (`FunctionWords.isSubstitutable` ∪ `PronounPersonMap.isPronoun`)
        /// for which the tagger gave a verdict.
        public let knownFunctionWords: Int
        /// Tokens with heuristic CONTENT ground truth (≥6 chars, not on any
        /// closed list, not digit-bearing) for which the tagger gave a
        /// verdict.
        public let knownContentWords: Int
        /// SAFE direction: a known function word the tagger called content.
        /// Costs a missed D-06 insertion repair — never a corruption.
        public let functionMisclassifiedAsContent: Int
        /// DANGEROUS direction: a known content word the tagger called a
        /// function word. Would let `EditGuard` accept an invented
        /// noun/verb/adjective/adverb/number as an "insertable function
        /// word" — this is the number the ship gate is bound to.
        public let contentMisclassifiedAsFunction: Int
        /// Known tokens (function or content) for which `isFunctionWord`
        /// returned `nil` — excluded from both misclassification counts,
        /// tracked separately since abstention is not an error.
        public let taggerUnavailable: Int

        public init(
            total: Int,
            knownFunctionWords: Int,
            knownContentWords: Int,
            functionMisclassifiedAsContent: Int,
            contentMisclassifiedAsFunction: Int,
            taggerUnavailable: Int
        ) {
            self.total = total
            self.knownFunctionWords = knownFunctionWords
            self.knownContentWords = knownContentWords
            self.functionMisclassifiedAsContent = functionMisclassifiedAsContent
            self.contentMisclassifiedAsFunction = contentMisclassifiedAsFunction
            self.taggerUnavailable = taggerUnavailable
        }
    }

    /// Measures NLTagger's agreement with two closed-form ground-truth
    /// definitions over `sentences`:
    ///
    /// - Known FUNCTION truth: `FunctionWords.isSubstitutable(token,
    ///   language:)` (closed allowlist, D-02's function<->function
    ///   substitution set, a superset of D-06's insertion set) OR
    ///   `PronounPersonMap.isPronoun(token, language:)` — ground truth BY
    ///   CONSTRUCTION, these are hand-curated closed lists.
    /// - Known CONTENT truth: the token is >= 6 characters AND not on
    ///   either closed list above AND not digit-bearing
    ///   (`EditGuardTokenizer.isDigitBearing`). **This is a HEURISTIC, not a
    ///   ground truth** — a long German token absent from the closed
    ///   function-word lists is OVERWHELMINGLY a noun/verb/adjective/adverb
    ///   in dictation, but the closed lists only cover PERSONAL pronouns
    ///   and the D-02/D-06 function-word set, not demonstrative pronouns
    ///   (`dieser`/`diesem`), possessive pronouns (`meinen`/`deiner`),
    ///   relative pronouns (`welche`), inflected modal-verb forms
    ///   (`kannst`/`solltest` — only the base forms `kann`/`soll` are
    ///   listed), or compound prepositions (`aufgrund`). A hand spot-check
    ///   of 20 tokens classified "content" by this heuristic is reported in
    ///   `44-NLTAGGER-PROBE.md`, and it found real residual imprecision —
    ///   stated honestly there, not smoothed over.
    ///
    /// Tokens matching neither definition are skipped, not counted.
    public static func measureAgreement(_ sentences: [String], language: String) -> ProbeResult {
        var knownFunctionWords = 0
        var knownContentWords = 0
        var functionMisclassifiedAsContent = 0
        var contentMisclassifiedAsFunction = 0
        var taggerUnavailable = 0

        for sentence in sentences {
            let tokens = EditGuardTokenizer.tokenize(sentence).filter { $0.kind == .word }
            for token in tokens {
                let isKnownFunction = FunctionWords.isSubstitutable(token.normalized, language: language)
                    || PronounPersonMap.isPronoun(token.normalized, language: language)
                let isKnownContent = !isKnownFunction
                    && token.normalized.count >= 6
                    && !EditGuardTokenizer.isDigitBearing(token.text)

                guard isKnownFunction || isKnownContent else { continue }

                guard let verdict = isFunctionWord(token.text, in: sentence, language: language) else {
                    taggerUnavailable += 1
                    continue
                }

                if isKnownFunction {
                    knownFunctionWords += 1
                    if verdict == false {
                        functionMisclassifiedAsContent += 1
                    }
                } else {
                    knownContentWords += 1
                    if verdict == true {
                        contentMisclassifiedAsFunction += 1
                    }
                }
            }
        }

        return ProbeResult(
            total: knownFunctionWords + knownContentWords,
            knownFunctionWords: knownFunctionWords,
            knownContentWords: knownContentWords,
            functionMisclassifiedAsContent: functionMisclassifiedAsContent,
            contentMisclassifiedAsFunction: contentMisclassifiedAsFunction,
            taggerUnavailable: taggerUnavailable
        )
    }
}
