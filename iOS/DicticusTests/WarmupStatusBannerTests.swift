import XCTest
@testable import Dicticus

@MainActor
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

    // MARK: - Exact copy per stage (46-UI-SPEC.md Copywriting Contract — must not drift silently)
    //
    // Constructs a `WarmupStatusBanner` value directly and reads its `headline`/
    // `bodyText`/`iconName` properties — no rendering, per the plan's "do not attempt
    // to snapshot-render the view" instruction. This is the regression net the
    // coordinator asked for after the loading-stage copy revision (260810 UAT
    // follow-up, candidate A): a future edit that silently reintroduces jargon or
    // drifts from the locked contract fails here, not in a human's read-through.

    private func makeBanner(
        stage: WarmupBannerStage,
        downloadProgress: Double = 0,
        warmupStartedAt: Date? = nil,
        error: String? = nil
    ) -> WarmupStatusBanner {
        WarmupStatusBanner(
            stage: stage,
            downloadProgress: downloadProgress,
            warmupStartedAt: warmupStartedAt,
            error: error,
            onDownloadNow: {},
            onRetry: {}
        )
    }

    func test_copy_downloading_exact() {
        let banner = makeBanner(stage: .downloading)
        XCTAssertEqual(banner.headline, "Downloading speech model\u{2026}")
        XCTAssertEqual(
            banner.bodyText,
            "One-time download, about 626 MB. You can start recording anytime — we'll transcribe once it's ready."
        )
        XCTAssertEqual(banner.iconName, "arrow.down.circle")
    }

    func test_copy_loading_exact() {
        // Candidate A (permission-first) — user-selected 2026-08-10, supersedes the
        // original "Waking up the transcription engine…" jargon-headline copy.
        let banner = makeBanner(stage: .loading)
        XCTAssertEqual(banner.headline, "Go ahead — you can start recording")
        XCTAssertEqual(
            banner.bodyText,
            "Dicticus is getting ready in the background, which takes a few seconds. It'll catch up with what you've said as soon as it's done."
        )
        XCTAssertEqual(banner.iconName, "gearshape.2")
    }

    func test_copy_modelMissing_exact() {
        let banner = makeBanner(stage: .modelMissing)
        XCTAssertEqual(banner.headline, "Speech model not downloaded")
        XCTAssertEqual(banner.bodyText, "Recordings will wait until you download it.")
        XCTAssertEqual(banner.iconName, "tray.and.arrow.down")
    }

    func test_copy_failed_exact_echoesErrorVerbatim() {
        let banner = makeBanner(stage: .failed, error: "Model load failed: The network connection was lost.")
        XCTAssertEqual(banner.headline, "Couldn't load the speech model")
        XCTAssertEqual(banner.bodyText, "Model load failed: The network connection was lost.")
        XCTAssertEqual(banner.iconName, "exclamationmark.triangle.fill")
    }

    func test_copy_failed_nilError_fallsBackToUnknownError() {
        let banner = makeBanner(stage: .failed, error: nil)
        XCTAssertEqual(banner.bodyText, "Unknown error.")
    }
}
