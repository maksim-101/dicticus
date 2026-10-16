import XCTest
import WhisperKit
@testable import Dicticus

/// Regression net for the preview voice gate (Phase 51-11): the decision whether the frames
/// added since the last decode hold voice, and the per-tick bookkeeping that turns a run of
/// silent ticks into one pause signal. Energies only; no model and no transcript text.
@MainActor
final class LivePreviewGateTests: XCTestCase {

    private func run(_ value: Float, _ count: Int) -> [Float] {
        Array(repeating: value, count: count)
    }

    // MARK: - hasNewVoice

    func testSilenceAfterSpeechIsNotNewVoice() {
        let energies = run(0.002, 10) + run(0.05, 10) + run(0.002, 5)
        XCTAssertFalse(LivePreviewVoiceGate.hasNewVoice(energies: energies, sinceFrame: 20))
    }

    func testSpeechInTheNewFramesIsNewVoice() {
        let energies = run(0.002, 10) + run(0.05, 10) + run(0.002, 5)
        XCTAssertTrue(LivePreviewVoiceGate.hasNewVoice(energies: energies, sinceFrame: 10))
    }

    func testContinuousSpeechAfterAQuietStartIsNewVoice() {
        // A threshold computed from the last five frames alone would take their own level
        // for the noise floor (0.04 x 3.5 = 0.14, above every frame) and call this silence.
        let speech = (0..<40).map { Float(0.04 + 0.04 * Double($0 % 5) / 4) }
        let energies = run(0.002, 10) + speech
        XCTAssertTrue(LivePreviewVoiceGate.hasNewVoice(energies: energies, sinceFrame: energies.count - 5))
    }

    func testLowGainSpeechAboveTheMeasuredFloorIsNewVoice() {
        let energies = run(0.001, 10) + run(0.009, 6)
        XCTAssertTrue(LivePreviewVoiceGate.hasNewVoice(energies: energies, sinceFrame: 10))
    }

    func testSteadyFanNoiseIsNotVoice() {
        let energies = (0..<30).map { Float(0.010 + 0.002 * Double($0 % 3) / 2) }
        XCTAssertFalse(LivePreviewVoiceGate.hasNewVoice(energies: energies, sinceFrame: 0))
        XCTAssertFalse(LivePreviewVoiceGate.hasNewVoice(energies: energies, sinceFrame: 20))
    }

    func testNoNewFramesIsNotVoice() {
        let energies = run(0.002, 10) + run(0.05, 10)
        XCTAssertFalse(LivePreviewVoiceGate.hasNewVoice(energies: energies, sinceFrame: energies.count))
        XCTAssertFalse(LivePreviewVoiceGate.hasNewVoice(energies: [], sinceFrame: 0))
    }

    // MARK: - per-tick bookkeeping

    private let voiced = Array(repeating: Float(0.05), count: 5)
    private let silent = Array(repeating: Float(0.002), count: 5)

    private func firstTick(_ gate: inout LivePreviewVoiceGate) {
        // The press-time quiet that sets the floor.
        _ = gate.step(newFrameEnergies: Array(repeating: 0.002, count: 10))
    }

    func testPauseSignalFiresOnlyOnTheFirstSilentTickAfterVoice() {
        var gate = LivePreviewVoiceGate(inputSampleRate: 16000)
        firstTick(&gate)
        let ticks = [voiced, voiced, silent, silent, voiced, silent]
        let outcomes = ticks.map { gate.step(newFrameEnergies: $0) }

        XCTAssertEqual(outcomes, [
            .decode, .decode, .skip(signalPause: true), .skip(signalPause: false), .decode, .skip(signalPause: true)
        ])
    }

    func testSilenceBeforeAnyVoiceNeverSignalsAPause() {
        var gate = LivePreviewVoiceGate(inputSampleRate: 16000)
        let outcomes = (0..<3).map { _ in gate.step(newFrameEnergies: silent) }

        XCTAssertEqual(outcomes, Array(repeating: .skip(signalPause: false), count: 3))
    }

    func testAVoicedTickMarksEveryFrameDecodedAndASkippedTickMarksNone() {
        var gate = LivePreviewVoiceGate(inputSampleRate: 16000)
        firstTick(&gate)
        XCTAssertEqual(gate.decodedFrameCount, 0, "a skipped tick marked frames as decoded")

        _ = gate.step(newFrameEnergies: voiced)
        XCTAssertEqual(gate.decodedFrameCount, 15)
        XCTAssertEqual(gate.energies.count, 15)

        _ = gate.step(newFrameEnergies: silent)
        XCTAssertEqual(gate.decodedFrameCount, 15, "a skipped tick marked frames as decoded")
        XCTAssertEqual(gate.energies.count, 20)
    }

    func testSpeechThatStartsRightAtTheTickAfterSilenceIsDecodedFromTheOldMark() {
        var gate = LivePreviewVoiceGate(inputSampleRate: 16000)
        firstTick(&gate)
        _ = gate.step(newFrameEnergies: voiced)
        _ = gate.step(newFrameEnergies: silent)
        _ = gate.step(newFrameEnergies: silent)

        XCTAssertEqual(gate.step(newFrameEnergies: voiced), .decode)
    }

    // MARK: - framing of raw samples

    func testOnlyCompleteHundredMillisecondFramesAreConsumed() {
        var gate = LivePreviewVoiceGate(inputSampleRate: 16000)
        // 1600 samples per frame. 2.5 frames: two are consumed, the half frame waits.
        let outcome = gate.step(samples: Array(repeating: 0.002, count: 1600) + Array(repeating: 0.05, count: 2400))

        XCTAssertEqual(gate.framedSamples, 3200)
        XCTAssertEqual(gate.energies.count, 2)
        XCTAssertEqual(outcome, .decode)

        _ = gate.step(samples: Array(repeating: 0.05, count: 800))
        XCTAssertEqual(gate.framedSamples, 3200, "a partial frame was consumed")
        XCTAssertEqual(gate.energies.count, 2)

        // The snapshot starts at framedSamples, so it holds the waiting half frame again plus new audio.
        _ = gate.step(samples: Array(repeating: 0.05, count: 800 + 2400))
        XCTAssertEqual(gate.framedSamples, 6400)
        XCTAssertEqual(gate.energies.count, 4)
    }

    func testFrameLengthFollowsTheInputRate() {
        var gate = LivePreviewVoiceGate(inputSampleRate: 48000)
        _ = gate.step(samples: Array(repeating: 0.05, count: 4800))
        XCTAssertEqual(gate.energies.count, 1)
        XCTAssertEqual(gate.framedSamples, 4800)
    }

    // MARK: - decoder rules around the model (no WhisperKit: the decode is a closure)

    private final class Calls: @unchecked Sendable {
        var decodes = 0
        var silences = 0
    }

    private let rate = 16000.0

    private func audio(_ value: Float, seconds: Double) -> [Float] {
        Array(repeating: value, count: Int(seconds * rate))
    }

    private func chunk(_ text: String, noSpeechProb: Float = 0) -> TranscriptionResult {
        TranscriptionResult(
            text: text,
            segments: [TranscriptionSegment(text: text, noSpeechProb: noSpeechProb)],
            language: "en",
            timings: TranscriptionTimings())
    }

    private func makeDecoder(
        buffer: AudioSampleBuffer, calls: Calls, results: [TranscriptionResult]
    ) -> LivePreviewDecoder {
        LivePreviewDecoder(
            transcribe: { _, _ in calls.decodes += 1; return results },
            buffer: buffer,
            inputSampleRate: rate,
            dictionary: { $0 },
            onSilence: { calls.silences += 1 })
    }

    func testATickWithoutVoiceNeverReachesTheModel() async {
        let buffer = AudioSampleBuffer()
        buffer.append(audio(0.002, seconds: 1.5))
        let calls = Calls()
        let decoder = makeDecoder(buffer: buffer, calls: calls, results: [chunk("never decoded")])

        let text = await decoder.decodeTail()

        XCTAssertNil(text)
        XCTAssertEqual(calls.decodes, 0, "a tick with no voice ran the model")
        XCTAssertEqual(decoder.skippedNoVoice, 1)
        XCTAssertFalse(decoder.lastTickRanModel)
        XCTAssertEqual(calls.silences, 0, "silence before any voice is not a pause")
    }

    func testTheFirstSilentTickAfterVoiceSignalsOnePauseAndLaterVoiceDecodesAgain() async {
        let buffer = AudioSampleBuffer()
        buffer.append(audio(0.002, seconds: 0.8) + audio(0.05, seconds: 0.6))
        let calls = Calls()
        let decoder = makeDecoder(buffer: buffer, calls: calls, results: [chunk("hello there friend")])

        let first = await decoder.decodeTail()
        XCTAssertEqual(first, "hello there friend")
        XCTAssertEqual(calls.decodes, 1)
        XCTAssertTrue(decoder.lastTickRanModel)
        XCTAssertEqual(calls.silences, 0)

        buffer.append(audio(0.002, seconds: 0.3))
        let pause = await decoder.decodeTail()
        XCTAssertNil(pause)
        XCTAssertEqual(calls.decodes, 1, "the silent tick decoded")
        XCTAssertEqual(calls.silences, 1, "the first silent tick after voice must signal the pause")

        buffer.append(audio(0.002, seconds: 0.3))
        _ = await decoder.decodeTail()
        XCTAssertEqual(calls.silences, 1, "the pause is signalled once")
        XCTAssertEqual(decoder.skippedNoVoice, 2)

        buffer.append(audio(0.05, seconds: 0.3))
        let resumed = await decoder.decodeTail()
        XCTAssertNotNil(resumed)
        XCTAssertEqual(calls.decodes, 2)
    }

    func testThePreviewKeepsTextThatTheFinalPathsClipRulesWouldDiscard() async {
        // The final path drops a lone "you" from a clip under 1.5 s, and a decode whose segments
        // all carry a high no-speech probability. The preview applies neither (D-03).
        let clipSeconds = 1.3
        XCTAssertNotNil(BoilerplateHallucination.matchShortStock("you", durationSeconds: Float(clipSeconds), voiceDetected: true))
        XCTAssertTrue(NoSpeechDiscard.looksLikeSilence(noSpeechProbs: [0.99]))

        let buffer = AudioSampleBuffer()
        buffer.append(audio(0.002, seconds: 0.6) + audio(0.05, seconds: 0.7))
        let calls = Calls()
        let decoder = makeDecoder(buffer: buffer, calls: calls, results: [chunk("you", noSpeechProb: 0.99)])

        let text = await decoder.decodeTail()

        XCTAssertEqual(text, "you")
        XCTAssertEqual(calls.decodes, 1)
    }

    func testTooLittleAudioIsNotConsumedByTheGate() async {
        let buffer = AudioSampleBuffer()
        buffer.append(audio(0.002, seconds: 0.3) + audio(0.05, seconds: 0.4))
        let calls = Calls()
        let decoder = makeDecoder(buffer: buffer, calls: calls, results: [chunk("early")])

        let early = await decoder.decodeTail()
        XCTAssertNil(early)
        XCTAssertEqual(decoder.skippedNoVoice, 0, "a short opening word must not be consumed without a decode")

        buffer.append(audio(0.05, seconds: 0.6))
        let later = await decoder.decodeTail()
        XCTAssertEqual(later, "early")
    }
}
