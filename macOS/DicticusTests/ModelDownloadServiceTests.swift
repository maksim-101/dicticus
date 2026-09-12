import XCTest
@testable import Dicticus

final class ModelDownloadServiceTests: XCTestCase {

    // MARK: - Model path

    func testModelPathEndsWithGGUFFileName() {
        let path = ModelDownloadService.modelPath()
        XCTAssertTrue(path.lastPathComponent == "qwen3.5-4b-q4_k_m.gguf",
                       "Model path must end with GGUF filename")
    }

    func testModelPathContainsDicticusModelsDirectory() {
        let path = ModelDownloadService.modelPath().path
        XCTAssertTrue(path.contains("Dicticus/Models"),
                       "Model path must be under Dicticus/Models/ in Application Support")
    }

    func testModelPathIsInApplicationSupport() {
        let path = ModelDownloadService.modelPath().path
        XCTAssertTrue(path.contains("Application Support"),
                       "Model must be cached in Application Support directory (D-10)")
    }

    // MARK: - Model URL (CLEANRD-01: ungated repo)

    func testModelURLPointsToUngatedUnslothRepo() {
        let url = ModelDownloadService.modelURL.absoluteString
        XCTAssertTrue(url.contains("unsloth/Qwen3.5-4B-GGUF"),
                       "Must use the ungated unsloth repo for Qwen3.5-4B (verified HTTP 200, gated:False)")
        XCTAssertFalse(url.contains("/Qwen3.5-4B-Instruct"),
                        "Must NOT use the GATED Qwen/Qwen3.5-4B-Instruct repo (requires login)")
    }

    func testModelURLPointsToQ4_K_MQuantization() {
        let url = ModelDownloadService.modelURL.absoluteString
        XCTAssertTrue(url.contains("Q4_K_M"),
                       "Must download the Q4_K_M quantization (the file benchmarked + fidelity-gated)")
    }

    // MARK: - Cache check

    /// D-08 rewrite: `isModelCached()` now means "exists AND verified" — a stricter
    /// condition than plain existence, so the old bidirectional equivalence no
    /// longer holds. Only the one-directional implication survives: cached implies
    /// a file is there. Read-only against the real path — never writes.
    func testIsModelCached_impliesFileExists() {
        let isCached = ModelDownloadService.isModelCached()
        let fileExists = FileManager.default.fileExists(
            atPath: ModelDownloadService.modelPath().path
        )
        XCTAssertTrue(!isCached || fileExists,
                       "isModelCached must never be true when no file exists")
    }

    // MARK: - Expected hash constant (D-06/D-08, Wave-0 §D derived value)

    func testExpectedSHA256_isThe64HexPinFromWave0() {
        let hash = ModelDownloadService.expectedModelSHA256
        XCTAssertEqual(hash.count, 64)
        XCTAssertTrue(hash.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
                       "expectedModelSHA256 must be exactly 64 lowercase hex characters")
        XCTAssertTrue(hash.hasPrefix("00fe7986"))
        XCTAssertTrue(hash.hasSuffix("f11a4"))
        XCTAssertEqual(ModelDownloadService.expectedModelByteCount, 2_740_937_888)
        XCTAssertEqual(ModelDownloadService.expectedSHA256(forFileName: ModelDownloadService.modelFileName),
                        ModelDownloadService.expectedModelSHA256)
        XCTAssertNil(ModelDownloadService.expectedSHA256(forFileName: "other.gguf"))
    }

    // MARK: - acquireVerifiedModel retry state machine (D-08, fake downloader — hermetic)

    private static let abcHash = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

    private final class CallCounter {
        private(set) var count = 0
        func increment() { count += 1 }
    }

    /// Writes `contents` to a fresh temp file and returns its URL — simulates a
    /// downloader's returned temp-file URL without touching the network.
    private func writeTempFile(_ contents: String, in dir: URL, named name: String = "download.tmp") -> URL {
        let url = dir.appendingPathComponent(name).appendingPathExtension(UUID().uuidString)
        try? contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testAcquire_noFile_goodDownload_movesStampsAndVerifies() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("p50-acquire-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let modelURL = dir.appendingPathComponent("qwen3.5-4b-q4_k_m.gguf")
        let downloadCount = CallCounter()

        try await ModelDownloadService.acquireVerifiedModel(
            at: modelURL,
            expectedSHA256: Self.abcHash,
            download: {
                downloadCount.increment()
                return self.writeTempFile("abc", in: dir)
            }
        )

        XCTAssertEqual(downloadCount.count, 1)
        XCTAssertEqual(try String(contentsOf: modelURL, encoding: .utf8), "abc")
        XCTAssertTrue(ModelIntegrity.isVerifiedCheaply(modelURL: modelURL, expectedSHA256: Self.abcHash))
    }

    func testAcquire_existingMismatch_thenGoodDownload_succeeds() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("p50-acquire-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let modelURL = dir.appendingPathComponent("qwen3.5-4b-q4_k_m.gguf")
        try "xyz".write(to: modelURL, atomically: true, encoding: .utf8)
        let downloadCount = CallCounter()

        try await ModelDownloadService.acquireVerifiedModel(
            at: modelURL,
            expectedSHA256: Self.abcHash,
            download: {
                downloadCount.increment()
                return self.writeTempFile("abc", in: dir)
            }
        )

        XCTAssertEqual(downloadCount.count, 1)
        XCTAssertEqual(try String(contentsOf: modelURL, encoding: .utf8), "abc")
        XCTAssertNotNil(ModelIntegrity.readStamp(for: modelURL))
    }

    func testAcquire_twoBadDownloads_throwsAndLeavesNothing() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("p50-acquire-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let modelURL = dir.appendingPathComponent("qwen3.5-4b-q4_k_m.gguf")
        let downloadCount = CallCounter()

        do {
            try await ModelDownloadService.acquireVerifiedModel(
                at: modelURL,
                expectedSHA256: Self.abcHash,
                download: {
                    downloadCount.increment()
                    return self.writeTempFile("xyz", in: dir)
                }
            )
            XCTFail("expected acquireVerifiedModel to throw after two mismatches")
        } catch let error as ModelIntegrityError {
            XCTAssertEqual(error, .verificationFailed(attempts: 2))
        }

        XCTAssertEqual(downloadCount.count, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: modelURL.path))
        XCTAssertNil(ModelIntegrity.readStamp(for: modelURL))
    }

    func testAcquire_existingMismatchThenBadDownload_throwsAfterOneRedownload() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("p50-acquire-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let modelURL = dir.appendingPathComponent("qwen3.5-4b-q4_k_m.gguf")
        try "xyz".write(to: modelURL, atomically: true, encoding: .utf8)
        let downloadCount = CallCounter()

        do {
            try await ModelDownloadService.acquireVerifiedModel(
                at: modelURL,
                expectedSHA256: Self.abcHash,
                download: {
                    downloadCount.increment()
                    return self.writeTempFile("xyz", in: dir)
                }
            )
            XCTFail("expected acquireVerifiedModel to throw")
        } catch let error as ModelIntegrityError {
            XCTAssertEqual(error, .verificationFailed(attempts: 2))
        }

        XCTAssertEqual(downloadCount.count, 1)
    }

    func testAcquire_existingVerified_neverDownloads() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("p50-acquire-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let modelURL = dir.appendingPathComponent("qwen3.5-4b-q4_k_m.gguf")
        try "abc".write(to: modelURL, atomically: true, encoding: .utf8)
        // Pre-verify so a valid stamp exists.
        _ = ModelIntegrity.verify(modelURL: modelURL, expectedSHA256: Self.abcHash)
        let downloadCount = CallCounter()

        try await ModelDownloadService.acquireVerifiedModel(
            at: modelURL,
            expectedSHA256: Self.abcHash,
            download: {
                downloadCount.increment()
                return self.writeTempFile("xyz", in: dir)
            }
        )

        XCTAssertEqual(downloadCount.count, 0)
    }

    // MARK: - File name constant

    func testModelFileNameMatchesURLCaseInsensitive() {
        // modelFileName is intentionally lowercase (matches the spike-010 dev file
        // on disk), while the HuggingFace URL uses the repo's mixed-case filename —
        // so this comparison is case-insensitive by design (CLEANRD-01).
        let urlFileName = ModelDownloadService.modelURL.lastPathComponent
        XCTAssertEqual(ModelDownloadService.modelFileName.lowercased(), urlFileName.lowercased(),
                        "modelFileName constant must match the URL's file name case-insensitively")
    }

    // MARK: - Orphan cleanup (CLEANRD-01, T-36.6-04)

    func testRemoveOrphanedModelsDeletesLegacyFilesButKeepsCurrent() throws {
        let modelsDir = ModelDownloadService.modelPath().deletingLastPathComponent()
        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        // Every retired model (Gemma AND the now-superseded Qwen2.5) must be reclaimed.
        let legacyPaths = ModelDownloadService.legacyModelFileNames.map {
            modelsDir.appendingPathComponent($0)
        }
        let currentPath = ModelDownloadService.modelPath()

        // Don't clobber a real dev-machine current-model file if one is already cached.
        let wasCurrentPresent = FileManager.default.fileExists(atPath: currentPath.path)
        if !wasCurrentPresent {
            FileManager.default.createFile(atPath: currentPath.path, contents: Data("stub".utf8))
        }
        for p in legacyPaths {
            FileManager.default.createFile(atPath: p.path, contents: Data("stub".utf8))
        }

        defer {
            for p in legacyPaths { try? FileManager.default.removeItem(at: p) }
            if !wasCurrentPresent { try? FileManager.default.removeItem(at: currentPath) }
        }

        for p in legacyPaths {
            XCTAssertTrue(FileManager.default.fileExists(atPath: p.path),
                          "Precondition: stub legacy file \(p.lastPathComponent) must exist before cleanup")
        }

        ModelDownloadService.removeOrphanedModelsIfPresent()

        for p in legacyPaths {
            XCTAssertFalse(FileManager.default.fileExists(atPath: p.path),
                           "Retired GGUF \(p.lastPathComponent) must be removed to reclaim disk")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: currentPath.path),
                      "Current model GGUF must remain untouched")
    }
}
