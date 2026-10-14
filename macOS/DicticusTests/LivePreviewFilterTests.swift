import XCTest
@testable import Dicticus

/// Regression net for the preview text filters: D-03 (phantom chunks and whole-utterance
/// boilerplate), D-19 (foreign script) and D-05 (dictionary runs last, only on kept text).
/// Dictionary behaviour is injected, so `DictionaryService.shared` is never touched.
@MainActor
final class LivePreviewFilterTests: XCTestCase {

    @MainActor
    private final class Counter { var calls = 0 }

    private let identity: @MainActor (String) -> String = { $0 }

    private func preview(
        _ chunks: [(text: String, language: String)],
        dictionary: (@MainActor (String) -> String)? = nil
    ) -> String? {
        LivePreviewDecoder.previewText(from: chunks, dictionary: dictionary ?? identity)
    }

    func testShipListPhantomsAreDropped() {
        XCTAssertNil(preview([("Thank you.", "en")]))
        XCTAssertNil(preview([("Vielen Dank fürs Zuschauen.", "de")]))
    }

    func testSingleChunkInOtherLanguageIsDropped() {
        XCTAssertNil(preview([("Merci beaucoup pour votre attention", "fr")]))
    }

    func testNonLatinScriptIsDropped() {
        XCTAssertNil(preview([("Спасибо за внимание", "en")]))
    }

    func testWhitespaceOnlyIsDropped() {
        XCTAssertNil(preview([("  \n ", "en")]))
        XCTAssertNil(preview([]))
    }

    func testPhantomChunkIsDroppedAndDictionaryAppliedToTheRest() {
        let text = preview(
            [("We deploy to cloud", "en"), ("Thank you.", "en")],
            dictionary: { $0.replacingOccurrences(of: "cloud", with: "Claude") }
        )
        XCTAssertEqual(text, "We deploy to Claude")
    }

    func testDictionaryNeverResurrectsAFilteredPhantom() {
        XCTAssertNil(preview([("Thank you.", "en")], dictionary: { _ in "REWRITTEN" }))
        XCTAssertNil(preview([("Спасибо", "en")], dictionary: { _ in "REWRITTEN" }))
    }

    func testPlainSpeechPassesThroughTheDictionaryOnce() {
        let counter = Counter()
        let text = preview([("das ist ein Test", "de")], dictionary: { counter.calls += 1; return $0.uppercased() })
        XCTAssertEqual(text, "DAS IST EIN TEST")
        XCTAssertEqual(counter.calls, 1)
    }
}
