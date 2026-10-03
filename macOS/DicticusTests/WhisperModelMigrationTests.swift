import XCTest
@testable import Dicticus

/// Quick task 261003-raz: the one-shot move of the Whisper model out of ~/Documents.
/// Every call injects temp directories and a throwaway defaults suite; the real
/// Documents folder and the app's real defaults are never touched.
final class WhisperModelMigrationTests: XCTestCase {

    private var tempRoot: URL!
    private var legacyBase: URL!
    private var newBase: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        tempRoot = fm.temporaryDirectory.appendingPathComponent("raz-\(UUID().uuidString)")
        legacyBase = tempRoot.appendingPathComponent("legacy")
        newBase = tempRoot.appendingPathComponent("new")
        try fm.createDirectory(at: legacyBase, withIntermediateDirectories: true)
        try fm.createDirectory(at: newBase, withIntermediateDirectories: true)
        suiteName = "raz-tests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? fm.removeItem(at: tempRoot)
    }

    private var legacyRepo: URL { legacyBase.appendingPathComponent(AsrModelLoader.whisperRepoSubpath) }
    private var newRepo: URL { newBase.appendingPathComponent(AsrModelLoader.whisperRepoSubpath) }
    private var sidecarSubpath: String { ".cache/huggingface/download/\(AsrModelLoader.modelName)" }

    private func write(_ text: String, to url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func seedLegacy() throws {
        let variant = legacyRepo.appendingPathComponent(AsrModelLoader.modelName)
        try write("weights", to: variant.appendingPathComponent("AudioEncoder.mlmodelc/weights/weight.bin"))
        try write("meta", to: legacyRepo
            .appendingPathComponent(sidecarSubpath)
            .appendingPathComponent("AudioEncoder.mlmodelc/weights/weight.bin.metadata"))
        try write("marker", to: legacyRepo
            .appendingPathComponent("openai_whisper-large-v3-v20240930/marker.txt"))
        try write("{}", to: legacyBase
            .appendingPathComponent(AsrModelLoader.whisperTokenizerSubpath)
            .appendingPathComponent("tokenizer.json"))
    }

    private func migrate() -> AsrModelLoader.LegacyWhisperMigration {
        AsrModelLoader.migrateLegacyWhisperModelIfNeeded(
            defaults: defaults, legacyBase: legacyBase, newBase: newBase, fileManager: fm)
    }

    private func exists(_ url: URL) -> Bool { fm.fileExists(atPath: url.path) }

    func testFreshInstallLeavesLegacyFilesInPlace() throws {
        try seedLegacy()

        XCTAssertEqual(migrate(), .noPriorInstall)
        XCTAssertTrue(exists(legacyRepo.appendingPathComponent(AsrModelLoader.modelName)))
        XCTAssertFalse(exists(newRepo.appendingPathComponent(AsrModelLoader.modelName)))
        XCTAssertTrue(defaults.bool(forKey: AsrModelLoader.legacyWhisperMigrationKey))
    }

    func testPriorInstallMovesVariantWithSidecarAndCopiesTokenizer() throws {
        try seedLegacy()
        defaults.set(true, forKey: PermissionManager.onboardingKey)

        XCTAssertEqual(migrate(), .moved)

        let weight = "AudioEncoder.mlmodelc/weights/weight.bin"
        XCTAssertTrue(exists(newRepo.appendingPathComponent(AsrModelLoader.modelName).appendingPathComponent(weight)))
        XCTAssertTrue(exists(newRepo.appendingPathComponent(sidecarSubpath).appendingPathComponent(weight + ".metadata")))
        XCTAssertFalse(exists(legacyRepo.appendingPathComponent(AsrModelLoader.modelName)))
        XCTAssertFalse(exists(legacyRepo.appendingPathComponent(sidecarSubpath)))
        let tokenizer = AsrModelLoader.whisperTokenizerSubpath + "/tokenizer.json"
        XCTAssertTrue(exists(newBase.appendingPathComponent(tokenizer)))
        XCTAssertTrue(exists(legacyBase.appendingPathComponent(tokenizer)))
        XCTAssertTrue(exists(legacyRepo.appendingPathComponent("openai_whisper-large-v3-v20240930/marker.txt")))
        XCTAssertTrue(defaults.bool(forKey: AsrModelLoader.legacyWhisperMigrationKey))
        XCTAssertEqual(migrate(), .alreadyRan)
    }

    func testExistingDestinationLeavesLegacyAlone() throws {
        try seedLegacy()
        defaults.set(true, forKey: PermissionManager.onboardingKey)
        try fm.createDirectory(
            at: newRepo.appendingPathComponent(AsrModelLoader.modelName), withIntermediateDirectories: true)

        XCTAssertEqual(migrate(), .destinationExists)
        XCTAssertTrue(exists(legacyRepo.appendingPathComponent(AsrModelLoader.modelName)))
        XCTAssertTrue(defaults.bool(forKey: AsrModelLoader.legacyWhisperMigrationKey))
    }
}
