import XCTest
import AVFoundation
@testable import Dicticus

@MainActor
final class IOSTranscriptionServiceTests: XCTestCase {
    // Language restriction tests — call IOSTranscriptionService.testRestrictLanguage()
    func testRestrictLanguageGerman() {
        XCTAssertEqual(IOSTranscriptionService.testRestrictLanguage("de"), "de")
    }
    func testRestrictLanguageEnglish() {
        XCTAssertEqual(IOSTranscriptionService.testRestrictLanguage("en"), "en")
    }
    func testRestrictLanguageFrenchFallsBackToEnglish() {
        XCTAssertEqual(IOSTranscriptionService.testRestrictLanguage("fr"), "en")
    }
    func testRestrictLanguageEmptyFallsBackToEnglish() {
        XCTAssertEqual(IOSTranscriptionService.testRestrictLanguage(""), "en")
    }

    // Language detection tests — call IOSTranscriptionService.testDetectLanguage()
    func testDetectLanguageGerman() {
        XCTAssertEqual(
            IOSTranscriptionService.testDetectLanguage("Dies ist ein Testsatz in deutscher Sprache"), "de"
        )
    }
    func testDetectLanguageEnglish() {
        XCTAssertEqual(
            IOSTranscriptionService.testDetectLanguage("This is a test sentence in English language"), "en"
        )
    }

    // MARK: - Language detection "other" marker tests (D-08/MLANG-03, Phase 42-02)
    // Loosening the recognizer's languageConstraints lets a genuine non-de/en
    // language surface instead of being forced into de/en.

    func testDetectLanguageFrenchReturnsOther() {
        XCTAssertEqual(
            IOSTranscriptionService.testDetectLanguage("Ceci est une phrase de test en langue française"),
            "other",
            "Confident French text should be detected as 'other', not forced into de/en"
        )
    }

    func testDetectLanguageSpanishReturnsOther() {
        XCTAssertEqual(
            IOSTranscriptionService.testDetectLanguage("Esta es una oración de prueba en idioma español"),
            "other",
            "Confident Spanish text should be detected as 'other', not forced into de/en"
        )
    }

    // Non-Latin script detection tests
    func testContainsNonLatinScriptPureLatinReturnsFalse() {
        XCTAssertFalse(IOSTranscriptionService.containsNonLatinScript("Hello world"))
    }
    func testContainsNonLatinScriptGermanReturnsFalse() {
        XCTAssertFalse(IOSTranscriptionService.containsNonLatinScript("Guten Tag"))
    }
    func testContainsNonLatinScriptCyrillicReturnsTrue() {
        XCTAssertTrue(IOSTranscriptionService.containsNonLatinScript("Привет мир"))
    }
    func testContainsNonLatinScriptCJKReturnsTrue() {
        XCTAssertTrue(IOSTranscriptionService.containsNonLatinScript("你好世界"))
    }
    func testContainsNonLatinScriptArabicReturnsTrue() {
        XCTAssertTrue(IOSTranscriptionService.containsNonLatinScript("مرحبا"))
    }
    func testContainsNonLatinScriptEmptyReturnsFalse() {
        XCTAssertFalse(IOSTranscriptionService.containsNonLatinScript(""))
    }
    func testContainsNonLatinScriptNumbersAndPunctuationReturnsFalse() {
        XCTAssertFalse(IOSTranscriptionService.containsNonLatinScript("123 !@#"))
    }

    // Configuration tests (require WhisperKit model)
    func testInitialStateIsIdle() async throws {
        let service = try await makeServiceOrSkip()
        XCTAssertEqual(service.state, .idle)
    }
    func testMinimumDurationValue() async throws {
        let service = try await makeServiceOrSkip()
        XCTAssertEqual(service.minimumDurationSeconds, 0.3, accuracy: 0.001)
    }
    func testDefaultSilenceThreshold() async throws {
        let service = try await makeServiceOrSkip()
        XCTAssertEqual(service.silenceThreshold, IOSTranscriptionService.vadProbabilityThreshold, accuracy: 0.001)
    }

    func testPostProcessingTogglesDefaultToTrue() async throws {
        let service = try await makeServiceOrSkip()
        XCTAssertTrue(service.useCustomDictionary)
        XCTAssertTrue(service.useITN)
    }

    // IOSBG-01 / 36-AVSESSION: startRecording() must use .playAndRecord so the mic session
    // survives backgrounding (UIBackgroundModes:audio keep-alive requires this category).
    func testStartRecordingUsesPlayAndRecordCategory() async throws {
        let service = try await makeServiceOrSkip()
        try service.startRecording()
        XCTAssertEqual(
            AVAudioSession.sharedInstance().category,
            .playAndRecord,
            "startRecording() must set AVAudioSession category to .playAndRecord for background keep-alive"
        )
        service.cancelRecording()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func makeServiceOrSkip() async throws -> IOSTranscriptionService {
        try XCTSkipUnless(
            IOSTranscriptionService.isWhisperKitAvailable(),
            "Skipping — WhisperKit model not loaded."
        )
        guard let service = try? await IOSTranscriptionService.makeForTesting() else {
            throw XCTSkip("WhisperKit init failed.")
        }
        return service
    }
}
