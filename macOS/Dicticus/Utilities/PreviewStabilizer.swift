import Foundation

/// Decides which words of the live preview the panel shows as settled and which as tentative
/// (Phase 51, plan 51-10). It shapes only what the panel shows; the pasted text comes from the
/// final decode (D-01).
///
/// A word settles only after two consecutive previews agree on it, and the last `holdBack` words
/// of the newest preview never settle. Settled words are append-only. The preview re-decodes a
/// sliding tail of the audio, so each new hypothesis is aligned on the end of the settled text
/// instead of being compared from its first word.
struct PreviewStabilizer {
    static let holdBack = 2
    static let anchorLength = 3

    private(set) var settled: [String] = []
    private(set) var tentative: [String] = []
    /// Previews whose settled tail was missing but whose older settled words still anchored (Whisper revised a word).
    private(set) var conflicts = 0
    /// Previews that shared nothing with the recent settled words (speech resumed beyond the window).
    private(set) var gaps = 0

    var settledText: String { settled.joined(separator: " ") }
    var tentativeText: String { tentative.joined(separator: " ") }

    mutating func ingest(_ hypothesis: String) {
        let words = hypothesis.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else {
            tentative = []
            return
        }
        let start = alignmentStart(in: words)
        let rest = Array(words[start...])
        let agreed = zip(tentative, rest).prefix(while: { $0 == $1 }).count
        let count = max(0, min(agreed, rest.count - Self.holdBack))
        settled.append(contentsOf: rest[..<count])
        tentative = Array(rest[count...])
    }

    mutating func settleAll() {
        settled.append(contentsOf: tentative)
        tentative = []
    }

    /// Index in `words` just past the settled text.
    private mutating func alignmentStart(in words: [String]) -> Int {
        if settled.count < Self.anchorLength {
            return min(settled.count, words.count)
        }
        let normalized = words.map(Self.normalize)
        let anchor = settled.suffix(Self.anchorLength).map(Self.normalize)
        if let index = Self.rightmost(of: anchor, in: normalized) {
            return index + Self.anchorLength
        }
        return fallbackStart(in: normalized)
    }

    /// The settled tail is missing from the hypothesis. Look for the most recent pair of settled
    /// words that still occurs: Whisper revised a word after it settled (conflict). With no shared
    /// pair the hypothesis is new speech beyond the window, for example after a long pause (gap).
    /// Settled words are never touched; only the agreement baseline restarts.
    private mutating func fallbackStart(in normalized: [String]) -> Int {
        let settledNormalized = settled.map(Self.normalize)
        let oldest = max(0, settled.count - (normalized.count + Self.anchorLength))
        var pairStart = settled.count - 2
        while pairStart >= oldest {
            let pair = Array(settledNormalized[pairStart..<pairStart + 2])
            if let hit = Self.rightmost(of: pair, in: normalized) {
                conflicts += 1
                let wordsAfterPair = settled.count - (pairStart + 2)
                return min(hit + 2 + wordsAfterPair, normalized.count)
            }
            pairStart -= 1
        }
        gaps += 1
        return 0
    }

    /// Lowercased, without leading or trailing punctuation and symbols.
    static func normalize(_ word: String) -> String {
        let edge = CharacterSet.punctuationCharacters.union(.symbols)
        return word.lowercased().trimmingCharacters(in: edge)
    }

    /// Start index of the rightmost run of `needle` in `haystack`.
    private static func rightmost(of needle: [String], in haystack: [String]) -> Int? {
        guard needle.count <= haystack.count else { return nil }
        for index in stride(from: haystack.count - needle.count, through: 0, by: -1)
        where Array(haystack[index..<index + needle.count]) == needle {
            return index
        }
        return nil
    }
}
