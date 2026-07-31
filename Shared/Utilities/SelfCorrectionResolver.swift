import Foundation

/// Phase 20 D-02 Action 2: deterministic self-correction resolution.
///
/// Resolves in-stream speech repairs of the shape
/// `"<reparandum>, <connector> <repair>"` by dropping the reparandum and
/// the connector, leaving only the repair. Connector list and design
/// constraints come from CONTEXT.md decision D-02 and the Wave 0 RED
/// suite `iOS/DicticusTests/SelfCorrectionResolverTests.swift`.
///
/// Critical guards (locked by tests + adversarial fixtures):
///   1. **Comma-prefix guard.** The connector MUST be preceded by a
///      comma. Defends against "I mean it" / "Ich meine es ernst" /
///      "or rather not" content phrases.
///   2. **Evidence-only deletion (Phase 43/D-01).** Backward tokens are
///      dropped ONLY when the reparandum is positively identified: either
///      an exact backward-token alignment within the last 6 backward
///      tokens, or a single-same-type typed-value anchor shared with the
///      sentence-boundary path (`singleSameTypeBoundaryValue`). No
///      evidence → abstain, leaving the text byte-identical (safe miss).
///      There is no blind "guess a drop count" fallback anymore.
///   3. **Abort path** when there is no clear repair candidate:
///         a) The connector itself is followed by a comma — but ONLY
///            when the connector is parenthetical-eligible (`I mean`,
///            `ich meine`, `besser gesagt`, etc.). For pure correction
///            markers (`no`, `nein`, `actually`, `eigentlich`, ...)
///            the post-connector comma is just punctuation flanking the
///            interjection ("..., No, it's at..."); we advance past it
///            and continue with the repair.
///         b) The first repair token is a relative / object pronoun
///            that signals a clausal continuation rather than a
///            substitute noun (`I mean what …`, `ich meine es …`).
///      On abort: leave the entire match span untouched. Do NOT drop the
///      connector pair; do NOT drop trailing content tokens.
///
/// Connector lists (case-insensitive):
///   de: `ich meine`, `besser gesagt`, `genauer gesagt`,
///       `oder vielmehr`, `oder besser`, `nein`, `ne`
///   en: `I mean`, `I meant`, `or rather`, `or better`, `scratch that`, `no`, `actually`
///
/// Evidence/abstain algorithm (Phase 43/D-01 — the blind drop-count
/// fallback that used to live here was removed; it deleted backward
/// tokens on failure to find evidence, which was the data-loss bug):
///   1. Find the first repair token (after stripping the whole leading
///      connector chain — Phase 43/D-03).
///   2. Look for that token in the last 6 backward tokens. If found at
///      position `k` from the end (1-indexed), drop `k` tokens. This is
///      the alignment-by-first-repair-token rule that handles all the
///      "X Franken / X Euro" parallel cases cleanly.
///   3. Else, try the shared typed-value anchor (Phase 43/D-07): if the
///      repair side leads with a typed value (digit/clock/price/etc.,
///      optionally preceded by a preposition) and the backward span
///      contains EXACTLY ONE value of that same type, align the drop on
///      that backward value's token position.
///   4. Else, try the shared anchored-noun evidence source (Phase
///      43/43-04/D-04): if the backward span contains a closed
///      copula/possessive frame ("his name is"/"her name is"/"sein Name
///      ist"/"ihr Name ist") immediately followed by the SOLE same-shape
///      proper-noun candidate in the backward span, and the repair side
///      LEADS with a same-shape proper-noun candidate, align the drop on
///      that backward candidate's token position. Gated by
///      `enableAnchoredNoun` — ships disabled (abstain) if it fails its
///      own scale-replay pass (see 43-04-SUMMARY.md for the verdict).
///   5. Else ABSTAIN — leave the text byte-identical (no fallback drop).
///
/// Pure transform — no actors, no state. Idempotent: a second invocation
/// on already-resolved text leaves it unchanged because either the
/// connector is gone or the repair phrase no longer has a comma-prefixed
/// connector.
public enum SelfCorrectionResolver {

    // MARK: - Public API

    /// Production entry point — comma-prefix guard active, non-comma path OFF.
    /// D-03: never corrupt. This is the shipped default; do NOT change its
    /// behavior without clearing the D-05 winner-selection checkpoint.
    ///
    /// 42-07/SELFCORR-02: ALSO runs the spike-012 sentence-boundary path
    /// (`resolveSentenceBoundaryPath`) — BEFORE the comma path — so German
    /// (and unified English) typed-value restatements across a sentence
    /// boundary ("… um 14 Uhr ein Meeting. Nein, es ist um 15 Uhr.") resolve
    /// in production. The comma path itself, and the 4-arg
    /// `enableNonComma`/`enableVerbatimRestatements` overload used by the
    /// Plan-05 spike/harness variants, are unchanged.
    ///
    /// Order matters: boundary-BEFORE-comma is required, not incidental.
    /// The boundary path's own guard (S2 must be entirely
    /// marker+[copula]+[prep]+typedValue+punct) means it ABSTAINS on every
    /// existing comma-path fixture, so running it first is a no-op for all
    /// of them — EXCEPT the exact typed-value-at-a-sentence-boundary shape
    /// it targets, which it now resolves cleanly before the comma path's
    /// own (unrelated, pre-existing) "marker followed by a comma inside a
    /// longer sentence" match can ever see it. Composing the other way
    /// (comma-path first) was verified to corrupt the EN reference capture
    /// "…at 8:00. No, actually it's 9:00." into "…at it's 9:00." — the comma
    /// path's existing `, actually` match fires on the comma that sits
    /// between "No" and "actually" before the boundary path gets a chance.
    ///
    /// - Parameter enableVoiceCommands: Phase 39/D-07 — the user-facing
    ///   Settings toggle (default ON), threaded down from
    ///   `TextProcessingService` through `RulesCleanupService.clean(...)`.
    ///   This is a UX escape hatch for users who dictate ABOUT editing
    ///   (e.g. "scratch that" meant as literal content) — it is NOT the
    ///   safety mechanism. The actual safety mechanism is the compile-time
    ///   `enableScratchCommand`/`enableScratchMidUtterance` gate flags
    ///   above, which govern shipping independently of this runtime
    ///   toggle per the `selfcorr43` scale-replay verdict. Defaulting to
    ///   `true` means every existing call site (harness, tests,
    ///   `containsCorrectionMarker`'s consumers) compiles unchanged and
    ///   exercises the new path by default.
    public static func resolve(_ text: String, language: String, enableVoiceCommands: Bool = true) -> String {
        let boundaryResolved = resolveSentenceBoundaryPath(text, language: language)
        let commaResolved = resolve(
            boundaryResolved,
            language: language,
            enableNonComma: false,
            enableVerbatimRestatements: false
        )
        // Phase 39/D-07: the runtime user toggle gates only the scratch-
        // command sibling pass — it does not disable any of the resolver's
        // pre-existing self-correction evidence sources above.
        guard enableVoiceCommands else { return commaResolved }
        // Phase 39/D-03: the scratch-command delete pass runs LAST, after
        // both the boundary path and the comma path, so it only ever
        // sees spans the existing evidence-or-abstain logic has already
        // declined to touch (see resolveScratchCommandPath's own doc
        // comment for the full placement rationale).
        return resolveScratchCommandPath(commaResolved, language: language)
    }

    /// Spike/harness entry point for Plan 05 variants A and B.
    ///
    /// This overload is intentionally NOT the production default.  Wire
    /// `enableNonComma: true` into the production call-site only after the
    /// D-05 winner-selection checkpoint clears (Task 3 of Plan 05).
    ///
    /// - Parameters:
    ///   - enableNonComma: Variant A — fire on `pureCorrectionConnectors`
    ///     even without a preceding comma.  Gated by: (i) connector is NOT
    ///     at string start (sentence-start guard, Pitfall 5), (ii) backward-
    ///     alignment guard REQUIRED — alignment failure aborts (no fallback
    ///     drop for non-comma fires), (iii) existing abort-pronoun and idiom
    ///     guards remain active.  OFF by default.
    ///   - enableVerbatimRestatements: Variant B — PLUS immediate verbatim-
    ///     restatement collapse `tok tok` where tok length ≥ 2 (EN) / ≥ 3
    ///     (DE).  Has no effect when `enableNonComma` is false.  OFF by
    ///     default.
    public static func resolve(
        _ text: String,
        language: String,
        enableNonComma: Bool,
        enableVerbatimRestatements: Bool
    ) -> String {
        // Verbatim-restatement collapse (Variant B) runs first — it is trivially
        // safe (the duplicate token is its own repair) and independent of the
        // connector logic below.
        var result = text
        if enableNonComma && enableVerbatimRestatements {
            result = collapseVerbatimRestatements(result, language: language)
        }
        // Run the comma-path resolver first (always active).
        result = resolveCommaPath(result, language: language)
        // Optionally run the non-comma path (Variant A/B extension).
        if enableNonComma {
            result = resolveNonCommaPath(result, language: language)
        }
        return result
    }

    /// [42-06/T-42-06] Whole-token / whole-phrase PRESENCE check for a
    /// self-correction connector marker ("no", "actually", "nein",
    /// "eigentlich", "ich meine", ...) anywhere in `text`, for `language`.
    ///
    /// Reuses the same connector lists as `resolve` — does NOT re-run the
    /// comma-prefix/abort-guard resolution pipeline, just detects whether a
    /// marker is present at all. Used by `CleanupService.gatePerSentence`'s
    /// self-correction-aware baseline switch to decide, per gate window,
    /// whether the RAW dictation (rather than the degraded rules-cleaned
    /// baseline) should be used as the gate's reference text.
    ///
    /// Whole-token matching (not substring `.contains`) avoids false
    /// positives on unrelated words that merely contain a marker as a
    /// substring (e.g. the "ne" in "generally" or German "einen").
    public static func containsCorrectionMarker(_ text: String, language: String) -> Bool {
        let tokens = wordTokens(text)
        guard !tokens.isEmpty else { return false }

        for connector in connectorList(for: language) {
            let connectorTokens = wordTokens(connector)
            guard !connectorTokens.isEmpty else { continue }
            if connectorTokens.count == 1 {
                if tokens.contains(connectorTokens[0]) { return true }
            } else if tokens.count >= connectorTokens.count {
                for start in 0...(tokens.count - connectorTokens.count)
                where Array(tokens[start..<(start + connectorTokens.count)]) == connectorTokens {
                    return true
                }
            }
        }
        return false
    }

    /// Lowercased, punctuation-stripped word tokens (splits on any non
    /// letter/digit character) — used only by `containsCorrectionMarker`,
    /// which needs punctuation-insensitive whole-token matching distinct
    /// from the whitespace-only `tokenize(_:)` used by the resolution path.
    private static func wordTokens(_ s: String) -> [String] {
        s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    // MARK: - Private implementation

    /// Original comma-prefix-only resolve path (unchanged logic from the
    /// shipped resolver).  Extracted so `resolveNonCommaPath` can compose
    /// with it cleanly.
    private static func resolveCommaPath(_ text: String, language: String) -> String {
        let connectors = connectorList(for: language)
        let abortPronouns = pronounAbortSet(for: language)
        guard !connectors.isEmpty else { return text }

        // Build the connector alternation. Sort longest-first so multi-word
        // connectors win over single-word prefixes (e.g. "or rather" before
        // "or" — even though we don't ship "or" as a connector, the same
        // discipline applies to "I meant" / "I mean").
        let alternation = connectors
            .sorted(by: { $0.count > $1.count })
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")

        // The connector MUST be preceded by `, ` (comma + whitespace) to
        // fire — this is the comma-prefix guard. Capture the connector
        // span itself for span replacement; the comma-and-space prefix
        // sits OUTSIDE the match group so it is also consumed.
        // Group layout: full match = `, <connector>\s*` (consumed),
        // group 1 = the connector text itself.
        let pattern = "(?i)(?:^|,)\\s*(\(alternation))\\b(\\s*)"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, options: [], range: fullRange)
        guard !matches.isEmpty else { return text }

        let pureCorrection = pureCorrectionConnectors

        // Process matches in REVERSE so range arithmetic stays stable.
        var result = text
        for match in matches.reversed() {
            guard let matchRange = Range(match.range, in: result) else { continue }

            // Pull the connector text out of capture group 1 so we can
            // distinguish parenthetical-eligible vs. pure-correction
            // connectors when handling abort 3a / advancing past a
            // post-connector comma.
            let connectorRange = match.range(at: 1)
            let connectorText: String = {
                guard let r = Range(connectorRange, in: result) else { return "" }
                return String(result[r]).lowercased()
            }()
            let isPureCorrection = pureCorrection.contains(connectorText)

            // What sits AFTER the match? We need the first repair token
            // and any trailing context, AND we need to detect the abort
            // signal of an immediately-following comma.
            let afterMatchStart = matchRange.upperBound
            if afterMatchStart >= result.endIndex { continue }

            // For pure-correction connectors ("no", "nein", "actually",
            // "eigentlich", ...) a literal "," immediately after the
            // connector is just punctuation flanking the interjection.
            // Advance past that comma and any trailing whitespace so the
            // repair-side scan starts at the real first repair token.
            // For parenthetical-eligible connectors we leave the cursor
            // alone — the comma is the abort signal handled below.
            var effectiveStart = afterMatchStart
            if isPureCorrection,
               effectiveStart < result.endIndex,
               result[effectiveStart] == ","
            {
                effectiveStart = result.index(after: effectiveStart)
                while effectiveStart < result.endIndex,
                      result[effectiveStart].isWhitespace
                {
                    effectiveStart = result.index(after: effectiveStart)
                }
            }
            if effectiveStart >= result.endIndex { continue }

            let after = String(result[effectiveStart...])

            // Abort 3a: the connector is followed by a comma → clausal
            // continuation (e.g. ", ich meine, mit der ganzen Familie").
            // Only fires for parenthetical-eligible connectors. Pure
            // correction markers already advanced past the comma above.
            if !isPureCorrection, let firstChar = after.first, firstChar == "," {
                continue
            }

            // D-03/SELFCORR-04: consume the WHOLE leading connector chain
            // ("no actually", "nein eigentlich") before identifying the
            // true first repair token. A second (or further) leading
            // pure-correction connector is not itself a repair token — it
            // is part of the same interjection as the first — so strip it,
            // and any comma/whitespace immediately flanking it, repeating
            // until no further leading connector remains. This is the
            // mechanical fix for the dangling-connector defect (43-
            // RESEARCH.md Finding 1): the connector-matching regex only
            // ever matches ONE connector token per span, so a second
            // chained connector would otherwise become (and fail to align
            // as) the "first repair token" on its own.
            while let chainLen = leadingPureCorrectionConnectorLength(String(result[effectiveStart...])) {
                var newStart = result.index(effectiveStart, offsetBy: chainLen)
                if newStart < result.endIndex, result[newStart] == "," {
                    newStart = result.index(after: newStart)
                }
                while newStart < result.endIndex, result[newStart].isWhitespace {
                    newStart = result.index(after: newStart)
                }
                guard newStart != effectiveStart else { break }  // safety: no progress
                effectiveStart = newStart
            }
            if effectiveStart >= result.endIndex { continue }
            let afterChainStripped = String(result[effectiveStart...])

            // Tokenize the repair side (everything after the connector
            // chain, up to but NOT including the next sentence-ending
            // boundary for the purpose of identifying the FIRST repair
            // token; we still keep the rest of `afterChainStripped` in the
            // output verbatim).
            let repairTokensFull = tokenize(afterChainStripped)
            guard !repairTokensFull.isEmpty else { continue }
            let firstRepairToken = repairTokensFull[0]
            let firstRepairLower = firstRepairToken.lowercasedTrimmingPunctuation()

            // Abort 3b: relative / object pronoun head signals a clausal
            // continuation rather than a substitute noun phrase.
            if abortPronouns.contains(firstRepairLower) {
                continue
            }

            // Tokenize the backward span (text BEFORE the leading comma
            // of the match — i.e. before `result[matchRange]`).
            let beforeText = String(result[result.startIndex..<matchRange.lowerBound])

            // Abort 3c: Idiom Guard. Certain phrases end in a comma but are
            // not reparandum starts (e.g. "By the way, I meant...").
            let lowerBefore = beforeText.lowercased().trimmingCharacters(in: .whitespaces)
            if lowerBefore.hasSuffix("by the way") ||
               lowerBefore.hasSuffix("wie gesagt") ||
               lowerBefore.hasSuffix("im gegenteil") {
                continue
            }

            let backwardTokens = tokenize(beforeText)
            guard !backwardTokens.isEmpty else { continue }

            // Determine drop count.
            let backwardCount = backwardTokens.count
            let lastSixIndex = max(0, backwardCount - 6)
            let lastSix = Array(backwardTokens[lastSixIndex..<backwardCount])
            // 1) Try alignment-by-first-repair-token in the last 6.
            //    Compare with case-insensitive strict-equality (no punctuation
            //    folding on the backward side because backward tokens rarely
            //    end in sentence punctuation; the repair-side strip is enough).
            //
            //    Phase 43/D-03 fix: scan from the END of the window backward
            //    (nearest-to-the-connector match wins), not left-to-right.
            //    Once the chained-connector strip (above) can expose a common
            //    word (e.g. a repeated preposition like "um") as the first
            //    repair token, a left-to-right scan over a 6-token window
            //    that spans a PRIOR, unrelated sentence can align on a
            //    coincidental EARLIER occurrence of that word instead of the
            //    one immediately preceding the connector — dropping an
            //    unrelated earlier sentence's content (confirmed via the
            //    scale replay on a real capture: "Das Meeting ist um fünf.
            //    Meeting um neun, nein eigentlich um acht." previously
            //    aligned on the FIRST "um" in "ist um fünf" instead of the
            //    "um" immediately before "neun", corrupting the unrelated
            //    first sentence). The nearest occurrence is the only
            //    positionally-defensible reparandum candidate.
            //
            //    Phase 43/D-06 (43-03): ALSO match when the backward token
            //    and the first repair token are a digit-vs-word pair of the
            //    SAME canonical single-digit value (e.g. backward "8"
            //    aligning against a repair leading with "acht") — this is
            //    the mixed digit/word case the number-word anchor must
            //    combine correctly with the existing bare-digit `plain`
            //    type (43-03 scope guard). Gated by `enableNumberWordAnchor`.
            var dropCount: Int? = nil
            for (offset, token) in lastSix.enumerated().reversed() {
                let tokenNorm = token.lowercasedTrimmingPunctuation()
                if tokenNorm == firstRepairLower {
                    // offset is 0-based from the start of `lastSix`;
                    // distance from end = lastSix.count - offset.
                    dropCount = lastSix.count - offset
                    break  // nearest (right-most / closest to connector) match wins
                }
                if enableNumberWordAnchor,
                   let backwardDigit = canonicalDigit(tokenNorm),
                   let repairDigit = canonicalDigit(firstRepairLower),
                   backwardDigit == repairDigit
                {
                    dropCount = lastSix.count - offset
                    break
                }
            }

            // 2) Alignment found nothing -> try the shared typed-value
            //    evidence source (Phase 43/D-01 + D-07 convergence). The
            //    repair side must LEAD with a typed value (digit/clock/
            //    price/etc., optionally preceded by a preposition), and
            //    the backward span must contain EXACTLY ONE value of that
            //    SAME type — the exact same "exactly-one-candidate-or-
            //    abstain" decision the sentence-boundary path already uses
            //    (`singleSameTypeBoundaryValue`), reused here rather than
            //    re-derived, so there is one place to reason about
            //    corruption. A copula-led repair ("... it's 9:00 ...") does
            //    not match `leadingTypedValue`'s anchored pattern (it does
            //    not lead with the value), so it correctly falls through to
            //    abstain — merging the boundary path's copula handling into
            //    the comma path is out of scope (43-RESEARCH.md Finding 3).
            if dropCount == nil,
               let typed = leadingTypedValue(afterChainStripped, preps: boundaryPreps(for: language)),
               let valueRangeInBefore = singleSameTypeBoundaryValue(beforeText, vtype: typed.vtype),
               let matchStart = Range(valueRangeInBefore, in: beforeText)?.lowerBound,
               let tokenIndex = tokenIndexStartingAt(beforeText, target: matchStart)
            {
                dropCount = backwardCount - tokenIndex
            }

            // 3) No alignment AND no typed-value evidence -> try the
            //    shared anchored-noun evidence source (Phase 43/43-04/
            //    D-04): the repair side must LEAD with a same-shape
            //    proper-noun candidate, AND the backward span must contain
            //    a closed copula/possessive frame ("his name is"/"her name
            //    is"/"sein Name ist"/"ihr Name ist") immediately followed
            //    by the SOLE same-shape candidate in the backward span —
            //    the identical exactly-one-candidate discipline as the
            //    typed-value anchor (`singleSameShapeProperNoun`, shared
            //    with the boundary path's own anchored-noun check). Gated
            //    by `enableAnchoredNoun`; see 43-04-SUMMARY.md for the
            //    recorded scale-replay verdict.
            if dropCount == nil,
               enableAnchoredNoun,
               let nounCandidate = leadingProperNounCandidate(afterChainStripped),
               let candidateRangeInBefore = anchoredNounFrameCandidate(beforeText, frames: anchoredNounFrames(for: language), shape: nounCandidate.shape),
               let matchStart = Range(candidateRangeInBefore, in: beforeText)?.lowerBound,
               let tokenIndex = tokenIndexStartingAt(beforeText, target: matchStart)
            {
                dropCount = backwardCount - tokenIndex
            }

            // 4) No alignment AND no typed-value/anchored-noun evidence ->
            //    ABSTAIN (Phase 43/D-01). The former blind fallback that
            //    guessed a drop count here is the data-loss bug this phase
            //    removes; it deleted backward tokens with no positive
            //    evidence of a reparandum. This mirrors resolveNonCommaPath's
            //    existing "abort, no fallback drop" discipline.
            guard let drop = dropCount, drop > 0 else { continue }
            let actualDrop = min(drop, min(6, backwardCount))
            guard actualDrop > 0 else { continue }

            // Compute the character range to drop on the BACKWARD side.
            // We drop `actualDrop` trailing tokens AND any whitespace
            // immediately preceding the leading comma — the comma itself
            // is already consumed by the match.
            let dropFromIndex = backwardCount - actualDrop
            // Find the start char-index of token at `dropFromIndex` inside
            // `beforeText`. Re-scan `beforeText` to recover positions.
            let dropStart = startIndexOfNthToken(beforeText, n: dropFromIndex)
            guard let realDropStart = dropStart else { continue }

            // The replacement: remove tokens from realDropStart through
            // the effective repair start (i.e. through the consumed
            // connector + trailing whitespace + any pure-correction
            // ", " advance). Then leave the original tail (`after`)
            // intact starting at its first repair token.
            let trailing = result[effectiveStart..<result.endIndex]
            // Strip trailing whitespace before the dropped span
            // (so we don't leave a stray double-space).
            var prefix = String(result[result.startIndex..<realDropStart])
            while prefix.hasSuffix(" ") || prefix.hasSuffix("\t") {
                prefix.removeLast()
            }
            // Re-insert a single space if the prefix is non-empty AND
            // the trailing starts with a non-whitespace, non-punctuation
            // character (so that "Das" + " " + "fünf Stück." reads naturally
            // when we drop e.g. " kostet 110 Franken").
            let needsSpace: Bool = {
                guard !prefix.isEmpty, let firstTrailing = trailing.first else { return false }
                return !firstTrailing.isWhitespace && !".,;:!?".contains(firstTrailing)
            }()
            let glue = needsSpace ? " " : ""
            result = prefix + glue + trailing
        }

        // Final whitespace tidy: collapse any accidental double spaces.
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        return result
    }

    // MARK: - Variant A: non-comma path (spike only — OFF by default)

    /// Non-comma path for `pureCorrectionConnectors` (Plan 05 Variant A/B).
    ///
    /// Fires on `pureCorrectionConnectors` at word boundaries WITHOUT requiring
    /// a preceding comma.  Guards:
    ///   (i)  Sentence-start guard: connector must NOT be the first token (Pitfall 5).
    ///   (ii) Backward-alignment REQUIRED: the first repair token must be found in
    ///        the last 6 backward tokens.  If alignment fails → abort (no fallback
    ///        drop for non-comma fires — safety-first per RESEARCH).
    ///   (iii) All existing guards: abort-pronoun, idiom guard.
    private static func resolveNonCommaPath(_ text: String, language: String) -> String {
        let abortPronouns = pronounAbortSet(for: language)
        let pureCorrection = pureCorrectionConnectors

        // Build alternation of ONLY pureCorrectionConnectors, longest-first.
        let pureSorted = pureCorrection.sorted(by: { $0.count > $1.count })
        let alternation = pureSorted
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")

        // Match a pure-correction connector at a word boundary, preceded by
        // whitespace (ensuring it is not at sentence start — guard (i)).
        // The lookbehind `(?<=\S)\s+` requires at least one non-whitespace
        // character before the whitespace run that precedes the connector.
        // This prevents firing when the connector is the very first token.
        // Group 1 = connector text.
        let pattern = "(?i)(?<=\\S)\\s+(\(alternation))(?=\\s|$)"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }

        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        let matches = regex.matches(in: text, options: [], range: fullRange)
        guard !matches.isEmpty else { return text }

        var result = text
        for match in matches.reversed() {
            guard let matchRange = Range(match.range, in: result) else { continue }

            // Verify the connector capture group resolved (it always should since
            // the pattern requires group 1, but guard for safety).
            let connectorRange = match.range(at: 1)
            guard Range(connectorRange, in: result) != nil else { continue }

            // After-connector text.
            var effectiveStart = matchRange.upperBound
            // Advance past any leading whitespace.
            while effectiveStart < result.endIndex, result[effectiveStart].isWhitespace {
                effectiveStart = result.index(after: effectiveStart)
            }
            // If end-of-string after connector, skip.
            if effectiveStart >= result.endIndex { continue }

            // Also advance past an optional post-connector comma + whitespace
            // (pure-correction connector flanked by commas: "nine, no, actually").
            if result[effectiveStart] == "," {
                effectiveStart = result.index(after: effectiveStart)
                while effectiveStart < result.endIndex, result[effectiveStart].isWhitespace {
                    effectiveStart = result.index(after: effectiveStart)
                }
            }
            if effectiveStart >= result.endIndex { continue }

            let after = String(result[effectiveStart...])
            let repairTokensFull = tokenize(after)
            guard !repairTokensFull.isEmpty else { continue }
            let firstRepairLower = repairTokensFull[0].lowercasedTrimmingPunctuation()

            // Abort 3b: pronoun abort.
            if abortPronouns.contains(firstRepairLower) { continue }

            // Backward span: everything before the match (before the whitespace
            // run that precedes the connector).
            let beforeText = String(result[result.startIndex..<matchRange.lowerBound])
                .trimmingCharacters(in: .whitespaces)
            let fullBeforeText = String(result[result.startIndex..<matchRange.lowerBound])

            // Abort 3c: Idiom Guard.
            let lowerBefore = beforeText.lowercased()
            if lowerBefore.hasSuffix("by the way") ||
               lowerBefore.hasSuffix("wie gesagt") ||
               lowerBefore.hasSuffix("im gegenteil") {
                continue
            }

            let backwardTokens = tokenize(fullBeforeText)
            guard !backwardTokens.isEmpty else { continue }

            let backwardCount = backwardTokens.count
            let lastSixIndex = max(0, backwardCount - 6)
            let lastSix = Array(backwardTokens[lastSixIndex..<backwardCount])

            // Guard (ii): alignment REQUIRED for non-comma fires.
            // Find the first repair token in the last-6 backward window.
            var dropCount: Int? = nil
            for (offset, token) in lastSix.enumerated() {
                if token.lowercasedTrimmingPunctuation() == firstRepairLower {
                    dropCount = lastSix.count - offset
                    break
                }
            }
            // If alignment failed → abort (no fallback drop in non-comma mode).
            guard let drop = dropCount else { continue }

            let actualDrop = min(drop, min(6, backwardCount))
            guard actualDrop > 0 else { continue }

            let dropFromIndex = backwardCount - actualDrop
            guard let realDropStart = startIndexOfNthToken(fullBeforeText, n: dropFromIndex) else {
                continue
            }

            let trailing = result[effectiveStart..<result.endIndex]
            var prefix = String(result[result.startIndex..<realDropStart])
            while prefix.hasSuffix(" ") || prefix.hasSuffix("\t") { prefix.removeLast() }
            let needsSpace: Bool = {
                guard !prefix.isEmpty, let firstTrailing = trailing.first else { return false }
                return !firstTrailing.isWhitespace && !".,;:!?".contains(firstTrailing)
            }()
            result = prefix + (needsSpace ? " " : "") + trailing
        }

        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        return result
    }

    // MARK: - Variant B: verbatim-restatement collapse (spike only — OFF by default)

    /// Collapse immediate verbatim token restatements of the form `tok tok`
    /// where tok length ≥ 2 (EN) or ≥ 3 (DE).
    ///
    /// Safe by construction: the second occurrence is an exact duplicate of
    /// the first, so removing it cannot corrupt content.  The min-length guard
    /// prevents collapsing legitimate repeated monosyllables ("a a boy" in DE)
    /// or short particles.
    private static func collapseVerbatimRestatements(_ text: String, language: String) -> String {
        let minLen = language.hasPrefix("de") ? 3 : 2
        var result = text
        var changed = true
        // Iterate to collapse chains like "go to go to" → "go to".
        var iterations = 0
        while changed && iterations < 5 {
            changed = false
            iterations += 1
            // Match `(\bword\b)\s+\1` where the repeated word has length ≥ minLen.
            // We use a simple token-scan to avoid regex back-reference portability issues
            // across NSRegularExpression.
            let tokens = tokenize(result)
            guard tokens.count >= 2 else { break }
            var i = 0
            var newTokens: [String] = []
            while i < tokens.count {
                // Check if tokens[i] is a repeated pair start.
                // Look-ahead for single-token repetition: tok tok.
                if i + 1 < tokens.count,
                   tokens[i].lowercased() == tokens[i + 1].lowercased(),
                   tokens[i].count >= minLen
                {
                    newTokens.append(tokens[i])
                    i += 2          // skip the duplicate
                    changed = true
                }
                // Check two-token phrase repetition: tok1 tok2 tok1 tok2.
                else if i + 3 < tokens.count,
                        tokens[i].lowercased() == tokens[i + 2].lowercased(),
                        tokens[i + 1].lowercased() == tokens[i + 3].lowercased(),
                        tokens[i].count + tokens[i + 1].count >= minLen
                {
                    newTokens.append(tokens[i])
                    newTokens.append(tokens[i + 1])
                    i += 4          // skip the duplicate pair
                    changed = true
                } else {
                    newTokens.append(tokens[i])
                    i += 1
                }
            }
            result = newTokens.joined(separator: " ")
        }
        return result
    }

    // MARK: - Sentence-boundary path (spike 012 port, 42-07/SELFCORR-02)

    /// Sentence-boundary self-correction path — sibling to `resolveCommaPath`
    /// / `resolveNonCommaPath`. Ported FAITHFULLY from the VALIDATED spike
    /// (`.planning/spikes/012-german-selfcorrection-boundary/selfcorr_boundary.py`:
    /// 18/18 typed positives resolve, 23/23 negatives + 2 noun/name positives
    /// byte-identical, 0 corruptions across 1408 real debug-log texts). Wired
    /// into the production 2-arg `resolve(_:language:)` above.
    ///
    /// Detects `<S1 …value1…> <boundary . ! ?> <marker>[,] [copula] [prep]
    /// <value2><end>` and substitutes value2's typed core for value1 in S1,
    /// dropping the whole correction sentence S2. Two non-overlapping string
    /// edits (replace value1; delete S2 + its leading separator) applied
    /// right-to-left so earlier offsets stay valid — this preserves S1's own
    /// terminal punctuation and every other sentence byte-for-byte.
    ///
    /// Safety anchor (DO NOT RELAX — this is the D-03 zero-corruption
    /// guarantee): fires ONLY when (a) S2 is *entirely*
    /// `marker+ [copula] [prep] <typed value> <punct>*` (no leftover
    /// content), and (b) S1 contains EXACTLY ONE typed value of the SAME
    /// type as value2 (clock / `Uhr` time / am-pm / price / plain number).
    /// Zero or >1 same-type values in S1 → ABSTAIN (byte-identical, safe
    /// miss).
    ///
    /// Phase 43/43-04/D-04 (this deliberately re-opens the "noun/name
    /// restatements always ABSTAIN" claim this doc-comment used to make):
    /// a RESTRICTED anchored proper-noun evidence source is ALSO tried,
    /// gated by `enableAnchoredNoun`. It fires only when S2 is entirely
    /// `marker+ <closed copula/possessive frame> <same-shape proper-noun
    /// candidate> <punct>*` (`anchoredNounFrames` /
    /// `parseAnchoredNounBoundaryClause`) AND S1 contains EXACTLY ONE
    /// same-shape proper-noun candidate (`singleSameShapeProperNoun`) — the
    /// identical exactly-one-candidate discipline as the typed-value
    /// anchor, applied to proper-noun shape instead of value type. General
    /// (non-anchored, non-frame) noun/name restatements still ABSTAIN;
    /// this only recovers the narrow copula/possessive-frame subset that
    /// cleared its own zero-corruption scale-replay gate — see
    /// 43-04-SUMMARY.md for the recorded verdict (enabled at zero
    /// corruption, or shipped disabled with the corrupting example named).
    private static func resolveSentenceBoundaryPath(_ text: String, language: String) -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }

        let spans = boundarySentenceSpans(text)
        guard spans.count >= 2 else { return text }

        let markers = pureCorrectionMarkers(for: language)
        guard !markers.isEmpty else { return text }
        let copulas = boundaryCopulas(for: language)
        let preps = boundaryPreps(for: language)

        let nsText = text as NSString
        var edits: [(range: NSRange, replacement: String)] = []
        var used = Set<Int>()

        for i in 1..<spans.count {
            if used.contains(i) || used.contains(i - 1) { continue }
            let s2Range = spans[i]
            let s2 = nsText.substring(with: s2Range)
            guard !s2.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            let s1Range = spans[i - 1]
            let s1 = nsText.substring(with: s1Range)

            // Evidence source A (validated, spike 012): S2 is a typed-value
            // correction clause AND S1 holds EXACTLY ONE same-type value.
            var valueRangeInS1: NSRange?
            var replacementValue: String?
            if let parsed = parseBoundaryCorrectionClause(s2, markers: markers, copulas: copulas, preps: preps),
               let range = singleSameTypeBoundaryValue(s1, vtype: parsed.vtype) {
                valueRangeInS1 = range
                replacementValue = parsed.value
            } else if enableAnchoredNoun,
                      let nounParsed = parseAnchoredNounBoundaryClause(s2, markers: markers, frames: anchoredNounFrames(for: language)),
                      let range = singleSameShapeProperNoun(s1, shape: nounParsed.shape) {
                // Evidence source B (Phase 43/43-04/D-04, gated): S2 is a
                // closed-frame anchored-noun correction clause AND S1 holds
                // EXACTLY ONE same-shape proper-noun candidate.
                valueRangeInS1 = range
                replacementValue = nounParsed.value
            }

            guard let vRange = valueRangeInS1, let replacement = replacementValue else {
                continue  // neither evidence source fired -> ABSTAIN
            }

            let v1AbsRange = NSRange(
                location: s1Range.location + vRange.location,
                length: vRange.length
            )
            // Edit 1: substitute the repair value for the reparandum in S1.
            edits.append((v1AbsRange, replacement))
            // Edit 2: delete the correction sentence S2 plus its leading
            // separator (everything from the end of S1's content through
            // the end of S2).
            let s1End = s1Range.location + s1Range.length
            let s2End = s2Range.location + s2Range.length
            edits.append((NSRange(location: s1End, length: s2End - s1End), ""))
            used.insert(i)
            used.insert(i - 1)
        }

        guard !edits.isEmpty else { return text }

        var result = text
        for (range, replacement) in edits.sorted(by: { $0.range.location > $1.range.location }) {
            guard let r = Range(range, in: result) else { continue }
            result.replaceSubrange(r, with: replacement)
        }
        // Collapse accidental double spaces introduced by an edit, keeping
        // parity with the comma path's final tidy.
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        return result
    }

    /// Sentence spans: boundary = `[.!?]+` followed by whitespace + an
    /// uppercase opener (or end-of-string). Deliberately does NOT split
    /// inside "a.m.", "p.m.", decimals ("10.30"), or "e.g." because those
    /// periods are not followed by whitespace+uppercase — critical for the
    /// real `"… at 9 a.m. No, actually it's 8 a.m."` capture, whose `a.m.`
    /// period would otherwise shatter the sentence. Ported verbatim from
    /// spike 012 `split_sentences`.
    private static func boundarySentenceSpans(_ text: String) -> [NSRange] {
        let nsText = text as NSString
        let fullLength = nsText.length
        guard
            let boundaryRegex = try? NSRegularExpression(pattern: "[.!?]+", options: []),
            let openerRegex = try? NSRegularExpression(pattern: "^\\s+[\"'“”]?[A-ZÄÖÜ]", options: [])
        else {
            return [NSRange(location: 0, length: fullLength)]
        }

        var spans: [NSRange] = []
        var start = 0
        let boundaryMatches = boundaryRegex.matches(in: text, options: [], range: NSRange(location: 0, length: fullLength))
        for match in boundaryMatches {
            let end = match.range.location + match.range.length
            let restRange = NSRange(location: end, length: fullLength - end)
            let opensNewSentence: Bool
            if restRange.length == 0 {
                opensNewSentence = true
            } else {
                // Match against an ISOLATED copy of the "rest" substring so
                // `^` in openerRegex anchors to the true start of `rest`
                // rather than the start of the full `text` (NSRegularExpression's
                // `^` anchors to the search STRING's start, not a `range:`
                // subrange's start — isolating avoids that footgun).
                let rest = nsText.substring(with: restRange)
                let restLength = (rest as NSString).length
                opensNewSentence = openerRegex.firstMatch(
                    in: rest, options: [], range: NSRange(location: 0, length: restLength)
                ) != nil
            }
            if opensNewSentence {
                let spanRange = NSRange(location: start, length: end - start)
                if !nsText.substring(with: spanRange).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    spans.append(spanRange)
                }
                start = end
            }
        }
        if start < fullLength {
            let tailRange = NSRange(location: start, length: fullLength - start)
            if !nsText.substring(with: tailRange).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                spans.append(tailRange)
            }
        }
        return spans
    }

    /// If `s2` is ENTIRELY `marker+ (copula)? (prep)? <typed value> <punct>*`,
    /// return the typed value text + its type. Otherwise nil (ABSTAIN).
    /// Ported verbatim from spike 012 `_parse_correction_clause`.
    private static func parseBoundaryCorrectionClause(
        _ s2: String,
        markers: [String],
        copulas: [String],
        preps: [String]
    ) -> (value: String, vtype: String)? {
        let markerAlt = boundaryAlternation(markers)
        guard !markerAlt.isEmpty else { return nil }
        let copulaAlt = boundaryAlternation(copulas)
        let prepAlt = boundaryAlternation(preps)
        let markerGrp = "(?:(?:\(markerAlt))\\b\\s*,?\\s+)+"
        let copulaGrp = copulaAlt.isEmpty ? "" : "(?:(?:\(copulaAlt))\\b\\s+)?"
        let prepGrp = prepAlt.isEmpty ? "" : "(?:(?:\(prepAlt))\\b\\s+)?"

        let nsS2 = s2 as NSString
        let fullRange = NSRange(location: 0, length: nsS2.length)
        for (vtype, vpat) in boundaryValueTypes {
            let pattern = "^\\s*\(markerGrp)\(copulaGrp)\(prepGrp)(\(vpat))\\s*[.!?\"'”]*\\s*$"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            guard let match = regex.firstMatch(in: s2, options: [], range: fullRange), match.numberOfRanges > 1 else {
                continue
            }
            let valueRange = match.range(at: 1)
            guard let r = Range(valueRange, in: s2) else { continue }
            return (String(s2[r]), vtype)
        }
        return nil
    }

    /// Return the range of the SOLE same-type typed value in `s1`, or nil if
    /// there are zero or more than one (ambiguous -> ABSTAIN). Ported
    /// verbatim from spike 012 `_single_same_type_value`.
    private static func singleSameTypeBoundaryValue(_ s1: String, vtype: String) -> NSRange? {
        guard let vpat = boundaryValueTypes.first(where: { $0.type == vtype })?.pattern else { return nil }
        guard let regex = try? NSRegularExpression(pattern: vpat, options: [.caseInsensitive]) else { return nil }
        let nsS1 = s1 as NSString
        let matches = regex.matches(in: s1, options: [], range: NSRange(location: 0, length: nsS1.length))
        guard matches.count == 1 else { return nil }
        return matches[0].range
    }

    /// Regex alternation, longest-first, deduplicated and escaped. Ported
    /// from spike 012 `_alt`.
    private static func boundaryAlternation(_ words: [String]) -> String {
        let unique = Array(Set(words)).sorted { $0.count > $1.count }
        return unique.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
    }

    /// The pure-correction markers (spike 012 `PURE_CORRECTION_DE`/`_EN`)
    /// derived from the EXISTING `germanConnectors`/`englishConnectors` +
    /// `pureCorrectionConnectors` lists below — no separate literal list, so
    /// the boundary path can never drift from the comma path's vocabulary.
    private static func pureCorrectionMarkers(for language: String) -> [String] {
        connectorList(for: language).filter { pureCorrectionConnectors.contains($0) }
    }

    /// Copula phrases that introduce the restated value ("das ist um 11 Uhr" /
    /// "it's 9:00"). Spike 012 `COPULAS_DE`/`COPULAS_EN`.
    private static let boundaryCopulasDE: [String] = ["das ist", "es ist", "es sind", "das sind", "das war", "es war"]
    private static let boundaryCopulasEN: [String] = ["it's", "it is", "it was", "that's", "that is", "that was"]

    /// Optional preposition frame in front of the restated value. Spike 012
    /// `PREPS_DE`/`PREPS_EN`.
    private static let boundaryPrepsDE: [String] = ["um", "am", "auf", "für"]
    private static let boundaryPrepsEN: [String] = ["at", "on", "for", "around"]

    private static func boundaryCopulas(for language: String) -> [String] {
        language.prefix(2).lowercased() == "en" ? boundaryCopulasEN : boundaryCopulasDE
    }

    private static func boundaryPreps(for language: String) -> [String] {
        language.prefix(2).lowercased() == "en" ? boundaryPrepsEN : boundaryPrepsDE
    }

    /// Typed value patterns, ordered SPECIFIC -> GENERIC. Spike 012
    /// `VALUE_TYPES`. Regex syntax is identical between Python `re` and ICU
    /// `NSRegularExpression` for these patterns — ported verbatim.
    ///
    /// Phase 43/43-03 (D-06): the `plain` pattern is widened, gated by
    /// `enableNumberWordAnchor`, to ALSO match a recognized DE/EN single-
    /// digit cardinal WORD (not just a bare digit) — see
    /// `numberWordAlternationPattern`. Computed (not a stored `let`) so the
    /// gate flag can toggle it at call time; every caller
    /// (`leadingTypedValue`, `singleSameTypeBoundaryValue`,
    /// `parseBoundaryCorrectionClause`) already looks this table up by
    /// type name, so the widening is transparent to all three.
    private static var boundaryValueTypes: [(type: String, pattern: String)] {
        let plainPattern = enableNumberWordAnchor
            ? #"\d+(?:[.,]\d+)?"# + "|" + numberWordAlternationPattern
            : #"\d+(?:[.,]\d+)?"#
        return [
            ("clock", #"\d{1,2}:\d{2}"#),
            ("time_uhr", #"\d{1,2}(?:[.,]\d{2})?\s*uhr"#),
            ("ampm", #"\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)"#),
            ("price", #"\d+(?:[.,]\d+)?\s*(?:franken|euros?|dollars?|chf|eur|usd|fr\.?|cent|rappen|pounds?|pence)"#),
            ("plain", plainPattern),
        ]
    }

    // MARK: - D-06: DE/EN single-digit number-word anchor (Phase 43/43-03)

    /// Gate flag for the number-word typed-value anchor (D-06). Default
    /// enabled; flipped to `false` (source ships DISABLED — number-word
    /// cases ABSTAIN and fall back to the LLM, never corrupt) only if the
    /// dedicated `selfcorr43` scale-replay pass (43-03 Task 2) finds even
    /// one prose corruption caused by the widened source. See
    /// 43-03-SUMMARY.md for the recorded verdict.
    private static let enableNumberWordAnchor = true

    /// DE single-digit cardinal -> canonical digit. Deliberately EXCLUDES
    /// "ein" — the German indefinite article ("ein Meeting", "ein Franken")
    /// — which would be a near-certain false-positive number-word match on
    /// completely ordinary prose; "eins" is the unambiguous standalone-
    /// cardinal form (43-RESEARCH.md Finding 2 covers eins..neun; "ein" is
    /// excluded here as a deliberate, more conservative narrowing to keep
    /// the D-06 zero-corruption gate honest). "null" (zero) is included as
    /// trivially safe per 43-CONTEXT.md D-06.
    private static let numberWordToDigitDE: [String: String] = [
        "null": "0", "eins": "1", "zwei": "2", "drei": "3", "vier": "4",
        "fünf": "5", "sechs": "6", "sieben": "7", "acht": "8", "neun": "9",
    ]

    /// EN single-digit cardinal -> canonical digit. Deliberately EXCLUDES
    /// "one" — overloaded as a generic pronoun/noun in ordinary English
    /// prose ("the one that...", "a big one") — a near-certain false-
    /// positive source; "zero" is included as trivially safe.
    private static let numberWordToDigitEN: [String: String] = [
        "zero": "0", "two": "2", "three": "3", "four": "4", "five": "5",
        "six": "6", "seven": "7", "eight": "8", "nine": "9",
    ]

    /// Canonical single-digit-string normalizer (Phase 43/43-03/D-06): maps
    /// a recognized DE or EN single-digit cardinal WORD, or an already-bare
    /// single digit character, to the SAME canonical key ("neun" / "nine" /
    /// "9" all normalize to "9") so word and digit forms compare EQUAL when
    /// matching repair-to-reparandum type. Returns nil for anything else
    /// (multi-digit numbers, unrecognized words, "ein"/"one"). Used by the
    /// comma path's exact-alignment scan to recognize a digit-vs-word mixed
    /// correction (e.g. backward "8" aligning against a repair leading with
    /// "acht") in addition to literal string equality.
    private static func canonicalDigit(_ token: String) -> String? {
        let lower = token.lowercased()
        if let d = numberWordToDigitDE[lower] { return d }
        if let d = numberWordToDigitEN[lower] { return d }
        if lower.count == 1, let c = lower.first, c.isNumber { return String(c) }
        return nil
    }

    /// Regex alternation of every recognized DE+EN number word (longest-
    /// first, deduplicated, word-boundary anchored so "acht" cannot match
    /// inside "achtung"). Used to widen the shared `plain` typed-value
    /// pattern so a bare number WORD (not just a digit) is recognized as a
    /// typed value by `leadingTypedValue` / `singleSameTypeBoundaryValue` /
    /// `parseBoundaryCorrectionClause` — the D-07 shared evidence path both
    /// self-correction paths already call.
    ///
    /// CORRUPTION GUARD (confirmed via `testGermanOderBesser` during 43-03
    /// implementation): a bare number word is EXTREMELY common as an
    /// ordinary quantity determiner immediately before a noun ("drei
    /// Stück", "acht Leute", "five minutes") — unlike a bare digit, which
    /// almost never appears that way in real dictation. Matching "drei" in
    /// "Drei Stück, oder besser fünf Stück." wrongly counted it as typed-
    /// value evidence and caused the comma path to drop "Drei Stück, oder
    /// besser" outright — a real corruption of a case that must ABSTAIN.
    /// The trailing negative lookahead `(?!\s*\p{L})` requires the number
    /// word NOT be immediately followed by (optional whitespace then)
    /// another letter, so it only counts as evidence when it stands ALONE
    /// as the corrected value (followed by punctuation/end-of-string), not
    /// when it heads a noun phrase. This intentionally excludes Uhr-
    /// suffixed word times ("acht Uhr") from this widened source — that
    /// combination is unaffected/deferred, not a regression (43-RESEARCH.md
    /// Finding 2 complexity flag; out of scope for this plan).
    private static var numberWordAlternationPattern: String {
        let words = Array(numberWordToDigitDE.keys) + Array(numberWordToDigitEN.keys)
        let unique = Array(Set(words)).sorted { $0.count > $1.count }
        let escaped = unique.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        return "\\b(?:\(escaped))\\b(?!\\s*\\p{L})"
    }

    // MARK: - D-04: restricted anchored proper-noun evidence source (Phase 43/43-04)

    /// Gate flag for the anchored proper-noun restatement evidence source
    /// (D-04). Default enabled; flipped to `false` (source ships DISABLED —
    /// anchored-noun cases ABSTAIN and fall back to the LLM, never corrupt)
    /// only if the dedicated `selfcorr43` scale-replay pass (43-04 Task 2)
    /// finds even one prose corruption caused by this source. See
    /// 43-04-SUMMARY.md for the recorded verdict.
    private static let enableAnchoredNoun = true

    /// Closed copula/possessive frame list (D-04) — deliberately NOT the
    /// general `boundaryCopulas` table (shared with the typed-value
    /// evidence path); kept as its own small, closed list so widening it
    /// later cannot silently affect typed-value matching (D-04 scope
    /// guard, 43-RESEARCH.md Finding 3).
    private static let anchoredNounFramesDE: [String] = ["sein name ist", "ihr name ist"]
    private static let anchoredNounFramesEN: [String] = ["his name is", "her name is"]

    private static func anchoredNounFrames(for language: String) -> [String] {
        language.prefix(2).lowercased() == "en" ? anchoredNounFramesEN : anchoredNounFramesDE
    }

    /// Regex fragment for a same-shape proper-noun candidate. Shape 2 = a
    /// "Firstname Lastname" pair (two consecutive Title-Case words); shape
    /// 1 = a single standalone Title-Case word that is NOT part of a
    /// longer 2-word candidate (lookaround-guarded so "Joe" inside "Joe
    /// Miller" is never double-counted as its own separate shape-1
    /// candidate).
    private static func properNounCandidatePattern(shape: Int) -> String {
        let word = "[A-ZÄÖÜ][a-zäöüß]+"
        if shape == 2 {
            return "\(word)\\s+\(word)"
        }
        return "(?<![A-ZÄÖÜ][a-zäöüß]+\\s)\(word)(?!\\s[A-ZÄÖÜ])"
    }

    /// Return the range of the SOLE same-shape proper-noun candidate in
    /// `text`, or nil if there are zero or more than one (ambiguous ->
    /// ABSTAIN). The exactly-one-candidate discipline shared with
    /// `singleSameTypeBoundaryValue` — same guard philosophy, applied to
    /// proper-noun shape instead of typed-value type (D-07).
    private static func singleSameShapeProperNoun(_ text: String, shape: Int) -> NSRange? {
        let pattern = "\\b" + properNounCandidatePattern(shape: shape) + "\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let ns = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        guard matches.count == 1 else { return nil }
        return matches[0].range
    }

    /// If `s` LEADS with a same-shape proper-noun candidate, return the
    /// matched candidate text and its shape. Otherwise nil. Comma path's
    /// anchored-noun repair-side evidence source, parallel to
    /// `leadingTypedValue` — tries the more specific 2-word shape before
    /// falling back to the 1-word shape.
    private static func leadingProperNounCandidate(_ s: String) -> (value: String, shape: Int)? {
        let ns = s as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        for shape in [2, 1] {
            let pattern = "^\\s*(" + properNounCandidatePattern(shape: shape) + ")\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            guard let match = regex.firstMatch(in: s, options: [], range: fullRange), match.numberOfRanges > 1 else { continue }
            let r = match.range(at: 1)
            guard let range = Range(r, in: s) else { continue }
            return (String(s[range]), shape)
        }
        return nil
    }

    /// If `beforeText` contains a closed anchored-noun frame ("his name
    /// is"/"her name is"/...) immediately followed by the SOLE same-shape
    /// proper-noun candidate in `beforeText`, return that candidate's
    /// range. Otherwise nil (ABSTAIN — no frame, or the sole candidate
    /// found by the exactly-one-candidate check isn't the one immediately
    /// preceded by the frame). Comma path's anchored-noun backward-span
    /// evidence source.
    private static func anchoredNounFrameCandidate(_ beforeText: String, frames: [String], shape: Int) -> NSRange? {
        guard let candidateRange = singleSameShapeProperNoun(beforeText, shape: shape) else { return nil }
        guard let candidateSwiftRange = Range(candidateRange, in: beforeText) else { return nil }
        let beforeCandidate = String(beforeText[beforeText.startIndex..<candidateSwiftRange.lowerBound])
        let frameAlt = boundaryAlternation(frames)
        guard !frameAlt.isEmpty else { return nil }
        let pattern = "(?:\(frameAlt))\\s*$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = beforeCandidate as NSString
        guard regex.firstMatch(in: beforeCandidate, options: [], range: NSRange(location: 0, length: ns.length)) != nil else {
            return nil
        }
        return candidateRange
    }

    /// Boundary path's anchored-noun evidence source: if `s2` is ENTIRELY
    /// `marker+ <closed frame> <same-shape proper-noun candidate>
    /// <punct>*`, return the candidate text + its shape. Otherwise nil
    /// (ABSTAIN). Deliberately a SEPARATE matcher from
    /// `parseBoundaryCorrectionClause` — D-04's scope guard keeps the
    /// anchored-noun frame list out of the general `boundaryCopulas` table
    /// so widening it cannot silently affect typed-value matching; only
    /// the exactly-one-candidate DECISION is shared (D-07).
    private static func parseAnchoredNounBoundaryClause(
        _ s2: String, markers: [String], frames: [String]
    ) -> (value: String, shape: Int)? {
        let markerAlt = boundaryAlternation(markers)
        guard !markerAlt.isEmpty else { return nil }
        let frameAlt = boundaryAlternation(frames)
        guard !frameAlt.isEmpty else { return nil }
        let markerGrp = "(?:(?:\(markerAlt))\\b\\s*,?\\s+)+"
        let nsS2 = s2 as NSString
        let fullRange = NSRange(location: 0, length: nsS2.length)
        for shape in [2, 1] {
            let candidatePattern = properNounCandidatePattern(shape: shape)
            let pattern = "^\\s*\(markerGrp)(?:\(frameAlt))\\s+(\(candidatePattern))\\s*[.!?\"'”]*\\s*$"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            guard let match = regex.firstMatch(in: s2, options: [], range: fullRange), match.numberOfRanges > 1 else { continue }
            let valueRange = match.range(at: 1)
            guard let r = Range(valueRange, in: s2) else { continue }
            return (String(s2[r]), shape)
        }
        return nil
    }

    // MARK: - Connector + abort lists

    private static let germanConnectors: [String] = [
        "ich meine",
        "besser gesagt",
        "genauer gesagt",
        "oder vielmehr",
        "oder besser",
        "nein",
        "ne",
        "eigentlich",
        "das war",
        "ah nein",
        "ach nein",
        "moment mal",
        "ach moment",
        "ein moment",
        "ach ein moment",
        "wart mal",
        "wart",
        "warte",
    ]

    private static let englishConnectors: [String] = [
        "I mean",
        "I meant",
        "or rather",
        "or better",
        "scratch that",
        "no",
        "actually",
        "wait",
        "hold on",
    ]

    /// Connectors whose post-connector comma is *just punctuation*
    /// flanking the interjection ("..., No, it's at five 30 PM")
    /// rather than a clausal-continuation signal. For these we
    /// advance past the comma+whitespace and keep collapsing instead
    /// of aborting via guard 3a.
    ///
    /// Pure-correction connectors are a strict subset of the union
    /// of `germanConnectors` + `englishConnectors`. Anything NOT in
    /// this set (e.g. `I mean`, `ich meine`, `besser gesagt`) keeps
    /// the original abort-on-comma behavior so canonical false-
    /// positives like "..., ich meine, mit der ganzen Familie." stay
    /// untouched.
    private static let pureCorrectionConnectors: Set<String> = [
        // English
        "no", "actually", "wait", "hold on", "scratch that",
        // German
        "nein", "ne", "eigentlich", "das war",
        "ah nein", "ach nein",
        "moment mal", "ach moment", "ein moment", "ach ein moment",
        "wart mal", "wart", "warte",
    ]

    private static let germanAbortPronouns: Set<String> = [
        // Object / relative pronouns and demonstrative heads that signal
        // a clausal continuation rather than a substitute noun.
        "es", "das", "dass", "den", "dem", "der", "die",
        "was", "wer", "wie", "wo", "ob", "wenn",
    ]

    private static let englishAbortPronouns: Set<String> = [
        "it", "what", "that", "which", "who", "whom",
        "this", "when", "why", "how", "where",
    ]

    private static func connectorList(for language: String) -> [String] {
        let prefix = language.prefix(2).lowercased()
        switch prefix {
        case "en": return englishConnectors
        case "de": return germanConnectors
        default:   return germanConnectors
        }
    }

    private static func pronounAbortSet(for language: String) -> Set<String> {
        let prefix = language.prefix(2).lowercased()
        switch prefix {
        case "en": return englishAbortPronouns
        case "de": return germanAbortPronouns
        default:   return germanAbortPronouns
        }
    }

    // MARK: - Scratch command evidence source (Phase 39 / D-03, D-06)

    /// D-04 case 2 (named span) is a PARAMETERIZATION of the bare-command
    /// path (D-04 case 3) rather than a second code path — Claude's
    /// Discretion, resolved in favor of one path (39-CONTEXT.md).
    private enum ScratchSpanKind {
        case sentence
        case word
    }

    private struct ScratchCommand {
        let phrase: String
        let span: ScratchSpanKind
    }

    private static let englishScratchCommands: [ScratchCommand] = [
        ScratchCommand(phrase: "scratch that", span: .sentence),
        ScratchCommand(phrase: "scratch the last sentence", span: .sentence),
        ScratchCommand(phrase: "ignore the last sentence", span: .sentence),
        ScratchCommand(phrase: "forget the last sentence", span: .sentence),
        ScratchCommand(phrase: "scratch the last word", span: .word),
        ScratchCommand(phrase: "ignore the last word", span: .word),
    ]

    /// D-06: precision over recall — this list is DELIBERATELY small. Do
    /// NOT add synonyms, do NOT add bare-verb forms, do NOT add "löschen"
    /// in any form. The researcher grepped the user's real 940-record
    /// debug-log corpus: German imperatives (streichen / löschen /
    /// vergessen / ignorieren) are ordinary content words in this user's
    /// actual dictation, several of them while dictating coding
    /// instructions to an AI assistant. Every added phrase is another
    /// literal-prose collision. Growth comes later, from observed misses
    /// in the corpus, not from planning-time guessing.
    ///
    /// "streich das" / "streiche das" are the HIGHEST-RISK phrases in
    /// this list — shortest, most collision-prone. Plan 39-05's
    /// classification pass over the `selfcorr43` scale-replay is their
    /// acceptance authority.
    private static let germanScratchCommands: [ScratchCommand] = [
        ScratchCommand(phrase: "ignoriere den letzten Satz", span: .sentence),
        ScratchCommand(phrase: "ignorier den letzten Satz", span: .sentence),
        ScratchCommand(phrase: "vergiss den letzten Satz", span: .sentence),
        ScratchCommand(phrase: "streich das", span: .sentence),
        ScratchCommand(phrase: "streiche das", span: .sentence),
        ScratchCommand(phrase: "ignoriere das letzte Wort", span: .word),
        ScratchCommand(phrase: "vergiss das letzte Wort", span: .word),
        ScratchCommand(phrase: "streich das letzte Wort", span: .word),
        ScratchCommand(phrase: "streiche das letzte Wort", span: .word),
    ]

    /// The ONLY word tokens permitted to sit between a clause boundary
    /// and the command phrase (D-05 left anchor). The user's own
    /// canonical German exemplar is "Bitte ignoriere den letzten Satz",
    /// so the polite prefix must be tolerated on the left AND consumed
    /// by the delete. Deliberately NOT included: "also" / "so" — "Also
    /// streiche diesen…" is a real corpus sentence, and admitting a
    /// general discourse-marker prefix would widen the firing surface
    /// for zero user benefit.
    private static let scratchDiscoursePrefixesDE: Set<String> = ["bitte"]
    private static let scratchDiscoursePrefixesEN: Set<String> = ["please"]

    /// D-05's verb-complement exclusion, made explicit and separately
    /// testable. Deliberately redundant with the left-anchor boundary
    /// check (a blocker word is not a punctuation mark, so the anchor
    /// already rejects it) — belt and braces on the one guard whose
    /// failure destroys user content.
    private static let scratchComplementBlockersEN: Set<String> = [
        "to", "just", "and", "or", "not", "can", "could", "should",
        "would", "will", "might", "must", "don't", "doesn't", "didn't",
    ]
    private static let scratchComplementBlockersDE: Set<String> = [
        "zu", "einfach", "und", "oder", "nicht", "kann", "kannst",
        "könnte", "sollte", "soll", "will", "wollte", "würde", "muss",
        "musst",
    ]

    private static func scratchCommandList(for language: String) -> [ScratchCommand] {
        switch language.prefix(2).lowercased() {
        case "de": return germanScratchCommands
        case "en": return englishScratchCommands
        default:   return []
        }
    }

    private static func scratchDiscoursePrefixes(for language: String) -> Set<String> {
        switch language.prefix(2).lowercased() {
        case "de": return scratchDiscoursePrefixesDE
        case "en": return scratchDiscoursePrefixesEN
        default:   return []
        }
    }

    private static func scratchComplementBlockers(for language: String) -> Set<String> {
        switch language.prefix(2).lowercased() {
        case "de": return scratchComplementBlockersDE
        case "en": return scratchComplementBlockersEN
        default:   return []
        }
    }

    /// Gate flag governing the ENTIRE scratch-command evidence source
    /// (D-10). Default enabled; flipped to `false` (source ABSTAINS —
    /// the phrase is pasted literally, never corrupts) if even one prose
    /// corruption is classified attributable to it.
    ///
    /// RECORDED VERDICT (39-05, SECOND MITIGATION, 2026-07-11): SHIPS
    /// FULLY DISABLED. This evidence source has now failed its ship gate
    /// TWICE in two successive review passes — the whole feature
    /// abstains, not just the mid-utterance sub-case. With this flag
    /// `false`, every scratch command phrase (English and German) is
    /// pasted literally and nothing is ever destroyed.
    ///
    /// **Defect 1 (CR-01, `39-REVIEW.md`, found by post-hoc code
    /// review):** the `.word`-span path performs TWO separate deletions
    /// against the immutable original text and, when the command has
    /// trailing content, glues the retained prefix directly onto the
    /// retained suffix with no separator inserted:
    ///
    ///   IN:  "The server is called alpha beta. Scratch the last word.
    ///         It ships Friday."
    ///   OUT: "The server is called alphaIt ships Friday."
    ///
    /// This was mitigated same-day by shipping `enableScratchMidUtterance
    /// = false` (see that flag below) — narrowing the surface to
    /// tail-only commands, which was believed to route around the
    /// defect entirely.
    ///
    /// **Defect 2 (CR-02, `39-VERIFICATION.md`, found by independent
    /// fresh-eyes re-verification, 2026-07-11 — the SAME day, a second
    /// review pass):** even in the tail-only surface that the CR-01
    /// mitigation left ENABLED, the `.word`-span path silently rewrites
    /// or drops the PRECEDING sentence's own terminal punctuation
    /// whenever that sentence does not end in "." — a defect entirely
    /// independent of CR-01's trailing-content shape:
    ///
    ///   IN:  "Is it alpha beta? Scratch the last word."
    ///   OUT: "Is it alpha."                                  ("?" → ".")
    ///
    ///   IN:  "This is amazing alpha beta! Scratch the last word."
    ///   OUT: "This is amazing alpha."                        ("!" → ".")
    ///
    ///   IN:  "Alpha beta! Scratch the last word"
    ///   OUT: "Alpha"                                         ("!" dropped, no replacement)
    ///
    ///   IN:  "Das ist super Alpha Beta! Vergiss das letzte Wort."
    ///   OUT: "Das ist super Alpha."                          (German, same defect)
    ///
    ///   CONTROL (the one shape that works — every shipped fixture used
    ///   exactly this shape): "The server is called alpha beta. Scratch
    ///   the last word." → "The server is called alpha." (correct,
    ///   because the preceding sentence already ended in ".")
    ///
    /// **Architectural root cause (shared by both defects):** the
    /// `.word`-span case (see the `.word` case in
    /// `resolveScratchCommandPath` below) performs two independent
    /// deletions — Edit A (the "last word" token, found via a
    /// whitespace-only tokenizer that does not distinguish the
    /// PRECEDING sentence's own terminal punctuation from an ordinary
    /// word boundary) and Edit B (the command's own clause) — plus a
    /// Step 7 terminal-punctuation "restore" that only ever re-inserts
    /// the COMMAND's OWN consumed terminator, never the terminator that
    /// was actually deleted from the preceding sentence. The `.sentence`
    /// -span path, by contrast, uses ONE contiguous `deleteRange` (no
    /// two-edit arithmetic, no restore heuristic to get wrong) and is
    /// clean under every adversarial probe tried against it. Gap
    /// closure must rebuild the `.word` path on the `.sentence` path's
    /// single-contiguous-range model rather than patching the two-edit
    /// arithmetic further.
    ///
    /// **Why the ship gates gave a false pass — the most important
    /// fact for the next reader:** the `selfcorr43` scale-replay
    /// (18 changed / 1894 texts, zero new pairs versus the pre-phase
    /// baseline) was TELLING THE TRUTH — it genuinely found zero new
    /// corruptions — but it is structurally blind: the real debug-log
    /// corpus contains ZERO genuine scratch-command usages (RESEARCH
    /// A4 — every hit is meta-discussion about designing this feature),
    /// so it cannot exercise the firing path at all, let alone the
    /// punctuation-mutation shape. Separately, every one of plan
    /// 39-01's 11 hand-authored positive fixtures places the command at
    /// the END of the string with a PRECEDING PERIOD — the one shape
    /// that happens to work — so the fixture suite was a monoculture
    /// that could not have caught CR-02 either. Sound replay method,
    /// blind corpus; sound fixture method, monoculture fixture shapes.
    /// Neither gate was rubber-stamped; both were structurally unable
    /// to see this class of defect.
    ///
    /// See `39-REVIEW.md` (CR-01) and `39-VERIFICATION.md` (CR-02) for
    /// full empirical detail. See `39-SELFCORR43-CLASSIFICATION.md` for
    /// the (now superseded, but honestly-arrived-at) original scale-
    /// replay classification. The call site's `guard enableScratchCommand
    /// else { return text }` below is left fully in place,
    /// reachable-but-disabled — re-enabling this is a one-line flip once
    /// the `.word` case is rebuilt on the `.sentence` model and
    /// re-verified against BOTH defect shapes, not just CR-01's.
    private static let enableScratchCommand = false

    /// Gate flag governing ONLY D-11's WIDER mid-utterance firing
    /// surface — a command followed by real trailing content.
    /// Independent from `enableScratchCommand` because D-11's firing
    /// surface is materially wider than D-04 case 3's bare-tail case and
    /// must be able to fail (and degrade to tail-only) independently.
    /// Default enabled; flipped to `false` only if 39-05's scale-replay
    /// classifies even one corruption attributable to the wider anchor.
    ///
    /// CORRECTED VERDICT (39-05 mitigation, 2026-07-11): SHIPS DISABLED.
    /// The original 2026-07-11 verdict below ("SHIPS ENABLED", based on
    /// the `selfcorr43` scale-replay reporting 18 changed / 1894 texts —
    /// identical to the 18/1878 pre-phase baseline, zero new changed
    /// pairs) was a FALSE PASS. The scale-replay corpus contains ZERO
    /// genuine scratch-command usages (RESEARCH A4 — every hit is
    /// meta-discussion about designing this feature), so it structurally
    /// could not exercise the firing path that corrupts. Post-hoc code
    /// review (`39-REVIEW.md` CR-01) found the defect by inspection and
    /// empirically confirmed it by compiling this file standalone and
    /// running it against adversarial input — not via the gate. The
    /// `.word`-span two-edit deletion (see the `.word` case below) glues
    /// the retained prefix directly onto the retained suffix with no
    /// separator whenever the command has trailing content, e.g.:
    ///
    ///   IN:  "The server is called alpha beta. Scratch the last word.
    ///         It ships Friday."
    ///   OUT: "The server is called alphaIt ships Friday."
    ///
    /// This is the exact `hasTrailingContent` case this flag gates at
    /// the call site below — so the corruption is attributable to this
    /// flag, and per the plan's own non-negotiable rule ("even ONE
    /// corruption attributable to `enableScratchMidUtterance` → that
    /// flag alone ships `false`"), it now ships `false`. The feature
    /// degrades to tail-only: a scratch command must sit at the end of
    /// the utterance to fire (D-04 case 3's original, narrower, verified
    /// surface). The call site's `hasTrailingContent` guard below is
    /// left fully in place, reachable-but-disabled, so re-enabling this
    /// is a one-line flip once the `.word` case's delete-range
    /// arithmetic is fixed to insert a separator (see `39-REVIEW.md`
    /// CR-01 "Fix" section) and re-verified. See
    /// `39-SELFCORR43-CLASSIFICATION.md` for the original (now
    /// superseded) replay numbers.
    ///
    /// ORIGINAL RECORDED VERDICT (39-05, 2026-07-11, SUPERSEDED ABOVE):
    /// SHIPS ENABLED — same evidence as `enableScratchCommand` above
    /// (18/1894, 0 new changed pairs, 0 corruptions attributable to the
    /// wider mid-utterance anchor specifically). Human-confirmed
    /// 2026-07-11; see `39-SELFCORR43-CLASSIFICATION.md`.
    ///
    /// SUPERSEDED AGAIN, SAME DAY (39-05 SECOND mitigation, 2026-07-11,
    /// CR-02): a second defect, independent of this flag's own
    /// trailing-content shape, was found in the tail-only surface this
    /// mitigation left enabled — see `enableScratchCommand`'s doc
    /// comment above for the full CR-02 detail. The parent
    /// `enableScratchCommand` flag now ships `false` and its guard
    /// short-circuits before this flag's `hasTrailingContent` check is
    /// ever reached, so this flag's own value is currently moot. It is
    /// left at `false` (its already-correct value) rather than being
    /// reset to `true`, since the CR-01 defect it was built to contain
    /// remains unfixed. When gap closure rebuilds the `.word` case, both
    /// flags must be re-evaluated together against BOTH defect shapes.
    private static let enableScratchMidUtterance = false

    private static let scratchLeftBoundaryPunctuation = Set<Character>(".!?,;:")
    private static let scratchRightBoundaryPunctuation = Set<Character>(".!?,;")
    private static let scratchSentenceTerminators = Set<Character>(".!?")

    /// The delete engine for the D-03/D-06 scratch-command family. Runs
    /// as the LAST step of production `resolve(_:language:)` — after
    /// `resolveSentenceBoundaryPath` and `resolveCommaPath` — so it only
    /// ever sees spans the existing evidence-or-abstain logic has
    /// already declined to touch.
    ///
    /// **Placement rationale.** 39-RESEARCH.md recommended TWO
    /// integration points: a step "3.5" inside `resolveCommaPath`'s
    /// cascade for the comma-prefixed sub-case, plus a sibling pass for
    /// the rest. This plan deliberately uses ONE sibling pass instead.
    /// `resolveCommaPath` already ABSTAINS on a comma-prefixed bare
    /// command (the repair side is bare punctuation, so alignment/
    /// typed-value/anchored-noun evidence all return nil and the guard
    /// at the "no drop" line hits `continue`), leaving its output
    /// byte-identical — so this pass, running afterwards, sees the
    /// comma-prefixed command completely intact and covers it via its
    /// own left anchor accepting a comma as a clause boundary.
    /// `resolveCommaPath` therefore needs ZERO modification. Most
    /// importantly, this source NEVER routes through
    /// `actualDrop = min(drop, min(6, backwardCount))` — that cap
    /// silently truncates any sentence-length delete to its last 6
    /// tokens. There is NO token cap anywhere in this function: a
    /// whole-sentence delete routinely exceeds 6 tokens, and inheriting
    /// that cap would truncate it silently.
    private static func resolveScratchCommandPath(_ text: String, language: String) -> String {
        guard enableScratchCommand else { return text }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }

        let commands = scratchCommandList(for: language)
        guard !commands.isEmpty else { return text }

        let discoursePrefixes = scratchDiscoursePrefixes(for: language)
        let complementBlockers = scratchComplementBlockers(for: language)

        // Flat, escaped, longest-first alternation — identical
        // construction to resolveCommaPath's connector alternation. No
        // nesting, no unbounded quantifiers (T-39-05: no catastrophic-
        // backtracking surface). Longest-first ensures e.g. "streiche das
        // letzte Wort" wins over "streiche das" when both could match at
        // the same position.
        let sortedCommands = commands.sorted(by: { $0.phrase.count > $1.phrase.count })
        let alternation = sortedCommands
            .map { NSRegularExpression.escapedPattern(for: $0.phrase) }
            .joined(separator: "|")
        let pattern = "\\b(?:\(alternation))\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let nsMatches = regex.matches(in: text, options: [], range: fullRange)
        guard !nsMatches.isEmpty else { return text }

        let spanRangesRaw = boundarySentenceSpans(text)
        var spanRanges: [Range<String.Index>] = []
        for s in spanRangesRaw {
            guard let r = Range(s, in: text) else { return text }
            spanRanges.append(r)
        }
        guard !spanRanges.isEmpty else { return text }

        var edits: [(range: NSRange, replacement: String)] = []
        var acceptedEditRanges: [Range<String.Index>] = []
        var finalConsumedTerminator: String? = nil

        // Iterate matches in REVERSE so range arithmetic against the
        // immutable `text` stays stable, and so an earlier (leftward)
        // match can be skipped if it overlaps an edit already accepted
        // from a later (rightward) match.
        for nsMatch in nsMatches.reversed() {
            guard let matchRange = Range(nsMatch.range, in: text) else { continue }
            if acceptedEditRanges.contains(where: { $0.overlaps(matchRange) }) { continue }

            let matchedText = String(text[matchRange])
            guard let command = sortedCommands.first(where: {
                $0.phrase.caseInsensitiveCompare(matchedText) == .orderedSame
            }) else { continue }

            // Step 2: Left anchor (D-05 clause a).
            guard let commandStart = scratchLeftAnchor(
                matchStart: matchRange.lowerBound,
                text: text,
                discoursePrefixes: discoursePrefixes
            ) else { continue }

            // Step 3: Verb-complement exclusion (D-05 clause b).
            // Redundant with step 2 by construction (a blocker word is
            // not a boundary punctuation mark, so the left anchor
            // already rejects it) — kept explicit because D-05 names it.
            if let blockerRange = scratchPrecedingToken(endingAt: commandStart, in: text, lowerBound: text.startIndex) {
                let blockerToken = text[blockerRange].lowercased()
                if complementBlockers.contains(blockerToken) { continue }
            }

            // Step 4: Right guard — the command must terminate its own
            // clause. This is the highest-yield guard in the design: a
            // command is a command precisely because nothing rides
            // along with it.
            guard let (commandEnd, consumedTerminator) = scratchRightGuard(matchEnd: matchRange.upperBound, text: text) else {
                continue
            }

            // Step 5: D-11 gate — degrade to tail-only if the wider
            // mid-utterance anchor is disabled.
            let hasTrailingContent = scratchHasNonWhitespace(from: commandEnd, in: text)
            if hasTrailingContent && !enableScratchMidUtterance { continue }

            // Step 6: Target region.
            guard let spanIdx = spanRanges.firstIndex(where: { $0.contains(commandStart) }) else { continue }
            let spanRange = spanRanges[spanIdx]
            let spanStart = spanRange.lowerBound
            let commandBeginsItsSpan = text[spanStart..<commandStart].allSatisfy { $0.isWhitespace }

            switch command.span {
            case .sentence:
                let deleteStart: String.Index
                if commandBeginsItsSpan {
                    // The command is its own sentence — target the
                    // PREVIOUS span. No previous span means nothing
                    // precedes; the phrase is pasted literally, which
                    // is correct.
                    guard spanIdx > 0 else { continue }
                    deleteStart = spanRanges[spanIdx - 1].lowerBound
                } else {
                    // The command sits at the tail of a span with
                    // content before it (comma-prefixed / unpunctuated
                    // sub-cases). Per 39-RESEARCH.md Open Question 2,
                    // "the preceding sentence" means back to the last
                    // .!? boundary — NOT back to the last comma. This
                    // can over-delete comma-separated clauses; that is
                    // the intended, user-accepted coarseness.
                    deleteStart = spanStart
                }
                let deleteRange = deleteStart..<commandEnd
                edits.append((NSRange(deleteRange, in: text), ""))
                acceptedEditRanges.append(deleteRange)

            case .word:
                // Edit B's clause-deletion left boundary: scan backward
                // from commandStart over whitespace and, if present, a
                // single , or ; and any whitespace before that.
                var clauseStart = commandStart
                while clauseStart > text.startIndex, text[text.index(before: clauseStart)].isWhitespace {
                    clauseStart = text.index(before: clauseStart)
                }
                if clauseStart > text.startIndex, [",", ";"].contains(text[text.index(before: clauseStart)]) {
                    clauseStart = text.index(before: clauseStart)
                    while clauseStart > text.startIndex, text[text.index(before: clauseStart)].isWhitespace {
                        clauseStart = text.index(before: clauseStart)
                    }
                }

                // The search region for "the last word token" EXCLUDES
                // the boundary comma/semicolon consumed above (Edit B
                // owns that), so the two edits are adjacent, never
                // overlapping.
                let searchRange: Range<String.Index>
                if commandBeginsItsSpan {
                    guard spanIdx > 0 else { continue }
                    searchRange = spanRanges[spanIdx - 1]
                } else {
                    searchRange = spanStart..<clauseStart
                }

                guard let lastToken = scratchLastWordToken(in: searchRange, text: text) else { continue }

                var editAStart = lastToken.lowerBound
                while editAStart > searchRange.lowerBound, text[text.index(before: editAStart)].isWhitespace {
                    editAStart = text.index(before: editAStart)
                }
                let editARange = editAStart..<lastToken.upperBound
                let clauseRange = clauseStart..<commandEnd

                // There is no token cap anywhere in this function
                // (unlike resolveCommaPath's `actualDrop` cap) — a
                // whole-word or whole-sentence delete is never
                // truncated.
                edits.append((NSRange(editARange, in: text), ""))
                edits.append((NSRange(clauseRange, in: text), ""))
                acceptedEditRanges.append(editARange)
                acceptedEditRanges.append(clauseRange)
            }

            if commandEnd == text.endIndex, let terminator = consumedTerminator {
                finalConsumedTerminator = terminator
            }
        }

        guard !edits.isEmpty else { return text }

        var result = text
        for (range, replacement) in edits.sorted(by: { $0.range.location > $1.range.location }) {
            guard let r = Range(range, in: result) else { continue }
            result.replaceSubrange(r, with: replacement)
        }

        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        // Step 7: terminal-punctuation restore. Without this, a
        // word-span delete that consumed the command's own trailing
        // period (e.g. "…beta." -> the deleted token carried the
        // period with it) would silently lose the sentence's full stop.
        if !result.isEmpty,
           let terminator = finalConsumedTerminator,
           let last = result.last,
           !scratchSentenceTerminators.contains(last)
        {
            result += terminator
        }

        return result
    }

    /// D-05 left anchor: scan backward from `matchStart` over
    /// whitespace. If the boundary is a punctuation mark or string
    /// start, anchor directly. Otherwise the immediately preceding word
    /// token must be an accepted discourse prefix ("bitte"/"please",
    /// D-05) whose OWN left side anchors the same way — the prefix is
    /// then consumed as part of the command clause. Any other preceding
    /// word → ABSTAIN (nil). Mirrors the resolver's existing comma-
    /// prefix guard, the guard that has actually held up in production.
    private static func scratchLeftAnchor(
        matchStart: String.Index,
        text: String,
        discoursePrefixes: Set<String>
    ) -> String.Index? {
        var scanIdx = matchStart
        while scanIdx > text.startIndex, text[text.index(before: scanIdx)].isWhitespace {
            scanIdx = text.index(before: scanIdx)
        }
        if scanIdx == text.startIndex {
            return matchStart
        }
        if scratchLeftBoundaryPunctuation.contains(text[text.index(before: scanIdx)]) {
            return matchStart
        }
        guard let tokenRange = scratchPrecedingToken(endingAt: scanIdx, in: text, lowerBound: text.startIndex) else {
            return nil
        }
        let token = text[tokenRange].lowercased()
        guard discoursePrefixes.contains(token) else { return nil }

        var scanIdx2 = tokenRange.lowerBound
        while scanIdx2 > text.startIndex, text[text.index(before: scanIdx2)].isWhitespace {
            scanIdx2 = text.index(before: scanIdx2)
        }
        if scanIdx2 == text.startIndex {
            return tokenRange.lowerBound
        }
        if scratchLeftBoundaryPunctuation.contains(text[text.index(before: scanIdx2)]) {
            return tokenRange.lowerBound
        }
        return nil
    }

    /// D-05 right guard: scan forward from `matchEnd` over whitespace.
    /// If a clause-terminating punctuation run follows, consume it (and
    /// the whitespace after it) and return the resulting `commandEnd`,
    /// plus the consumed sentence-terminator text (`. ! ?`) IF nothing
    /// but whitespace follows it (used to restore a dropped trailing
    /// period). A letter, digit, or any other non-boundary character
    /// means the command does NOT terminate its own clause here →
    /// ABSTAIN (nil).
    private static func scratchRightGuard(
        matchEnd: String.Index,
        text: String
    ) -> (commandEnd: String.Index, consumedTerminator: String?)? {
        var idx = matchEnd
        while idx < text.endIndex, text[idx].isWhitespace {
            idx = text.index(after: idx)
        }
        if idx == text.endIndex {
            return (text.endIndex, nil)
        }
        guard scratchRightBoundaryPunctuation.contains(text[idx]) else { return nil }

        var punctEnd = idx
        while punctEnd < text.endIndex, scratchRightBoundaryPunctuation.contains(text[punctEnd]) {
            punctEnd = text.index(after: punctEnd)
        }
        let punctRun = String(text[idx..<punctEnd])

        var afterWs = punctEnd
        while afterWs < text.endIndex, text[afterWs].isWhitespace {
            afterWs = text.index(after: afterWs)
        }

        let isSentenceTerminatorRun = !punctRun.isEmpty && punctRun.allSatisfy { scratchSentenceTerminators.contains($0) }
        let consumedTerminator = (isSentenceTerminatorRun && afterWs == text.endIndex) ? punctRun : nil
        return (afterWs, consumedTerminator)
    }

    /// True if any non-whitespace character exists at or after `idx`.
    private static func scratchHasNonWhitespace(from idx: String.Index, in text: String) -> Bool {
        var i = idx
        while i < text.endIndex {
            if !text[i].isWhitespace { return true }
            i = text.index(after: i)
        }
        return false
    }

    /// The maximal run of non-whitespace characters ending exactly at
    /// `idx` (exclusive upper bound), not crossing below `lowerBound`.
    /// Returns nil if there is no such run (i.e. `idx` is already
    /// preceded by whitespace or is at `lowerBound`).
    private static func scratchPrecedingToken(
        endingAt idx: String.Index,
        in text: String,
        lowerBound: String.Index
    ) -> Range<String.Index>? {
        guard idx > lowerBound else { return nil }
        var start = idx
        while start > lowerBound, !text[text.index(before: start)].isWhitespace {
            start = text.index(before: start)
        }
        guard start < idx else { return nil }
        return start..<idx
    }

    /// The last whitespace-delimited token inside `range` (trailing
    /// whitespace inside `range` is skipped first). Used to find the
    /// "last word" for D-04 case 2's named-span `.word` deletion.
    private static func scratchLastWordToken(in range: Range<String.Index>, text: String) -> Range<String.Index>? {
        var idx = range.upperBound
        while idx > range.lowerBound, text[text.index(before: idx)].isWhitespace {
            idx = text.index(before: idx)
        }
        guard idx > range.lowerBound else { return nil }
        var start = idx
        while start > range.lowerBound, !text[text.index(before: start)].isWhitespace {
            start = text.index(before: start)
        }
        return start..<idx
    }

    // MARK: - Comma-path connector-chain + typed-value evidence helpers
    //         (Phase 43/D-03, D-01, D-07)

    /// If `s` starts (case-insensitively, at a word boundary) with a
    /// pure-correction connector, return that connector's character
    /// length. Otherwise nil. Longest-first so multi-word connectors
    /// ("ach nein", "moment mal") win over any shorter connector that
    /// happens to be a textual prefix. Used to strip chained connectors
    /// ("no actually", "nein eigentlich") as a single unit before the
    /// repair-side scan — Phase 43/D-03/SELFCORR-04.
    private static func leadingPureCorrectionConnectorLength(_ s: String) -> Int? {
        let lowerS = s.lowercased()
        let sorted = pureCorrectionConnectors.sorted(by: { $0.count > $1.count })
        for connector in sorted {
            guard lowerS.hasPrefix(connector) else { continue }
            let afterIdx = s.index(s.startIndex, offsetBy: connector.count)
            if afterIdx < s.endIndex {
                let nextChar = s[afterIdx]
                if nextChar.isLetter || nextChar.isNumber { continue }
            }
            return connector.count
        }
        return nil
    }

    /// If `s` LEADS with (optionally a preposition from `preps`, then) a
    /// typed value from the shared `boundaryValueTypes` table, return the
    /// matched value text and its type. Otherwise nil. This is the comma
    /// path's typed-value evidence source (Phase 43/D-01 + D-07
    /// convergence) — the repair side must lead with the value itself; a
    /// copula-led repair ("it's 9:00 ...") does not match this anchored
    /// pattern and correctly falls through to abstain (merging the
    /// sentence-boundary path's copula handling into the comma path is
    /// out of scope per 43-RESEARCH.md Finding 3).
    private static func leadingTypedValue(_ s: String, preps: [String]) -> (value: String, vtype: String)? {
        let prepAlt = boundaryAlternation(preps)
        let prepGrp = prepAlt.isEmpty ? "" : "(?:(?:\(prepAlt))\\b\\s+)?"
        let nsS = s as NSString
        let fullRange = NSRange(location: 0, length: nsS.length)
        for (vtype, vpat) in boundaryValueTypes {
            let pattern = "^\\s*\(prepGrp)(\(vpat))\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            guard let match = regex.firstMatch(in: s, options: [], range: fullRange), match.numberOfRanges > 1 else {
                continue
            }
            let valueRange = match.range(at: 1)
            guard let r = Range(valueRange, in: s) else { continue }
            return (String(s[r]), vtype)
        }
        return nil
    }

    /// Return the 0-based index of the whitespace-delimited token in `s`
    /// that STARTS exactly at `target`, or nil if no token starts there.
    /// Used to align a typed-value regex match (Phase 43/D-07) back onto
    /// the same token-index drop mechanics the exact-alignment path
    /// already uses (keeping the comma path's single-string splice
    /// mechanics unchanged — only the evidence DECISION is shared).
    private static func tokenIndexStartingAt(_ s: String, target: String.Index) -> Int? {
        var idx = 0
        var i = s.startIndex
        var inToken = false
        while i < s.endIndex {
            let c = s[i]
            if c.isWhitespace {
                if inToken {
                    idx += 1
                    inToken = false
                }
            } else {
                if !inToken {
                    if i == target { return idx }
                    inToken = true
                }
            }
            i = s.index(after: i)
        }
        return nil
    }

    // MARK: - Tokenization helpers

    /// Whitespace-separated tokens, dropping empty entries.
    private static func tokenize(_ s: String) -> [String] {
        return s.split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }

    /// Return the character index of the start of the n-th whitespace-
    /// separated token in `s`. n is 0-indexed.
    /// Returns nil if `s` has fewer than `n + 1` tokens.
    private static func startIndexOfNthToken(_ s: String, n: Int) -> String.Index? {
        var seen = 0
        var i = s.startIndex
        var inToken = false
        var tokenStart: String.Index? = nil
        while i < s.endIndex {
            let c = s[i]
            if c.isWhitespace {
                if inToken {
                    if seen == n {
                        return tokenStart
                    }
                    seen += 1
                    inToken = false
                }
            } else {
                if !inToken {
                    tokenStart = i
                    inToken = true
                }
            }
            i = s.index(after: i)
        }
        // Reached end while inside a token.
        if inToken {
            if seen == n { return tokenStart }
        }
        return nil
    }
}

// MARK: - String helpers

private extension String {
    /// Lowercase + strip a single trailing sentence-punctuation char if any.
    func lowercasedTrimmingPunctuation() -> String {
        var s = self
        if let last = s.last, ".,;:!?".contains(last), s.count > 1 {
            s = String(s.dropLast())
        }
        return s.lowercased()
    }
}
