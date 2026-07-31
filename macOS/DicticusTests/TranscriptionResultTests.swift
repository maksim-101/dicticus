import XCTest
@testable import Dicticus

// Tests for DicticusTranscriptionResult value type.
// Verifies struct stores values correctly with proper Sendable semantics.
final class TranscriptionResultTests: XCTestCase {

    // MARK: - Initialization tests

    func testInitializesWithCorrectValues() {
        let result = DicticusTranscriptionResult(text: "hello", language: "en", confidence: 0.95)
        XCTAssertEqual(result.text, "hello", "text should match initializer argument")
        XCTAssertEqual(result.language, "en", "language should match initializer argument")
        XCTAssertEqual(result.confidence, 0.95, accuracy: 0.001, "confidence should match initializer argument")
    }

    func testGermanLanguage() {
        let result = DicticusTranscriptionResult(text: "Hallo Welt", language: "de", confidence: 0.9)
        XCTAssertEqual(result.language, "de", "language should be 'de' for German")
    }

    func testEnglishLanguage() {
        let result = DicticusTranscriptionResult(text: "Hello world", language: "en", confidence: 0.9)
        XCTAssertEqual(result.language, "en", "language should be 'en' for English")
    }

    // MARK: - Confidence bounds tests

    func testConfidenceAtZero() {
        let result = DicticusTranscriptionResult(text: "", language: "en", confidence: 0.0)
        XCTAssertEqual(result.confidence, 0.0, accuracy: 0.001, "confidence 0.0 should be stored correctly")
    }

    func testConfidenceAtOne() {
        let result = DicticusTranscriptionResult(text: "perfect", language: "en", confidence: 1.0)
        XCTAssertEqual(result.confidence, 1.0, accuracy: 0.001, "confidence 1.0 should be stored correctly")
    }

    // MARK: - Text content tests

    func testEmptyText() {
        let result = DicticusTranscriptionResult(text: "", language: "en", confidence: 0.5)
        XCTAssertEqual(result.text, "", "empty text should be stored correctly")
    }

    func testLongText() {
        let longText = String(repeating: "word ", count: 100)
        let result = DicticusTranscriptionResult(text: longText, language: "de", confidence: 0.8)
        XCTAssertEqual(result.text, longText, "long text should be stored without truncation")
    }
}
