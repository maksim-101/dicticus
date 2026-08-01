import XCTest
@testable import Dicticus

/// Quick task 260801-ftf: contract tests for `DictionaryService.renameEntry`, the
/// shared in-place-edit method backing both the macOS row "Edit…" affordance and
/// the iOS tappable row.
///
/// This class drives the REAL `DictionaryService.shared` singleton (there is no
/// injectable instance — it is a private-init singleton, like every other
/// dictionary test). The dictionary has a 3-incident data-loss history, and a
/// test suite was the wiper on 2026-07-24 — so isolation is asserted, not
/// assumed, before any mutator call. Every fixture below is an invented brand;
/// this is a public repo and no real org, product, or person appears here.
@MainActor
final class DictionaryEntryEditTests: XCTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(
            DicticusTestBootstrap.didBootstrap,
            "DicticusTestBootstrap did not run — refusing to touch DictionaryService.shared, which would write to the real user dictionary"
        )
        DictionaryService.shared.removeAll()
    }

    // MARK: - Replacement-only edit

    func testReplacementOnlyEditPreservesCreatedAtExactly() {
        DictionaryService.shared.setReplacement(for: "kwibble", with: "Quibbly")
        let before = DictionaryService.shared.dictionary["kwibble"]!

        let result = DictionaryService.shared.renameEntry(from: "kwibble", to: "kwibble", replacement: "QuibblyPro")

        XCTAssertEqual(result, .saved)
        let after = DictionaryService.shared.dictionary["kwibble"]!
        XCTAssertEqual(after.replacement, "QuibblyPro")
        XCTAssertEqual(after.createdAt, before.createdAt)
    }

    // MARK: - Rename (original changed)

    func testRenameMovesKeyAndReplacementAndPreservesCreatedAtExactly() {
        DictionaryService.shared.setReplacement(for: "flar dex", with: "FlarDex")
        let before = DictionaryService.shared.dictionary["flar dex"]!

        let result = DictionaryService.shared.renameEntry(from: "flar dex", to: "flardexer", replacement: "FlarDexer")

        XCTAssertEqual(result, .saved)
        XCTAssertNil(DictionaryService.shared.dictionary["flar dex"])
        let after = DictionaryService.shared.dictionary["flardexer"]!
        XCTAssertEqual(after.replacement, "FlarDexer")
        XCTAssertEqual(after.createdAt, before.createdAt)
    }

    // MARK: - Source promotion

    func testEditingImportedEntryPromotesSourceToUser() {
        let importResult = DictionaryService.shared.importData(Data("kwibble,Quibbly\n".utf8), format: "csv", strategy: .incomingWins)
        guard case .success = importResult else {
            XCTFail("setup import failed: \(importResult)")
            return
        }
        // Prove the pre-state is really .imported — a test that silently started
        // from .user would pass vacuously.
        XCTAssertEqual(DictionaryService.shared.dictionary["kwibble"]?.source, .imported)

        let result = DictionaryService.shared.renameEntry(from: "kwibble", to: "kwibble", replacement: "QuibblyPro")

        XCTAssertEqual(result, .saved)
        XCTAssertEqual(DictionaryService.shared.dictionary["kwibble"]?.source, .user)
    }

    // MARK: - Collision

    func testRenameCollisionLeavesBothEntriesUnchanged() {
        DictionaryService.shared.setReplacement(for: "nim bus nine", with: "Nimbus9")
        DictionaryService.shared.setReplacement(for: "vurtle cast", with: "Vurtlecast")
        let before = DictionaryService.shared.dictionary

        let result = DictionaryService.shared.renameEntry(from: "nim bus nine", to: "vurtle cast", replacement: "NimbusRenamed")

        XCTAssertEqual(result, .collision("vurtle cast"))
        XCTAssertEqual(DictionaryService.shared.dictionary, before)
        XCTAssertEqual(DictionaryService.shared.dictionary.count, 2)
        XCTAssertEqual(DictionaryService.shared.dictionary["nim bus nine"]?.replacement, "Nimbus9")
        XCTAssertEqual(DictionaryService.shared.dictionary["vurtle cast"]?.replacement, "Vurtlecast")
    }

    // MARK: - Validation: rejected paths must leave the dictionary byte-identical

    func testEmptyNewOriginalIsInvalidAndDictionaryUnchanged() {
        DictionaryService.shared.setReplacement(for: "kwibble", with: "Quibbly")
        let before = DictionaryService.shared.dictionary

        let result = DictionaryService.shared.renameEntry(from: "kwibble", to: "", replacement: "Quibbly2")

        guard case .invalid = result else {
            XCTFail("expected .invalid, got \(result)")
            return
        }
        XCTAssertEqual(DictionaryService.shared.dictionary, before)
    }

    func testWhitespaceOnlyNewOriginalIsInvalidAndDictionaryUnchanged() {
        DictionaryService.shared.setReplacement(for: "kwibble", with: "Quibbly")
        let before = DictionaryService.shared.dictionary

        let result = DictionaryService.shared.renameEntry(from: "kwibble", to: "   ", replacement: "Quibbly2")

        guard case .invalid = result else {
            XCTFail("expected .invalid, got \(result)")
            return
        }
        XCTAssertEqual(DictionaryService.shared.dictionary, before)
    }

    func testEmptyNewReplacementIsInvalidAndDictionaryUnchanged() {
        DictionaryService.shared.setReplacement(for: "kwibble", with: "Quibbly")
        let before = DictionaryService.shared.dictionary

        let result = DictionaryService.shared.renameEntry(from: "kwibble", to: "kwibble", replacement: "")

        guard case .invalid = result else {
            XCTFail("expected .invalid, got \(result)")
            return
        }
        XCTAssertEqual(DictionaryService.shared.dictionary, before)
    }

    func testWhitespaceOnlyNewReplacementIsInvalidAndDictionaryUnchanged() {
        DictionaryService.shared.setReplacement(for: "kwibble", with: "Quibbly")
        let before = DictionaryService.shared.dictionary

        let result = DictionaryService.shared.renameEntry(from: "kwibble", to: "kwibble", replacement: "   ")

        guard case .invalid = result else {
            XCTFail("expected .invalid, got \(result)")
            return
        }
        XCTAssertEqual(DictionaryService.shared.dictionary, before)
    }

    func testIdenticalOriginalAndReplacementIsInvalidAndDictionaryUnchanged() {
        DictionaryService.shared.setReplacement(for: "kwibble", with: "Quibbly")
        let before = DictionaryService.shared.dictionary

        let result = DictionaryService.shared.renameEntry(from: "kwibble", to: "SameText", replacement: "SameText")

        guard case .invalid = result else {
            XCTFail("expected .invalid, got \(result)")
            return
        }
        XCTAssertEqual(DictionaryService.shared.dictionary, before)
    }

    // MARK: - Unknown key

    func testUnknownSourceKeyReturnsNotFoundAndInsertsNothing() {
        let before = DictionaryService.shared.dictionary // empty, post removeAll()

        let result = DictionaryService.shared.renameEntry(from: "nonexistent-key", to: "flar dex", replacement: "FlarDex")

        XCTAssertEqual(result, .notFound)
        XCTAssertEqual(DictionaryService.shared.dictionary, before)
        XCTAssertNil(DictionaryService.shared.dictionary["flar dex"])
    }

    // MARK: - Trimming

    func testWhitespaceIsTrimmedFromBothNewFieldsBeforeStorage() {
        DictionaryService.shared.setReplacement(for: "nim bus nine", with: "Nimbus9")

        let result = DictionaryService.shared.renameEntry(from: "nim bus nine", to: "  nim bus ten  ", replacement: "  Nimbus10  ")

        XCTAssertEqual(result, .saved)
        XCTAssertNil(DictionaryService.shared.dictionary["  nim bus ten  "])
        let after = DictionaryService.shared.dictionary["nim bus ten"]!
        XCTAssertEqual(after.replacement, "Nimbus10")
    }

    // MARK: - Case-only rename is not a collision

    func testCaseOnlyRenameSucceedsAndIsNotTreatedAsCollision() {
        DictionaryService.shared.setReplacement(for: "kwibble", with: "Quibbly")

        let result = DictionaryService.shared.renameEntry(from: "kwibble", to: "Kwibble", replacement: "Quibbly")

        XCTAssertEqual(result, .saved)
        XCTAssertNil(DictionaryService.shared.dictionary["kwibble"])
        XCTAssertEqual(DictionaryService.shared.dictionary["Kwibble"]?.replacement, "Quibbly")
        XCTAssertEqual(DictionaryService.shared.dictionary.count, 1)
    }
}
