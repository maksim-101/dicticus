import XCTest
@testable import Dicticus

/// Live Activity tap-through deep link (`dicticus://liveactivity`) — user-
/// requested fix so tapping the Live Activity always opens Dicticus on the
/// Dictate tab, regardless of which tab was previously selected, cold launch
/// or foreground alike. See DeepLinkRouter's doc comment and
/// 46-LIVEACTIVITY-REDESIGN.md for the full design rationale.
///
/// `DeepLinkRouter` is a singleton (`.shared`) so these tests assert on the
/// *delta* produced by each call rather than an absolute count, keeping tests
/// independent of run order / prior test pollution of the shared instance.
@MainActor
final class DeepLinkRouterTests: XCTestCase {

    func testHandleLiveActivityTap_RecognizesLiveActivityURL() {
        let router = DeepLinkRouter.shared
        let before = router.dictateTabRequestCount
        let url = URL(string: "dicticus://liveactivity")!

        let recognized = router.handleLiveActivityTap(url)

        XCTAssertTrue(recognized, "dicticus://liveactivity must be recognized as the Live Activity tap-through link")
        XCTAssertEqual(router.dictateTabRequestCount, before + 1,
            "Recognizing the Live Activity link must bump dictateTabRequestCount so ContentView force-selects the Dictate tab")
    }

    /// Critical boundary: the navigation-only link must never be confused
    /// with `dicticus://dictate`, which starts a NEW recording via
    /// pendingDictation (WR-03). Conflating the two would either (a) fail to
    /// navigate on a genuine Live Activity tap, or worse (b) make a Live
    /// Activity tap spontaneously start a recording — exactly the class of
    /// bug the pendingDictationSetAt staleness guard (0a18fb2) exists to
    /// prevent.
    func testHandleLiveActivityTap_DoesNotRecognizeStartDictationURL() {
        let router = DeepLinkRouter.shared
        let before = router.dictateTabRequestCount
        let url = URL(string: "dicticus://dictate")!

        let recognized = router.handleLiveActivityTap(url)

        XCTAssertFalse(recognized, "dicticus://dictate must NOT be treated as the Live Activity navigation link")
        XCTAssertEqual(router.dictateTabRequestCount, before,
            "dicticus://dictate must not bump dictateTabRequestCount — that path never touches DeepLinkRouter")
    }

    func testHandleLiveActivityTap_IgnoresUnrelatedScheme() {
        let router = DeepLinkRouter.shared
        let before = router.dictateTabRequestCount
        let url = URL(string: "https://example.com/liveactivity")!

        let recognized = router.handleLiveActivityTap(url)

        XCTAssertFalse(recognized)
        XCTAssertEqual(router.dictateTabRequestCount, before)
    }

    func testHandleLiveActivityTap_IgnoresUnrelatedHost() {
        let router = DeepLinkRouter.shared
        let before = router.dictateTabRequestCount
        let url = URL(string: "dicticus://someotherhost")!

        let recognized = router.handleLiveActivityTap(url)

        XCTAssertFalse(recognized)
        XCTAssertEqual(router.dictateTabRequestCount, before)
    }

    /// Repeated taps must each register — e.g. tapping the activity twice in
    /// a row (once while backgrounded producing a foreground event, again
    /// later) must force the tab both times, not just the first.
    func testHandleLiveActivityTap_RepeatedTapsEachIncrementCount() {
        let router = DeepLinkRouter.shared
        let before = router.dictateTabRequestCount
        let url = URL(string: "dicticus://liveactivity")!

        router.handleLiveActivityTap(url)
        router.handleLiveActivityTap(url)

        XCTAssertEqual(router.dictateTabRequestCount, before + 2)
    }
}
