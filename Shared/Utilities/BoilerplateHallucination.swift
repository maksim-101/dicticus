import Foundation

/// Pure whole-utterance boilerplate-hallucination discard predicate — quick task
/// 260827-81z. Closes a measured class: 10 of 959 raw macOS decodes over 14 days were
/// pause hallucinations (1.04%), and 9 of those 10 were the exact whole utterance
/// "Thank you.", with no legitimate standalone "Thank you." dictation anywhere in the
/// corpus. NoSpeechDiscard cannot catch these — a CONFIDENT Whisper hallucination has a
/// LOW noSpeechProb by construction (WHISP-03 cycle 2).
///
/// Mirrors `NoSpeechDiscard`'s shape: a plain `enum` namespace, no state, no platform
/// imports, directly unit-testable. Lives in `Shared/` for the same reason
/// `NoSpeechDiscard` does — a Whisper-specific predicate with a shared test target and
/// therefore a single test copy — and is called only from macOS (iOS runs Parakeet and
/// does not exhibit this hallucination class).
///
/// **Hard constraint: no threshold of any kind.** This is a string comparison and
/// nothing else — no confidence, avgLogprob, noSpeechProb, compression ratio,
/// temperature, energy, RMS, or frame count is read anywhere in this file. General
/// confidence gating was measured and rejected in spike 260805-qx7 (brand mishearings
/// score deeper than garbles, recall 28.6%).
///
/// Matching semantics, pinned:
/// - Trim leading/trailing whitespace and newlines, then compare for EXACT string
///   equality against the closed list below. No lowercasing, no punctuation stripping,
///   no substring search, no prefix/suffix matching, no normalisation.
/// - Case-sensitive: Whisper emits its subtitle boilerplate verbatim with
///   training-data casing; case-insensitive matching would widen the discard surface
///   with zero measured recall gain.
/// - An empty or whitespace-only input returns nil.
enum BoilerplateHallucination {

    /// The closed ship list. Exactly these five entries — widening this list is a
    /// deliberate, reviewed edit (see `BoilerplateHallucinationTests.testShipListIsExactlyFiveEntries`),
    /// not silent drift.
    ///
    /// Deliberately EXCLUDED, and said here so a future widening is a reviewed edit:
    /// - Year-stamped subtitle credits (e.g. the ZDF `Untertitelung` family) — the
    ///   year-variant space is unbounded and brittle, and there is no local evidence
    ///   for them.
    /// - Bare `Vielen Dank.` and `Danke.` — both are plausible real German dictations;
    ///   there is zero measured evidence they are hallucinated, and the false-positive
    ///   cost of blocking them is a lost dictation.
    static let shipList: Set<String> = [
        "Thank you.",                    // 9 of 10 measured live pause hallucinations
        "Thanks for watching!",          // canonical Whisper YouTube-subtitle boilerplate
        "Thank you for watching.",       // canonical Whisper YouTube-subtitle boilerplate
        "Please subscribe to my channel.", // canonical Whisper YouTube-subtitle boilerplate
        "Vielen Dank fürs Zuschauen."     // canonical Whisper YouTube-subtitle boilerplate (German)
    ]

    /// Returns the matched ship-list phrase when `text`, trimmed of leading/trailing
    /// whitespace and newlines, is an EXACT match for one of `shipList`'s entries.
    /// Returns nil otherwise, including for an empty or whitespace-only input.
    ///
    /// Returning the matched phrase (rather than a `Bool`) is what makes the discard
    /// log record auditable: the caller can log which boilerplate class fired.
    static func match(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return shipList.contains(trimmed) ? trimmed : nil
    }
}
