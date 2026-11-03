import XCTest
import CryptoKit
@testable import Dicticus

/// Wave 0 scaffold — IOSModelDownloadService tests (D-10, Q6).
///
/// **TDD RED state.** Wave 2 adds `iOS/Dicticus/Services/IOSModelDownloadService.swift`
/// with these required test seams:
///
/// - `init(sessionConfiguration: URLSessionConfiguration)` — lets tests inject
///   a `URLSessionConfiguration` whose `protocolClasses = [MockURLProtocol.self]`.
/// - `static var modelURL: URL`
/// - `static var modelFileName: String` (`"qwen2.5-3b-instruct-q4_k_m.gguf"`, CLEANRD-01)
/// - `static func modelPath() -> URL`
/// - `static func isModelCached() -> Bool`
/// - `@Published var state: DownloadState` (`.idle / .downloading / .paused / .completed / .failed`)
/// - `@Published var progress: Double` (0.0 … 1.0)
/// - `func start()`, `func pause()`, `func resume()`
/// - `func startAndWaitForCompletion() async` and `func waitForCompletion() async`
///   — test-helper methods that await the final state (Wave 2 may implement as
///   async wrappers around Combine sinks or AsyncSequence).
///
/// Once Wave 2 lands, flip `isWave2Ready` to `true` and fill in the TODO bodies
/// below. `MockURLProtocol` (shipped in this plan) drives all chunked-progress,
/// Range-header resume, and failure-injection scenarios.
@MainActor
final class IOSModelDownloadServiceTests: XCTestCase {

    /// Wave 2 ready — IOSModelDownloadService landed in 19-03.
    private let isWave2Ready = true

    override func setUp() async throws {
        try await super.setUp()
        MockURLProtocol.reset()
        // Make sure any leftover GGUF from a previous test doesn't skew
        // the backup-exclusion assertion (fresh download each run).
        try? FileManager.default.removeItem(at: IOSModelDownloadService.modelPath())
        try? FileManager.default.removeItem(at: IOSModelDownloadService.modelPath().appendingPathExtension("stamp.json"))
    }

    override func tearDown() async throws {
        MockURLProtocol.reset()
        try? FileManager.default.removeItem(at: IOSModelDownloadService.modelPath())
        try? FileManager.default.removeItem(at: IOSModelDownloadService.modelPath().appendingPathExtension("stamp.json"))
        try await super.tearDown()
    }

    /// Make a service wired to MockURLProtocol with a small in-memory payload.
    private func makeService(payloadBytes: Int = 8 * 1024, chunkCount: Int = 4) -> IOSModelDownloadService {
        let payload = Data(repeating: 0xAB, count: payloadBytes)
        MockURLProtocol.responseData[IOSModelDownloadService.modelURL.absoluteString] = payload
        MockURLProtocol.chunkCount = chunkCount
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        return IOSModelDownloadService(sessionConfiguration: cfg, expectedSHA256: Self.sha256Hex(of: payload))
    }

    private static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - D-10: Progress callbacks over ≥3 chunks

    func testProgressCallbacks() async throws {
        try XCTSkipIf(!isWave2Ready,
                      "Pending Wave 2: IOSModelDownloadService not yet implemented")
        MockURLProtocol.chunkDelay = 0.02
        let service = makeService(payloadBytes: 8 * 1024, chunkCount: 4)

        var progressSamples: [Double] = []
        let cancel = service.$progress.sink { value in
            progressSamples.append(value)
        }
        defer { cancel.cancel() }

        try await service.startAndWaitForCompletion()

        XCTAssertEqual(service.state, .completed)
        XCTAssertGreaterThanOrEqual(progressSamples.count, 3,
                                    "Expected at least 3 progress samples across chunks")
        XCTAssertEqual(progressSamples.last ?? 0, 1.0, accuracy: 0.01)

        // Monotonic non-decreasing (allowing for the initial 0.0 reset on start()).
        let meaningful = progressSamples.drop(while: { $0 == 0 })
        var prev = 0.0
        for sample in meaningful {
            XCTAssertGreaterThanOrEqual(sample, prev, "progress must not decrease: \(sample) < \(prev)")
            prev = sample
        }
    }

    // MARK: - D-10: Pause / resume with Range header

    func testPauseResume() async throws {
        try XCTSkipIf(!isWave2Ready,
                      "Pending Wave 2: IOSModelDownloadService not yet implemented")
        // 200 ms between chunks, 10 chunks → ~2 s total; pause mid-way.
        MockURLProtocol.chunkDelay = 0.2
        let service = makeService(payloadBytes: 10 * 1024, chunkCount: 10)
        service.start()
        try await Task.sleep(nanoseconds: 500_000_000)
        service.pause()

        // Poll briefly for the cancel-with-resume-data callback to publish .paused.
        let deadline = Date().addingTimeInterval(2.0)
        while service.state != .paused && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(service.state, .paused)
        let midProgress = service.progress
        XCTAssertGreaterThan(midProgress, 0.0)
        XCTAssertLessThan(midProgress, 1.0)

        // Resume: drop chunk delay so the remainder completes quickly.
        MockURLProtocol.chunkDelay = 0.01
        service.resume()
        await service.waitForCompletion()
        XCTAssertEqual(service.state, .completed)
        XCTAssertEqual(service.progress, 1.0, accuracy: 0.01)
    }

    // MARK: - Q6: Backup exclusion

    func testBackupExclusion() async throws {
        try XCTSkipIf(!isWave2Ready,
                      "Pending Wave 2: IOSModelDownloadService not yet implemented")
        MockURLProtocol.chunkDelay = 0
        let service = makeService(payloadBytes: 1024, chunkCount: 1)
        try await service.startAndWaitForCompletion()

        let url = IOSModelDownloadService.modelPath()
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                      "Downloaded GGUF should be at canonical modelPath()")

        let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertTrue(values.isExcludedFromBackup ?? false,
                      "Q6: downloaded GGUF must be marked isExcludedFromBackup")
    }

    // MARK: - isModelCached lifecycle

    func testIsModelCachedReflectsDiskState() async throws {
        XCTAssertFalse(IOSModelDownloadService.isModelCached())
        MockURLProtocol.chunkDelay = 0
        let service = makeService(payloadBytes: 512, chunkCount: 1)
        try await service.startAndWaitForCompletion()

        // The payload's hash is not the pin, so the stamp records a fact that does not
        // make the file "cached" for the shipped model.
        let url = IOSModelDownloadService.modelPath()
        let payloadHash = Self.sha256Hex(of: Data(repeating: 0xAB, count: 512))
        XCTAssertEqual(ModelIntegrity.readStamp(for: url)?.sha256, payloadHash)
        XCTAssertFalse(IOSModelDownloadService.isModelCached())

        try FileManager.default.removeItem(at: url)
        XCTAssertFalse(IOSModelDownloadService.hasModelFile())
        XCTAssertFalse(IOSModelDownloadService.isModelCached())
    }

    // MARK: - 261103-9c7: integrity (HTTP status, pinned SHA-256, stamp)

    private var stampPath: URL {
        IOSModelDownloadService.modelPath().appendingPathExtension("stamp.json")
    }

    /// RED-1: an error response must not be saved as the model.
    func testNon2xxResponseFailsAndLeavesNoFile() async throws {
        MockURLProtocol.chunkDelay = 0
        MockURLProtocol.forcedStatusCode = 404
        let service = makeService(payloadBytes: 512, chunkCount: 1)
        do {
            try await service.startAndWaitForCompletion()
            XCTFail("a 404 download must throw")
        } catch {}
        guard case .failed(let message) = service.state else {
            return XCTFail("expected .failed, got \(service.state)")
        }
        XCTAssertTrue(message.contains("404"), "message must name the status: \(message)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: IOSModelDownloadService.modelPath().path))
    }

    /// RED-2: with the default (pinned) hash, bytes that are not the pinned model are rejected.
    func testDefaultPinRejectsWrongBytesAndLeavesNoFileOrStamp() async throws {
        MockURLProtocol.chunkDelay = 0
        MockURLProtocol.responseData[IOSModelDownloadService.modelURL.absoluteString] =
            Data(repeating: 0xAB, count: 512)
        MockURLProtocol.chunkCount = 1
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        let service = IOSModelDownloadService(sessionConfiguration: cfg)
        do {
            try await service.startAndWaitForCompletion()
            XCTFail("a download that does not match the pin must throw")
        } catch {}
        guard case .failed = service.state else {
            return XCTFail("expected .failed, got \(service.state)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: IOSModelDownloadService.modelPath().path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stampPath.path))
    }

    /// RED-3: a file with no stamp is not "cached" (it has never been hashed).
    func testUnstampedFileIsNotCached() throws {
        let modelsDir = IOSModelDownloadService.modelPath().deletingLastPathComponent()
        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: IOSModelDownloadService.modelPath().path, contents: Data("stub".utf8))
        XCTAssertFalse(IOSModelDownloadService.isModelCached())
    }

    /// A verified download keeps the file, flags it out of backups and stamps it afterwards.
    func testVerifiedDownloadStampsFileAfterBackupFlag() async throws {
        MockURLProtocol.chunkDelay = 0
        let service = makeService(payloadBytes: 2048, chunkCount: 2)
        try await service.startAndWaitForCompletion()
        XCTAssertEqual(service.state, .completed)

        let url = IOSModelDownloadService.modelPath()
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup ?? false)
        let facts = try XCTUnwrap(ModelIntegrity.fileFacts(at: url))
        let stamp = try XCTUnwrap(ModelIntegrity.readStamp(for: url))
        XCTAssertEqual(stamp.sha256, Self.sha256Hex(of: Data(repeating: 0xAB, count: 2048)))
        XCTAssertEqual(stamp.bytes, facts.bytes)
        XCTAssertEqual(stamp.mtime, facts.mtime)
    }

    /// A hash mismatch with an injected expectation deletes nothing into place and fails.
    func testInjectedHashMismatchFails() async throws {
        MockURLProtocol.chunkDelay = 0
        MockURLProtocol.responseData[IOSModelDownloadService.modelURL.absoluteString] = Data(repeating: 0xCD, count: 256)
        MockURLProtocol.chunkCount = 1
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        let service = IOSModelDownloadService(sessionConfiguration: cfg, expectedSHA256: String(repeating: "0", count: 64))
        do {
            try await service.startAndWaitForCompletion()
            XCTFail("mismatching hash must throw")
        } catch {}
        guard case .failed(let message) = service.state else {
            return XCTFail("expected .failed, got \(service.state)")
        }
        XCTAssertTrue(message.contains("did not match"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: IOSModelDownloadService.modelPath().path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stampPath.path))
    }

    /// A stamp that carries the pin and matches the file makes it cached without hashing.
    func testStampWithPinMakesFileCached() throws {
        let url = IOSModelDownloadService.modelPath()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: Data("stub".utf8))
        try ModelIntegrity.writeStamp(for: url, sha256: ModelIntegrity.pinnedModelSHA256)
        XCTAssertTrue(IOSModelDownloadService.isModelCached())
        // Touching the file invalidates the stamp (size changes).
        try Data("stub-longer".utf8).write(to: url)
        XCTAssertFalse(IOSModelDownloadService.isModelCached())
    }

    // MARK: verifyExistingModel (older build's unstamped file)

    private func writeStub() throws {
        let url = IOSModelDownloadService.modelPath()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: Data("stub".utf8))
    }

    func testVerifyExistingModelHashesOnceThenUsesStamp() throws {
        try writeStub()
        var calls = 0
        let first = IOSModelDownloadService.verifyExistingModel(hasher: { _ in calls += 1; return ModelIntegrity.pinnedModelSHA256 })
        XCTAssertEqual(first, .verified(rehashed: true))
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(IOSModelDownloadService.isModelCached())
        let second = IOSModelDownloadService.verifyExistingModel(hasher: { _ in calls += 1; return "never" })
        XCTAssertEqual(second, .verified(rehashed: false))
        XCTAssertEqual(calls, 1)
    }

    func testVerifyExistingModelMismatchDeletesFileAndStamp() throws {
        try writeStub()
        let verdict = IOSModelDownloadService.verifyExistingModel(hasher: { _ in "not-the-pin" })
        XCTAssertEqual(verdict, .mismatch(actual: "not-the-pin"))
        XCTAssertFalse(IOSModelDownloadService.hasModelFile())
        XCTAssertFalse(FileManager.default.fileExists(atPath: stampPath.path))
    }

    func testVerifyExistingModelHashErrorKeepsFile() throws {
        try writeStub()
        struct Boom: Error {}
        let verdict = IOSModelDownloadService.verifyExistingModel(hasher: { _ in throw Boom() })
        XCTAssertEqual(verdict, .mismatch(actual: "hash-error"))
        XCTAssertTrue(IOSModelDownloadService.hasModelFile(), "a transient read error must not delete the model")
    }

    func testVerifyExistingModelMissing() {
        XCTAssertEqual(IOSModelDownloadService.verifyExistingModel(hasher: { _ in "x" }), .missing)
    }

    /// Guards a future model swap that updates one platform's file name and forgets the pin.
    func testShippedFileNameHasTheSharedPin() {
        let pin = ModelIntegrity.expectedSHA256(forFileName: IOSModelDownloadService.modelFileName)
        XCTAssertEqual(pin, ModelIntegrity.pinnedModelSHA256)
        XCTAssertEqual(pin?.count, 64)
        XCTAssertNil(ModelIntegrity.expectedSHA256(forFileName: "other.gguf"))
    }

    // MARK: - Sanity: MockURLProtocol Range header handling

    func testMockURLProtocolHonorsRangeHeader() throws {
        let expectation = expectation(description: "range response")
        let totalBytes = 1024
        let url = URL(string: "https://example.test/mock.bin")!
        MockURLProtocol.responseData[url.absoluteString] = Data(repeating: 0x42, count: totalBytes)
        MockURLProtocol.chunkDelay = 0  // fast

        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: cfg)

        var req = URLRequest(url: url)
        req.setValue("bytes=512-", forHTTPHeaderField: "Range")
        var capturedStatus: Int = 0
        var capturedLength: Int = 0
        session.dataTask(with: req) { data, response, _ in
            if let http = response as? HTTPURLResponse {
                capturedStatus = http.statusCode
            }
            capturedLength = data?.count ?? 0
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5)
        XCTAssertEqual(capturedStatus, 206, "Range request must produce 206 Partial Content")
        XCTAssertEqual(capturedLength, totalBytes - 512,
                       "Range response body must start at offset 512")
    }

    // MARK: - Orphan cleanup (CLEANRD-01, T-36.6-04)

    func testRemoveOrphanedGemmaIfPresentDeletesLegacyFileButKeepsQwen() throws {
        let modelsDir = IOSModelDownloadService.modelPath().deletingLastPathComponent()
        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        let legacyPath = modelsDir.appendingPathComponent(IOSModelDownloadService.legacyModelFileNames[0])
        let qwenPath = IOSModelDownloadService.modelPath()

        FileManager.default.createFile(atPath: qwenPath.path, contents: Data("stub".utf8))
        FileManager.default.createFile(atPath: legacyPath.path, contents: Data("stub".utf8))

        defer {
            try? FileManager.default.removeItem(at: legacyPath)
            try? FileManager.default.removeItem(at: qwenPath)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyPath.path),
                       "Precondition: stub Gemma file must exist before cleanup")

        IOSModelDownloadService.removeOrphanedModelsIfPresent()

        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyPath.path),
                        "Orphaned Gemma GGUF must be removed once Qwen is present")
        XCTAssertTrue(FileManager.default.fileExists(atPath: qwenPath.path),
                       "Qwen GGUF must remain untouched")
    }
}
