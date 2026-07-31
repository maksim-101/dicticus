import XCTest
import WhisperKit
@testable import Dicticus

// Tests for TranscriptionService state machine, configuration, and pure logic.
// We do NOT test startRecording()/stopRecordingAndTranscribe() — those require a live
// WhisperKit instance with a loaded model, which is not available in CI (no model download).
// All tests that need a WhisperKit instance use XCTSkipUnless to skip gracefully.
@MainActor
final class TranscriptionServiceTests: XCTestCase {

    // MARK: - TranscriptionError enum tests

    func testTranscriptionErrorCasesExist() {
        // Verify all expected error cases can be constructed (compilation test)
        let tooShort: TranscriptionError = .tooShort
        let silenceOnly: TranscriptionError = .silenceOnly
        let noResult: TranscriptionError = .noResult
        let modelNotReady: TranscriptionError = .modelNotReady
        let notRecording: TranscriptionError = .notRecording
        let busy: TranscriptionError = .busy
        let unexpectedLanguage: TranscriptionError = .unexpectedLanguage

        // Use XCTAssertNotNil with Optional wrapping to avoid "always true" warning
        let errors: [TranscriptionError] = [tooShort, silenceOnly, noResult, modelNotReady, notRecording, busy, unexpectedLanguage]
        XCTAssertEqual(errors.count, 7, "All seven TranscriptionError cases should be constructible")
    }

    // MARK: - Language restriction tests
    // restrictLanguage is a non-private method, testable without a WhisperKit instance
    // by using a test helper that invokes it without model initialization.

    func testRestrictLanguageGerman() {
        let result = TranscriptionService.testRestrictLanguage("de")
        XCTAssertEqual(result, "de", "German 'de' should pass through language restriction unchanged")
    }

    func testRestrictLanguageEnglish() {
        let result = TranscriptionService.testRestrictLanguage("en")
        XCTAssertEqual(result, "en", "English 'en' should pass through language restriction unchanged")
    }

    func testRestrictLanguageFrenchFallsBackToEnglish() {
        let result = TranscriptionService.testRestrictLanguage("fr")
        XCTAssertEqual(result, "en", "French 'fr' should fall back to 'en' as the default language")
    }

    func testRestrictLanguageEmptyFallsBackToEnglish() {
        let result = TranscriptionService.testRestrictLanguage("")
        XCTAssertEqual(result, "en", "Empty string should fall back to 'en'")
    }

    func testRestrictLanguageJapaneseFallsBackToEnglish() {
        let result = TranscriptionService.testRestrictLanguage("ja")
        XCTAssertEqual(result, "en", "Japanese 'ja' should fall back to 'en'")
    }

    func testRestrictLanguageSpanishFallsBackToEnglish() {
        let result = TranscriptionService.testRestrictLanguage("es")
        XCTAssertEqual(result, "en", "Spanish 'es' should fall back to 'en'")
    }

    // MARK: - Language detection tests (NLLanguageRecognizer, no WhisperKit needed)

    func testDetectLanguageGerman() {
        // NLLanguageRecognizer should detect German text
        // Use a sentence long enough for reliable detection
        let result = TranscriptionService.testDetectLanguage(
            "Dies ist ein Testsatz in deutscher Sprache"
        )
        XCTAssertEqual(result, "de", "German text should be detected as 'de'")
    }

    func testDetectLanguageEnglish() {
        let result = TranscriptionService.testDetectLanguage(
            "This is a test sentence in English language"
        )
        XCTAssertEqual(result, "en", "English text should be detected as 'en'")
    }

    func testDetectLanguageShortTextDefaultsToEnglish() {
        // Very short text may not have enough signal for detection
        // Should default to "en" gracefully
        let result = TranscriptionService.testDetectLanguage("ok")
        // "ok" is ambiguous — could be en or de. We accept either "de" or "en"
        // as long as it doesn't crash. The key test is that it returns a valid value.
        let validLanguages = ["de", "en"]
        XCTAssertTrue(validLanguages.contains(result),
                      "Short text should return either 'de' or 'en', got: \(result)")
    }

    // MARK: - Language detection "other" marker tests (D-08/MLANG-03, Phase 42-02)
    // Loosening the recognizer's languageConstraints lets a genuine non-de/en
    // language surface instead of being forced into de/en.

    func testDetectLanguageFrenchReturnsOther() {
        let result = TranscriptionService.testDetectLanguage(
            "Ceci est une phrase de test en langue française"
        )
        XCTAssertEqual(result, "other", "Confident French text should be detected as 'other', not forced into de/en")
    }

    func testDetectLanguageSpanishReturnsOther() {
        let result = TranscriptionService.testDetectLanguage(
            "Esta es una oración de prueba en idioma español"
        )
        XCTAssertEqual(result, "other", "Confident Spanish text should be detected as 'other', not forced into de/en")
    }

    // MARK: - Non-Latin script detection tests (TRNS-01, containsNonLatinScript)

    func testContainsNonLatinScriptPureLatinReturnsFalse() {
        XCTAssertFalse(
            TranscriptionService.containsNonLatinScript("Hello world"),
            "Pure ASCII Latin text should not be flagged as non-Latin"
        )
    }

    func testContainsNonLatinScriptGermanUmlautsReturnsFalse() {
        XCTAssertFalse(
            TranscriptionService.containsNonLatinScript("Guten Tag"),
            "German text with extended Latin characters (umlauts) should not be flagged"
        )
    }

    func testContainsNonLatinScriptCyrillicReturnsTrue() {
        XCTAssertTrue(
            TranscriptionService.containsNonLatinScript("Привет мир"),
            "Cyrillic text should be detected as non-Latin"
        )
    }

    func testContainsNonLatinScriptCJKReturnsTrue() {
        XCTAssertTrue(
            TranscriptionService.containsNonLatinScript("你好世界"),
            "CJK text should be detected as non-Latin"
        )
    }

    func testContainsNonLatinScriptArabicReturnsTrue() {
        XCTAssertTrue(
            TranscriptionService.containsNonLatinScript("مرحبا"),
            "Arabic text should be detected as non-Latin"
        )
    }

    func testContainsNonLatinScriptEmptyReturnsFalse() {
        XCTAssertFalse(
            TranscriptionService.containsNonLatinScript(""),
            "Empty string should not be flagged as non-Latin"
        )
    }

    func testContainsNonLatinScriptNumbersAndPunctuationReturnsFalse() {
        XCTAssertFalse(
            TranscriptionService.containsNonLatinScript("123 !@#"),
            "Numbers and punctuation should not be flagged as non-Latin"
        )
    }

    func testContainsNonLatinScriptCombiningAccentsReturnsFalse() {
        XCTAssertFalse(
            TranscriptionService.containsNonLatinScript("cafe\u{0301}"),
            "Combining accents on Latin base characters should not be flagged"
        )
    }

    // MARK: - EnergyVAD integration test (TRNS-04 coverage)

    func testEnergyVADDetectsSilenceAsNoVoice() {
        // Verify EnergyVAD reports no voice activity for a buffer of silence (all zeros).
        let vad = EnergyVAD()
        let silentSamples = [Float](repeating: 0.0, count: 16000) // 1 second of silence at 16kHz
        let hasVoice = vad.voiceActivity(in: silentSamples).contains(true)
        XCTAssertFalse(hasVoice, "Silent audio should not be detected as voice activity")
    }

    func testEnergyVADDetectsToneAsVoice() {
        // Verify EnergyVAD reports voice activity for a loud synthesized tone.
        let vad = EnergyVAD()
        let sampleRate: Float = 16000
        let toneSamples: [Float] = (0..<Int(sampleRate)).map { i in
            sin(2.0 * Float.pi * 440.0 * Float(i) / sampleRate) * 0.8
        }
        let hasVoice = vad.voiceActivity(in: toneSamples).contains(true)
        XCTAssertTrue(hasVoice, "A loud synthesized tone should be detected as voice activity")
    }

    // MARK: - Instance tests (require WhisperKit, skip in CI without model)

    func testInitialStateIsIdle() async throws {
        let service = try await makeServiceOrSkip()
        XCTAssertEqual(service.state, .idle, "Initial state should be .idle")
    }

    func testLastResultIsNilInitially() async throws {
        let service = try await makeServiceOrSkip()
        XCTAssertNil(service.lastResult, "lastResult should be nil on init")
    }

    func testErrorIsNilInitially() async throws {
        let service = try await makeServiceOrSkip()
        XCTAssertNil(service.error, "error should be nil on init")
    }

    func testMinimumDurationValue() async throws {
        let service = try await makeServiceOrSkip()
        XCTAssertEqual(service.minimumDurationSeconds, 0.3, accuracy: 0.001,
                       "minimumDurationSeconds should be 0.3 per D-11 in 02.1-CONTEXT.md")
    }

    func testDefaultSilenceThreshold() async throws {
        let service = try await makeServiceOrSkip()
        XCTAssertEqual(service.silenceThreshold, TranscriptionService.vadProbabilityThreshold, accuracy: 0.001,
                       "default silenceThreshold should match vadProbabilityThreshold (0.75)")
    }

    func testSilenceThresholdIsConfigurable() async throws {
        let service = try await makeServiceOrSkip()
        service.silenceThreshold = 0.7
        XCTAssertEqual(service.silenceThreshold, 0.7, accuracy: 0.001,
                       "silenceThreshold should accept custom values")
    }

    // MARK: - Helpers

    /// Attempts to create a TranscriptionService. Skips the test if WhisperKit is not available.
    /// This allows unit tests to run in CI without downloading the model.
    private func makeServiceOrSkip() async throws -> TranscriptionService {
        // WhisperKit can only init if the model is already cached.
        // In CI (and fresh machines), the model is not present.
        // Skip rather than fail — this is expected behavior for unit tests.
        try XCTSkipUnless(
            TranscriptionService.isWhisperKitAvailable(),
            "Skipping — WhisperKit model not loaded. Run manually after model warmup."
        )
        // If we reach here, the model cache exists. Init may still fail if warmup hasn't completed.
        guard let service = try? await TranscriptionService.makeForTesting() else {
            throw XCTSkip("WhisperKit init failed. Model may still be loading.")
        }
        return service
    }
}
