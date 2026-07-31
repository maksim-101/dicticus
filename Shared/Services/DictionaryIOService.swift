import Foundation

/// RFC 4180 CSV parse error with 1-based line numbers.
enum CSVParseError: LocalizedError {
    case wrongColumnCount(line: Int, found: Int)
    case unclosedQuote(line: Int)

    var errorDescription: String? {
        switch self {
        case .wrongColumnCount(let l, let n):
            return "Line \(l): expected 2 columns, found \(n)"
        case .unclosedQuote(let l):
            return "Line \(l): unclosed quoted field"
        }
    }
}

/// A parsed row from a dictionary CSV file.
struct CSVImportRow {
    let original: String
    let replacement: String
}

/// Controls how imported entries are merged with existing dictionary entries.
///
/// replaceAll: removes ALL existing entries (including .user), inserts all incoming as .imported.
/// This is the nuclear option — documented here per Open Question 1 resolution.
enum MergeStrategy {
    case replaceAll
    case existingWins
    case incomingWins
}

/// Pure import/export engine for the Dicticus dictionary.
///
/// No @MainActor, no singleton, no I/O side effects. Callers (DictionaryService, which
/// is @MainActor) instantiate directly and call synchronously — safe at ~1000-row scale
/// per RESEARCH Finding 8.
public final class DictionaryIOService {

    public init() {}

    // MARK: - CSV Parsing

    /// Parse RFC 4180 CSV content (two-column: original,replacement).
    ///
    /// Handles: UTF-8 BOM strip, CRLF normalization, quoted fields with embedded
    /// commas/newlines/doubled quotes, header-row detection, blank-line skipping.
    /// Throws on structural errors (wrong column count, unclosed quote).
    /// Returns stripped rows for empty/identical replacements as warnings.
    func parseCSV(_ content: String) throws -> (rows: [CSVImportRow], warnings: [(line: Int, message: String)]) {
        var content = content

        // Strip UTF-8 BOM (Pitfall 3).
        if content.hasPrefix("\u{FEFF}") {
            content = String(content.dropFirst())
        }

        // Normalize CRLF to LF so the scanner only handles LF.
        content = content.replacingOccurrences(of: "\r\n", with: "\n")

        // Ensure trailing newline so the last row is always terminated.
        if !content.isEmpty && !content.hasSuffix("\n") {
            content.append("\n")
        }

        var rows: [CSVImportRow] = []
        var warnings: [(line: Int, message: String)] = []
        var lineNumber = 0
        var index = content.startIndex

        while index < content.endIndex {
            // Parse one logical row (may span multiple physical lines if inside quotes).
            let rowFields = try parseOneRow(content: content, index: &index, lineNumber: &lineNumber)

            lineNumber += 1

            // Skip blank rows.
            if rowFields.isEmpty || (rowFields.count == 1 && rowFields[0].isEmpty) {
                lineNumber -= 1
                continue
            }

            // Skip header row: original,replacement (case-insensitive).
            if rowFields.count == 2
                && rowFields[0].lowercased() == "original"
                && rowFields[1].lowercased() == "replacement" {
                lineNumber -= 1
                continue
            }

            // Validate column count.
            if rowFields.count != 2 {
                throw CSVParseError.wrongColumnCount(line: lineNumber, found: rowFields.count)
            }

            let original = rowFields[0]
            let replacement = rowFields[1]

            // Validate: empty replacement.
            if replacement.isEmpty {
                warnings.append((line: lineNumber, message: "Line \(lineNumber): empty replacement for '\(original)' — skipped"))
                continue
            }

            // Validate: identical key and replacement.
            if original == replacement {
                warnings.append((line: lineNumber, message: "Line \(lineNumber): original == replacement '\(original)' — skipped"))
                continue
            }

            rows.append(CSVImportRow(original: original, replacement: replacement))
        }

        return (rows: rows, warnings: warnings)
    }

    /// Parse one logical CSV row, advancing `index` past the terminating LF.
    /// Uses `lineNumber` only for error reporting (not incremented here).
    private func parseOneRow(content: String, index: inout String.Index, lineNumber: inout Int) throws -> [String] {
        var fields: [String] = []

        while index < content.endIndex {
            let ch = content[index]

            if ch == "\n" {
                // Empty field before LF — only possible if row started with comma.
                // Normal row terminator: advance past it.
                index = content.index(after: index)
                break
            }

            if ch == "\"" {
                // Quoted field.
                index = content.index(after: index)
                var field = ""
                var closed = false

                while index < content.endIndex {
                    let qch = content[index]
                    if qch == "\"" {
                        let next = content.index(after: index)
                        if next < content.endIndex && content[next] == "\"" {
                            // Doubled-quote escape — literal ".
                            field.append("\"")
                            index = content.index(after: next)
                        } else {
                            // End of quoted field.
                            index = next
                            closed = true
                            break
                        }
                    } else {
                        field.append(qch)
                        index = content.index(after: index)
                    }
                }

                if !closed {
                    throw CSVParseError.unclosedQuote(line: lineNumber + 1)
                }

                fields.append(field)

                // After closing quote: expect comma, LF, or end.
                if index < content.endIndex {
                    if content[index] == "," {
                        index = content.index(after: index)
                        // If next char is LF or end, there's a trailing empty field.
                        if index < content.endIndex && content[index] == "\n" {
                            fields.append("")
                            index = content.index(after: index)
                            break
                        } else if index >= content.endIndex {
                            fields.append("")
                            break
                        }
                        // else: continue to next field
                    } else if content[index] == "\n" {
                        index = content.index(after: index)
                        break
                    }
                }

            } else {
                // Unquoted field — scan until comma or LF.
                var field = ""
                while index < content.endIndex {
                    let uch = content[index]
                    if uch == "," {
                        index = content.index(after: index)
                        fields.append(field)
                        // Trailing comma with LF or end-of-content next = empty last field.
                        if index < content.endIndex && content[index] == "\n" {
                            fields.append("")
                            index = content.index(after: index)
                            return fields
                        } else if index >= content.endIndex {
                            fields.append("")
                            return fields
                        }
                        // Continue to next field.
                        break
                    } else if uch == "\n" {
                        index = content.index(after: index)
                        fields.append(field)
                        return fields
                    } else {
                        field.append(uch)
                        index = content.index(after: index)
                    }
                }
                // If we exited the inner loop without returning (hit a comma and will continue),
                // do NOT append field again — it was appended before break above.
                // If we exited because index >= endIndex, append now.
                if index >= content.endIndex {
                    // EOF reached mid-field (only when the input lacked a trailing
                    // newline; parseCSV normally appends one). Always commit the
                    // in-progress field so a legitimately empty trailing field is
                    // preserved rather than silently dropped.
                    fields.append(field)
                    break
                }
            }
        }

        return fields
    }

    // MARK: - JSON Parsing

    /// Parse a JSON export file. Decodes [{original, replacement, createdAt}] arrays.
    /// The `source` field is always overridden to `.imported` on import per Open Question 2.
    func parseJSON(_ data: Data) throws -> [CSVImportRow] {
        struct JSONEntry: Decodable {
            let original: String
            let replacement: String
            // createdAt present in export but not needed here; source always overridden to .imported.
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entries = try decoder.decode([JSONEntry].self, from: data)
        return entries.map { CSVImportRow(original: $0.original, replacement: $0.replacement) }
    }

    // MARK: - CSV Serialization

    /// Serialize a dictionary to RFC 4180 CSV.
    /// Fields containing commas, double-quotes, or newlines are quoted and escaped.
    func serializeCSV(_ dict: [String: DictionaryMetadata]) -> String {
        var lines = ["original,replacement"]
        let sorted = dict.keys.sorted()
        for key in sorted {
            guard let meta = dict[key] else { continue }
            lines.append("\(csvField(key)),\(csvField(meta.replacement))")
        }
        return lines.joined(separator: "\n")
    }

    private func csvField(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }

    // MARK: - JSON Serialization

    /// Serialize a dictionary to JSON. Entries sorted by key. ISO8601 dates.
    func serializeJSON(_ dict: [String: DictionaryMetadata]) -> Data {
        struct JSONEntry: Encodable {
            let original: String
            let replacement: String
            let createdAt: Date
            let source: String
        }
        let entries = dict.keys.sorted().compactMap { key -> JSONEntry? in
            guard let meta = dict[key] else { return nil }
            return JSONEntry(original: key, replacement: meta.replacement, createdAt: meta.createdAt, source: meta.source.rawValue)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(entries)) ?? Data()
    }

    // MARK: - Merge

    /// Merge incoming rows into an existing dictionary using the specified strategy.
    ///
    /// All incoming entries are tagged source: .imported regardless of their provenance
    /// in the source file (Open Question 2 resolution).
    ///
    /// Empty replacements and key==replacement entries are stripped (same rules as parseCSV
    /// validation) so downstream dictionary is always clean.
    ///
    /// replaceAll: clears ALL existing entries (including .user — documented per Open Question 1)
    /// then inserts all valid incoming as .imported.
    func merge(incoming: [CSVImportRow], into existing: [String: DictionaryMetadata], strategy: MergeStrategy) -> [String: DictionaryMetadata] {
        var result: [String: DictionaryMetadata]

        switch strategy {
        case .replaceAll:
            result = [:]
        case .existingWins, .incomingWins:
            result = existing
        }

        for row in incoming {
            // Strip empty replacement.
            guard !row.replacement.isEmpty else { continue }
            // Strip identical key==replacement.
            guard row.original != row.replacement else { continue }

            switch strategy {
            case .replaceAll, .incomingWins:
                result[row.original] = DictionaryMetadata(
                    replacement: row.replacement,
                    createdAt: Date(),
                    source: .imported
                )
            case .existingWins:
                if result[row.original] == nil {
                    result[row.original] = DictionaryMetadata(
                        replacement: row.replacement,
                        createdAt: Date(),
                        source: .imported
                    )
                }
            }
        }

        return result
    }
}
