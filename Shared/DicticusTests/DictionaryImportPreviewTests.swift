import XCTest
@testable import Dicticus

/// Quick task 260801-ftf: contract tests for the import-dialog safety feature —
/// `DictionaryIOService.preview(incoming:against:)` (pure) and
/// `DictionaryService.previewImport(_:format:)` (the read-only service wrapper).
/// This reproduces the 2026-08-01 near-miss at its real scale: a 25-entry CSV
/// imported over a 191-entry dictionary was one Return-keypress away from
/// destroying 166 entries. All fixtures below are invented, programmatically
/// generated stems — no real org, product, or person appears in this file.
///
/// The pure-function cases below need no singleton and no isolation concerns
/// (hand-built `[String: DictionaryMetadata]`, no `DictionaryService.shared`).
/// The `previewImport` cases DO drive the real singleton, so they follow the
/// same isolation gate as `DictionaryEntryEditTests`: this dictionary has a
/// 3-incident data-loss history and a test suite was one of the wipers.
final class DictionaryImportPreviewTests: XCTestCase {

    // MARK: - Pure `DictionaryIOService.preview` cases

    /// Reproduces the 2026-08-01 near-miss at its real scale: 191 existing
    /// entries, a 25-entry file where 22 originals already exist (conflicts)
    /// and 3 are new. `deletedByReplaceAll` — what Replace All would destroy —
    /// is asserted as the literal 169 so the test cannot silently drift with
    /// the implementation, and cross-checked against the independent
    /// `existingCount - conflictCount` arithmetic.
    func testRealScale191Existing25File22Conflict() {
        var existing: [String: DictionaryMetadata] = [:]
        for i in 0..<191 {
            existing["kwibble-\(i)"] = DictionaryMetadata(replacement: "Quibbly\(i)", createdAt: Date())
        }

        var incoming: [CSVImportRow] = []
        // 22 originals that collide with existing keys.
        for i in 0..<22 {
            incoming.append(CSVImportRow(original: "kwibble-\(i)", replacement: "QuibblyUpdated\(i)"))
        }
        // 3 brand-new originals.
        for i in 191..<194 {
            incoming.append(CSVImportRow(original: "kwibble-\(i)", replacement: "Quibbly\(i)"))
        }

        let io = DictionaryIOService()
        let preview = io.preview(incoming: incoming, against: existing)

        XCTAssertEqual(preview.fileCount, 25)
        XCTAssertEqual(preview.conflictCount, 22)
        XCTAssertEqual(preview.newCount, 3)
        XCTAssertEqual(preview.newCount + preview.conflictCount, preview.fileCount)
        XCTAssertEqual(preview.deletedByReplaceAll, 169)
        XCTAssertEqual(preview.deletedByReplaceAll, existing.count - preview.conflictCount)
    }

    func testDuplicateOriginalInFileCollapsesToOneEntry() {
        let existing: [String: DictionaryMetadata] = [
            "flar dex": DictionaryMetadata(replacement: "FlarDex", createdAt: Date())
        ]
        let incoming: [CSVImportRow] = [
            CSVImportRow(original: "nim bus nine", replacement: "Nimbus9"),
            CSVImportRow(original: "nim bus nine", replacement: "Nimbus9Duplicate"),
        ]

        let io = DictionaryIOService()
        let preview = io.preview(incoming: incoming, against: existing)

        XCTAssertEqual(preview.fileCount, 1)
        XCTAssertEqual(preview.newCount + preview.conflictCount, preview.fileCount)
    }

    func testSkippedRowsExcludedFromFileCountAndCountedSeparately() {
        let existing: [String: DictionaryMetadata] = [:]
        let incoming: [CSVImportRow] = [
            CSVImportRow(original: "vurtle cast", replacement: "Vurtlecast"),
            CSVImportRow(original: "empty replacement", replacement: ""),
            CSVImportRow(original: "identical pair", replacement: "identical pair"),
        ]

        let io = DictionaryIOService()
        let preview = io.preview(incoming: incoming, against: existing)

        XCTAssertEqual(preview.fileCount, 1)
        XCTAssertEqual(preview.skippedCount, 2)
    }

    func testEmptyDictionaryYieldsZeroConflictsAndZeroDeletions() {
        let existing: [String: DictionaryMetadata] = [:]
        let incoming: [CSVImportRow] = [
            CSVImportRow(original: "kwibble", replacement: "Quibbly"),
            CSVImportRow(original: "flar dex", replacement: "FlarDex"),
        ]

        let io = DictionaryIOService()
        let preview = io.preview(incoming: incoming, against: existing)

        XCTAssertEqual(preview.conflictCount, 0)
        XCTAssertEqual(preview.deletedByReplaceAll, 0)
        XCTAssertEqual(preview.newCount, 2)
    }

    // MARK: - `DictionaryService.previewImport` — read-only, drives the real singleton

    @MainActor
    func testPreviewImportOverBrokenCSVReturnsFailureAndLeavesDictionaryUnchanged() throws {
        try XCTSkipUnless(
            DicticusTestBootstrap.didBootstrap,
            "DicticusTestBootstrap did not run — refusing to touch DictionaryService.shared, which would write to the real user dictionary"
        )
        DictionaryService.shared.removeAll()
        DictionaryService.shared.setReplacement(for: "nim bus nine", with: "Nimbus9")
        let before = DictionaryService.shared.dictionary

        // Structurally broken: three columns where two are expected.
        let brokenCSV = "kwibble,Quibbly,extra\n"
        let result = DictionaryService.shared.previewImport(Data(brokenCSV.utf8), format: "csv")

        guard case .failure(let message) = result else {
            XCTFail("expected .failure, got \(result)")
            return
        }
        XCTAssertFalse(message.isEmpty)
        XCTAssertEqual(DictionaryService.shared.dictionary, before)
    }

    @MainActor
    func testPreviewImportOverValidCSVMatchesPureComputationAndLeavesDictionaryUnchanged() throws {
        try XCTSkipUnless(
            DicticusTestBootstrap.didBootstrap,
            "DicticusTestBootstrap did not run — refusing to touch DictionaryService.shared, which would write to the real user dictionary"
        )
        DictionaryService.shared.removeAll()
        DictionaryService.shared.setReplacement(for: "kwibble", with: "Quibbly")
        DictionaryService.shared.setReplacement(for: "flar dex", with: "FlarDex")
        let before = DictionaryService.shared.dictionary

        let csv = "kwibble,QuibblyUpdated\nvurtle cast,Vurtlecast\n"
        let result = DictionaryService.shared.previewImport(Data(csv.utf8), format: "csv")

        guard case .preview(let preview) = result else {
            XCTFail("expected .preview, got \(result)")
            return
        }
        XCTAssertEqual(preview.fileCount, 2)
        XCTAssertEqual(preview.conflictCount, 1)
        XCTAssertEqual(preview.newCount, 1)
        XCTAssertEqual(DictionaryService.shared.dictionary, before)
    }
}
