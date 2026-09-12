import XCTest
@testable import Dicticus

/// Hermetic fixtures for `ModelIntegrity` (Phase 50 D-08). Every fixture uses a fresh
/// temp directory under `FileManager.default.temporaryDirectory` and removes it in
/// `tearDown` — NEVER `ModelDownloadService.modelPath()` or the real Application
/// Support directory (a mismatch path run against the real path would delete the
/// user's 2.74 GB model; see the plan's enforced prohibition).
final class ModelIntegrityTests: XCTestCase {

    /// FIPS 180-4 known-answer vectors — an oracle independent of CryptoKit itself.
    private static let abcVector = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    private static let emptyVector = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("p50-integrity-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        super.tearDown()
    }

    private func write(_ contents: String, named name: String = "qwen3.5-4b-q4_k_m.gguf") -> URL {
        let url = tempDir.appendingPathComponent(name)
        try? contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// A hasher that counts invocations and delegates to the real streaming hasher —
    /// used to assert idempotency (RELY-02 idempotency probe).
    private final class CountingHasher {
        private(set) var callCount = 0
        func hash(_ url: URL) throws -> String {
            callCount += 1
            return try ModelIntegrity.sha256Hex(of: url)
        }
    }

    // MARK: - sha256Hex known vectors

    func testSha256Hex_knownVectors() throws {
        let abcURL = write("abc")
        XCTAssertEqual(try ModelIntegrity.sha256Hex(of: abcURL), Self.abcVector)

        let emptyURL = write("", named: "empty.gguf")
        XCTAssertEqual(try ModelIntegrity.sha256Hex(of: emptyURL), Self.emptyVector)
    }

    // MARK: - stampURL

    func testStampURL_isSidecarNextToModel() {
        let modelURL = tempDir.appendingPathComponent("qwen3.5-4b-q4_k_m.gguf")
        let stampURL = ModelIntegrity.stampURL(for: modelURL)
        XCTAssertEqual(stampURL.lastPathComponent, "qwen3.5-4b-q4_k_m.gguf.stamp.json")
    }

    // MARK: - verify: missing

    func testVerify_missingFile_isMissing() {
        let modelURL = tempDir.appendingPathComponent("qwen3.5-4b-q4_k_m.gguf")
        let verdict = ModelIntegrity.verify(modelURL: modelURL, expectedSHA256: Self.abcVector)
        XCTAssertEqual(verdict, .missing)
        XCTAssertNil(ModelIntegrity.readStamp(for: modelURL))
    }

    // MARK: - verify: no stamp, hashes once and stamps

    func testVerify_noStamp_hashesOnceAndStamps() throws {
        let modelURL = write("abc")
        let hasher = CountingHasher()
        let verdict = ModelIntegrity.verify(modelURL: modelURL, expectedSHA256: Self.abcVector, hasher: hasher.hash)
        XCTAssertEqual(verdict, .verified(rehashed: true))
        XCTAssertEqual(hasher.callCount, 1)

        let stamp = try XCTUnwrap(ModelIntegrity.readStamp(for: modelURL))
        XCTAssertEqual(stamp.sha256, Self.abcVector)
        XCTAssertEqual(stamp.bytes, 3)
        let facts = try XCTUnwrap(ModelIntegrity.fileFacts(at: modelURL))
        XCTAssertEqual(stamp.mtime, facts.mtime)
    }

    // MARK: - verify: idempotency (RELY-02 explicit)

    func testVerify_validStamp_doesNotRehash() {
        let modelURL = write("abc")
        let hasher = CountingHasher()
        let first = ModelIntegrity.verify(modelURL: modelURL, expectedSHA256: Self.abcVector, hasher: hasher.hash)
        XCTAssertEqual(first, .verified(rehashed: true))
        XCTAssertEqual(hasher.callCount, 1)

        let second = ModelIntegrity.verify(modelURL: modelURL, expectedSHA256: Self.abcVector, hasher: hasher.hash)
        XCTAssertEqual(second, .verified(rehashed: false))
        XCTAssertEqual(hasher.callCount, 1, "a second verify with a valid stamp must call the hasher zero times")
    }

    // MARK: - verify: adjacency — mtime-only change re-hashes (RELY-02 explicit)

    func testVerify_mtimeOnlyChange_rehashesAndRestamps() throws {
        let modelURL = write("abc")
        let hasher = CountingHasher()
        _ = ModelIntegrity.verify(modelURL: modelURL, expectedSHA256: Self.abcVector, hasher: hasher.hash)
        XCTAssertEqual(hasher.callCount, 1)

        let bumped = Date().addingTimeInterval(60)
        try FileManager.default.setAttributes([.modificationDate: bumped], ofItemAtPath: modelURL.path)

        let verdict = ModelIntegrity.verify(modelURL: modelURL, expectedSHA256: Self.abcVector, hasher: hasher.hash)
        XCTAssertEqual(verdict, .verified(rehashed: true))
        XCTAssertEqual(hasher.callCount, 2, "an mtime-only change must trigger exactly one re-hash")

        let stamp = try XCTUnwrap(ModelIntegrity.readStamp(for: modelURL))
        let facts = try XCTUnwrap(ModelIntegrity.fileFacts(at: modelURL))
        XCTAssertEqual(stamp.mtime, facts.mtime)
    }

    // MARK: - verify: content change is a mismatch and leaves the file

    func testVerify_contentChange_isMismatchAndLeavesFile() throws {
        let modelURL = write("abc")
        _ = ModelIntegrity.verify(modelURL: modelURL, expectedSHA256: Self.abcVector)

        let handle = try FileHandle(forWritingTo: modelURL)
        handle.seekToEndOfFile()
        handle.write(Data("d".utf8))
        try handle.close()

        let newHash = try ModelIntegrity.sha256Hex(of: modelURL)
        let verdict = ModelIntegrity.verify(modelURL: modelURL, expectedSHA256: Self.abcVector)
        XCTAssertEqual(verdict, .mismatch(actual: newHash))
        XCTAssertTrue(FileManager.default.fileExists(atPath: modelURL.path),
                       "verify never deletes — deletion is acquireVerifiedModel's policy")
    }

    // MARK: - verify: empty file is a mismatch (RELY-02 explicit)

    func testVerify_emptyFile_isMismatch() {
        let modelURL = write("", named: "empty2.gguf")
        let verdict = ModelIntegrity.verify(modelURL: modelURL, expectedSHA256: Self.abcVector)
        XCTAssertEqual(verdict, .mismatch(actual: Self.emptyVector))
    }

    // MARK: - isVerifiedCheaply never hashes or writes

    func testIsVerifiedCheaply_neverHashesOrWrites() {
        let modelURL = write("abc")
        XCTAssertFalse(ModelIntegrity.isVerifiedCheaply(modelURL: modelURL, expectedSHA256: Self.abcVector))
        XCTAssertNil(ModelIntegrity.readStamp(for: modelURL),
                     "isVerifiedCheaply must never write a stamp")
    }

    // MARK: - stampMatches pure table

    func testStampMatches_pureTable() {
        let stamp = ModelIntegrity.Stamp(sha256: Self.abcVector, bytes: 3, mtime: 1000.0)

        XCTAssertFalse(ModelIntegrity.stampMatches(nil, bytes: 3, mtime: 1000.0, expectedSHA256: Self.abcVector))
        XCTAssertTrue(ModelIntegrity.stampMatches(stamp, bytes: 3, mtime: 1000.0, expectedSHA256: Self.abcVector))
        XCTAssertFalse(ModelIntegrity.stampMatches(stamp, bytes: 4, mtime: 1000.0, expectedSHA256: Self.abcVector))
        XCTAssertFalse(ModelIntegrity.stampMatches(stamp, bytes: 3, mtime: 1000.001, expectedSHA256: Self.abcVector))
        XCTAssertFalse(ModelIntegrity.stampMatches(stamp, bytes: 3, mtime: 1000.0, expectedSHA256: Self.emptyVector))
    }
}
