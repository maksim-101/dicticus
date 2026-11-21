import XCTest
@testable import Dicticus

/// Slice 52: one row per correct spelling. Drives the real `DictionaryService.shared`
/// on the ephemeral test suite (asserted below, as in `DictionaryEntryEditTests`).
/// Every fixture is an invented word; this is a public repo.
@MainActor
final class DictionaryGroupTests: XCTestCase {

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

    private func persisted() -> [String: DictionaryMetadata] {
        DictionaryService.loadGuarded(from: DictionaryService.defaults, key: DictionaryService.dictionaryKey).dictionary
    }

    // MARK: - Grouping

    func testGroupingCollectsFormsPerExactSpelling() {
        let d = Date(timeIntervalSince1970: 1000)
        let entries: [String: DictionaryMetadata] = [
            "kwib ly": DictionaryMetadata(replacement: "Quibbly", createdAt: d, source: .imported),
            "quibli": DictionaryMetadata(replacement: "Quibbly", createdAt: d.addingTimeInterval(60), source: .user),
            "Kwiblee": DictionaryMetadata(replacement: "Quibbly", createdAt: d, source: .default),
            "flor": DictionaryMetadata(replacement: "quibbly", createdAt: d, source: .user),
            "Quibbly": DictionaryMetadata(replacement: "Zornex", createdAt: d, source: .user),
        ]
        let groups = DictionaryService.groups(of: entries)
        XCTAssertEqual(groups.count, 3, "case variants of a spelling stay separate rows")

        let q = groups.first { $0.spelling == "Quibbly" }!
        XCTAssertEqual(q.forms, ["kwib ly", "Kwiblee", "quibli"])
        XCTAssertEqual(q.newestCreatedAt, d.addingTimeInterval(60))
        XCTAssertEqual(q.source, .user)
        XCTAssertEqual(groups.first { $0.spelling == "quibbly" }?.forms, ["flor"])
        XCTAssertEqual(groups.first { $0.spelling == "Zornex" }?.forms, ["Quibbly"], "a spelling that is also another entry's key stays its own row")
        XCTAssertEqual(groups.reduce(0) { $0 + $1.forms.count }, entries.count)
    }

    /// Criterion 1's count on the owner's dictionary: runs only when TEST_RUNNER_DICT_BLOB
    /// names a read-only copy of the blob outside the repo.
    func testLiveDictionaryGroupCount() throws {
        guard let path = ProcessInfo.processInfo.environment["DICT_BLOB"], !path.isEmpty else {
            throw XCTSkip("DICT_BLOB not set")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let entries = try JSONDecoder().decode([String: DictionaryMetadata].self, from: data)
        let groups = DictionaryService.groups(of: entries)
        print("LIVE DICTIONARY: groups \(groups.count) entries \(entries.count)")
        XCTAssertEqual(groups.reduce(0) { $0 + $1.forms.count }, entries.count)
    }

    // MARK: - addHeardForm

    func testAddHeardFormJoinsExistingSpellingAndAppliesOnNextDictation() {
        service.setReplacement(for: "kwib ly", with: "Quibbly")
        XCTAssertEqual(service.addHeardForm("quibli", to: "Quibbly"), .saved)

        XCTAssertEqual(DictionaryService.groups(of: service.dictionary).first?.forms, ["kwib ly", "quibli"])
        XCTAssertEqual(service.dictionary["quibli"]?.source, .user)
        XCTAssertEqual(service.applyWithTrace(to: "open quibli now").text, "open Quibbly now")
        XCTAssertEqual(persisted(), service.dictionary)
    }

    func testAddHeardFormOnCaseVariantOfExistingKeyChangesThatEntry() {
        service.setReplacement(for: "Zorn ex", with: "Zornex")
        XCTAssertEqual(service.addHeardForm("zorn EX", to: "Quibbly"), .saved)

        XCTAssertEqual(service.dictionary.count, 1, "no second key that matches the same text")
        XCTAssertEqual(service.dictionary["Zorn ex"]?.replacement, "Quibbly")
        XCTAssertEqual(service.existingKey(for: "ZORN EX"), "Zorn ex")
        XCTAssertEqual(persisted(), service.dictionary)
    }

    func testAddHeardFormRefusalsLeaveDictionaryUnchanged() {
        service.setReplacement(for: "kwib ly", with: "Quibbly")
        let before = service.dictionary
        XCTAssertEqual(service.addHeardForm("  ", to: "Quibbly"), .invalid("Heard form cannot be empty."))
        XCTAssertEqual(service.addHeardForm("quibli", to: " "), .invalid("Correct spelling cannot be empty."))
        XCTAssertEqual(service.addHeardForm("Quibbly", to: "Quibbly"), .invalid("Heard form and correct spelling cannot be identical."))
        XCTAssertEqual(service.dictionary, before)
        XCTAssertEqual(persisted(), before)
    }

    func testAddHeardFormDoesNotTouchCaseSensitiveUppercaseKey() {
        service.setReplacement(for: "QUIB", with: "Quib Tool")
        XCTAssertEqual(service.addHeardForm("quib", to: "Kwib"), .saved)

        XCTAssertEqual(service.dictionary["QUIB"]?.replacement, "Quib Tool")
        XCTAssertEqual(service.dictionary["quib"]?.replacement, "Kwib")
        XCTAssertEqual(service.dictionary.count, 2)
    }

    func testSpellingThatIsAnotherEntrysHeardFormIsRefused() {
        service.setReplacement(for: "kwib ly", with: "Quibbly")
        service.setReplacement(for: "flor", with: "Zornex")
        let before = service.dictionary

        XCTAssertEqual(service.renameSpelling(from: "Quibbly", to: "flor"),
                       .invalid("“flor” is itself a heard form of “Zornex”; choose another spelling."))
        XCTAssertEqual(service.addHeardForm("zib", to: "flor"),
                       .invalid("“flor” is itself a heard form of “Zornex”; choose another spelling."))
        if case .invalid = service.renameSpelling(from: "Quibbly", to: "kwib ly") {} else { XCTFail("a spelling exactly equal to one of its own forms must be refused") }
        XCTAssertEqual(service.dictionary, before)
        XCTAssertEqual(persisted(), before)
    }

    func testAddHeardFormToSpellingThatACaseVariantKeyAlreadyMapsToIsSaved() {
        service.setReplacement(for: "gitlo", with: "GitLo")
        XCTAssertEqual(service.addHeardForm("git lo", to: "GitLo"), .saved)
        XCTAssertEqual(service.dictionary["git lo"]?.replacement, "GitLo")
    }

    func testRenameSpellingMergingIntoSpellingACaseVariantKeyMapsToIsSaved() {
        service.setReplacement(for: "gitlo", with: "GitLo")
        service.setReplacement(for: "git low", with: "Git Low")
        XCTAssertEqual(service.renameSpelling(from: "Git Low", to: "GitLo"), .saved)
        XCTAssertEqual(service.dictionary["gitlo"]?.replacement, "GitLo")
        XCTAssertEqual(service.dictionary["git low"]?.replacement, "GitLo")
    }

    func testRenameSpellingEqualToAFormUpToCaseIsSaved() {
        service.setReplacement(for: "kloudo", with: "Cloudo")
        XCTAssertEqual(service.renameSpelling(from: "Cloudo", to: "Kloudo"), .saved)
        XCTAssertEqual(service.dictionary["kloudo"]?.replacement, "Kloudo")
    }

    // MARK: - renameSpelling

    func testRenameSpellingChangesEveryFormKeepsCreatedAtPromotesSource() throws {
        _ = service.importData(Data("kwib ly,Quibbly\nquibli,Quibbly\nflor,Zornex\n".utf8), format: "csv", strategy: .incomingWins)
        let before = service.dictionary

        XCTAssertEqual(service.renameSpelling(from: "Quibbly", to: "QuibblyPro"), .saved)

        for key in ["kwib ly", "quibli"] {
            let after = try XCTUnwrap(service.dictionary[key])
            XCTAssertEqual(after.replacement, "QuibblyPro")
            XCTAssertEqual(after.createdAt, before[key]?.createdAt)
            XCTAssertEqual(after.source, .user)
        }
        XCTAssertEqual(service.dictionary["flor"], before["flor"], "other rows untouched")
        XCTAssertEqual(persisted(), service.dictionary)
    }

    func testRenameSpellingToAnotherRowsSpellingMergesRows() {
        service.setReplacement(for: "kwib ly", with: "Quibbly")
        service.setReplacement(for: "flor", with: "Zornex")
        XCTAssertEqual(service.renameSpelling(from: "Quibbly", to: "Zornex"), .saved)
        let groups = DictionaryService.groups(of: service.dictionary)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.forms, ["flor", "kwib ly"])
    }

    func testRenameSpellingRefusalsLeaveDictionaryUnchanged() {
        service.setReplacement(for: "kwib ly", with: "Quibbly")
        service.setReplacement(for: "quibli", with: "Quibbly")
        let before = service.dictionary
        XCTAssertEqual(service.renameSpelling(from: "Quibbly", to: "  "), .invalid("Correct spelling cannot be empty."))
        if case .invalid = service.renameSpelling(from: "Quibbly", to: "quibli") {} else { XCTFail("a spelling equal to one of its own forms must be refused") }
        XCTAssertEqual(service.renameSpelling(from: "Nothing", to: "X"), .notFound)
        XCTAssertEqual(service.dictionary, before)
        XCTAssertEqual(persisted(), before)
    }

    func testRenameSpellingToSameSpellingWritesNothing() throws {
        _ = service.importData(Data("kwib ly,Quibbly\n".utf8), format: "csv", strategy: .incomingWins)
        XCTAssertEqual(service.dictionary["kwib ly"]?.source, .imported)

        XCTAssertEqual(service.renameSpelling(from: "Quibbly", to: " Quibbly "), .saved)
        XCTAssertEqual(service.dictionary["kwib ly"]?.source, .imported)
    }

    // MARK: - Removal

    func testRemoveHeardFormAndRemoveGroup() {
        service.setReplacement(for: "kwib ly", with: "Quibbly")
        service.setReplacement(for: "quibli", with: "Quibbly")
        service.setReplacement(for: "flor", with: "Zornex")

        service.removeHeardForm("quibli")
        XCTAssertEqual(Set(service.dictionary.keys), ["kwib ly", "flor"])

        service.removeGroup(spelling: "Quibbly")
        XCTAssertEqual(Set(service.dictionary.keys), ["flor"])
        XCTAssertEqual(persisted(), service.dictionary)

        let before = service.dictionary
        service.removeHeardForm("absent")
        service.removeGroup(spelling: "Absent")
        XCTAssertEqual(service.dictionary, before)
    }

    func testUndoOfRemovalsRestoresTheRemovedEntries() {
        service.setReplacement(for: "kwib ly", with: "Quibbly")
        service.setReplacement(for: "quibli", with: "Quibbly")
        service.setReplacement(for: "flor", with: "Zornex")
        service.setReplacement(for: "gitlo", with: "GitLo")
        let before = service.dictionary

        service.restoreEntries(service.removeHeardForm("quibli"))
        XCTAssertEqual(service.dictionary, before)

        let removed = service.removeGroups(spellings: ["Quibbly", "Zornex"])
        XCTAssertEqual(Set(service.dictionary.keys), ["gitlo"])
        XCTAssertEqual(Set(removed.keys), ["kwib ly", "quibli", "flor"])
        service.restoreEntries(removed)
        XCTAssertEqual(service.dictionary, before, "createdAt and source come back unchanged")
        XCTAssertEqual(persisted(), before)
    }

    /// F1a: the popover quick-add stored `replacement: ""`, which deletes the heard word.
    func testSetReplacementRefusesEmptyReplacement() {
        service.setReplacement(for: "kwib ly", with: "")
        service.setReplacement(for: "flor", with: "   ")
        XCTAssertTrue(service.dictionary.isEmpty)
        XCTAssertTrue(persisted().isEmpty)

        service.setReplacement(for: "Quibbly", with: "Quibbly")
        XCTAssertEqual(service.dictionary["Quibbly"]?.replacement, "Quibbly", "an identical pair anchors the fuzzy pass")
    }

    func testRestoreEntryUndoesAddAndChange() {
        service.setReplacement(for: "kwib ly", with: "Quibbly")
        let old = service.dictionary["kwib ly"]

        service.addHeardForm("kwib ly", to: "Zornex")
        service.restoreEntry("kwib ly", to: old)
        XCTAssertEqual(service.dictionary["kwib ly"], old)

        service.addHeardForm("flor", to: "Zornex")
        service.restoreEntry("flor", to: nil)
        XCTAssertNil(service.dictionary["flor"])
        XCTAssertEqual(persisted(), service.dictionary)
    }

    // MARK: - Search

    func testFilterMatchesSpellingOrHeardFormIgnoringCaseAndDiacritics() {
        let d = Date()
        let groups = DictionaryService.groups(of: [
            "flor dex": DictionaryMetadata(replacement: "FlorDex", createdAt: d),
            "flora via": DictionaryMetadata(replacement: "Floravia", createdAt: d),
            "zorn x": DictionaryMetadata(replacement: "Zornex", createdAt: d),
            "grun bach": DictionaryMetadata(replacement: "Grünbach", createdAt: d),
        ])
        func spellings(_ q: String) -> Set<String> { Set(DictionaryService.filter(groups, query: q).map(\.spelling)) }

        XCTAssertEqual(spellings("FLOR"), ["FlorDex", "Floravia"], "spelling and heard form, any case")
        XCTAssertEqual(spellings("zorn x"), ["Zornex"], "heard form only")
        XCTAssertEqual(spellings("grunbach"), ["Grünbach"], "umlaut ignored")
        XCTAssertEqual(spellings("grün"), ["Grünbach"])
        XCTAssertEqual(spellings("quibbly"), [])
        XCTAssertEqual(spellings("  "), Set(groups.map(\.spelling)), "empty query keeps every row")
    }

    // MARK: - Everyday words

    func testEverydayWord() {
        XCTAssertTrue(service.isEverydayWord("cloud"))
        XCTAssertTrue(service.isEverydayWord("Cloud"))
        XCTAssertTrue(service.isEverydayWord("Haus"))
        XCTAssertFalse(service.isEverydayWord("Quibbly"))
        XCTAssertFalse(service.isEverydayWord("cloud code"), "multi-word forms are not judged")
        XCTAssertFalse(service.isEverydayWord(""))
    }
}
