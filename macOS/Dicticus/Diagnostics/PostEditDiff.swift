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

    static func tokenize(_ s: String) -> [Token] {
        []
    }

    static func exclusion(bundleID: String?, role: String?, subrole: String?) -> Outcome? {
        nil
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
        .failure(.pasteTime)
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
