import XCTest
@testable import Dicticus

/// Quick task 261002-6oi: the brand matcher's candidate order came from the
/// live-dictionary provider, which hands targets over in hash-seeded Swift
/// Dictionary order (found in 260930-s1d). Two spellings of one brand that
/// differ only in case, a space or a dot therefore resolved differently from
/// one process to the next.
///
/// Documented order (BrandMatcher.resolvedCanonicals): bundled canonicals in
/// their given order, then live-dictionary targets by Swift String `<`.
/// Each pair below shares every letter and digit, so the matcher scores both
/// members identically by construction; the equal-score preconditions assert
/// that (the phonetic key is computed from letters only, so it is identical
/// too). Talvoro is an invented stand-in and every carrier sentence is
/// invented; no dictation text is quoted. Uses the REAL bundled lexicon via
/// `BrandMatcher.bundledLexiconMatcher`; every assertion is an exact string.
@MainActor
final class BrandTieBreakDeterminismTests: XCTestCase {

    private func matcher(bundled: [String], live: [String]) -> BrandMatcher {
        let m = BrandMatcher.bundledLexiconMatcher(canonicals: bundled)
        m.liveDictionaryCanonicalProvider = { live }
        return m
    }

    /// Both members must report exactly one rewrite with identical scores
    /// when each is the only candidate.
    private func assertEqualScore(_ a: String, _ b: String, input: String,
                                  file: StaticString = #filePath, line: UInt = #line) {
        let ra = matcher(bundled: [], live: [a]).applyReportingRewrites(to: input, language: "en").rewrites
        let rb = matcher(bundled: [], live: [b]).applyReportingRewrites(to: input, language: "en").rewrites
        XCTAssertEqual(ra.count, 1, "\(a) must rewrite once", file: file, line: line)
        XCTAssertEqual(rb.count, 1, "\(b) must rewrite once", file: file, line: line)
        guard let x = ra.first, let y = rb.first else { return }
        XCTAssertEqual(x.jw, y.jw, file: file, line: line)
        XCTAssertEqual(x.dl, y.dl, file: file, line: line)
    }

    // MARK: - T1: equal-score tie (space variant)

    func testT1SpacingPairResolvesTheSameInBothProviderOrders() {
        let input = "Restart the Talvoro hub tonight."
        let expected = "Restart the Talvoro Hub tonight."
        assertEqualScore("TalvoroHub", "Talvoro Hub", input: input)
        XCTAssertEqual(
            matcher(bundled: [], live: ["TalvoroHub", "Talvoro Hub"]).apply(to: input, language: "en"),
            expected, "order: TalvoroHub first")
        XCTAssertEqual(
            matcher(bundled: [], live: ["Talvoro Hub", "TalvoroHub"]).apply(to: input, language: "en"),
            expected, "order: Talvoro Hub first")
    }

    // MARK: - T2: case variants collapse in dedupe

    func testT2CasePairResolvesTheSameInBothProviderOrders() {
        let input = "Open talvoro.io in the browser."
        let expected = "Open Talvoro.io in the browser."
        assertEqualScore("talvoro.io", "Talvoro.io", input: input)
        XCTAssertEqual(
            matcher(bundled: [], live: ["talvoro.io", "Talvoro.io"]).apply(to: input, language: "en"),
            expected, "order: talvoro.io first")
        XCTAssertEqual(
            matcher(bundled: [], live: ["Talvoro.io", "talvoro.io"]).apply(to: input, language: "en"),
            expected, "order: Talvoro.io first")
    }

    // MARK: - T3: bundled canonicals outrank live targets

    func testT3BundledCanonicalOutranksLiveTarget() {
        let input = "Ask talvoro about it."
        let expected = "Ask Talvoro about it."
        XCTAssertEqual(
            matcher(bundled: ["Talvoro"], live: [".talvoro"]).apply(to: input, language: "en"),
            expected, "bundled first, live dotted variant")
        XCTAssertEqual(
            matcher(bundled: ["Talvoro"], live: [".talvoro", "talvoro"]).apply(to: input, language: "en"),
            expected, "bundled first, live variants")
    }
}
