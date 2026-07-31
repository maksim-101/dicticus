import Foundation

/// Phase 44 Plan 03 (D-04): the closed DE/EN pronoun -> grammatical-person
/// map behind the pronoun-lock. `NLTagger` exposes no morphological person
/// feature (44-RESEARCH.md report 01 §4: "CANNOT satisfy requirement (d)
/// because it does not expose morphological features like grammatical
/// person"), so this is a hand-curated, closed-list lookup — the same shape
/// as `FunctionWords` and `FiniteVerbCues` in this file group.
///
/// RISK DIRECTION: the pronoun-lock's job is to reject a person CHANGE or a
/// deletion (D-04: "a pronoun may never be deleted nor change person"). A
/// pronoun this map fails to recognize (`isPronoun` false negative) silently
/// disables the lock for that token — the unsafe direction. A word wrongly
/// recognized as a pronoun merely costs an over-strict rejection elsewhere.
/// Keep the map complete for the closed personal-pronoun class; do not widen
/// it to cover possessive determiners or relative pronouns without a
/// reviewed plan update.
///
/// KNOWN GAP (documented, not silently absorbed): German `sie`/`Sie` is
/// genuinely ambiguous between formal 2nd person (`Sie`/`Ihnen`) and 3rd
/// person (`sie` = she/they, `ihnen` = them). Both `sie` and `ihnen` are
/// mapped to `.third` here — a single dictionary key can only carry one
/// value, and the 3rd-person reading is the more frequent one in this
/// user's corpus. Consequence: a formal `Sie` -> `er` substitution reads as
/// same-person (both classify `.third`) and is NOT caught by the
/// pronoun-lock's person-change check — this is an accepted residual
/// false-negative, not a bug to "fix" by guessing formality from casing. A
/// `sie`/`ihnen` -> `ich` substitution IS still caught (`.first` !=
/// `.third`). See `ClosedListTests.testSieAmbiguityIsDocumented`, which
/// pins this decision so a later agent cannot flip it silently.
///
/// Pure lookup — no state, no actor isolation, no `NaturalLanguage` import.
public enum PronounPersonMap {

    public enum Person: Int, Sendable {
        case first = 1
        case second = 2
        case third = 3
    }

    /// German personal pronouns -> grammatical person. 18 entries — see
    /// `ClosedListTests.testGermanPronounShipList`. Formal `sie`/`ihnen`
    /// intentionally appear only under `.third` (see KNOWN GAP above); this
    /// is the sole reason those two tokens are not also listed as `.second`.
    public static let german: [String: Person] = [
        // 1st person
        "ich": .first, "mich": .first, "mir": .first, "wir": .first,
        "uns": .first, "unser": .first,
        // 2nd person (informal du/ihr forms only — see KNOWN GAP)
        "du": .second, "dich": .second, "dir": .second, "ihr": .second,
        "euch": .second,
        // 3rd person (includes formal sie/ihnen — see KNOWN GAP)
        "er": .third, "ihn": .third, "ihm": .third, "sie": .third,
        "es": .third, "ihnen": .third, "sich": .third
    ]

    /// English personal/possessive pronouns -> grammatical person. 19
    /// entries — see `ClosedListTests.testEnglishPronounShipList`.
    public static let english: [String: Person] = [
        // 1st person
        "i": .first, "me": .first, "we": .first, "us": .first,
        "my": .first, "our": .first,
        // 2nd person
        "you": .second, "your": .second, "yours": .second,
        // 3rd person
        "he": .third, "him": .third, "she": .third, "her": .third,
        "it": .third, "they": .third, "them": .third, "his": .third,
        "their": .third, "its": .third
    ]

    // MARK: - Public API

    /// Lowercased lookup. `nil` if `token` is not in the closed pronoun set.
    ///
    /// - Parameters:
    ///   - token: surface-form token; lowercased internally.
    ///   - language: BCP-47-ish tag; first 2 letters used, `"en"` -> English,
    ///     anything else -> German (mirrors `FillerWordRemover.fillerSet(for:)`).
    public static func person(of token: String, language: String) -> Person? {
        let lower = token.lowercased()
        let prefix = language.prefix(2).lowercased()
        return prefix == "en" ? english[lower] : german[lower]
    }

    /// Is `token` in the closed pronoun set for `language`?
    public static func isPronoun(_ token: String, language: String) -> Bool {
        person(of: token, language: language) != nil
    }
}
