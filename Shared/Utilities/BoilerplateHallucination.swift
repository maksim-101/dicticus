import Foundation

/// Pure whole-utterance boilerplate-hallucination discard predicate — quick task
/// 260827-81z. Closes a measured class: about 1% of raw macOS decodes were pause
/// hallucinations, nearly all of them the exact whole utterance "Thank you.", with no
/// legitimate standalone "Thank you." dictation in the measured set. NoSpeechDiscard cannot catch these — a CONFIDENT Whisper hallucination has a
/// LOW noSpeechProb by construction (WHISP-03 cycle 2).
///
/// Mirrors `NoSpeechDiscard`'s shape: a plain `enum` namespace, no state, no platform
/// imports, directly unit-testable. Lives in `Shared/` for the same reason
/// `NoSpeechDiscard` does — a Whisper-specific predicate with a shared test target and
/// therefore a single test copy — and is called only from macOS (iOS runs Parakeet and
/// does not exhibit this hallucination class). That holds for both lists below.
///
/// **Hard constraint: no threshold of any kind.** This is a string comparison and
/// nothing else — no confidence, avgLogprob, noSpeechProb, compression ratio,
/// temperature, energy, RMS, or frame count is read anywhere in this file. General
/// confidence gating was measured and rejected in spike 260805-qx7 (brand mishearings
/// score deeper than garbles, recall 28.6%).
///
/// Reviewed amendment (quick task 260930-s1g): `matchShortStock` and ONLY it reads two
/// non-text inputs, both named here so no third can arrive silently. (1) Clip duration,
/// the lever Layer 1's 0.3 s guard and Phase 50's 2.0 s bypass already use; it is not a
/// confidence signal. (2) The Layer-2 gate's already-computed `voiceDetected` Bool. This
/// file reads no energy value and sets no energy threshold; the gate made that call for
/// its own discard decision, and it is not a confidence signal either.
///
/// Reviewed amendment (quick task 261008-gb2): `chunkDropReasons` and ONLY it reads two
/// further non-text inputs, named here so no more can arrive silently. (1) The number of
/// chunks WhisperKit returned for the clip (a long clip is decoded as one result per
/// voice-activity chunk). (2) Each chunk's detected language code. Neither is a confidence
/// or energy signal. The prohibition list above stays in force word for word. The
/// per-chunk path removes one leading "-" before comparing (the measured leading-dash
/// form of the phantom); whole-clip `match` keeps its pinned no-normalisation semantics.
/// Still called only from macOS.
///
/// Matching semantics, pinned (for `shipList`; `matchShortStock` compares lowercased, see below):
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
        "Thank you.",                    // the measured live pause hallucination
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

    /// Closed short list (quick task 260930-s1g): a lone "you", "and" or "-" that Whisper
    /// decodes from a stray short key press or from a recording in which the voice gate
    /// heard nothing. Compared lowercased against the trimmed whole utterance. Widening
    /// is a reviewed edit (`testShortStockListIsExactlyThreeEntries`).
    ///
    /// Measured over the macOS discard logs: no false positives; no standalone
    /// "you"/"and"/"-" that a speaker meant appears in the cleanup records.
    /// Deliberately EXCLUDED:
    /// punctuated forms (`You.`, `And.`) on both arms, since a person can plausibly
    /// dictate them, and energy or VAD AND-terms on the duration arm, which did not
    /// separate the hits from anything.
    static let shortStockList: Set<String> = ["you", "and", "-"]

    /// Duration-arm bound, exclusive. The measured duration-arm hits last
    /// 1.1-1.3 s; genuine one-word dictations (`Okay.`, `Done.`, `Yes.`) are
    /// outside the set at any length.
    static let shortStockMaxDurationSeconds: Float = 1.5

    /// Returns the trimmed text when it is, lowercased, a member of `shortStockList` AND
    /// (`durationSeconds < shortStockMaxDurationSeconds` OR the gate found no voice).
    /// Set membership is required on both arms; the two conditions are an OR. Returns nil
    /// otherwise, including for an empty or whitespace-only input.
    ///
    /// - Duration arm: the measured hits last 1.1-1.3 s.
    /// - No-voice arm: `voiceDetected == false` is exactly a logged `vad_true_frame_count`
    ///   of 0, because `AdaptiveVoiceGate.evaluate` sets `voiceDetected` to
    ///   `maxFrameEnergy > threshold` and the count is the number of frames above that
    ///   threshold. Among the no-voice pass records only these phantoms hit; the
    ///   others decode to several tokens and are untouched. These clips reach Whisper only through Phase 50 D-01's duration
    ///   bypass, so for these three tokens this arm is that bypass's backstop.
    static func matchShortStock(_ text: String, durationSeconds: Float, voiceDetected: Bool) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, shortStockList.contains(trimmed.lowercased()) else { return nil }
        guard durationSeconds < shortStockMaxDurationSeconds || !voiceDetected else { return nil }
        return trimmed
    }

    /// Why `chunkDropReasons` removed one chunk of a decode.
    enum ChunkDropReason: String {
        case boilerplateSegment
        case nonDeEnLanguage
    }

    /// Languages a chunk may be tagged with and still be kept. Dicticus dictates German
    /// and English; Whisper tags a chunk with a third language only when it garbles or
    /// hallucinates.
    static let chunkLanguages: Set<String> = ["de", "en"]

    /// Per-chunk drop (quick task 261008-gb2, F1 and F2). `match` compares the joined clip
    /// text, so a pause phantom that is one chunk of a long clip ("... real speech" +
    /// "Thank you.") is invisible to it.
    ///
    /// F1: for a decode of two or more chunks, a chunk whose text, trimmed and with one
    /// leading "-" removed, is exactly a ship-list phrase gets `.boilerplateSegment`. A sole
    /// chunk is left to the whole-clip `match`. A ship-list phrase inside a longer chunk
    /// never matches. Measured over the macOS discard logs: non-sole ship-list chunks
    /// are rare among multi-chunk passes, and no genuinely dictated "thank you" sits
    /// alone in a chunk.
    ///
    /// F2: a chunk whose language is not in `chunkLanguages` gets `.nonDeEnLanguage`, at any
    /// chunk count. Measured over the same logs: such chunks are rare (a sole non-Latin
    /// clip the non-Latin check already refused, a sole Spanish-tagged clip that was
    /// garbled German speech, a Polish-tagged chunk after German speech). Deliberately no rule for
    /// an "en" chunk inside a "de" clip: code-switching is a supported way to dictate.
    ///
    /// The boilerplate check runs first. Returns one entry per input chunk, in order.
    static func chunkDropReasons(_ chunks: [(text: String, language: String)]) -> [ChunkDropReason?] {
        chunks.map { chunk in
            if chunks.count >= 2 {
                var t = chunk.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.hasPrefix("-") {
                    t = String(t.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if match(t) != nil { return .boilerplateSegment }
            }
            return chunkLanguages.contains(chunk.language) ? nil : .nonDeEnLanguage
        }
    }
}
