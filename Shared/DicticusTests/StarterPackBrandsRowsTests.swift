import XCTest
@testable import Dicticus

/// Phase 49.7 BRAND-02 / D-05.
///
/// The four public heard-form rows (`host point`→Hostpoint, `1 password`→1Password,
/// `open router`→OpenRouter, `taffoli`→Tavily) ship in the bundled Brand Names
/// starter pack. Personal entries are deliberately absent from every bundled pack —
/// they exist only in a local, gitignored import CSV the user reviews before a
/// later plan imports them.
final class StarterPackBrandsRowsTests: XCTestCase {

    private func loadBrandsPackRows() throws -> (rows: [CSVImportRow], warnings: [(line: Int, message: String)]) {
        guard let url = Bundle.main.url(forResource: "starter-pack-brands", withExtension: "csv") else {
            XCTFail("starter-pack-brands.csv not found in bundle")
            return (rows: [], warnings: [])
        }
        let content = try String(contentsOf: url, encoding: .utf8)
        return try DictionaryIOService().parseCSV(content)
    }

    func testBrandsPackParsesWithoutWarningsAndCarriesPhase497Rows() throws {
        let (rows, warnings) = try loadBrandsPackRows()
        XCTAssertTrue(warnings.isEmpty, "unexpected warnings: \(warnings)")

        let byOriginal = Dictionary(uniqueKeysWithValues: rows.map { ($0.original, $0.replacement) })
        XCTAssertEqual(byOriginal["host point"], "Hostpoint")
        XCTAssertEqual(byOriginal["1 password"], "1Password")
        XCTAssertEqual(byOriginal["open router"], "OpenRouter")
        XCTAssertEqual(byOriginal["taffoli"], "Tavily")
    }

    func testBrandsPackHasNoDuplicateOriginals() throws {
        let (rows, _) = try loadBrandsPackRows()
        let originals = rows.map(\.original)
        XCTAssertEqual(Set(originals).count, originals.count, "duplicate original key would make the pack's 'kept' count lie")
    }
}
