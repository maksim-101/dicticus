import XCTest
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
    }

    override func tearDown() async throws {
        MockURLProtocol.reset()
        try? FileManager.default.removeItem(at: IOSModelDownloadService.modelPath())
        try await super.tearDown()
    }

    /// Make a service wired to MockURLProtocol with a small in-memory payload.
    private func makeService(payloadBytes: Int = 8 * 1024, chunkCount: Int = 4) -> IOSModelDownloadService {
        MockURLProtocol.responseData[IOSModelDownloadService.modelURL.absoluteString] =
            Data(repeating: 0xAB, count: payloadBytes)
        MockURLProtocol.chunkCount = chunkCount
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        return IOSModelDownloadService(sessionConfiguration: cfg)
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
        try XCTSkipIf(!isWave2Ready,
                      "Pending Wave 2: IOSModelDownloadService not yet implemented")
        // Fresh — setUp deletes any stale file.
        XCTAssertFalse(IOSModelDownloadService.isModelCached())
        MockURLProtocol.chunkDelay = 0
        let service = makeService(payloadBytes: 512, chunkCount: 1)
        try await service.startAndWaitForCompletion()
        XCTAssertTrue(IOSModelDownloadService.isModelCached())
        try FileManager.default.removeItem(at: IOSModelDownloadService.modelPath())
        XCTAssertFalse(IOSModelDownloadService.isModelCached())
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
