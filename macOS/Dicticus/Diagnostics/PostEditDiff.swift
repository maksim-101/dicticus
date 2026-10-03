#if DEBUG_RECORDER
// PostEditDiff — pure logic for the post-paste edit log (quick 261003-jvq, FABLE-ADVICE §5.3).
// Tokenizing, exclusion, span location, relocation, word diff, the observation Session and
// the record schema. Nothing here reads Accessibility or disk; PostEditProbe does the I/O.

import Foundation

enum PostEditDiff {

    static let pollIntervalMs = 500
    static let observationLimitSeconds = 60
    static let consecutiveLostToFinalize = 2
    static let axMessagingTimeoutSeconds: Float = 0.25
    static let fieldCapUTF16 = 100_000
    static let minPastedTokens = 3
    static let contextTokens = 3
    static let hunkSideCap = 6
    static let hunkCountCap = 8
    static let alignmentCellCap = 3_000_000
    static let anchorSlackUTF16 = 32

    static let excludedBundleIDs: Set<String> = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.agilebits.onepassword-osx",
        "com.apple.Passwords", "com.apple.keychainaccess", "com.bitwarden.desktop",
        "org.keepassxc.keepassxc", "com.lastpass.LastPass"
    ]

    enum Outcome: String, Codable, Sendable {
        case excludedApp = "excluded-app"
        case noFocusedElement = "no-focused-element"
        case secure
        case noTextValue = "no-text-value"
        case spanNotFound = "span-not-found"
        case fieldGone = "field-gone"
        case unchanged
        case edited
    }

    struct Token: Equatable, Sendable {
        let text: String
        let utf16Start: Int
        let utf16End: Int
    }

    /// U+0000 counts as a gap: iTerm2's Accessibility text reports cells a TUI never wrote as NUL,
    /// which is how word gaps in Claude Code's input box arrive (261003-orx).
    static func isSeparator(_ u: Unicode.Scalar) -> Bool {
        CharacterSet.whitespacesAndNewlines.contains(u) || u.value == 0 || (0x2500...0x257F).contains(u.value)
    }

    static func tokenize(_ s: String) -> [Token] {
        var out: [Token] = []
        var cur = String.UnicodeScalarView()
        var start = 0
        var offset = 0
        for u in s.unicodeScalars {
            if isSeparator(u) {
                if !cur.isEmpty {
                    out.append(Token(text: String(cur), utf16Start: start, utf16End: offset))
                    cur = String.UnicodeScalarView()
                }
            } else {
                if cur.isEmpty { start = offset }
                cur.append(u)
            }
            offset += u.utf16.count
        }
        if !cur.isEmpty { out.append(Token(text: String(cur), utf16Start: start, utf16End: offset)) }
        return out
    }

    static func exclusion(bundleID: String?, role: String?, subrole: String?) -> Outcome? {
        if let bundleID, excludedBundleIDs.contains(bundleID) { return .excludedApp }
        if subrole == "AXSecureTextField" { return .secure }
        return nil
    }

    enum LocateFailure: String, Error {
        case tooShort = "too_short"
        case pasteTime = "paste_time"
    }

    enum MatchKind: String, Codable, Sendable {
        case exact
        case tokens
    }

    static func locateAtPaste(
        pasted: String, field: String, fieldTokens: [Token], caretUTF16: Int?
    ) -> Result<(range: Range<Int>, matchKind: MatchKind), LocateFailure> {
        let pastedTexts = tokenize(pasted).map(\.text)
        let n = pastedTexts.count
        guard n >= minPastedTokens else { return .failure(.tooShort) }
        var ends: [Int] = []
        if fieldTokens.count >= n {
            for i in 0...(fieldTokens.count - n) where (0..<n).allSatisfy({ fieldTokens[i + $0].text == pastedTexts[$0] }) {
                ends.append(i + n)
            }
        }
        guard !ends.isEmpty else { return .failure(.pasteTime) }
        let chosenEnd: Int
        if let caretUTF16 {
            let caretIdx = fieldTokens.filter { $0.utf16End <= caretUTF16 }.count
            chosenEnd = ends.min { (abs($0 - caretIdx), -$0) < (abs($1 - caretIdx), -$1) }!
        } else {
            chosenEnd = ends.last!
        }
        let trimmed = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        let kind: MatchKind = field.contains(trimmed) ? .exact : .tokens
        return .success((range: (chosenEnd - n)..<chosenEnd, matchKind: kind))
    }

    struct Change: Codable, Sendable, Equatable {
        let kind: String
        let from: [String]?
        let to: [String]?
        let before: [String]?
        let after: [String]?
        let from_n: Int
        let to_n: Int
    }

    struct Record: Codable, Sendable, Equatable {
        let ts: String
        let paste_ts: String
        let dictation_ts: String?
        let dictation_emission: Int?
        let bundle_id: String?
        let mode: String
        let pasted_words: Int
        let outcome: Outcome
        let reason: String?
        let located_at_paste: Bool
        let match_kind: MatchKind?
        let end: String?
        let polls: Int
        let located_polls: Int
        let observed_ms: Int?
        let last_located_ms: Int?
        let ax_ms_max: Double
        let role: String?
        let subrole: String?
        let field_utf16: Int?
        let secure_input_enabled: Bool
        let changes: [Change]?
        let changes_truncated: Int?
        let word_edits: Int
        let observable_edit: Bool

        func finalized(result: (outcome: Outcome, reason: String?, changes: [Change]?, truncated: Int?, wordEdits: Int),
                       end: EndReason, polls: Int, locatedPolls: Int, observedMs: Int, lastLocatedMs: Int?,
                       axMsMax: Double, ts: String) -> Record {
            Record(
                ts: ts, paste_ts: paste_ts, dictation_ts: dictation_ts, dictation_emission: dictation_emission,
                bundle_id: bundle_id, mode: mode, pasted_words: pasted_words, outcome: result.outcome,
                reason: result.reason, located_at_paste: located_at_paste, match_kind: match_kind, end: end.rawValue,
                polls: polls, located_polls: locatedPolls, observed_ms: observedMs, last_located_ms: lastLocatedMs,
                ax_ms_max: axMsMax, role: role, subrole: subrole, field_utf16: field_utf16,
                secure_input_enabled: secure_input_enabled, changes: result.changes,
                changes_truncated: result.truncated, word_edits: result.wordEdits,
                observable_edit: result.outcome == .edited)
        }
    }

    /// Semi-global token alignment of the pasted span against the field: free leading and trailing
    /// field tokens, unit cost for substitution, insertion and deletion. Nil beyond the tolerance.
    static func relocate(pasted: [String], fieldTokens: [Token], caretUTF16: Int?, window: Range<Int>? = nil) -> Range<Int>? {
        let n = pasted.count
        guard n > 0, !fieldTokens.isEmpty else { return nil }
        let maxDist = max(1, (2 * n) / 5)
        let total = fieldTokens.count
        // Position anchor: only matches overlapping `window` (UTF-16 offsets) may be returned.
        func overlapsWindow(_ i: Int) -> Bool {
            guard let window else { return true }
            return fieldTokens[i].utf16End > window.lowerBound && fieldTokens[i].utf16Start < window.upperBound
        }
        let overlapping = (0..<total).filter(overlapsWindow)
        if window != nil && overlapping.isEmpty { return nil }
        let minEnd = (overlapping.first ?? 0) + 1
        let maxEnd = window == nil ? total : (overlapping.last ?? 0) + 1 + n + maxDist
        let caretIdx = caretUTF16.map { c in fieldTokens.filter { $0.utf16End <= c }.count } ?? total
        var lo = 0
        var hi = total
        if n * total > alignmentCellCap {
            lo = max(0, caretIdx - (2 * n + 100))
            hi = min(total, caretIdx + 2 * n + 100)
        }
        let window = fieldTokens[lo..<hi].map(\.text)
        var prev = [Int](repeating: 0, count: window.count + 1)
        for i in 1...n {
            var cur = [Int](repeating: 0, count: window.count + 1)
            cur[0] = i
            for j in stride(from: 1, through: window.count, by: 1) {
                let sub = prev[j - 1] + (pasted[i - 1] == window[j - 1] ? 0 : 1)
                cur[j] = min(sub, prev[j] + 1, cur[j - 1] + 1)
            }
            prev = cur
        }
        var best: (cost: Int, dist: Int, end: Int)?
        for j in stride(from: 1, through: window.count, by: 1) {
            let end = lo + j
            if end < minEnd || end > maxEnd { continue }
            let cand = (cost: prev[j], dist: abs(end - caretIdx), end: end)
            if let b = best {
                if (cand.cost, cand.dist, -cand.end) < (b.cost, b.dist, -b.end) { best = cand }
            } else {
                best = cand
            }
        }
        guard let best, best.cost <= maxDist else { return nil }

        let sliceStart = max(0, best.end - n - maxDist)
        let slice = fieldTokens[sliceStart..<best.end].map(\.text)
        let m = slice.count
        var d = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { d[i][0] = i }
        for i in 1...n {
            for j in stride(from: 1, through: m, by: 1) {
                let sub = d[i - 1][j - 1] + (pasted[i - 1] == slice[j - 1] ? 0 : 1)
                d[i][j] = min(sub, d[i - 1][j] + 1, d[i][j - 1] + 1)
            }
        }
        var i = n
        var j = m
        var firstExact: Int?
        var lastExact: Int?
        while i > 0 {
            if j > 0, d[i][j] == d[i - 1][j - 1] + (pasted[i - 1] == slice[j - 1] ? 0 : 1) {
                if pasted[i - 1] == slice[j - 1] {
                    firstExact = j - 1
                    if lastExact == nil { lastExact = j - 1 }
                }
                i -= 1; j -= 1
            } else if d[i][j] == d[i - 1][j] + 1 {
                i -= 1
            } else {
                j -= 1
            }
        }
        // Privacy: the range starts and ends on exact token matches, so a substituted or inserted
        // neighbour at either boundary (text the user did not dictate) is never part of the span.
        guard let firstExact, let lastExact else { return nil }
        let range = (sliceStart + firstExact)..<(sliceStart + lastExact + 1)
        if window != nil && !range.contains(where: overlapsWindow) { return nil }
        return range
    }

    private static func reduced(_ tokens: [String]) -> String {
        String(String.UnicodeScalarView(
            tokens.joined(separator: " ").lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }))
    }

    /// Token LCS between the pasted span and its current text, grouped into maximal hunks.
    /// Context is drawn from the pasted array only, so field text outside the span cannot leak.
    static func diff(pasted: [String], current: [String], countsOnly: Bool = false) -> (changes: [Change], truncated: Int) {
        let n = pasted.count
        let m = current.count
        var l = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: 1, through: n, by: 1) {
            for j in stride(from: 1, through: m, by: 1) {
                l[i][j] = pasted[i - 1] == current[j - 1] ? l[i - 1][j - 1] + 1 : max(l[i - 1][j], l[i][j - 1])
            }
        }
        var matches: [(Int, Int)] = []
        var i = n
        var j = m
        while i > 0 && j > 0 {
            if pasted[i - 1] == current[j - 1] {
                matches.append((i - 1, j - 1)); i -= 1; j -= 1
            } else if l[i - 1][j] >= l[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }
        matches.reverse()
        matches.append((n, m))

        var changes: [Change] = []
        var prevP = 0
        var prevC = 0
        for (a, b) in matches {
            if a > prevP || b > prevC {
                let from = Array(pasted[prevP..<a])
                let to = Array(current[prevC..<b])
                // Privacy: a hunk touching either end of the span logs counts only; its replacement
                // text sits at the boundary, where field text outside the span could be mistaken for it.
                let touchesEnd = prevP == 0 || prevC == 0 || a == n || b == m
                if countsOnly || touchesEnd || from.count > hunkSideCap || to.count > hunkSideCap {
                    changes.append(Change(kind: "rewrite", from: nil, to: nil, before: nil, after: nil,
                                          from_n: from.count, to_n: to.count))
                } else {
                    let kind = reduced(from) == reduced(to) ? "case_punct" : "word"
                    changes.append(Change(
                        kind: kind, from: from, to: to,
                        before: Array(pasted[max(0, prevP - contextTokens)..<prevP]),
                        after: Array(pasted[a..<min(n, a + contextTokens)]),
                        from_n: from.count, to_n: to.count))
                }
            }
            prevP = a + 1
            prevC = b + 1
        }
        let kept = Array(changes.prefix(hunkCountCap))
        return (kept, changes.count - kept.count)
    }

    /// Where the span sat at paste time (UTF-16 offsets in the field) and how long the field was then.
    struct Anchor: Equatable, Sendable {
        let start: Int
        let end: Int
        let fieldUTF16: Int

        init(range: Range<Int>, fieldTokens: [Token]) {
            start = fieldTokens[range.lowerBound].utf16Start
            end = fieldTokens[range.upperBound - 1].utf16End
            fieldUTF16 = fieldTokens.last?.utf16End ?? 0
        }
    }

    enum EndReason: String {
        case focusLeft = "focus_left"
        case nextDictation = "next_dictation"
        case revertToRaw = "revert_to_raw"
        case timeout
        case elementGone = "element_gone"
        case spanLost = "span_lost"
    }

    enum FieldRead {
        case gone
        case read(tokens: [Token], caretUTF16: Int?, stillFocused: Bool)
    }

    struct Session: Sendable {
        let pasted: [String]
        let anchor: Anchor?
        private(set) var lastLocated: [String]?
        private(set) var polls = 0
        private(set) var locatedPolls = 0
        private(set) var consecutiveLost = 0
        private(set) var sawGone = false

        init(pasted: [String], anchor: Anchor?) {
            self.pasted = pasted
            self.anchor = anchor
        }

        mutating func ingest(_ read: FieldRead, elapsedMs: Int) -> EndReason? {
            polls += 1
            switch read {
            case .gone:
                sawGone = true
                return .elementGone
            case .read(let tokens, let caretUTF16, let stillFocused):
                var window: Range<Int>?
                if let anchor {
                    // Growth is capped at the span's own length: a user insertion cannot push a
                    // far-away look-alike sentence into the window.
                    let growth = min(max(0, (tokens.last?.utf16End ?? 0) - anchor.fieldUTF16), anchor.end - anchor.start)
                    window = (anchor.start - PostEditDiff.anchorSlackUTF16)
                        ..< (anchor.end + PostEditDiff.anchorSlackUTF16 + growth)
                }
                if let range = PostEditDiff.relocate(pasted: pasted, fieldTokens: tokens, caretUTF16: caretUTF16, window: window) {
                    lastLocated = tokens[range].map(\.text)
                    locatedPolls += 1
                    consecutiveLost = 0
                } else {
                    consecutiveLost += 1
                }
                if !stillFocused { return .focusLeft }
                if consecutiveLost >= PostEditDiff.consecutiveLostToFinalize { return .spanLost }
                return nil
            }
        }

        func result() -> (outcome: Outcome, reason: String?, changes: [Change]?, truncated: Int?, wordEdits: Int) {
            guard locatedPolls > 0, let lastLocated else {
                return sawGone ? (.fieldGone, nil, nil, nil, 0) : (.spanNotFound, "lost", nil, nil, 0)
            }
            let d = PostEditDiff.diff(pasted: pasted, current: lastLocated, countsOnly: anchor == nil)
            if d.changes.isEmpty { return (.unchanged, nil, nil, nil, 0) }
            return (.edited, nil, d.changes, d.truncated > 0 ? d.truncated : nil,
                    d.changes.filter { $0.kind == "word" }.count)
        }
    }

    static func encodeLine(_ r: Record) -> Data? {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard var data = try? enc.encode(r) else { return nil }
        data.append(0x0A)
        return data
    }
}

#endif
