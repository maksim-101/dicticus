import Foundation
import WhisperKit

/// Interim decode for the live transcript overlay (Phase 51, D-01..D-05, D-19).
///
/// Reads a non-destructive tail snapshot of the capture buffer, resamples it off the
/// main actor, decodes it on the service's WhisperKit instance and runs the text-only
/// phantom filters and the dictionary. The result feeds the preview panel and nothing
/// else; the pasted text always comes from the end-of-recording decode.
///
/// The energy gates and the short-clip rules of the final path are deliberately not
/// applied here (D-03), and this type writes no diagnostic records.
@MainActor
final class LivePreviewDecoder {

    /// Newest audio decoded per tick. The pane shows 3-4 lines, about 10-12 s of speech.
    static let tailSeconds: Double = 15

    /// WhisperKit decodes nothing below about 1 s of audio (its window padding).
    static let minimumPreviewSeconds: Double = 1.2

    nonisolated static let targetSampleRate: Double = 16000

    /// The final path's decode options, plus no temperature fallback: a fallback
    /// re-decode would multiply the time the release has to wait for the drain.
    static let decodeOptions = DecodingOptions(
        language: nil,
        temperatureFallbackCount: 0,
        detectLanguage: true,
        withoutTimestamps: true,
        suppressBlank: true,
        compressionRatioThreshold: 2.4,
        logProbThreshold: -1.0,
        noSpeechThreshold: 0.6,
        chunkingStrategy: .vad
    )

    struct Timing: Sendable {
        var snapshotMs: Double
        var resampleMs: Double
        var decodeMs: Double
        var filterMs: Double
        var tokenCount: Int
    }

    private let whisperKit: WhisperKit
    private let buffer: AudioSampleBuffer
    private let inputSampleRate: Double
    private let dictionary: @MainActor (String) -> String
    private var lastDecodedCount = -1

    private(set) var lastTiming: Timing?

    init(
        whisperKit: WhisperKit,
        buffer: AudioSampleBuffer,
        inputSampleRate: Double,
        dictionary: @escaping @MainActor (String) -> String = { DictionaryService.shared.apply(to: $0) }
    ) {
        self.whisperKit = whisperKit
        self.buffer = buffer
        self.inputSampleRate = inputSampleRate
        self.dictionary = dictionary
    }

    /// The one WhisperKit call of this file. Takes 16 kHz samples and explicit options
    /// so the latency sweep can time both option sets through the same code.
    func decodeResampled(_ samples16k: [Float], options: DecodingOptions) async throws -> [TranscriptionResult] {
        try await whisperKit.transcribe(audioArray: samples16k, decodeOptions: options)
    }

    /// One preview tick. Returns nil when there is no new audio, too little audio, a
    /// decode error, a cancellation, or when the filters reject the text.
    func decodeTail() async -> String? {
        let clock = ContinuousClock()
        let t0 = clock.now

        let currentCount = buffer.count
        guard currentCount != lastDecodedCount else { return nil }
        let rate = inputSampleRate
        let tail = buffer.snapshotTail(maxSamples: Int(Self.tailSeconds * rate))
        let t1 = clock.now

        guard Double(tail.count) / rate >= Self.minimumPreviewSeconds else { return nil }
        lastDecodedCount = currentCount

        let samples16k: [Float]
        if abs(rate - Self.targetSampleRate) > 1.0 {
            samples16k = await Task.detached(priority: .userInitiated) {
                TranscriptionService.resampleAudio(tail, from: rate, to: Self.targetSampleRate)
            }.value
        } else {
            samples16k = tail
        }
        let t2 = clock.now

        let results: [TranscriptionResult]
        do {
            results = try await decodeResampled(samples16k, options: Self.decodeOptions)
        } catch {
            return nil
        }
        let t3 = clock.now

        // A cancelled decode can return normally with partial text.
        guard !Task.isCancelled else { return nil }

        let text = Self.previewText(
            from: results.map { (text: $0.text, language: $0.language) },
            dictionary: dictionary
        )
        let t4 = clock.now

        lastTiming = Timing(
            snapshotMs: Self.milliseconds(t1 - t0),
            resampleMs: Self.milliseconds(t2 - t1),
            decodeMs: Self.milliseconds(t3 - t2),
            filterMs: Self.milliseconds(t4 - t3),
            tokenCount: results.reduce(0) { $0 + $1.segments.reduce(0) { $0 + $1.tokens.count } }
        )
        return text
    }

    /// Text-only filter chain. Phantom chunks and whole-utterance boilerplate are
    /// dropped (D-03), foreign script is dropped (D-19), and the dictionary runs last,
    /// only on text that survived (D-05).
    static func previewText(
        from chunks: [(text: String, language: String)],
        dictionary: @MainActor (String) -> String
    ) -> String? {
        let drops = BoilerplateHallucination.chunkDropReasons(chunks)
        let joined = zip(chunks, drops)
            .filter { $0.1 == nil }
            .map(\.0.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !joined.isEmpty,
              BoilerplateHallucination.match(joined) == nil,
              !TranscriptionService.containsNonLatinScript(joined)
        else { return nil }
        return dictionary(joined)
    }

    private static func milliseconds(_ d: Duration) -> Double {
        Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }
}
