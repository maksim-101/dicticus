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
    // Phase 46-02: IOSTranscriptionService no longer owns recording state — the
    // `.state`/AVAudioSession-category tests moved to AudioRecorderTests.
    // minimumDurationSeconds moved to a type-level constant (IOSTranscriptionService
    // .minimumDurationSeconds) so DictationViewModel can consult it without an
    // instance (a recording can be captured before any transcriber exists).
    func testMinimumDurationValue() {
        XCTAssertEqual(IOSTranscriptionService.minimumDurationSeconds, 0.3, accuracy: 0.001)
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

    private func makeServiceOrSkip() async throws -> IOSTranscriptionService {
        try XCTSkipUnless(
            IOSTranscriptionService.isModelAvailable(),
            "Skipping — Parakeet model not cached."
        )
        guard let service = try? await IOSTranscriptionService.makeForTesting() else {
            throw XCTSkip("FluidAudio init failed.")
        }
        return service
    }

    // MARK: - Decoder-state independence (Phase 47.1 Task 3, D-02/RESEARCH Pitfall 5 /
    // Assumption A2)
    //
    // FluidAudio's `TdtDecoderState` is `inout` and mutated by every `transcribe()` call.
    // `IOSTranscriptionService.transcribe(wavURL:)` recreates it fresh at the start of
    // every call rather than persisting one across the service's lifetime. This test
    // proves that choice: two consecutive decodes of byte-identical audio through the
    // SAME warm service must produce byte-identical text — if decoder state leaked from
    // the first call into the second, the second call's output would differ from the
    // first (an order-dependent artifact), even though the input audio is unchanged.

    /// Writes a short tone-burst WAV (not pure silence, which Layer 2's AdaptiveVoiceGate
    /// would discard before the decoder is ever reached) to a fresh temp file and returns
    /// its URL. 16kHz mono Float32, matching `IOSTranscriptionService`'s own sample rate.
    private func writeToneBurstWav() throws -> URL {
        let sampleRate = 16000.0
        let duration = 1.0
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        let writer = try RecordingFileWriter(url: url, format: format)
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let channelData = buffer.floatChannelData![0]
        let toneFrequency = 220.0
        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            channelData[frame] = Float(sin(2.0 * Double.pi * toneFrequency * t) * 0.8)
        }
        writer.append(buffer)
        _ = writer.finalize()
        return url
    }

    func testTwoConsecutiveDecodesOnSameServiceAreIndependent() async throws {
        try XCTSkipUnless(
            IOSTranscriptionService.isModelAvailable(),
            "Skipping — Parakeet model not cached."
        )
        guard let service = try? await IOSTranscriptionService.makeForTesting() else {
            throw XCTSkip("FluidAudio init failed.")
        }

        let wavURL1 = try writeToneBurstWav()
        let wavURL2 = try writeToneBurstWav()
        defer {
            try? FileManager.default.removeItem(at: wavURL1)
            try? FileManager.default.removeItem(at: wavURL2)
        }

        // Compare full outcomes (not just the happy path): a synthetic tone-burst may
        // legitimately decode to empty text / throw .noResult on this model — what
        // matters for D-02/Pitfall 5 is that the SAME input produces the SAME outcome
        // on both calls, proving no state leaked from call 1 into call 2.
        let outcome1 = await Self.transcribeOutcome(service: service, wavURL: wavURL1)
        let outcome2 = await Self.transcribeOutcome(service: service, wavURL: wavURL2)

        XCTAssertEqual(
            outcome1, outcome2,
            "Two consecutive decodes of byte-identical audio through the same warm service must produce the same outcome — a divergence would indicate leaked decoder state (D-02/Pitfall 5)"
        )
    }

    private enum TranscribeOutcome: Equatable {
        case text(String)
        case threw(String)
    }

    private static func transcribeOutcome(service: IOSTranscriptionService, wavURL: URL) async -> TranscribeOutcome {
        do {
            let result = try await service.transcribe(wavURL: wavURL)
            return .text(result.text)
        } catch {
            return .threw(String(describing: error))
        }
    }
}
