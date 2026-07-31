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

    func testIsModelCachedReturnsFalseWhenNotDownloaded() {
        // This test verifies the cache check logic works when the model
        // has not been downloaded to the test environment.
        // On CI or clean machines, this will always be false.
        // On dev machines with the model cached, this tests the positive path.
        let isCached = ModelDownloadService.isModelCached()
        let fileExists = FileManager.default.fileExists(
            atPath: ModelDownloadService.modelPath().path
        )
        XCTAssertEqual(isCached, fileExists,
                        "isModelCached must reflect actual file existence")
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
