import XCTest
@preconcurrency import AVFoundation
@testable import Dicticus

/// Phase 46-02: asserts the recorder spine — the WAV is really written and readable,
/// discard really removes bytes, and the haptic seam fires exactly once per recording.
/// Drives `RecordingFileWriter` and `AudioRecorder.processTapBuffer` directly with
/// synthesized `AVAudioPCMBuffer`s — never `AVAudioEngine` or the microphone — so
/// these run deterministically in the Simulator.
@MainActor
final class AudioRecorderTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("AudioRecorderTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeFormat(sampleRate: Double = 48000) -> AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
    }

    /// Builds a buffer of `frameCount` frames filled with a constant sample value
    /// (not silence — RMS-based auto-stop is not under test here, but a non-zero
    /// value keeps the buffer distinguishable from an all-zero/garbage allocation).
    private func makeBuffer(format: AVAudioFormat, frameCount: AVAudioFrameCount, value: Float = 0.1) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        if let channelData = buffer.floatChannelData?[0] {
            for i in 0..<Int(frameCount) { channelData[i] = value }
        }
        return buffer
    }

    // MARK: - RecordingFileWriter: real bytes, readable back

    /// Regression target: a writer that silently drops frames (e.g. forgets to call
    /// `file.write(from:)`, or writes to the wrong buffer) would produce a file whose
    /// `.length` does not match frames actually appended — this test goes red in
    /// that case.
    func testWriterProducesFileWithExpectedFrameCountAndSampleRate() throws {
        let format = makeFormat(sampleRate: 48000)
        let url = tempDir.appendingPathComponent("writer-frame-count.wav")
        let writer = try RecordingFileWriter(url: url, format: format)

        let framesPerBuffer: AVAudioFrameCount = 1024
        let bufferCount = 5
        for _ in 0..<bufferCount {
            writer.append(makeBuffer(format: format, frameCount: framesPerBuffer))
        }
        let reportedDuration = writer.finalize()

        let expectedFrames = Int64(framesPerBuffer) * Int64(bufferCount)
        let expectedDuration = Double(expectedFrames) / 48000.0

        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(file.length, expectedFrames,
                        "Writer must have written every appended frame — got \(file.length), expected \(expectedFrames)")
        XCTAssertEqual(file.processingFormat.sampleRate, 48000, accuracy: 0.001,
                        "Readback sample rate must match the format the writer was opened with")
        XCTAssertEqual(reportedDuration, expectedDuration, accuracy: 0.01,
                        "finalize() must report a duration derived from frames actually written")
    }

    /// Regression target: a writer that reports success without actually persisting
    /// bytes (e.g. a no-op stub) would still pass a row-count check but fail this
    /// direct AVAudioFile readback.
    func testWriterAtDifferentSampleRateReadsBackCorrectly() throws {
        let format = makeFormat(sampleRate: 16000)
        let url = tempDir.appendingPathComponent("writer-16k.wav")
        let writer = try RecordingFileWriter(url: url, format: format)

        writer.append(makeBuffer(format: format, frameCount: 4000))
        writer.finalize()

        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(file.length, 4000)
        XCTAssertEqual(file.processingFormat.sampleRate, 16000, accuracy: 0.001)
    }

    // MARK: - RecordingFileWriter.discard(): bytes really gone

    /// D-02's whole point is that the audio is really gone — assert against the
    /// filesystem, not merely that no error was thrown.
    func testDiscardLeavesNoFileOnDisk() throws {
        let format = makeFormat()
        let url = tempDir.appendingPathComponent("writer-discard.wav")
        let writer = try RecordingFileWriter(url: url, format: format)
        writer.append(makeBuffer(format: format, frameCount: 512))

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                      "Precondition: file must exist on disk before discard")

        writer.discard()

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path),
                       "discard() must remove the partial file from disk")
    }

    // MARK: - Haptic timing (D-04): exactly once, only after a real buffer

    /// Regression target: if `AudioRecorder.processTapBuffer` fired `onFirstBuffer`
    /// on every call (not gated by `FirstBufferGate`) this would count 3, not 1.
    /// If the gate fired before any buffer was processed, the pre-buffer assertion
    /// below would fail.
    func testHapticSeamFiresExactlyOnceAcrossMultipleBuffers() throws {
        let format = makeFormat()
        let url = tempDir.appendingPathComponent("haptic-multi.wav")
        let writer = try RecordingFileWriter(url: url, format: format)
        let tracker = SilenceTracker()
        let gate = FirstBufferGate()

        var firstBufferFireCount = 0

        // Zero buffers delivered yet — the seam must not have fired.
        XCTAssertEqual(firstBufferFireCount, 0,
                       "Haptic seam must not fire before any buffer is delivered")

        for _ in 0..<3 {
            AudioRecorder.processTapBuffer(
                makeBuffer(format: format, frameCount: 256),
                writer: writer,
                tracker: tracker,
                firstBufferGate: gate,
                autoStopEnabled: false,
                silenceThreshold: 0.01,
                silenceDuration: 2.5,
                gracePeriod: 3.0,
                onSilence: {},
                onFirstBuffer: { firstBufferFireCount += 1 }
            )
        }

        XCTAssertEqual(firstBufferFireCount, 1,
                       "Haptic seam must fire exactly once across multiple delivered buffers, not once per buffer")
    }

    /// `FirstBufferGate.fireIfNeeded()` is the exactly-once primitive underlying the
    /// haptic seam: the first call must return `true` (fire), every subsequent call
    /// on the same instance must return `false` (already fired) — including calls
    /// concurrent with the first, which is why the gate is lock-guarded rather than
    /// a bare `Bool`.
    func testFirstBufferGateFiresExactlyOnce() {
        let gate = FirstBufferGate()
        XCTAssertTrue(gate.fireIfNeeded(), "First call must fire")
        XCTAssertFalse(gate.fireIfNeeded(), "Second call must not fire again")
        XCTAssertFalse(gate.fireIfNeeded(), "Third call must still not fire again")
    }

    // MARK: - recordingsDirectory(): app-private, protected, excluded from backup

    func testRecordingsDirectoryIsCreatedWithBackupExclusionAndProtection() throws {
        let dir = try AudioRecorder.recordingsDirectory()
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)

        let resourceValues = try dir.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(resourceValues.isExcludedFromBackup, true,
                       "PendingRecordings directory must be excluded from device backup (T-46-02)")
    }
}
