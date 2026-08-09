import XCTest
@testable import Dicticus

/// Quick task 260809-g7h — Defects A1, A2, C:
///
/// A1: `isCommon`'s edge-only `depunct` leaves a contraction's interior
/// apostrophe in place ("we've"), which misses the lexicon (word lists carry
/// the stem, not the apostrophe form) and is therefore wrongly treated as
/// DISTINCTIVE — eligible for fuzzy brand rewriting ("we've" -> "Wi-Fi").
///
/// A2: the phonetic-only accept in `matchToken` is unbounded by canonical
/// length, so a 3-character canonical ("UAT") collides with far more
/// ordinary text than a longer one ("uuid" -> "UAT").
///
/// C: a near-exact single token that is the canonical plus a pure inflection
/// suffix loses its inflection ("LLMs" -> "LLM").
///
/// Real bundled lexicon via `BrandMatcher.bundledLexiconMatcher` — a
/// hand-supplied lexicon would let the contraction guard pass vacuously.
/// Every assertion is an EXACT string.
@MainActor
final class BrandContractionInflectionTests: XCTestCase {

    static let canonicals: [String] = ["Wi-Fi", "UAT", "LLM", "Sonnet", "Tauri", "Dicticus"]

    private func makeMatcher() -> BrandMatcher {
        BrandMatcher.bundledLexiconMatcher(canonicals: BrandContractionInflectionTests.canonicals)
    }

    // MARK: - Contraction sweep (Defect A1)

    func testContractionWeveNotRewrittenToWiFi() {
        XCTAssertEqual(makeMatcher().apply(to: "I think we've got it.", language: "en"),
                       "I think we've got it.")
    }

    func testContractionWereUnchanged() {
        XCTAssertEqual(makeMatcher().apply(to: "we're on the call now.", language: "en"),
                       "we're on the call now.")
    }

    func testContractionIllUnchanged() {
        XCTAssertEqual(makeMatcher().apply(to: "I'll check it later.", language: "en"),
                       "I'll check it later.")
    }

    func testContractionDontUnchanged() {
        XCTAssertEqual(makeMatcher().apply(to: "don't do that again.", language: "en"),
                       "don't do that again.")
    }

    func testContractionTheyveUnchanged() {
        XCTAssertEqual(makeMatcher().apply(to: "they've already moved on.", language: "en"),
                       "they've already moved on.")
    }

    func testContractionIsntUnchanged() {
        XCTAssertEqual(makeMatcher().apply(to: "it isn't ready yet.", language: "en"),
                       "it isn't ready yet.")
    }

    func testClassifyCommonRecognizesContractions() {
        let bm = makeMatcher()
        XCTAssertTrue(bm.classifyCommon("we've"))
        XCTAssertTrue(bm.classifyCommon("don't"))
        XCTAssertTrue(bm.classifyCommon("they've"))
    }

    // MARK: - Short-canonical phonetic guard (Defect A2)

    func testUuidNotRewrittenToUAT() {
        XCTAssertEqual(makeMatcher().apply(to: "I generated a uuid for it.", language: "en"),
                       "I generated a uuid for it.")
    }

    /// CONTROL: must still fire — a phonetic-only accept against a canonical
    /// that clears the length floor (verified fact 5: jw 0.64, dl 3).
    func testTowryStillRewritesToTauriControl() {
        XCTAssertEqual(makeMatcher().apply(to: "Towry", language: "en"), "Tauri")
    }

    func testSonatStillRewritesToSonnetControl() {
        XCTAssertEqual(makeMatcher().apply(to: "Sonat", language: "en"), "Sonnet")
    }

    func testDicticosStillRewritesToDicticusControl() {
        XCTAssertEqual(makeMatcher().apply(to: "Dicticos", language: "en"), "Dicticus")
    }

    // MARK: - Inflection preservation (Defect C)

    func testLLMsKeepsInflection() {
        XCTAssertEqual(makeMatcher().apply(to: "where I have LLMs available", language: "en"),
                       "where I have LLMs available")
    }

    func testLLMIdentityUnchanged() {
        XCTAssertEqual(makeMatcher().apply(to: "the LLM is loaded", language: "en"),
                       "the LLM is loaded")
    }
}
