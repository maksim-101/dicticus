import XCTest
@testable import Dicticus

/// Context-mode prompt A/B (2026-08-02 investigation follow-on).
///
/// Every dictation typed into a terminal resolves to `DictationContext.code`
/// (`ContextResolver.swift:16` maps com.googlecode.iterm2), so the identifier-safe
/// `v-transcriptionist-code` prompt runs even when the utterance is ordinary prose with no
/// technical tokens in it at all. Aggregate pass-through rates do not separate the two
/// prompts (39% code vs 38% default), so the question is not *how often* they differ but
/// *how* — this drives the same utterance through both and records each pair for
/// classification.
///
/// Opt-in only; skips unless a corpus path is supplied:
///
///     DICTICUS_CTX_CORPUS=/path/corpus.json DICTICUS_CTX_OUT=/path/out.jsonl \
///     xcodebuild test -only-testing:DicticusTests/ContextPromptAbTests
final class ContextPromptAbTests: XCTestCase {

    private struct Utterance: Decodable {
        let text: String
        let lang: String
    }

    @MainActor
    func testCodeVsDefaultPromptOnProse() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let corpusPath = env["DICTICUS_CTX_CORPUS"] else {
            throw XCTSkip("Set DICTICUS_CTX_CORPUS to run the context prompt A/B.")
        }
        try XCTSkipUnless(ModelDownloadService.isModelCached(), "Cleanup model not cached.")

        let corpus = try JSONDecoder().decode(
            [Utterance].self,
            from: Data(contentsOf: URL(fileURLWithPath: corpusPath))
        )
        XCTAssertFalse(corpus.isEmpty)

        CleanupService.initializeBackend()
        let service = CleanupService()
        try service.loadModel(from: ModelDownloadService.modelPath().path)

        let outPath = env["DICTICUS_CTX_OUT"] ?? NSTemporaryDirectory().appending("ctx-ab.jsonl")
        FileManager.default.createFile(atPath: outPath, contents: nil)
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: outPath))
        defer { try? handle.close() }

        for item in corpus {
            // Same service instance and same input for both arms, so the only variable is
            // the context that selects the system body.
            let codeOut = await service.cleanup(
                text: item.text, language: item.lang, context: .code
            )
            let defaultOut = await service.cleanup(
                text: item.text, language: item.lang, context: .default
            )
            let row: [String: Any] = [
                "input": item.text,
                "lang": item.lang,
                "code": codeOut,
                "default": defaultOut,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: row) {
                handle.write(data)
                handle.write(Data("\n".utf8))
            }
        }
        print("Context A/B wrote \(corpus.count) rows to \(outPath)")
    }
}
