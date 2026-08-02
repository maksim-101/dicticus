import XCTest
import AVFoundation
@testable import Dicticus

/// Archived-WAV replay harness (quick task 260802-ass).
///
/// Not a regression test — a measurement tool. It replays capture WAVs written by the
/// DEBUG_RECORDER build through the live transcription path and emits one JSON row per
/// file, so ASR behaviour can be compared across recording days with the code held
/// constant.
///
/// Opt-in only. Without `DICTICUS_REPLAY_DIR` set it skips immediately, so a normal
/// `xcodebuild test` run never loads a 1.5 GB model or spends minutes transcribing.
///
///     DICTICUS_REPLAY_DIR="$HOME/Library/Application Support/Dicticus/DebugRecordings" \
///     DICTICUS_REPLAY_OUT=/tmp/replay.jsonl \
///     xcodebuild test -only-testing:DicticusTests/AsrReplayHarnessTests
///
/// The input directory is read strictly read-only; output goes to `DICTICUS_REPLAY_OUT`
/// (defaults to a temp file) and never into the recordings directory itself.
final class AsrReplayHarnessTests: XCTestCase {

    @MainActor
    func testReplayArchivedCaptures() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let replayDir = env["DICTICUS_REPLAY_DIR"] else {
            throw XCTSkip("Set DICTICUS_REPLAY_DIR to run the ASR replay harness.")
        }
        guard TranscriptionService.isWhisperKitAvailable() else {
            throw XCTSkip("WhisperKit model not cached — cannot replay.")
        }
        guard let service = try await TranscriptionService.makeForTesting() else {
            throw XCTSkip("Could not construct TranscriptionService.")
        }

        let dirURL = URL(fileURLWithPath: replayDir)
        let wavs = try FileManager.default
            .contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "wav" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        XCTAssertFalse(wavs.isEmpty, "No WAVs found in \(replayDir)")

        let outPath = env["DICTICUS_REPLAY_OUT"]
            ?? NSTemporaryDirectory().appending("asr-replay.jsonl")
        FileManager.default.createFile(atPath: outPath, contents: nil)
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: outPath))
        defer { try? handle.close() }

        for wav in wavs {
            let name = wav.lastPathComponent
            var row: [String: Any] = ["file": name]
            // Filenames are `capture-YYYY-MM-DDTHH-MM-SS.mmmZ.wav`; the day is the
            // grouping key for the per-day trend.
            if name.count > 18 {
                let start = name.index(name.startIndex, offsetBy: 8)
                let end = name.index(name.startIndex, offsetBy: 18)
                row["day"] = String(name[start..<end])
            }

            guard let (samples, sampleRate) = Self.readWav(wav) else {
                row["error"] = "unreadable"
                Self.write(row, to: handle)
                continue
            }

            row["duration"] = Double(samples.count) / sampleRate
            row["rms"] = Self.rms(samples)
            row["peak"] = samples.map { abs($0) }.max() ?? 0

            do {
                let out = try await service.testTranscribe(
                    samples: samples,
                    inputSampleRate: sampleRate,
                    promptText: env["DICTICUS_REPLAY_PROMPT"]
                )
                row["text"] = out.result.text
                row["language"] = out.result.language
                row["confidence"] = out.result.confidence
                row["avg_logprobs"] = out.avgLogprobs
                row["no_speech_probs"] = out.noSpeechProbs
            } catch {
                // Gate rejections (tooShort / silenceOnly / noResult) are real outcomes
                // of the live path, so they are recorded rather than treated as failures.
                row["error"] = "\(error)"
            }
            Self.write(row, to: handle)
        }

        print("ASR replay harness wrote \(wavs.count) rows to \(outPath)")
    }

    // MARK: - Helpers

    private static func write(_ row: [String: Any], to handle: FileHandle) {
        guard let data = try? JSONSerialization.data(withJSONObject: row) else { return }
        handle.write(data)
        handle.write(Data("\n".utf8))
    }

    private static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return (sum / Float(samples.count)).squareRoot()
    }

    /// Read a WAV into mono Float32 at its native rate. Resampling is deliberately left
    /// to the production path so the replay exercises it too.
    private static func readWav(_ url: URL) -> ([Float], Double)? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              (try? file.read(into: buffer)) != nil,
              let channels = buffer.floatChannelData
        else { return nil }

        let count = Int(buffer.frameLength)
        let channelCount = Int(format.channelCount)
        var samples = [Float](repeating: 0, count: count)
        if channelCount == 1 {
            samples = Array(UnsafeBufferPointer(start: channels[0], count: count))
        } else {
            for frame in 0..<count {
                var acc: Float = 0
                for channel in 0..<channelCount { acc += channels[channel][frame] }
                samples[frame] = acc / Float(channelCount)
            }
        }
        return (samples, format.sampleRate)
    }
}
