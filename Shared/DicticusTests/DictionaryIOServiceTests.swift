import XCTest
@testable import Dicticus

@MainActor
final class DictionaryIOServiceTests: XCTestCase {

    var sut: DictionaryIOService!

    override func setUp() {
        super.setUp()
        sut = DictionaryIOService()
    }

    // MARK: - CSV Parsing: basic

    func testParseCSV_basicRow() throws {
        let csv = "tail scale,Tailscale"
        let result = try sut.parseCSV(csv)
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.rows[0].original, "tail scale")
        XCTAssertEqual(result.rows[0].replacement, "Tailscale")
    }

    func testParseCSV_quotedCommaInOriginal() throws {
        let csv = #""tail scale, etc.",Tailscale"#
        let result = try sut.parseCSV(csv)
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.rows[0].original, "tail scale, etc.")
        XCTAssertEqual(result.rows[0].replacement, "Tailscale")
    }

    func testParseCSV_doubledQuoteInOriginal() throws {
        let csv = #""he said ""hi""",greeting"#
        let result = try sut.parseCSV(csv)
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.rows[0].original, #"he said "hi""#)
        XCTAssertEqual(result.rows[0].replacement, "greeting")
    }

    func testParseCSV_embeddedNewlineDoesNotSplitRow() throws {
        let csv = "\"line one\nline two\",replacement"
        let result = try sut.parseCSV(csv)
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.rows[0].original, "line one\nline two")
    }

    func testParseCSV_stripsBOM() throws {
        let csv = "\u{FEFF}true nest,TrueNAS"
        let result = try sut.parseCSV(csv)
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.rows[0].original, "true nest")
    }

    func testParseCSV_normalizesCRLF() throws {
        let csv = "foo,bar\r\nbaz,qux"
        let result = try sut.parseCSV(csv)
        XCTAssertEqual(result.rows.count, 2)
        XCTAssertEqual(result.rows[0].original, "foo")
        XCTAssertEqual(result.rows[1].original, "baz")
    }

    func testParseCSV_skipsBlankLines() throws {
        let csv = "foo,bar\n\nbaz,qux"
        let result = try sut.parseCSV(csv)
        XCTAssertEqual(result.rows.count, 2)
    }

    func testParseCSV_skipsHeaderRow() throws {
        let csv = "original,replacement\nfoo,bar"
        let result = try sut.parseCSV(csv)
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.rows[0].original, "foo")
    }

    func testParseCSV_skipsHeaderRowCaseInsensitive() throws {
        let csv = "Original,Replacement\nfoo,bar"
        let result = try sut.parseCSV(csv)
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.rows[0].original, "foo")
    }

    // MARK: - CSV Parsing: errors

    func testParseCSV_wrongColumnCountThrowsWithLineNumber() throws {
        let csv = "foo,bar,extra"
        do {
            _ = try sut.parseCSV(csv)
            XCTFail("Expected CSVParseError.wrongColumnCount to be thrown")
        } catch CSVParseError.wrongColumnCount(let line, let found) {
            XCTAssertEqual(line, 1)
            XCTAssertEqual(found, 3)
        }
    }

    func testParseCSV_wrongColumnCountLineNumberTracked() throws {
        let csv = "foo,bar\nbaz,qux,extra"
        do {
            _ = try sut.parseCSV(csv)
            XCTFail("Expected CSVParseError.wrongColumnCount to be thrown")
        } catch CSVParseError.wrongColumnCount(let line, _) {
            XCTAssertEqual(line, 2)
        }
    }

    func testParseCSV_unclosedQuoteThrowsWithLineNumber() throws {
        let csv = #""unclosed,replacement"#
        do {
            _ = try sut.parseCSV(csv)
            XCTFail("Expected CSVParseError.unclosedQuote to be thrown")
        } catch CSVParseError.unclosedQuote(let line) {
            XCTAssertEqual(line, 1)
        }
    }

    // MARK: - CSV Parsing: validation warnings

    func testParseCSV_emptyReplacementStrippedAsWarning() throws {
        let csv = "bad word,"
        let result = try sut.parseCSV(csv)
        XCTAssertEqual(result.rows.count, 0)
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertEqual(result.warnings[0].line, 1)
    }

    func testParseCSV_identicalKeyReplacementStrippedAsWarning() throws {
        let csv = "xcode,xcode"
        let result = try sut.parseCSV(csv)
        XCTAssertEqual(result.rows.count, 0)
        XCTAssertEqual(result.warnings.count, 1)
    }

    func testParseCSV_noTrailingNewlineFinalRowPreserved() throws {
        // WR-05: a final row without a trailing newline must still parse its
        // unquoted fields correctly (parseCSV appends the newline; the EOF
        // guard must commit the in-progress field rather than drop it).
        let csv = "foo,bar"
        let result = try sut.parseCSV(csv)
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.rows[0].original, "foo")
        XCTAssertEqual(result.rows[0].replacement, "bar")
    }

    // MARK: - JSON Parsing

    func testParseJSON_basic() throws {
        let jsonString = """
        [
          {"original": "foo", "replacement": "bar", "createdAt": "2024-01-01T00:00:00Z"}
        ]
        """
        let data = Data(jsonString.utf8)
        let rows = try sut.parseJSON(data)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].original, "foo")
        XCTAssertEqual(rows[0].replacement, "bar")
    }

    func testParseJSON_sourceSetToImported() throws {
        let jsonString = """
        [
          {"original": "foo", "replacement": "bar", "createdAt": "2024-01-01T00:00:00Z", "source": "user"}
        ]
        """
        let data = Data(jsonString.utf8)
        let rows = try sut.parseJSON(data)
        // Verify parsing works regardless of source in JSON — importer always overrides to .imported
        XCTAssertEqual(rows.count, 1)
    }

    // MARK: - Merge strategies

    func testMerge_replaceAll_clearsExistingAndInsertsIncoming() {
        var existing: [String: DictionaryMetadata] = [
            "existing": DictionaryMetadata(replacement: "Existing", createdAt: Date(), source: .user)
        ]
        let incoming = [CSVImportRow(original: "new", replacement: "New")]
        let result = sut.merge(incoming: incoming, into: existing, strategy: .replaceAll)
        XCTAssertNil(result["existing"])
        XCTAssertEqual(result["new"]?.replacement, "New")
        XCTAssertEqual(result["new"]?.source, .imported)
    }

    func testMerge_replaceAll_removesUserEntries() {
        var existing: [String: DictionaryMetadata] = [
            "user-entry": DictionaryMetadata(replacement: "User", createdAt: Date(), source: .user),
            "default-entry": DictionaryMetadata(replacement: "Default", createdAt: Date(), source: .default)
        ]
        let incoming: [CSVImportRow] = []
        let result = sut.merge(incoming: incoming, into: existing, strategy: .replaceAll)
        XCTAssertTrue(result.isEmpty)
    }

    func testMerge_existingWins_doesNotOverwriteExisting() {
        let existing: [String: DictionaryMetadata] = [
            "foo": DictionaryMetadata(replacement: "OldValue", createdAt: Date(), source: .user)
        ]
        let incoming = [CSVImportRow(original: "foo", replacement: "NewValue")]
        let result = sut.merge(incoming: incoming, into: existing, strategy: .existingWins)
        XCTAssertEqual(result["foo"]?.replacement, "OldValue")
    }

    func testMerge_existingWins_insertsNewKeys() {
        let existing: [String: DictionaryMetadata] = [:]
        let incoming = [CSVImportRow(original: "foo", replacement: "bar")]
        let result = sut.merge(incoming: incoming, into: existing, strategy: .existingWins)
        XCTAssertEqual(result["foo"]?.replacement, "bar")
        XCTAssertEqual(result["foo"]?.source, .imported)
    }

    func testMerge_incomingWins_upsertAllKeys() {
        let existing: [String: DictionaryMetadata] = [
            "foo": DictionaryMetadata(replacement: "OldValue", createdAt: Date(), source: .user)
        ]
        let incoming = [CSVImportRow(original: "foo", replacement: "NewValue")]
        let result = sut.merge(incoming: incoming, into: existing, strategy: .incomingWins)
        XCTAssertEqual(result["foo"]?.replacement, "NewValue")
        XCTAssertEqual(result["foo"]?.source, .imported)
    }

    func testMerge_stripsEmptyReplacement() {
        let existing: [String: DictionaryMetadata] = [:]
        let incoming = [CSVImportRow(original: "foo", replacement: "")]
        let result = sut.merge(incoming: incoming, into: existing, strategy: .incomingWins)
        XCTAssertNil(result["foo"])
    }

    func testMerge_stripsIdenticalKeyReplacement() {
        let existing: [String: DictionaryMetadata] = [:]
        let incoming = [CSVImportRow(original: "foo", replacement: "foo")]
        let result = sut.merge(incoming: incoming, into: existing, strategy: .incomingWins)
        XCTAssertNil(result["foo"])
    }

    // MARK: - Round-trip

    func testCSVRoundTrip_preservesOriginalAndReplacement() throws {
        let dict: [String: DictionaryMetadata] = [
            "tail scale": DictionaryMetadata(replacement: "Tailscale", createdAt: Date(), source: .user),
            "true nest": DictionaryMetadata(replacement: "TrueNAS", createdAt: Date(), source: .user)
        ]
        let csv = sut.serializeCSV(dict)
        let result = try sut.parseCSV(csv)
        let parsed = Dictionary(uniqueKeysWithValues: result.rows.map { ($0.original, $0.replacement) })
        XCTAssertEqual(parsed["tail scale"], "Tailscale")
        XCTAssertEqual(parsed["true nest"], "TrueNAS")
    }

    func testCSVRoundTrip_handlesCommasInValues() throws {
        let dict: [String: DictionaryMetadata] = [
            "tail scale, etc.": DictionaryMetadata(replacement: "Tailscale, etc.", createdAt: Date(), source: .user)
        ]
        let csv = sut.serializeCSV(dict)
        let result = try sut.parseCSV(csv)
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.rows[0].original, "tail scale, etc.")
        XCTAssertEqual(result.rows[0].replacement, "Tailscale, etc.")
    }

    func testJSONRoundTrip_preservesOriginalReplacementAndCreatedAt() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let dict: [String: DictionaryMetadata] = [
            "foo": DictionaryMetadata(replacement: "bar", createdAt: date, source: .user)
        ]
        let data = sut.serializeJSON(dict)
        let rows = try sut.parseJSON(data)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].original, "foo")
        XCTAssertEqual(rows[0].replacement, "bar")
    }
}
