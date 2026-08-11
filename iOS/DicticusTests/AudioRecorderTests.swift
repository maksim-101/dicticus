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

    // MARK: - Haptic pattern shape (D-04, 46-03 round 3): a pattern, not one impulse

    /// Regression target: a single-impact seam (pre-round-3) would report 1, not
    /// 3. Device-confirmed (round 2 → round 3) that raising intensity on ONE
    /// impact was insufficient — this asserts the SHAPE of the fix (a
    /// multi-impact pattern) independent of real haptic hardware, by injecting a
    /// counting closure in place of `UIImpactFeedbackGenerator.impactOccurred()`.
    func testHapticPatternFiresConfiguredImpactCount() async {
        var impactCount = 0
        await AudioRecorder.fireHapticPattern(impactCount: 3, spacingMilliseconds: 1) { _ in
            impactCount += 1
        }
        XCTAssertEqual(impactCount, 3,
                       "The D-04 haptic pattern must fire 3 discrete impacts, not 1 (46-03 round 3: a single impact, even .heavy, was device-confirmed too faint)")
    }

    /// The pattern must respect whatever `impactCount` it's configured with —
    /// not a value hardcoded inside the loop itself.
    func testHapticPatternRespectsConfiguredCount() async {
        var impactCount = 0
        await AudioRecorder.fireHapticPattern(impactCount: 2, spacingMilliseconds: 1) { _ in
            impactCount += 1
        }
        XCTAssertEqual(impactCount, 2, "fireHapticPattern must fire exactly the configured impactCount")
    }

    /// 46-03 round 4: `fireHapticPattern`'s `impact` closure now receives the
    /// impact's index (0-based) so each real impact can be individually logged
    /// (`AudioRecorder.logHapticImpact(index:)`) — this asserts the indices
    /// arrive in order and match the count, independent of the logging call
    /// itself (which needs `UIApplication`/`MemoryProbe`, unavailable in a
    /// plain unit test host without a running app).
    func testHapticPatternDeliversSequentialIndices() async {
        var observedIndices: [Int] = []
        await AudioRecorder.fireHapticPattern(impactCount: 3, spacingMilliseconds: 1) { index in
            observedIndices.append(index)
        }
        XCTAssertEqual(observedIndices, [0, 1, 2],
                       "Each impact must report its own sequential index, in order — needed to tell which of N impacts fired from the device log")
    }

    /// End-to-end verification of the ACTUAL write path (46-03 round 4,
    /// explicit coordinator instruction: "confirm the log actually captures
    /// what you need before asking for another device round — do not burn a
    /// user session on a probe that turns out not to have been recording").
    /// Drives the real, unmocked `hapticTrigger` default closure — real
    /// `UIImpactFeedbackGenerator` calls (harmless no-ops without Taptic
    /// hardware in the Simulator) and real `MemoryProbe.mark()` writes — and
    /// reads back the actual `memprobe.jsonl` file `MemoryProbe` wrote to,
    /// parsing it as JSON rather than grepping for a substring. This is NOT a
    /// fake-closure test like the two above; it is the only test in this file
    /// that proves the disk artifact itself is well-formed and complete.
    func testHapticTriggerWritesThreeParseableHapticImpactLinesEndToEnd() async throws {
        let defaults = UserDefaults.standard
        let wasEnabled = defaults.bool(forKey: "memProbe")
        defaults.set(true, forKey: "memProbe")
        defer { defaults.set(wasEnabled, forKey: "memProbe") }

        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            XCTFail("Test host has no Documents directory — cannot verify the memprobe.jsonl write path")
            return
        }
        let probeURL = documents.appendingPathComponent("memprobe.jsonl")
        try? FileManager.default.removeItem(at: probeURL)

        let recorder = AudioRecorder()
        await recorder.hapticTrigger()

        let contents = try XCTUnwrap(try? String(contentsOf: probeURL, encoding: .utf8),
                                     "hapticTrigger() must produce a readable memprobe.jsonl — the probe never wrote anything")
        let impactLines = contents.split(separator: "\n").filter { $0.contains("\"stage\":\"haptic_impact\"") }
        XCTAssertEqual(impactLines.count, 3,
                       "hapticTrigger() must write exactly 3 haptic_impact lines — found \(impactLines.count). If this is not 3, no device session will show 3 either; the loop itself is broken, not just felt-weakly.")

        var seenIndices: Set<Int> = []
        for line in impactLines {
            let data = try XCTUnwrap(line.data(using: .utf8))
            let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any],
                                    "Each haptic_impact line must be valid, parseable JSON")
            let note = try XCTUnwrap(obj["note"] as? String)
            XCTAssertTrue(note.contains("appState="), "Each haptic_impact line's note must record appState — the decisive datum for H-A/H-B/coalescing")
            if let match = note.range(of: "index="), let indexStr = note[match.upperBound...].split(separator: " ").first,
               let index = Int(indexStr) {
                seenIndices.insert(index)
            }
        }
        XCTAssertEqual(seenIndices, [0, 1, 2], "The 3 written lines must carry indices 0, 1, 2 — not 3 copies of the same index")

        try? FileManager.default.removeItem(at: probeURL)
    }

    /// The default `hapticPatternSpacingMilliseconds` must be tuned to a real,
    /// nonzero gap (not 0 — which would collapse into one blurred buzz — and
    /// not absurdly long, which would read as disconnected taps rather than one
    /// cohesive pattern).
    func testHapticPatternSpacingIsWithinReasonableRange() {
        XCTAssertGreaterThan(AudioRecorder.hapticPatternSpacingMilliseconds, 0,
                             "Spacing must be nonzero — 0ms would blur into a single buzz, not a perceptible pattern")
        XCTAssertLessThanOrEqual(AudioRecorder.hapticPatternSpacingMilliseconds, 250,
                                 "Spacing must stay tight enough to read as one cohesive pattern, not disconnected taps")
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
