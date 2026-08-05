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

// MARK: - Task 260805-pc5: ASR-mishearing starter-pack batch

/// Locks the 12 public ASR-mishearing corrections added to the bundled brands/tech
/// starter packs (D-02/D-03), and — just as important — proves the 5 D-05 exclusions
/// stay inert. Drives the real `DictionaryService.shared` singleton and the real app
/// bundle (via `importStarterPack`), so a bundle-read miss (which returns
/// `.success(added: 0)`) cannot make every assertion below pass vacuously — the
/// non-vacuity floor at the end guards against exactly that.
///
/// This dictionary has a 3-incident data-loss history and a test suite was one of the
/// wipers (2026-07-24), so the isolation gate below is copied verbatim from
/// `DictionaryEntryEditTests` — never construct a real `UserDefaults` suite here.
@MainActor
final class DictionaryStarterPackAsrBatchTests: XCTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(
            DicticusTestBootstrap.didBootstrap,
            "DicticusTestBootstrap did not run — refusing to touch DictionaryService.shared, which would write to the real user dictionary"
        )
        DictionaryService.shared.removeAll()
        DictionaryService.shared.isCaseSensitive = false
    }

    // MARK: - Negative: D-05 exclusions must be provably inert

    /// "HEY→agy" is a personal entry (D-05) never added to the bundled packs.
    /// Starting from a removeAll()ed dictionary with only the packs imported,
    /// genuine "Hey," must survive byte-identical.
    func testExcludedHeyNeverRewrittenToAgy() {
        importBothPacks()
        let sentence = "Hey, are you still there?"
        XCTAssertEqual(DictionaryService.shared.apply(to: sentence), sentence)
    }

    /// "commutes→commits" is excluded (D-05, real-word key). "commits" itself is
    /// never a dictionary key — only a replacement value (Kamitsu,commits) — so a
    /// sentence dictating the real word "commits" must survive byte-identical.
    func testExcludedCommutesNeverRewritesCommits() {
        importBothPacks()
        let sentence = "Let's review the commits from today."
        XCTAssertEqual(DictionaryService.shared.apply(to: sentence), sentence)
    }

    // MARK: - Negative: no over-firing

    /// "Sable 5,Fable 5" must only fire on the exact two-word phrase — "Sable"
    /// without the trailing digit must be left alone.
    func testSableWithoutDigitNotOverfired() {
        importBothPacks()
        let sentence = "The sable coat was warm."
        XCTAssertEqual(DictionaryService.shared.apply(to: sentence), sentence)
    }

    // MARK: - Positive: D-02 brands pack additions

    func testTavileTavaliTavoliAllResolveToTavily() {
        importBothPacks()
        XCTAssertEqual(
            DictionaryService.shared.apply(to: "The tool is called Tavile."),
            "The tool is called Tavily."
        )
        XCTAssertEqual(
            DictionaryService.shared.apply(to: "The tool is called Tavali."),
            "The tool is called Tavily."
        )
        XCTAssertEqual(
            DictionaryService.shared.apply(to: "The tool is called Tavoli."),
            "The tool is called Tavily."
        )
    }

    func testJalifinAndChellyfinResolveToJellyfin() {
        importBothPacks()
        XCTAssertEqual(
            DictionaryService.shared.apply(to: "I stream shows from Jalifin."),
            "I stream shows from Jellyfin."
        )
        XCTAssertEqual(
            DictionaryService.shared.apply(to: "I stream shows from chellyfin."),
            "I stream shows from Jellyfin."
        )
    }

    /// Case-insensitivity: "Chellyfin" (capitalized) resolves the same as
    /// "chellyfin" (the pack's literal key casing).
    func testChellyfinCapitalizedResolvesCaseInsensitively() {
        importBothPacks()
        XCTAssertEqual(
            DictionaryService.shared.apply(to: "I stream shows from Chellyfin."),
            "I stream shows from Jellyfin."
        )
    }

    func testClaudAiAndClodAiResolveToClaudeAi() {
        importBothPacks()
        XCTAssertEqual(
            DictionaryService.shared.apply(to: "Open claud.ai in the browser."),
            "Open claude.ai in the browser."
        )
        XCTAssertEqual(
            DictionaryService.shared.apply(to: "Open clod.ai in the browser."),
            "Open claude.ai in the browser."
        )
    }

    func testSable5AndPhil5ResolveToFable5() {
        importBothPacks()
        XCTAssertEqual(
            DictionaryService.shared.apply(to: "I'm using Sable 5 today."),
            "I'm using Fable 5 today."
        )
        XCTAssertEqual(
            DictionaryService.shared.apply(to: "I'm using Phil 5 today."),
            "I'm using Fable 5 today."
        )
    }

    func testStixicusResolvesToDicticus() {
        importBothPacks()
        XCTAssertEqual(
            DictionaryService.shared.apply(to: "Open Stixicus and dictate."),
            "Open Dicticus and dictate."
        )
    }

    // MARK: - Positive: D-03 tech pack additions

    func testKamitsuResolvesToCommits() {
        importBothPacks()
        XCTAssertEqual(
            DictionaryService.shared.apply(to: "Push the Kamitsu now."),
            "Push the commits now."
        )
    }

    func testStarpokResolvesToStopHook() {
        importBothPacks()
        XCTAssertEqual(
            DictionaryService.shared.apply(to: "Run the starpok before pushing."),
            "Run the stop hook before pushing."
        )
    }

    // MARK: - Non-vacuity floor

    /// Without this, a bundle-read miss returns `.success(added: 0)` for both
    /// packs and every assertion above would pass vacuously over an empty
    /// dictionary. Both real packs together carry well over 70 valid rows.
    func testBothPacksActuallyImportedNonVacuously() {
        importBothPacks()
        XCTAssertGreaterThanOrEqual(DictionaryService.shared.dictionary.count, 70)
        XCTAssertTrue(DictionaryService.shared.isStarterPackImported(.brands))
        XCTAssertTrue(DictionaryService.shared.isStarterPackImported(.tech))
    }

    // MARK: - Helper

    /// Imports only the brands and tech packs (never the general pack or seeded
    /// defaults), so every expected string above is deterministic — no other
    /// entry can interfere with the assertions.
    private func importBothPacks() {
        let brandsResult = DictionaryService.shared.importStarterPack(.brands)
        guard case .success = brandsResult else {
            XCTFail("importStarterPack(.brands) must return .success, got \(brandsResult)")
            return
        }
        let techResult = DictionaryService.shared.importStarterPack(.tech)
        guard case .success = techResult else {
            XCTFail("importStarterPack(.tech) must return .success, got \(techResult)")
            return
        }
    }
}
