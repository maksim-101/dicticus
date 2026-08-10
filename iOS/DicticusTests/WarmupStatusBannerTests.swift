import XCTest
@testable import Dicticus

final class WarmupStatusBannerTests: XCTestCase {

    // MARK: - Named behavior tests (per 46-04-PLAN.md <behavior>)

    func test_modelReady_notWarming_noError_returnsNil() {
        XCTAssertNil(WarmupBannerStage.resolve(hasModels: true, isWarming: false, isReady: true, error: nil))
    }

    func test_warming_withoutModelsOnDisk_isDownloading() {
        XCTAssertEqual(
            WarmupBannerStage.resolve(hasModels: false, isWarming: true, isReady: false, error: nil),
            .downloading
        )
    }

    func test_warming_withModelsOnDisk_isLoading() {
        XCTAssertEqual(
            WarmupBannerStage.resolve(hasModels: true, isWarming: true, isReady: false, error: nil),
            .loading
        )
    }

    func test_errorPresent_notWarming_isFailed_regardlessOfOtherFlags() {
        // Error + not warming must win over hasModels/isReady in every combination.
        XCTAssertEqual(
            WarmupBannerStage.resolve(hasModels: false, isWarming: false, isReady: false, error: "boom"),
            .failed
        )
        XCTAssertEqual(
            WarmupBannerStage.resolve(hasModels: true, isWarming: false, isReady: false, error: "boom"),
            .failed
        )
        XCTAssertEqual(
            WarmupBannerStage.resolve(hasModels: true, isWarming: false, isReady: true, error: "boom"),
            .failed
        )
        XCTAssertEqual(
            WarmupBannerStage.resolve(hasModels: false, isWarming: false, isReady: true, error: "boom"),
            .failed
        )
    }

    func test_noModelOnDisk_notWarming_notReady_noError_isModelMissing() {
        XCTAssertEqual(
            WarmupBannerStage.resolve(hasModels: false, isWarming: false, isReady: false, error: nil),
            .modelMissing
        )
    }

    // MARK: - Explicit regression guards (per PLAN's "two flag combinations most likely to regress")

    func test_regression_readyPlusStaleError_isFailedNotNil() {
        // A stale error string left over from a prior failed attempt must not be
        // masked by isReady flipping true on a later successful retry's stage read —
        // but per the resolve() contract itself, isReady never coexists with a
        // non-nil error in practice (retry() clears error before warmup(); success
        // clears isReady=false only via a fresh warmup cycle). This guards the pure
        // function's contract in isolation, independent of how the service happens
        // to sequence its own state today.
        XCTAssertEqual(
            WarmupBannerStage.resolve(hasModels: true, isWarming: false, isReady: true, error: "stale error"),
            .failed
        )
    }

    func test_regression_warmingWithErrorStillSet_isNotFailed() {
        // A stale error field must never leak a "failed" banner while a fresh
        // warm-up is genuinely in progress — isWarming always wins over a lingering
        // error string.
        XCTAssertEqual(
            WarmupBannerStage.resolve(hasModels: false, isWarming: true, isReady: false, error: "stale error"),
            .downloading
        )
        XCTAssertEqual(
            WarmupBannerStage.resolve(hasModels: true, isWarming: true, isReady: false, error: "stale error"),
            .loading
        )
    }

    // MARK: - Transient/unspecified state

    func test_hasModelsTrue_notWarmingYet_notReady_noError_returnsNil() {
        // The brief window before warmup() has been called on a launch where the
        // model is already cached — nothing to show yet, not a modelMissing state
        // (the model IS on disk).
        XCTAssertNil(
            WarmupBannerStage.resolve(hasModels: true, isWarming: false, isReady: false, error: nil)
        )
    }

    // MARK: - Full truth table (all 16 combinations of the 4 boolean-shaped inputs)

    func test_fullTruthTable_allSixteenCombinations() {
        struct Case {
            let hasModels: Bool
            let isWarming: Bool
            let isReady: Bool
            let error: String?
            let expected: WarmupBannerStage?
            let line: UInt
        }

        let cases: [Case] = [
            // hasModels, isWarming, isReady, error -> expected
            Case(hasModels: false, isWarming: false, isReady: false, error: nil, expected: .modelMissing, line: #line),
            Case(hasModels: false, isWarming: false, isReady: false, error: "e", expected: .failed, line: #line),
            Case(hasModels: false, isWarming: false, isReady: true, error: nil, expected: nil, line: #line),
            Case(hasModels: false, isWarming: false, isReady: true, error: "e", expected: .failed, line: #line),
            Case(hasModels: false, isWarming: true, isReady: false, error: nil, expected: .downloading, line: #line),
            Case(hasModels: false, isWarming: true, isReady: false, error: "e", expected: .downloading, line: #line),
            Case(hasModels: false, isWarming: true, isReady: true, error: nil, expected: .downloading, line: #line),
            Case(hasModels: false, isWarming: true, isReady: true, error: "e", expected: .downloading, line: #line),
            Case(hasModels: true, isWarming: false, isReady: false, error: nil, expected: nil, line: #line),
            Case(hasModels: true, isWarming: false, isReady: false, error: "e", expected: .failed, line: #line),
            Case(hasModels: true, isWarming: false, isReady: true, error: nil, expected: nil, line: #line),
            Case(hasModels: true, isWarming: false, isReady: true, error: "e", expected: .failed, line: #line),
            Case(hasModels: true, isWarming: true, isReady: false, error: nil, expected: .loading, line: #line),
            Case(hasModels: true, isWarming: true, isReady: false, error: "e", expected: .loading, line: #line),
            Case(hasModels: true, isWarming: true, isReady: true, error: nil, expected: .loading, line: #line),
            Case(hasModels: true, isWarming: true, isReady: true, error: "e", expected: .loading, line: #line),
        ]

        XCTAssertEqual(cases.count, 16, "truth table must cover all 2^4 combinations")

        for c in cases {
            let actual = WarmupBannerStage.resolve(
                hasModels: c.hasModels, isWarming: c.isWarming, isReady: c.isReady, error: c.error
            )
            XCTAssertEqual(
                actual, c.expected,
                "hasModels=\(c.hasModels) isWarming=\(c.isWarming) isReady=\(c.isReady) error=\(c.error ?? "nil")",
                line: c.line
            )
        }
    }
}
