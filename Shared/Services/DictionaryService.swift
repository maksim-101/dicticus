import Foundation
import Combine

/// Provenance tag for a dictionary entry. Persisted as a Codable string inside
/// `DictionaryMetadata`. Three cases: entries seeded by the app (default), entries
/// created/edited by the user directly (user), and entries imported from a file
/// (imported). Old records lacking this key decode as `.user` via `decodeIfPresent`.
enum LexiconSource: String, Codable {
    case `default`
    case user
    case imported

    /// Display sort priority: lower value surfaces higher in the list.
    /// user (0) > imported (1) > default (2).
    var sortPriority: Int {
        switch self {
        case .user:     return 0
        case .imported: return 1
        case .default:  return 2
        }
    }
}

/// Metadata for a dictionary entry.
///
/// Custom `init(from:)` uses `decodeIfPresent` so that existing persisted records
/// (which lack the `source` key) decode successfully with `source == .user` instead
/// of throwing `keyNotFound` and wiping the dictionary. This is the critical
/// upgrade-safety invariant for Phase 31-01 (RESEARCH Pitfall 1).
struct DictionaryMetadata: Codable, Equatable {
    let replacement: String
    let createdAt: Date
    let source: LexiconSource

    init(replacement: String, createdAt: Date, source: LexiconSource = .user) {
        self.replacement = replacement
        self.createdAt = createdAt
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        replacement = try c.decode(String.self, forKey: .replacement)
        createdAt   = try c.decode(Date.self,   forKey: .createdAt)
        source      = (try c.decodeIfPresent(LexiconSource.self, forKey: .source)) ?? .user
    }
}

/// Manages a custom dictionary of find-replace pairs for dictation correction.
@MainActor
class DictionaryService: ObservableObject {

    static let dictionaryKey = "customDictionaryMetadata"
    static let caseSensitiveKey = "dictionaryCaseSensitive"

    /// Phase 27 D-09: per-replacement trace entry emitted by `applyWithTrace`.
    /// Field names mirror the JSONL schema (`dictionary_replacements`) exactly so
    /// the recorder can encode the array with no name mapping.
    public struct Replacement: Codable, Sendable {
        public let key: String
        public let from: String
        public let to: String
    }

    /// Phase 27 D-09: blocked-fuzzy trace entry. Emitted when a candidate would
    /// have hit under the pre-guard distance rule (distance <= 2) but the new
    /// Levenshtein ratio cap (D-03, RESEARCH §6.1 Option 1: 0.25) blocks it.
    /// Field names mirror the JSONL schema (`dictionary_blocked`).
    /// `to` is included per D-06 amendment 2026-05-26 (RESEARCH §6.6) for
    /// single-file diagnosability of JSONL logs.
    public struct BlockedMatch: Codable, Sendable {
        public let key: String
        public let from: String
        public let to: String
        public let ratio: Double
    }

    /// Phase 27 D-03 (open-decision Option 1 per RESEARCH §6.1): Levenshtein
    /// ratio cap above which a fuzzy candidate is rejected. 0.25 keeps the
    /// existing Tailscele->Tailscale fuzzy hit (ratio 0.222) while blocking
    /// remind->Gemini (0.333) and applies->AppLite (0.286).
    private static let fuzzyRatioCap: Double = 0.25

    /// The active dictionary of [Original: Metadata] pairs.
    @Published private(set) var dictionary: [String: DictionaryMetadata] = [:]

    /// Whether matching should be case-sensitive.
    @Published var isCaseSensitive: Bool = false {
        didSet {
            Self.defaults.set(isCaseSensitive, forKey: Self.caseSensitiveKey)
        }
    }

    /// Phase 27 D-01a / D-02 / D-04: bundled common-word allowlist. Tokens
    /// matching an entry (lowercased) short-circuit the fuzzy pass entirely.
    /// Loaded once at init from `Shared/Resources/allowlist-{en,de}.txt`.
    private let commonWords: Set<String>

    /// Test-only accessor for the loaded allowlist. Used by
    /// `DictionaryServiceHallucinationGuardTests.testAllowlistLoadedFromBundle`.
    internal var commonWordsForTests: Set<String> { commonWords }

    /// Platform-conditional UserDefaults suite — single access point for all
    /// DictionaryService persistence. On macOS: .standard; on iOS: group suite.
    static var defaults: UserDefaults { DicticusDefaults.suite }

    /// Shared instance for use in TextProcessingService and DictionaryView.
    static let shared = DictionaryService()

    private init() {
        self.isCaseSensitive = Self.defaults.bool(forKey: Self.caseSensitiveKey)
        self.commonWords = Self.loadCommonWords()
        // DATA-LOSS GUARD (2026-07-19). loadGuarded returns suppressSeed == true
        // when a persisted dictionary blob is PRESENT but reads empty (a transient
        // UserDefaults/cfprefsd read/decode failure on relaunch) — in which case
        // the seed/migration path below MUST NOT run, or it would overwrite the
        // user's real dictionary with bundled defaults (exactly what wiped 205
        // entries down to 95 on 2026-07-19). Leaving the on-disk blob untouched
        // lets the next launch recover it. Regression-locked by
        // DictionaryDataLossGuardTests.
        let loadOutcome = Self.loadGuarded(from: Self.defaults, key: Self.dictionaryKey)
        dictionary = loadOutcome.dictionary
        guard !loadOutcome.suppressSeed else {
            print("[DictionaryService] DATA-LOSS GUARD: persisted dictionary present but unreadable this launch — skipping all seeding/migration to protect it.")
            return
        }

        // Migrate old data if it exists and new data is empty
        if dictionary.isEmpty {
            migrateOldFormat()
        }

        // Drop entries we previously shipped as defaults but have since
        // retired as harmful. Runs once per launch on the persisted set —
        // cheap, idempotent, and required for users who already have the
        // bad keys cached in UserDefaults.
        purgeRetiredDefaults()

        // Phase 31-01: tag persisted entries that pre-date the source field.
        // In Release builds this is a no-op (entries already decoded as .user
        // via decodeIfPresent). In dev builds it also purges stale personal
        // keys and re-seeds them cleanly via prepopulateWithDefaults().
        migrateLegacySource()

        // Always merge defaults — adds new entries on updates, preserves existing user entries
        prepopulateWithDefaults()
    }

    /// Phase 27 D-02 / D-05: load the bundled common-word allowlist into a
    /// single `Set<String>` (union of EN + DE top-N corpora). Returns an empty
    /// Set on any failure (RESEARCH §6.3 Assumption A2 defensive fallback) so
    /// init never crashes — the ratio cap (Guard B) still provides defense.
    ///
    /// Phase 27 WR-03: every entry is normalized to NFC
    /// (`.precomposedStringWithCanonicalMapping`). Swift `String` hashing /
    /// equality is byte-identical at the underlying storage level, so
    /// graphemically-equal NFD vs NFC forms hash differently. ASR pipelines
    /// occasionally emit decomposed German diacritics (`ü` = `u` + U+0308)
    /// while the bundled `.txt` corpora ship precomposed forms (`ü` = U+00FC).
    /// Without normalization the allowlist veto silently misses on exactly the
    /// German tokens the guard is designed to protect. Lookup site must NFC
    /// the token symmetrically — see fuzzyReplaceTokenWithTrace().
    private static func loadCommonWords() -> Set<String> {
        var words: Set<String> = []
        for resourceName in ["allowlist-en", "allowlist-de"] {
            guard let url = Bundle.main.url(forResource: resourceName, withExtension: "txt") else {
                print("[DictionaryService] allowlist load failed: \(resourceName).txt not found in bundle")
                continue
            }
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                        .lowercased()
                        .precomposedStringWithCanonicalMapping
                    if !trimmed.isEmpty {
                        words.insert(trimmed)
                    }
                }
            } catch {
                print("[DictionaryService] allowlist load failed: \(resourceName).txt — \(error.localizedDescription)")
            }
        }
        return words
    }

    /// Keys we previously shipped in `prepopulateWithDefaults()` but
    /// have since identified as net-harmful (false-positive matches
    /// against legitimate dictation). Removed on every launch from the
    /// persisted dictionary so existing installs converge to the new
    /// behavior without requiring a manual reset.
    ///
    /// 2026-05-06: dropped the "I'm" cluster — `"one m"` matched
    /// inside "one meeting" when ASR introduced any punctuation/space
    /// between tokens, producing "I'm meeting" hallucinations.
    ///
    /// 2026-05-22: dropped "Versal" — Levenshtein distance 2 from
    /// "versus", causing every spoken "versus" to be replaced with
    /// "Vercel". Replaced by exact-match "vercel" key (distance 3
    /// from "versus", outside fuzzy threshold). Phase 26 P2.
    private func purgeRetiredDefaults() {
        let retired: [String] = [
            "1m", "1 m", "I m", "one m", "One m",
            "Versal",
        ]
        var changed = false
        for key in retired {
            if dictionary.removeValue(forKey: key) != nil {
                changed = true
            }
        }
        if changed {
            save()
        }
    }

    /// Phase 31-01 (D-06): tag all persisted entries that pre-date the `source`
    /// field. After Phase 31-01, new entries always carry an explicit `source`
    /// set by the call site. Entries decoded from older persisted data already
    /// receive `source == .user` via `DictionaryMetadata.init(from:)` — this
    /// method handles the in-place save so the tag is persisted.
    ///
    /// Dev builds (PERSONAL_LEXICON flag on): purge keys that are no longer in
    /// DefaultLexicon + PersonalLexicon, then allow prepopulateWithDefaults() to
    /// reseed them cleanly so every developer-local entry carries source == .default.
    ///
    /// Release builds: leave all entries in place — entries already decoded as
    /// .user via decodeIfPresent. Ship NO personal-key list (D-06 leak rationale:
    /// the key names themselves reveal the developer's dictation patterns).
    private func migrateLegacySource() {
#if PERSONAL_LEXICON
        // Dev build: remove stale personal entries (no longer in either lexicon)
        // so prepopulateWithDefaults() can re-seed them with source == .default.
        // This converges existing dev installs to the new provenance model.
        let knownKeys = Set(DefaultLexicon.entries.keys).union(Set(PersonalLexicon.entries.keys))
        var changed = false
        for key in Array(dictionary.keys) {
            if !knownKeys.contains(key) {
                // Key is not in any known lexicon — it's a user entry; leave it alone.
                // Keys that ARE in known lexicons but came from an older build will
                // be removed and re-seeded by prepopulateWithDefaults() below since
                // they still appear in PersonalLexicon.entries. We only remove the
                // true personal-lexicon entries here to let prepopulate re-tag them.
                continue
            }
            // Key is from a known lexicon but may be tagged .user from the old build.
            // Remove so prepopulateWithDefaults() re-inserts it with source == .default.
            dictionary.removeValue(forKey: key)
            changed = true
        }
        if changed { save() }
#else
        // Release build: entries already decoded as .user via decodeIfPresent.
        // prepopulateWithDefaults() below persists, so no save is needed here.
#endif
    }

    private func migrateOldFormat() {
        let oldKey = "customDictionary"
        // Route through the storage seam (Self.defaults = DicticusDefaults.suite) so the
        // read and remove target the correct store on both macOS (.standard) and iOS
        // (group suite). Using UserDefaults.standard here would miss legacy iOS entries
        // stored in the group suite.
        if let oldStored = Self.defaults.dictionary(forKey: oldKey) as? [String: String] {
            for (original, replacement) in oldStored {
                dictionary[original] = DictionaryMetadata(replacement: replacement, createdAt: Date())
            }
            save()
            Self.defaults.removeObject(forKey: oldKey)
        }
    }

    /// Phase 27 WR-04: lifted from `private` → internal so the WR-04
    /// regression test can invoke the merge loop directly and assert
    /// the D-12 invariant (existing user customizations are never
    /// overwritten on re-merge). Not exposed publicly — `@testable
    /// import Dicticus` provides access; production callers continue
    /// to go through the singleton's private init only.
    ///
    /// Phase 31-01: the inline `defaults` literal has been extracted to
    /// `DefaultLexicon.entries` (always, public seed — empty for v2.4) and
    /// `PersonalLexicon.entries` (dev builds only, gitignored). Both are
    /// merged with `source: .default` using the same idempotent guard.
    internal func prepopulateWithDefaults() {
        // Merge public default entries (empty in v2.4; future releases may add entries here).
        // Skip identical original==replacement pairs: they are no-ops (replacing a word
        // with itself does nothing) and break export→import round-tripping, since the
        // import merge correctly refuses them (see DictionaryIOService.merge).
        for (original, replacement) in DefaultLexicon.entries {
            if original == replacement { continue }
            if dictionary[original] == nil {
                dictionary[original] = DictionaryMetadata(replacement: replacement, createdAt: Date(), source: .default)
            }
        }

#if PERSONAL_LEXICON
        // Merge developer-personal entries — dev builds only (gitignored file).
        // Release builds compile this block to zero bytes.
        for (original, replacement) in PersonalLexicon.entries {
            if original == replacement { continue }
            if dictionary[original] == nil {
                dictionary[original] = DictionaryMetadata(replacement: replacement, createdAt: Date(), source: .default)
            }
        }
#endif

        save()
    }

    func load() {
        dictionary = Self.loadGuarded(from: Self.defaults, key: Self.dictionaryKey).dictionary
    }

    /// Pure, injectable core of the 2026-07-19 data-loss guard (regression-locked
    /// by `DictionaryDataLossGuardTests`). Reads the persisted dictionary from
    /// `defaults[key]` and reports whether it is SAFE to seed bundled defaults.
    /// `suppressSeed` is true ONLY when a blob is PRESENT but decodes empty even
    /// after a retry — the present-but-unreadable case a caller must NEVER
    /// overwrite. A genuinely absent blob (real first run) returns
    /// `suppressSeed == false` so seeding proceeds normally.
    nonisolated static func loadGuarded(from defaults: UserDefaults, key: String) -> (dictionary: [String: DictionaryMetadata], suppressSeed: Bool) {
        func decode() -> [String: DictionaryMetadata] {
            guard let data = defaults.data(forKey: key),
                  let stored = try? JSONDecoder().decode([String: DictionaryMetadata].self, from: data) else { return [:] }
            return stored
        }
        let blobExists = defaults.data(forKey: key) != nil
        var dict = decode()
        if dict.isEmpty && blobExists {
            dict = decode()  // retry — cfprefsd races usually resolve on a second read
            if dict.isEmpty { return ([:], true) }
        }
        return (dict, false)
    }

    /// Rolling one-step backup key: `save()` copies the PREVIOUS persisted blob
    /// here before overwriting, so a single bad overwrite is always recoverable
    /// (belt-and-suspenders behind the init data-loss guard; 2026-07-19).
    static let dictionaryBackupKey = "customDictionaryMetadata_prevBackup"

    func save() {
        guard let data = try? JSONEncoder().encode(dictionary) else { return }
        if let previous = Self.defaults.data(forKey: Self.dictionaryKey), previous != data {
            Self.defaults.set(previous, forKey: Self.dictionaryBackupKey)
        }
        Self.defaults.set(data, forKey: Self.dictionaryKey)
    }

    func setReplacement(for original: String, with replacement: String) {
        let trimmedOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOriginal.isEmpty else { return }

        dictionary[trimmedOriginal] = DictionaryMetadata(
            replacement: replacement.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: Date()
        )
        save()
    }

    /// Result of an in-place entry edit (quick task 260801-ftf).
    enum EntryEditResult: Equatable {
        case saved
        case notFound
        case collision(String)   // the existing key that would have been clobbered
        case invalid(String)     // user-facing reason
    }

    /// Edit an existing entry's original and/or replacement in place — the shared
    /// service method backing both the macOS row "Edit…" affordance and the iOS
    /// tappable row (quick task 260801-ftf, backlog: dictionary-entry-editing.md).
    ///
    /// Two intentional metadata decisions, both sanctioned by the backlog:
    /// - `createdAt` is PRESERVED from the pre-edit entry. An edit is not a
    ///   creation; re-stamping it here would silently reshuffle the "Recent"
    ///   sort every time a user fixed a typo.
    /// - `source` is deliberately PROMOTED to `.user`. An edited entry is now
    ///   user-authored content, and the source-priority sort then surfaces it
    ///   where the user who just touched it expects to find it.
    ///
    /// Known limitation, documented not fixed: renaming an entry whose key
    /// exists in `DefaultLexicon`/`PersonalLexicon` frees that key, so
    /// `prepopulateWithDefaults()` re-seeds the old entry on the next launch.
    /// `DefaultLexicon.entries` is empty in release builds, so this only
    /// affects dev builds compiled with `PERSONAL_LEXICON`.
    ///
    /// Every guard below runs BEFORE any mutation, so no rejected path can
    /// leave the dictionary half-changed. Reaches persistence only through
    /// `save()` — never `Self.defaults` directly.
    @discardableResult
    func renameEntry(from oldOriginal: String, to newOriginal: String, replacement: String) -> EntryEditResult {
        // oldOriginal comes from the dictionary (a selected row's id), not a
        // text field — used verbatim as the lookup key, never trimmed.
        guard let existing = dictionary[oldOriginal] else { return .notFound }

        let trimmedNew = newOriginal.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedNew.isEmpty else { return .invalid("Original cannot be empty.") }
        guard !trimmedReplacement.isEmpty else { return .invalid("Replacement cannot be empty.") }
        guard trimmedNew != trimmedReplacement else { return .invalid("Original and replacement cannot be identical.") }

        // Exact-key collision only: the store is keyed by exact string, so
        // exact-key collision is precisely the clobber risk. A case-only
        // rename produces a distinct key and is therefore a legal rename, not
        // a collision — matching is case-insensitive by default, so this is a
        // no-op for matching behavior; the UI must not imply otherwise.
        if trimmedNew != oldOriginal, dictionary[trimmedNew] != nil {
            return .collision(trimmedNew)
        }

        dictionary.removeValue(forKey: oldOriginal)
        dictionary[trimmedNew] = DictionaryMetadata(replacement: trimmedReplacement, createdAt: existing.createdAt, source: .user)
        save()
        return .saved
    }

    func removeReplacement(for original: String) {
        dictionary.removeValue(forKey: original)
        save()
    }

    func removeAll() {
        dictionary.removeAll()
        save()
    }

    // MARK: - Import / Export (Phase 31-02)

    /// Result of a dictionary import operation.
    ///
    /// `added`   — new corrections actually applied.
    /// `kept`    — valid rows that were already in the dictionary and left unchanged.
    /// `warnings`— invalid rows (empty replacement, or identical original/replacement).
    /// added + kept + warnings.count accounts for every row in the file, so the
    /// summary never appears to "lose" rows.
    enum ImportResult {
        case success(added: Int, kept: Int, warnings: [String])
        case failure(String)

        /// User-facing summary for an import-result alert. Accounts for every row —
        /// added, already-present (kept unchanged), and invalid — instead of listing
        /// each skipped line, which overwhelms the dialog. `source` optionally names
        /// the origin (e.g. a starter pack title).
        func summaryMessage(source: String? = nil) -> String {
            switch self {
            case .failure(let error):
                return "Import failed: \(error)"
            case .success(let added, let kept, let warnings):
                let from = source.map { " from \($0)" } ?? ""
                var lines = ["Imported \(added) new \(added == 1 ? "entry" : "entries")\(from)."]
                if kept > 0 {
                    lines.append("\(kept) already in your dictionary (kept unchanged).")
                }
                if !warnings.isEmpty {
                    lines.append("\(warnings.count) \(warnings.count == 1 ? "row" : "rows") skipped — empty or identical original/replacement.")
                }
                return lines.joined(separator: "\n")
            }
        }
    }

    /// Import a CSV or JSON file into the dictionary using the specified merge strategy.
    ///
    /// Instantiates DictionaryIOService synchronously on the main actor (Finding 8 — safe
    /// at ~1000-row scale, <1ms parse time). Imported entries are tagged source: .imported.
    /// On parse/decode error, returns .failure with the localized error description.
    func importData(_ data: Data, format: String, strategy: MergeStrategy) -> ImportResult {
        let io = DictionaryIOService()
        do {
            let incoming: [CSVImportRow]
            var warningMessages: [String] = []
            switch format.lowercased() {
            case "csv":
                let result = try io.parseCSV(String(data: data, encoding: .utf8) ?? "")
                incoming = result.rows
                warningMessages = result.warnings.map { $0.message }
            case "json":
                let parsed = try io.parseJSON(data)
                var validRows: [CSVImportRow] = []
                for (offset, row) in parsed.enumerated() {
                    if row.replacement.isEmpty {
                        warningMessages.append("Entry \(offset + 1): empty replacement for '\(row.original)' — skipped")
                        continue
                    }
                    if row.original == row.replacement {
                        warningMessages.append("Entry \(offset + 1): original == replacement '\(row.original)' — skipped")
                        continue
                    }
                    validRows.append(row)
                }
                incoming = validRows
            default:
                return .failure("Unsupported format: \(format). Use 'csv' or 'json'.")
            }
            let merged = io.merge(incoming: incoming, into: dictionary, strategy: strategy)
            let addedCount = merged.keys.filter { dictionary[$0] != merged[$0] }.count
            // Valid rows that were not applied are duplicates left unchanged.
            let keptCount = max(0, incoming.count - addedCount)
            dictionary = merged
            save()
            return .success(added: addedCount, kept: keptCount, warnings: warningMessages)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// Export the full dictionary (all entries regardless of provenance) to CSV or JSON Data.
    func exportData(format: String) -> Data {
        let io = DictionaryIOService()
        switch format.lowercased() {
        case "json":
            return io.serializeJSON(dictionary)
        default:
            return Data(io.serializeCSV(dictionary).utf8)
        }
    }

    // MARK: - Starter Packs (Phase 31-03)

    /// Hard-coded registry of bundled offline starter packs (RESEARCH Finding 7 —
    /// hard-code to avoid scanning the bundle directory, which could pull in test CSVs).
    /// Raw values map to the CSV resource names under Shared/Resources/.
    enum StarterPack: String, CaseIterable {
        case tech    = "starter-pack-tech"
        case brands  = "starter-pack-brands"
        case general = "starter-pack-general"

        var displayTitle: String {
            switch self {
            case .tech:    return "Tech Terms"
            case .brands:  return "Brand Names"
            case .general: return "General Terms"
            }
        }
    }

    /// Import a bundled starter pack via the existing DICT-IO pipeline (existing-wins,
    /// entries tagged source: .imported). Reads the CSV from the app bundle.
    ///
    /// Returns .success(added: 0) on a missing/unreadable resource — same defensive
    /// pattern as loadCommonWords() (never throws, never crashes init or import).
    func importStarterPack(_ pack: StarterPack) -> ImportResult {
        guard let url = Bundle.main.url(forResource: pack.rawValue, withExtension: "csv") else {
            print("[DictionaryService] starter pack not found: \(pack.rawValue).csv")
            return .success(added: 0, kept: 0, warnings: ["Pack resource not found in bundle: \(pack.rawValue).csv"])
        }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            print("[DictionaryService] starter pack unreadable: \(pack.rawValue).csv")
            return .success(added: 0, kept: 0, warnings: ["Pack resource could not be read: \(pack.rawValue).csv"])
        }
        return importData(Data(content.utf8), format: "csv", strategy: .existingWins)
    }

    /// Whether every valid correction in a starter pack is already present in the
    /// dictionary — drives the "already imported" checkmark in the UI. Returns false
    /// for a missing/unreadable/empty pack. Cheap (packs are tiny, parsed on demand).
    func isStarterPackImported(_ pack: StarterPack) -> Bool {
        guard let url = Bundle.main.url(forResource: pack.rawValue, withExtension: "csv"),
              let content = try? String(contentsOf: url, encoding: .utf8),
              let parsed = try? DictionaryIOService().parseCSV(content) else {
            return false
        }
        let valid = parsed.rows.filter { !$0.replacement.isEmpty && $0.original != $0.replacement }
        guard !valid.isEmpty else { return false }
        return valid.allSatisfy { dictionary[$0.original] != nil }
    }

    /// Phase 27 D-08: `apply(to:)` is a thin wrapper over `applyWithTrace(to:)`.
    /// Single source of truth — production and recorder share one code path.
    func apply(to text: String) -> String {
        return applyWithTrace(to: text).text
    }

    /// Phase 27 D-08: canonical traced dictionary application. Returns the
    /// processed text plus per-replacement and per-blocked-fuzzy-candidate
    /// trace arrays. Both arrays are empty when nothing happened (D-07 default-
    /// empty contract for downstream JSONL stability).
    public func applyWithTrace(to text: String) -> (text: String, replacements: [Replacement], blocked: [BlockedMatch]) {
        var result = text
        var replacements: [Replacement] = []
        var blocked: [BlockedMatch] = []

        let sortedKeys = dictionary.keys.sorted { $0.count > $1.count }

        for original in sortedKeys {
            guard let metadata = dictionary[original] else { continue }

            // \b only works between \w (alphanumeric) and \W (non-alphanumeric).
            // It fails for "Swiss \" because " matches \W.
            // We use lookarounds to simulate word boundaries for any string.
            let escaped = NSRegularExpression.escapedPattern(for: original)

            // Pattern: Ensure match is not preceded or followed by an alphanumeric character
            // unless the original string itself starts/ends with one.
            let pattern = "(?<![a-zA-Z0-9])\(escaped)(?![a-zA-Z0-9])"

            let options: NSRegularExpression.Options = isCaseSensitive ? [] : [.caseInsensitive]

            do {
                let regex = try NSRegularExpression(pattern: pattern, options: options)
                let nsResult = result as NSString
                let fullRange = NSRange(location: 0, length: nsResult.length)
                let matches = regex.matches(in: result, options: [], range: fullRange)
                if !matches.isEmpty {
                    // Capture matched substrings (in original positions) before
                    // mutating `result` so trace.from carries the actual text.
                    for m in matches {
                        let matched = nsResult.substring(with: m.range)
                        replacements.append(Replacement(key: original, from: matched, to: metadata.replacement))
                    }
                    result = regex.stringByReplacingMatches(in: result, options: [], range: fullRange, withTemplate: metadata.replacement)
                }
            } catch {
                // Fallback: best-effort replacement; cannot reliably emit trace entries here.
                result = result.replacingOccurrences(of: original, with: metadata.replacement, options: isCaseSensitive ? [] : [.caseInsensitive])
            }
        }

        // Phase 25.1-03: fuzzy second pass after exact-match completes.
        let fuzzy = applyFuzzyPassWithTrace(result)
        result = fuzzy.text
        replacements.append(contentsOf: fuzzy.replacements)
        blocked.append(contentsOf: fuzzy.blocked)

        return (result, replacements, blocked)
    }

    /// Phase 25.1-03 — paper §2.2 fuzzy-match second pass.
    ///
    /// Runs after the exact-match lookaround regex pass in `applyWithTrace(to:)`.
    /// For each token of length ≥ 6 in `text`, checks dictionary keys of length
    /// ≥ 6 (single-token only) where `abs(token.count - key.count) <= 2`.
    ///
    /// Phase 27 D-01 defense-in-depth: each candidate must pass BOTH (a) the
    /// common-word allowlist veto (D-01a) and (b) the Levenshtein ratio cap
    /// (D-01b, D-03) before a replacement fires.
    ///
    /// Length-prefilter ≥ 6 is mandatory: distance-2 matches against short tokens
    /// (e.g. `the`/`she`) catastrophically false-positive. Multi-word keys are
    /// skipped — the exact-match regex pass handles those.
    private func applyFuzzyPassWithTrace(_ text: String) -> (text: String, replacements: [Replacement], blocked: [BlockedMatch]) {
        // Phase 27 WR-01: sort candidates lexicographically to make
        // fuzzy-match outcomes deterministic across launches. Dictionary key
        // iteration order is unspecified in Swift, so a token with two distinct
        // keys within distance ≤ 2 (one passing the ratio cap, one blocked)
        // could otherwise produce different outputs across runs depending on
        // which key the hash table happened to surface first. Lexicographic
        // sort is the simplest stable order; no quality signal is encoded.
        let candidateKeys = dictionary.keys
            .filter { $0.count >= 6 && !$0.contains(" ") }
            .sorted()
        if candidateKeys.isEmpty { return (text, [], []) }

        var replacements: [Replacement] = []
        var blocked: [BlockedMatch] = []

        // Walk character by character, collecting word tokens and preserving
        // all non-word characters (punctuation, whitespace) in their original
        // positions. Split on whitespace; preserve trailing punctuation per token.
        var result = ""
        var current = ""
        let isWordChar: (Character) -> Bool = { $0.isLetter || $0.isNumber }
        for ch in text {
            if isWordChar(ch) {
                current.append(ch)
            } else {
                if !current.isEmpty {
                    let r = fuzzyReplaceTokenWithTrace(current, candidates: candidateKeys)
                    result.append(r.0)
                    if let rep = r.1 { replacements.append(rep) }
                    if let blk = r.2 { blocked.append(blk) }
                    current = ""
                }
                result.append(ch)
            }
        }
        if !current.isEmpty {
            let r = fuzzyReplaceTokenWithTrace(current, candidates: candidateKeys)
            result.append(r.0)
            if let rep = r.1 { replacements.append(rep) }
            if let blk = r.2 { blocked.append(blk) }
        }
        return (result, replacements, blocked)
    }

    /// Phase 27 D-01 fuzzy-pass guard. Returns the (possibly replaced) token
    /// plus an optional `Replacement` (when a candidate fires) or an optional
    /// `BlockedMatch` (when a candidate would have hit pre-guard but is now
    /// rejected by either Guard A or Guard B). At most one of the optionals is
    /// non-nil per call.
    private func fuzzyReplaceTokenWithTrace(_ token: String, candidates: [String]) -> (String, Replacement?, BlockedMatch?) {
        guard token.count >= 6 else { return (token, nil, nil) }
        // Phase 27 WR-03: NFC-normalize before allowlist lookup. The allowlist
        // is loaded NFC (loadCommonWords), and ASR may emit NFD-decomposed
        // German diacritics. Without symmetric normalization the Set<String>
        // contains check would silently miss on ä/ö/ü/ß tokens — exactly the
        // inputs Guard A is built to protect.
        let lowered = token.lowercased().precomposedStringWithCanonicalMapping

        // Guard A (D-01a, D-04): allowlist veto. Common English/German words
        // never become fuzzy candidates regardless of distance.
        if commonWords.contains(lowered) {
            return (token, nil, nil)
        }

        for key in candidates {
            guard abs(token.count - key.count) <= 2 else { continue }
            let keyLowered = key.lowercased()
            // Skip identity — already handled by exact-match pass.
            if lowered == keyLowered { return (token, nil, nil) }

            let ratio = LevenshteinDistance.normalizedDistance(lowered, keyLowered)
            if ratio <= Self.fuzzyRatioCap {
                // Guard B passes — fire the replacement.
                let to = dictionary[key]?.replacement ?? token
                // Skip trace emission when the replacement produces no visible
                // change (the exact-match pass already produced the final form).
                if to == token {
                    return (token, nil, nil)
                }
                return (to, Replacement(key: key, from: token, to: to), nil)
            } else if LevenshteinDistance.distance(lowered, keyLowered) <= 2 {
                // Would have hit pre-guard; record as blocked for telemetry.
                let to = dictionary[key]?.replacement ?? token
                return (token, nil, BlockedMatch(key: key, from: token, to: to, ratio: ratio))
            }
        }
        return (token, nil, nil)
    }
}
