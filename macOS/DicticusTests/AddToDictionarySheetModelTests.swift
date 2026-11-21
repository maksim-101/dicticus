import XCTest
@testable import Dicticus

/// Slice 52: the History "Add to Dictionary" sheet's note, warnings, save and undo,
/// driven against `DictionaryService.shared` on the ephemeral test suite. Invented words only.
@MainActor
final class AddToDictionarySheetModelTests: XCTestCase {

    private var service: DictionaryService { DictionaryService.shared }

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(
            DicticusTestBootstrap.didBootstrap,
            "DicticusTestBootstrap did not run — refusing to touch DictionaryService.shared, which would write to the real user dictionary"
        )
        service.removeAll()
    }

    override func tearDown() {
        DictionaryService.shared.removeAll()
        super.tearDown()
    }

    func testJoiningSpellingNoteAndSaveAppliesOnNextDictation() {
        service.setReplacement(for: "kwib ly", with: "Quibbly")
        service.setReplacement(for: "quibli", with: "Quibbly")
        let model = AddToDictionaryModel(heard: "kwibbel", service: service)
        model.correct = "Quibbly"

        XCTAssertEqual(model.note, "Joins “Quibbly”, which has 2 heard forms.")
        XCTAssertEqual(model.warnings, [])
        XCTAssertEqual(model.save(), "Added: “kwibbel” → “Quibbly”. Applies from your next dictation.")
        XCTAssertEqual(DictionaryService.groups(of: service.dictionary).first?.forms.count, 3)
        XCTAssertEqual(service.applyWithTrace(to: "open kwibbel today").text, "open Quibbly today")
    }

    func testNewSpellingNoteAndAddDisabledStates() {
        let model = AddToDictionaryModel(heard: "flor dex", service: service)
        XCTAssertFalse(model.canAdd)
        XCTAssertEqual(model.note, "")
        model.correct = "FlorDex"
        XCTAssertEqual(model.note, "New word in the dictionary.")
        XCTAssertTrue(model.canAdd)
        model.correct = "flor dex"
        XCTAssertFalse(model.canAdd)
        XCTAssertNil(model.save())
        XCTAssertTrue(service.dictionary.isEmpty)
    }

    func testEverydayWordAndExistingKeyWarnings() {
        service.setReplacement(for: "cloud", with: "Quibbly")
        let model = AddToDictionaryModel(heard: "Cloud", service: service)
        model.correct = "Zornex"
        XCTAssertEqual(model.warnings.count, 2)
        XCTAssertTrue(model.warnings[0].contains("everyday word"))
        XCTAssertTrue(model.warnings[1].contains("becomes “Quibbly”"))

        model.correct = "Quibbly"
        XCTAssertEqual(model.warnings.count, 1, "no conflict warning when it already becomes that spelling")

        let invented = AddToDictionaryModel(heard: "kwibbel", service: service)
        invented.correct = "Quibbly"
        XCTAssertEqual(invented.warnings, [])
    }

    func testUndoRemovesNewKeyAndRestoresChangedKey() {
        let fresh = AddToDictionaryModel(heard: "kwibbel", service: service)
        fresh.correct = "Quibbly"
        XCTAssertNotNil(fresh.save())
        fresh.undo()
        XCTAssertNil(service.dictionary["kwibbel"])

        service.setReplacement(for: "Flor", with: "FlorDex")
        let old = service.dictionary["Flor"]
        let changed = AddToDictionaryModel(heard: "flor", service: service)
        changed.correct = "Zornex"
        XCTAssertNotNil(changed.save())
        XCTAssertEqual(service.dictionary["Flor"]?.replacement, "Zornex")
        changed.undo()
        XCTAssertEqual(service.dictionary["Flor"], old)
        XCTAssertEqual(service.dictionary.count, 1)
    }

    func testTypedHeardFormIsSavedAsTyped() {
        let model = AddToDictionaryModel(heard: " C# ", service: service)
        model.correct = "Csharp"
        XCTAssertNotNil(model.save())
        XCTAssertEqual(service.dictionary["C#"]?.replacement, "Csharp")
        XCTAssertNil(service.dictionary["C"])
    }

    func testSpellingThatIsAnotherHeardFormWarnsAndBlocksAdd() {
        service.setReplacement(for: "flor", with: "Zornex")
        let model = AddToDictionaryModel(heard: "zib", service: service)
        model.correct = "flor"
        XCTAssertFalse(model.canAdd)
        XCTAssertTrue(model.warnings.contains { $0.contains("is itself a heard form of “Zornex”") })
        XCTAssertNil(model.save())
        XCTAssertNil(service.dictionary["zib"])
    }

    func testUndoDoesNotRevertAnEntryChangedAfterTheSave() {
        let model = AddToDictionaryModel(heard: "quibli", service: service)
        model.correct = "Quibbly"
        XCTAssertNotNil(model.save())
        XCTAssertEqual(service.renameSpelling(from: "Quibbly", to: "QuibblyPro"), .saved)

        XCTAssertFalse(model.undo())
        XCTAssertEqual(service.dictionary["quibli"]?.replacement, "QuibblyPro")
        XCTAssertNil(model.undoState)
    }
}
