import XCTest
@testable import Dicticus

#if DEBUG_RECORDER
/// Slice 60: the retention probe writes one 16 kHz mono PCM16 WAV per dictation into its
/// folder, names it by timestamp, and purges files older than seven days.
final class AudioRetentionProbeTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioRetentionProbeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testRetainWritesAPlayableWav() async throws {
        let probe = AudioRetentionProbe(directoryURL: dir)
        let samples = (0..<16_000).map { Float(sin(Double($0) * 0.05)) * 0.5 }   // one second
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let written = await probe.retain(samples16k: samples, date: date)
        let name = try XCTUnwrap(written)
        XCTAssertTrue(name.hasSuffix(".wav"))
        XCTAssertFalse(name.contains(":"), "colons are not file-name safe")
        let data = try Data(contentsOf: dir.appendingPathComponent(name))
        XCTAssertEqual(data.count, 44 + samples.count * 2, "44-byte RIFF header plus 16-bit samples")
        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: data[8..<12], encoding: .ascii), "WAVE")
        let rate = data[24..<28].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        XCTAssertEqual(UInt32(littleEndian: rate), 16_000)
        let channels = data[22..<24].withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
        XCTAssertEqual(UInt16(littleEndian: channels), 1)
    }

    func testEmptyBufferWritesNothing() async {
        let probe = AudioRetentionProbe(directoryURL: dir)
        let name = await probe.retain(samples16k: [])
        XCTAssertNil(name)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).count, 0)
    }

    func testPurgeRemovesWavsOlderThanSevenDaysOnly() async throws {
        let probe = AudioRetentionProbe(directoryURL: dir)
        let old = dir.appendingPathComponent("old.wav")
        let recent = dir.appendingPathComponent("recent.wav")
        let other = dir.appendingPathComponent("notes.txt")
        for url in [old, recent, other] { try Data([0]).write(to: url) }
        let eightDaysAgo = Date().addingTimeInterval(-8 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: eightDaysAgo], ofItemAtPath: old.path)
        try FileManager.default.setAttributes([.modificationDate: eightDaysAgo], ofItemAtPath: other.path)
        await probe.purge(olderThan: Date().addingTimeInterval(-Double(AudioRetentionProbe.retentionDays * 86_400)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path), "an 8-day-old WAV is purged")
        XCTAssertTrue(FileManager.default.fileExists(atPath: recent.path), "a fresh WAV stays")
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.path), "only .wav files are touched")
    }
}
#endif
