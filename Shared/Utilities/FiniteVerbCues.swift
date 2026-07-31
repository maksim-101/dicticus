import Foundation

/// Phase 44 Plan 03 (D-04): the closed DE/EN modal/auxiliary + finite-suffix
/// cue table behind the mood-lock. `NLTagger`'s `.verb` lexical class makes
/// no finite/infinitive/modal distinction (44-RESEARCH.md report 01 §1:
/// "CANNOT satisfy requirement (c) because it does not distinguish finite
/// verbs or modals from infinitives"), so this is a hand-curated
/// closed-list-plus-suffix-heuristic lookup.
///
/// DIVISION OF LABOUR: this file only answers "is this token finite-or-
/// modal?" It does NOT decide whether a MOVE is a mood-lock violation — that
/// comparison (was the baseline's first token finite/modal? is the
/// candidate's first token finite/modal when the baseline's wasn't?) lives
/// in `EditGuard` (plan 44-10). A German sentence that legitimately starts
/// with a finite verb (a genuine yes/no question, or an imperative) is NOT
/// rejected by this file — the sentence-initial-position comparison is
/// EditGuard's job, not this file's. Do not re-implement that comparison
/// here.
///
/// RISK DIRECTION (deliberate — do not "fix" by adding disambiguation):
/// over-inclusion costs a rejected MOVE, i.e. a missed legitimate
/// word-order repair. Under-inclusion costs a statement silently turned
/// into a question or a command (the logged `"You can push"` ->
/// `"Can you push"` corruption, corpus 2026-07-11T04:26:02.697Z). The
/// asymmetry is decisive: this table fires on suspicion. German `-en` is
/// structurally ambiguous between infinitive and finite-plural on the
/// surface form alone — this is undecidable without full parsing, and this
/// file deliberately does NOT attempt to disambiguate it.
///
/// Pure lookup — no state, no actor isolation, no `NaturalLanguage` import.
public enum FiniteVerbCues {

    // MARK: - Modal + auxiliary finite forms

    /// German modal + auxiliary finite forms. 46 entries — see
    /// `ClosedListTests.testMoodLockCuesShipList`.
    public static let germanModalsAndAuxiliaries: Set<String> = [
        // Modal finite forms
        "kann", "kannst", "könnt", "können",
        "muss", "musst", "müsst", "müssen",
        "soll", "sollst", "sollt", "sollen",
        "will", "willst", "wollt", "wollen",
        "darf", "darfst", "dürft", "dürfen",
        "mag", "magst", "mögt", "mögen",
        // Auxiliary finite forms
        "ist", "bist", "sind", "seid", "bin",
        "war", "warst", "waren", "wart",
        "hat", "hast", "habt", "haben",
        "hatte", "hattest", "hatten",
        "wird", "wirst", "werdet", "werden",
        "wurde", "wurden"
    ]

    /// English modal + auxiliary finite forms. 20 entries — see
    /// `ClosedListTests.testMoodLockCuesShipList`.
    public static let englishModalsAndAuxiliaries: Set<String> = [
        "can", "could", "must", "should", "shall", "will", "would", "may", "might",
        "is", "are", "am", "was", "were",
        "do", "does", "did",
        "have", "has", "had"
    ]

    // MARK: - Irregular finite forms the suffix heuristic misses

    /// High-frequency German irregular finite verbs whose surface form the
    /// suffix heuristic below misses (short forms and stem-change forms).
    public static let germanIrregularFiniteForms: Set<String> = [
        "gibt", "geht", "steht", "kommt", "nimmt", "sieht", "liest",
        "spricht", "fährt", "läuft", "trägt", "hält", "weiss", "weiß"
    ]

    /// English finite forms the bare `-s` heuristic misses (irregular
    /// 3rd-person-singular spellings). English finite forms are mostly
    /// bare-stem or `-s`; this list covers the rest.
    public static let englishIrregularFiniteForms: Set<String> = [
        "goes", "gives", "says", "makes", "takes", "gets", "knows"
    ]

    /// Regular German finite-verb suffixes. Deliberately does NOT include a
    /// rule to distinguish infinitive `-en` from finite-plural `-en` — see
    /// the type-level doc comment.
    public static let germanFiniteSuffixes: [String] = ["e", "st", "t", "en", "et", "te", "ten"]

    // MARK: - Public API

    /// Is `token` finite-or-modal? Fires on suspicion — over-inclusion by
    /// design, see the type-level RISK DIRECTION doc comment.
    ///
    /// - Parameters:
    ///   - token: surface-form token; lowercased internally.
    ///   - language: BCP-47-ish tag; first 2 letters used, `"en"` -> English,
    ///     anything else -> German (mirrors `FillerWordRemover.fillerSet(for:)`).
    public static func isFiniteOrModal(_ token: String, language: String) -> Bool {
        let lower = token.lowercased()
        let prefix = language.prefix(2).lowercased()

        if prefix == "en" {
            if englishModalsAndAuxiliaries.contains(lower) || englishIrregularFiniteForms.contains(lower) {
                return true
            }
            // Bare `-s` heuristic for regular 3rd-person-singular forms.
            return lower.count >= 4 && lower.hasSuffix("s")
        }

        // German (default).
        if germanModalsAndAuxiliaries.contains(lower) || germanIrregularFiniteForms.contains(lower) {
            return true
        }
        guard lower.count >= 4 else { return false }
        return germanFiniteSuffixes.contains { lower.hasSuffix($0) }
    }
}
