import Foundation

/// Phase 20 D-02 Action 2: deterministic rules-first cleanup.
///
/// Thin orchestrator over the three Phase 20 rule utilities. Composition
/// order is fixed and order-sensitive (locked by RulesCleanupServiceTests):
///
///   1. `FillerWordRemover.strip` — remove conservative ship-list fillers.
///      Runs FIRST so a leading `"ähm, …"` is gone before self-correction
///      examines the comma-prefixed connector window.
///   2. `SelfCorrectionResolver.resolve` — drop reparandum tokens before a
///      comma-prefixed connector. Runs after filler so the backward window
///      sees only content tokens.
///   3. `SwissNumberFormatter.foldCurrencyUnits` — collapse spoken-out
///      `"X Franken Y Rappen"` (and EUR/USD/GBP analogs) to canonical
///      glyph-prefixed decimal form. Runs LAST so it operates on already-
///      cleaned digit sequences.
///   4. Whitespace collapse — `\s+` → single space, then trim.
///
/// Idempotency invariant (D-03): `clean(clean(x)) == clean(x)` for every
/// fixture in `RulesCleanup.fixtures.json`. Each utility is individually
/// idempotent, and whitespace collapse trivially is.
///
/// Pure transform — no `@MainActor`, no `@Published`, no I/O. Thread-safe
/// to call from any context.
public final class RulesCleanupService {

    public init() {}

    // Media-bleed artifact regex — strips a trailing standalone "Yeah" / "Mm-hmm" / "Mhm"
    // that appears after auto-stop fires too late. Pattern is $-anchored (no backtracking risk).
    // try! is correct: pattern is a compile-time constant validated in spike ArtifactStrip.
    private static let artifactRegex = try! NSRegularExpression(
        pattern: #"(?:\s+(?:yeah|mm-hmm|mhm))(?<trail>[.!?]?)\s*$"#,
        options: [.caseInsensitive])

    private static func stripTrailingArtifact(_ s: String) -> String {
        let r = NSRange(s.startIndex..<s.endIndex, in: s)
        guard let m = artifactRegex.firstMatch(in: s, options: [], range: r) else { return s }
        guard let range = Range(m.range, in: s) else { return s }
        var head = String(s[s.startIndex..<range.lowerBound])
        // Preserve terminal punctuation if head lacks one and the artifact carried it.
        if let trailRange = Range(m.range(withName: "trail"), in: s),
           !s[trailRange].isEmpty,
           let last = head.last, !".!?".contains(last) {
            head += String(s[trailRange])
        }
        return head
    }

    /// Run the rules-first cleanup pipeline.
    ///
    /// - Parameters:
    ///   - text: post-ITN, pre-LLM input.
    ///   - language: BCP-47-ish code; first 2 chars used for filler /
    ///     self-correction language gating. Currency-fold is language-
    ///     agnostic by design (the tokens themselves disambiguate).
    ///   - skipSelfCorrection: when true, the SelfCorrectionResolver step
    ///     is bypassed. Set by `TextProcessingService` in AI-cleanup mode
    ///     so the V3 LLM prompt can decide for itself whether a
    ///     self-correction is a genuine repair or part of the user's
    ///     intended phrasing — the resolver's deterministic comma-prefixed
    ///     drop conflicts with V3's "preserve self-corrections" rule.
    ///   - enableVoiceCommands: Phase 39/D-07 — the user-facing Settings
    ///     toggle (default ON). Threaded straight through to
    ///     `SelfCorrectionResolver.resolve(...)`, which gates only the new
    ///     scratch-command delete evidence source on it. This is a UX
    ///     escape hatch for users who dictate ABOUT editing — it is NOT
    ///     the safety mechanism; the compile-time gate flags in
    ///     `SelfCorrectionResolver` (`enableScratchCommand`,
    ///     `enableScratchMidUtterance`) are the actual safety mechanism
    ///     and govern shipping independently of this toggle.
    /// - Returns: cleaned text.
    public func clean(_ text: String, language: String, skipSelfCorrection: Bool = false, enableVoiceCommands: Bool = true) -> String {
        var result = FillerWordRemover.strip(text, language: language)
        if !skipSelfCorrection {
            result = SelfCorrectionResolver.resolve(result, language: language, enableVoiceCommands: enableVoiceCommands)
        }
        // Currency-fold is gated on `de` (Swiss/German speakers say
        // "Franken Rappen" / "Euro Cent"). The en-mode contract is that
        // German-flavored input passes through untouched — see
        // `RulesCleanupServiceTests.testLanguageGatingEnglishLeavesGermanFlavoredInputUntouched`.
        // The downstream `SwissNumberFormatter.format` (Step 3b in
        // TextProcessingService) still runs language-agnostically per
        // the existing Swiss-toggle gating.
        if language.prefix(2).lowercased() != "en" {
            result = SwissNumberFormatter.foldCurrencyUnits(result)
        }
        // Whitespace collapse — any run of whitespace → single space; trim.
        let collapsed = result
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        // Trailing-artifact strip — AI mode only (clean(...) is invoked only in
        // the aiCleanup branch of TextProcessingService; plain mode is unaffected).
        let stripped = RulesCleanupService.stripTrailingArtifact(collapsed)
        return stripped.trimmingCharacters(in: .whitespaces)
    }
}
