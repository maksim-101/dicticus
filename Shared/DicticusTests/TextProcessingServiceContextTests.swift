import XCTest
@testable import Dicticus

/// Phase 38 Plan 01 (D-01/D-03, CTXFMT-01/CTXFMT-02): context-threading
/// tests for `TextProcessingService` — the Step 3a.6 finishing-capitalization
/// gate scoped to `mode == .aiCleanup`, and the D-01 guarantee that the
/// plain path is byte-identical regardless of any injected `DictationContext`.
///
/// Named `TextProcessingServiceContextTests` (not `TextProcessingServiceTests`)
/// to avoid a duplicate-type-declaration collision: `macOS/DicticusTests/` and
/// `iOS/DicticusTests/` each already ship their own (byte-identical, non-Shared)
/// `TextProcessingServiceTests.swift`, and both are compiled into the SAME
/// `DicticusTests` target as this file (`../Shared/DicticusTests` is an
/// additional `sources:` entry alongside the per-platform `DicticusTests/`
/// directory in both `project.yml`s) — a second `final class
/// TextProcessingServiceTests` here would be an invalid redeclaration.
@MainActor
final class TextProcessingServiceContextTests: XCTestCase {

    /// Mirrors `TextProcessingServiceTests.MockCleanupProvider` (macOS/iOS
    /// DicticusTests) — minimal `CleanupProvider` conformance for isolated
    /// pipeline tests. `lastContext` is the spy assertion point proving the
    /// resolved context reaches the provider/prompt-build seam (approved
    /// scope extension — see SUMMARY.md "Deviations").
    final class MockCleanupProvider: CleanupProvider {
        var isLoaded: Bool = true
        var returnValue: String = "cleaned output"
        private(set) var lastContext: DictationContext = .default
        private(set) var callCount = 0

        func cleanup(text: String, language: String, dictionaryContext: [String: String]?, context: DictationContext = .default) async -> String {
            callCount += 1
            lastContext = context
            return returnValue
        }
    }

    var testHistory: HistoryService!

    override func setUp() {
        super.setUp()
        // Isolation: DictionaryService.shared is a process-wide singleton;
        // clear it so a stale entry from another test class's dictionary
        // fixture can't perturb these plain-text inputs via Step 1/1b.
        DictionaryService.shared.removeAll()
        let historyContainer = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("TPSContextTests-\(UUID().uuidString)", isDirectory: true)
        testHistory = HistoryService.makeForTesting(containerURLProvider: { historyContainer })
    }

    override func tearDown() {
        testHistory = nil
        super.tearDown()
    }

    // MARK: - applyFinalCapitalization: the D-03 code-context identifier skip

    func testCodeContextSkipsCamelCaseIdentifier() {
        let result = TextProcessingService.applyFinalCapitalization(
            "editGuard rejects the edit.", language: "en", context: .code
        )
        XCTAssertEqual(result, "editGuard rejects the edit.", "camelCase identifier must stay lowercase-initial under .code")
    }

    func testDefaultContextStillCapitalizesTheSameText() {
        let result = TextProcessingService.applyFinalCapitalization(
            "editGuard rejects the edit.", language: "en", context: .default
        )
        XCTAssertEqual(result, "EditGuard rejects the edit.", ".default must keep today's behavior — first letter capitalized")
    }

    func testCodeContextSkipsSnakeCaseIdentifier() {
        let result = TextProcessingService.applyFinalCapitalization(
            "snake_case wins.", language: "en", context: .code
        )
        XCTAssertEqual(result, "snake_case wins.")
    }

    func testCodeContextSkipsCamelCaseMidSentence() {
        let result = TextProcessingService.applyFinalCapitalization(
            "pairMovesFirst is fine.", language: "en", context: .code
        )
        XCTAssertEqual(result, "pairMovesFirst is fine.")
    }

    func testCodeContextSkipsCLIFlag() {
        let result = TextProcessingService.applyFinalCapitalization(
            "--verbose then quiet.", language: "en", context: .code
        )
        XCTAssertEqual(result, "--verbose then quiet.")
    }

    func testCodeContextSkipsVersionString() {
        let result = TextProcessingService.applyFinalCapitalization(
            "v3.6 shipped.", language: "en", context: .code
        )
        XCTAssertEqual(result, "v3.6 shipped.")
    }

    func testCodeContextStillCapitalizesOrdinaryProse() {
        // Not a technical identifier — .code must not suppress ordinary capitalization.
        let result = TextProcessingService.applyFinalCapitalization(
            "hello world.", language: "en", context: .code
        )
        XCTAssertEqual(result, "Hello world.")
    }

    func testCodeContextSkipsSentenceInitialIdentifierInSentenceTwo() {
        // Sentences 2..N path (capitalizeSentenceInitials), not sentence 1.
        let result = TextProcessingService.applyFinalCapitalization(
            "First up. editGuard rejects the edit.", language: "en", context: .code
        )
        XCTAssertEqual(result, "First up. editGuard rejects the edit.")
    }

    func testDefaultContextCapitalizesSentenceInitialInSentenceTwo() {
        let result = TextProcessingService.applyFinalCapitalization(
            "First up. editGuard rejects the edit.", language: "en", context: .default
        )
        XCTAssertEqual(result, "First up. EditGuard rejects the edit.")
    }

    func testNoContextArgumentIsUnchangedFromPre38Behavior() {
        // Existing call sites (pre-Phase-38, no context: argument) must keep
        // compiling and behaving exactly as before.
        let noArg = TextProcessingService.applyFinalCapitalization("of course, that makes sense.", language: "en")
        let explicitDefault = TextProcessingService.applyFinalCapitalization(
            "of course, that makes sense.", language: "en", context: .default
        )
        XCTAssertEqual(noArg, explicitDefault)
        XCTAssertEqual(noArg, "Of course, that makes sense.")
    }

    // MARK: - D-01: plain-mode byte-identical regardless of injected context

    func testPlainModeIsByteIdenticalRegardlessOfContext() async {
        let plainService = TextProcessingService(cleanupService: nil, historyService: testHistory)
        let input = "editGuard rejects the edit"

        let withoutContext = await plainService.process(text: input, language: "en", mode: .plain)
        let withCodeContext = await plainService.process(text: input, language: "en", mode: .plain, context: .code)
        let withProseContext = await plainService.process(text: input, language: "en", mode: .plain, context: .prose)

        XCTAssertEqual(withCodeContext, withoutContext, "D-01: a live context must never reach the plain-mode capitalization call")
        XCTAssertEqual(withProseContext, withoutContext)
    }

    // MARK: - End-to-end aiCleanup pipeline: context reaches Step 3a.6 through process(...)

    func testAiCleanupPipelineThreadsContextIntoFinishingCapitalization() async {
        let mock = MockCleanupProvider()
        // Echo the rules-cleaned input unchanged, simulating a pass-through
        // LLM — EditGuard.apply sees zero diff, so guardResult.text ==
        // rulesCleanedText and Step 3a.6 is the only thing left that can
        // change the output.
        mock.returnValue = "editGuard rejects the edit."
        let service = TextProcessingService(cleanupService: mock, historyService: testHistory)

        let codeOutput = await service.process(
            text: "editGuard rejects the edit.", language: "en", mode: .aiCleanup, context: .code
        )
        XCTAssertEqual(codeOutput, "editGuard rejects the edit.", "resolved .code context must reach Step 3a.6 through the full aiCleanup pipeline")

        let defaultOutput = await service.process(
            text: "editGuard rejects the edit.", language: "en", mode: .aiCleanup, context: .default
        )
        XCTAssertEqual(defaultOutput, "EditGuard rejects the edit.")
    }

    // MARK: - Approved scope extension: context reaches the CleanupProvider/CleanupPrompt seam

    /// Proves the resolved context is not just a telemetry value but actually
    /// reaches the provider seam that builds the LLM prompt — closing the
    /// gap flagged at the Task-1 checkpoint (CleanupService.cleanup ->
    /// CleanupPrompt.build). Without this, 38-02's fidelity gate would
    /// validate prompt bodies production could never send (R7).
    func testAiCleanupThreadsResolvedContextIntoCleanupProviderCall() async {
        let mock = MockCleanupProvider()
        mock.returnValue = "cleaned output"
        let service = TextProcessingService(cleanupService: mock, historyService: testHistory)

        _ = await service.process(text: "hello world", language: "en", mode: .aiCleanup, context: .code)
        XCTAssertEqual(mock.lastContext, .code, "the resolved .code context must reach CleanupProvider.cleanup(context:)")

        _ = await service.process(text: "hello world", language: "en", mode: .aiCleanup, context: .prose)
        XCTAssertEqual(mock.lastContext, .prose)

        let callCountBeforePlain = mock.callCount
        _ = await service.process(text: "hello world", language: "en", mode: .plain, context: .code)
        XCTAssertEqual(
            mock.callCount, callCountBeforePlain,
            "plain mode must never call the CleanupProvider at all — a .code context in plain mode can't leak through this seam"
        )
        XCTAssertEqual(mock.lastContext, .prose, "unchanged from the last aiCleanup call — plain mode never touched the provider")
    }

    /// `CleanupPrompt.version(for:context:)` is the concrete seam 38-02's
    /// fidelity gate depends on — proves it actually carries the `-code`
    /// suffix for a `.code`-resolved run, matching what a real
    /// `CleanupService.cleanup(context:)` call passes into
    /// `CleanupPrompt.build(context:)` (verified directly against
    /// `CleanupService.cleanup`'s own call in `Shared/Services/CleanupService.swift`).
    func testVersionForContextSeamCarriesCodeSuffixMatchingResolvedContext() {
        let resolved = ContextResolver.resolve(bundleID: "com.apple.Terminal")
        XCTAssertEqual(resolved, .code)
        XCTAssertEqual(CleanupPrompt.version(for: .transcriptionist, context: resolved), "v-transcriptionist-code")
    }
}
