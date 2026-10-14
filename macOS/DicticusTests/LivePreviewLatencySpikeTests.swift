import XCTest
import AVFoundation
@testable import Dicticus

/// Live-preview replay harness (Phase 51, spike 018).
///
/// A measurement tool in the style of `AsrReplayHarnessTests`: opt-in, model required,
/// skips without `DICTICUS_REPLAY_DIR`. It drives the shipping `LivePreviewDecoder`,
/// `LivePreviewSession` and the shared release path, and records counts and timings
/// only. No preview or final text is ever written to the output.
///
///     DICTICUS_REPLAY_DIR="$HOME/Library/Application Support/Dicticus/ReplayCorpus" \
///     TEST_RUNNER_DICTICUS_REPLAY_DIR="$DICTICUS_REPLAY_DIR" \
///     nice -n 10 xcodebuild test -only-testing:DicticusTests/LivePreviewLatencySpikeTests
final class LivePreviewLatencySpikeTests: XCTestCase {

    /// Live capture runs at the hardware rate (48 kHz in the discard logs).
    private static let captureRate: Double = 48000
    private static let smokeSeconds: Double = 8
    private static let chunkFrames = 4096

    private final class Recorder: @unchecked Sendable {
        var publishedCounts: [Int] = []
    }

    @MainActor
    func testSmoke_previewThenRelease() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let replayDir = env["DICTICUS_REPLAY_DIR"] else {
            throw XCTSkip("Set DICTICUS_REPLAY_DIR to run the live-preview smoke test.")
        }
        guard TranscriptionService.isWhisperKitAvailable() else {
            throw XCTSkip("WhisperKit model not cached — cannot decode.")
        }
        guard let service = try await TranscriptionService.makeForTesting() else {
            throw XCTSkip("Could not construct TranscriptionService.")
        }

        let wavs = try FileManager.default
            .contentsOfDirectory(at: URL(fileURLWithPath: replayDir), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "wav" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var picked: (name: String, samples: [Float], rate: Double)?
        for wav in wavs {
            guard let (samples, rate) = AsrReplayHarnessTests.readWav(wav),
                  Double(samples.count) / rate >= Self.smokeSeconds else { continue }
            picked = (wav.lastPathComponent, samples, rate)
            break
        }
        guard let clip = picked else {
            throw XCTSkip("No capture of at least \(Int(Self.smokeSeconds)) s in \(replayDir).")
        }

        let head = Array(clip.samples.prefix(Int(Self.smokeSeconds * clip.rate)))
        let live = abs(clip.rate - Self.captureRate) > 1
            ? TranscriptionService.resampleAudio(head, from: clip.rate, to: Self.captureRate)
            : head

        let buffer = AudioSampleBuffer()
        let decoder = service.testMakeLivePreviewDecoder(buffer: buffer, inputSampleRate: Self.captureRate)
        let recorder = Recorder()
        let session = LivePreviewSession(
            cadence: LivePreviewSession.productionCadence,
            isActive: { true },
            decode: { await decoder.decodeTail() },
            publish: { recorder.publishedCounts.append($0.count) }
        )
        session.start()

        let chunkDelay = Duration.seconds(Double(Self.chunkFrames) / Self.captureRate)
        var offset = 0
        while offset < live.count {
            let end = min(offset + Self.chunkFrames, live.count)
            buffer.append(Array(live[offset..<end]))
            offset = end
            try await Task.sleep(for: chunkDelay)
        }

        let clock = ContinuousClock()
        let releasedAt = clock.now
        let out = try await service.testReleaseAndTranscribe(
            previewSession: session,
            samples: buffer.drain(),
            inputSampleRate: Self.captureRate
        )
        let releaseToFinal = clock.now - releasedAt

        let stats = try XCTUnwrap(out.stats)
        XCTAssertGreaterThanOrEqual(recorder.publishedCounts.count, 1, "no preview was published")
        XCTAssertTrue(recorder.publishedCounts.allSatisfy { $0 > 0 }, "an empty preview was published")
        XCTAssertGreaterThanOrEqual(stats.ticks, 1, "the session never ticked")
        XCTAssertFalse(out.result.text.isEmpty, "the final decode returned no text")

        let row: [String: Any] = [
            "file": clip.name,
            "duration": Double(live.count) / Self.captureRate,
            "ticks": stats.ticks,
            "published": stats.published,
            "published_chars": recorder.publishedCounts,
            "cancelled_in_flight": stats.cancelledInFlight,
            "drain_ms": Self.milliseconds(stats.drainDuration),
            "release_to_final_ms": Self.milliseconds(releaseToFinal),
            "decode_ms": stats.decodeDurations.map(Self.milliseconds),
            "final_chars": out.result.text.count
        ]
        let outPath = env["DICTICUS_REPLAY_OUT"]
            ?? NSTemporaryDirectory().appending("live-preview-smoke.jsonl")
        let data = try JSONSerialization.data(withJSONObject: row) + Data("\n".utf8)
        FileManager.default.createFile(atPath: outPath, contents: data)
        print("Live-preview smoke wrote 1 row to \(outPath)")
    }

    private static func milliseconds(_ d: Duration) -> Double {
        Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }
}
