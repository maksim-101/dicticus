#if DEBUG_RECORDER
import XCTest
import AVFoundation
@testable import Dicticus

/// Quick task 261016-nx0: hold capture and flag write. Temp directory only, invented text only.
@MainActor
final class PreviewFlagRecorderTests: XCTestCase {

    private static let schemaKeys: Set<String> = [
        "schema", "flagged_at", "hold_started_at", "overlay_seq", "bundle_id", "wav", "sample_rate",
        "n_samples", "input_sample_rate", "release_ms", "events", "final_text", "final_language",
        "final_text_dictionary", "pasted_text", "git_commit", "app_version"
    ]

    private func makeRecorder() throws -> (PreviewFlagRecorder, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PreviewFlagRecorderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return (PreviewFlagRecorder(directoryURL: dir), dir)
    }

    private func sine(seconds: Double, rate: Double) -> [Float] {
        let n = Int(seconds * rate)
        return (0..<n).map { Float(0.1 * sin(2 * Double.pi * 440 * Double($0) / rate)) }
    }

    private func files(_ dir: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
    }

    private func json(_ dir: URL, stem: String) throws -> [String: Any] {
        let data = try Data(contentsOf: dir.appendingPathComponent(stem + ".json"))
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testFlagWritesReplayableWavAndTimeline() async throws {
        let (rec, dir) = try makeRecorder()
        rec.beginHold(seq: 7, bundleID: "com.example.editor")
        rec.notePublish(seq: 7, text: "The quarterly report", settled: "", tentative: "The quarterly report")
        rec.notePublish(seq: 7, text: "The quarterly report is ready", settled: "The quarterly", tentative: "report is ready")
        rec.noteSettle(seq: 7, settled: "The quarterly report is ready", tentative: "")
        rec.notePublish(seq: 7, text: "The quarterly report is ready for review", settled: "The quarterly report is ready", tentative: "for review")
        rec.notePublish(seq: 7, text: "The quarterly report is ready for review today", settled: "The quarterly report is ready", tentative: "for review today")
        rec.noteRelease(seq: 7)
        let input = sine(seconds: 1.0, rate: 48_000)
        rec.noteSamples(input, inputSampleRate: 48_000)
        rec.noteFinal(text: "The quarterly report is ready for review today.", language: "en")
        rec.notePasted(seq: 7, text: "The quarterly report is ready for review today.")
        XCTAssertTrue(rec.canFlag)

        let outcome = await rec.flag()
        guard case .written(let stem) = outcome else { return XCTFail("expected .written, got \(outcome)") }
        XCTAssertNotNil(stem.range(of: "^flag-[0-9]{8}T[0-9]{6}Z$", options: .regularExpression))
        XCTAssertEqual(files(dir), [stem + ".json", stem + ".wav"])
        XCTAssertFalse(rec.canFlag)

        let j = try json(dir, stem: stem)
        XCTAssertEqual(Set(j.keys), Self.schemaKeys)
        XCTAssertEqual(j["wav"] as? String, stem + ".wav")
        XCTAssertEqual(j["overlay_seq"] as? Int, 7)
        XCTAssertEqual(j["bundle_id"] as? String, "com.example.editor")
        XCTAssertEqual(j["input_sample_rate"] as? Double, 48_000)
        XCTAssertEqual(j["sample_rate"] as? Int, 16_000)
        let events = try XCTUnwrap(j["events"] as? [[String: Any]])
        XCTAssertEqual(events.map { $0["kind"] as? String }, ["publish", "publish", "settle", "publish", "publish"])
        XCTAssertEqual(events[1]["text"] as? String, "The quarterly report is ready")
        XCTAssertEqual(events[1]["settled"] as? String, "The quarterly")
        XCTAssertEqual(events[1]["tentative"] as? String, "report is ready")
        XCTAssertEqual(events[2]["settled"] as? String, "The quarterly report is ready")
        XCTAssertEqual(events[2]["tentative"] as? String, "")
        XCTAssertNil(events[2]["text"])
        let offsets = events.compactMap { $0["offset_ms"] as? Double }
        XCTAssertEqual(offsets.count, 5)
        XCTAssertEqual(offsets, offsets.sorted())
        let release = try XCTUnwrap(j["release_ms"] as? Double)
        XCTAssertTrue(offsets.allSatisfy { $0 <= release })
        XCTAssertEqual(j["final_text"] as? String, "The quarterly report is ready for review today.")
        XCTAssertEqual(j["final_language"] as? String, "en")
        XCTAssertEqual(j["pasted_text"] as? String, "The quarterly report is ready for review today.")
        XCTAssertTrue(j["final_text_dictionary"] is String)

        let expected = TranscriptionService.resampleAudio(input, from: 48_000, to: 16_000)
        let wav = try XCTUnwrap(AsrReplayHarnessTests.readWav(dir.appendingPathComponent(stem + ".wav")))
        XCTAssertEqual(wav.1, 16_000)
        XCTAssertEqual(wav.0.count, j["n_samples"] as? Int)
        XCTAssertEqual(wav.0.count, expected.count)
        XCTAssertEqual(Double(expected.count), 16_000, accuracy: 160)
        var maxDiff: Float = 0
        for (a, b) in zip(wav.0, expected) { maxDiff = max(maxDiff, abs(a - b)) }
        XCTAssertLessThanOrEqual(maxDiff, 1e-6, "max abs diff \(maxDiff)")
    }

    func testNothingToFlagWritesNothing() async throws {
        let (rec, dir) = try makeRecorder()
        let first = await rec.flag()
        XCTAssertEqual(first, .noHold)
        XCTAssertFalse(rec.canFlag)
        XCTAssertTrue(files(dir).filter { $0.hasPrefix("flag-") }.isEmpty)

        rec.beginHold(seq: 1, bundleID: nil)
        rec.notePublish(seq: 1, text: "Hello there", settled: "", tentative: "Hello there")
        rec.noteRelease(seq: 1)
        let second = await rec.flag()
        XCTAssertEqual(second, .noHold)
        XCTAssertTrue(files(dir).filter { $0.hasPrefix("flag-") }.isEmpty)

        rec.noteSamples([], inputSampleRate: 48_000)
        XCTAssertFalse(rec.canFlag)
    }

    func testNotesOutsideTheCurrentHoldAreIgnored() async throws {
        let (rec, dir) = try makeRecorder()
        rec.beginHold(seq: 1, bundleID: "com.example.one")
        rec.notePublish(seq: 1, text: "First hold", settled: "", tentative: "First hold")
        rec.noteRelease(seq: 1)
        rec.noteSamples(sine(seconds: 0.5, rate: 48_000), inputSampleRate: 48_000)
        rec.noteFinal(text: "First hold.", language: "en")

        rec.beginHold(seq: 2, bundleID: "com.example.two")
        XCTAssertFalse(rec.canFlag)
        rec.notePasted(seq: 1, text: "stale paste")
        rec.notePublish(seq: 1, text: "stale publish", settled: "", tentative: "stale publish")
        rec.noteSamples(sine(seconds: 0.5, rate: 48_000), inputSampleRate: 48_000)
        XCTAssertFalse(rec.canFlag, "samples before release must be ignored")

        rec.notePublish(seq: 2, text: "Second hold", settled: "", tentative: "Second hold")
        rec.noteRelease(seq: 2)
        rec.noteRelease(seq: 2)
        rec.notePublish(seq: 2, text: "late publish", settled: "", tentative: "late publish")
        let input = sine(seconds: 0.5, rate: 44_100)
        rec.noteSamples(input, inputSampleRate: 44_100)

        let outcome = await rec.flag()
        guard case .written(let stem) = outcome else { return XCTFail("expected .written, got \(outcome)") }
        let j = try json(dir, stem: stem)
        XCTAssertEqual(j["overlay_seq"] as? Int, 2)
        let events = try XCTUnwrap(j["events"] as? [[String: Any]])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?["text"] as? String, "Second hold")
        XCTAssertTrue(j["pasted_text"] is NSNull)
        XCTAssertTrue(j["final_text"] is NSNull)
        XCTAssertEqual(j["input_sample_rate"] as? Double, 44_100)
        let expected = TranscriptionService.resampleAudio(input, from: 44_100, to: 16_000)
        XCTAssertEqual(j["n_samples"] as? Int, expected.count)
    }

    func testSecondFlagOfSameHoldWritesNothing() async throws {
        let (rec, dir) = try makeRecorder()
        rec.beginHold(seq: 3, bundleID: nil)
        rec.noteRelease(seq: 3)
        rec.noteSamples(sine(seconds: 0.5, rate: 48_000), inputSampleRate: 48_000)
        let first = await rec.flag()
        guard case .written(let stem) = first else { return XCTFail("expected .written, got \(first)") }
        let second = await rec.flag()
        XCTAssertEqual(second, .alreadyFlagged(stem: stem))
        XCTAssertEqual(files(dir).count, 2)
    }

    func testPurgeRemovesOnlyExpiredFlagFiles() throws {
        let (_, dir) = try makeRecorder()
        let now = Date()
        let fm = FileManager.default
        func make(_ name: String, daysOld: Double) throws {
            let url = dir.appendingPathComponent(name)
            try Data("x".utf8).write(to: url)
            try fm.setAttributes([.modificationDate: now.addingTimeInterval(-daysOld * 86_400)], ofItemAtPath: url.path)
        }
        try make("flag-a.wav", daysOld: 15)
        try make("flag-a.json", daysOld: 15)
        try make("flag-b.json", daysOld: 1)
        try make("notes.txt", daysOld: 15)

        PreviewFlagRecorder.purgeExpired(in: dir, now: now)
        XCTAssertEqual(files(dir), ["flag-b.json", "notes.txt"])
    }
}
#endif
