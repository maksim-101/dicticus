import Foundation

/// Picking words out of a dictation's raw text to add them to the dictionary (slice 52).
enum WordPick {
    /// The whitespace-separated tokens of `text`, punctuation still attached.
    static func tokens(of text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// The text of the run of tokens between `anchor` and `index` (either order),
    /// joined by single spaces, with punctuation trimmed at both ends.
    static func text(of tokens: [String], from anchor: Int, to index: Int) -> String {
        guard !tokens.isEmpty else { return "" }
        let lo = max(0, min(anchor, index)), hi = min(tokens.count - 1, max(anchor, index))
        guard lo <= hi else { return "" }
        return trimmed(tokens[lo...hi].joined(separator: " "))
    }

    static func trimmed(_ s: String) -> String {
        let isWordChar: (Character) -> Bool = { $0.isLetter || $0.isNumber }
        guard let first = s.firstIndex(where: isWordChar), let last = s.lastIndex(where: isWordChar) else { return "" }
        return String(s[first...last])
    }
}
