import XCTest
@testable import Dicticus

/// Quick task 260830-fm2 — regression guard for the fuzzy brand matcher
/// rewriting a correctly-transcribed short acronym into an unrelated brand.
///
/// Live evidence (2026-08-30, `cleanup-2026-08-30.jsonl`):
/// `brand_rewrites: {'from': 'as BCAA.', 'to': 'USB-C', 'dl': 3, 'jw': 0.75}`.
/// The user said BCAA (branched-chain amino acids, a supplements context);
/// the matcher rewrote it to USB-C.
///
/// ROOT CAUSE (traced, not assumed): the accepted window is the 2-TOKEN
/// span "as BCAA.", not bare "BCAA" alone. Normalized+joined it is "asbcaa"
/// (6 chars), scored against canonical "USB-C" ("usbc", 4 chars) at
/// dl=3/jw=0.75 — exactly the logged values. Bare "bcaa" alone against
/// "usbc" scores dl=4/jw=0.0, which ALREADY fails every accept threshold in
/// `BrandMatcher.matchToken` — the single-token path was never the hole.
/// The 2-token window is only reachable because "as" (a preposition) is
/// NOT a member of `BrandMatcher.functionWordWindowGuardSet` (which unions
/// `FunctionWords`' pronoun + D-02 substitution sets, and those sets carry
/// no plain prepositions like "as"/"than"/"like" — see `FunctionWords.swift`,
/// which is scoped to EditGuard's insertion/substitution semantics, not
/// brand-window admission). The 2026-08-25 guard-A fix covered pronouns
/// ("IP and" -> "iPad"); this is the same class with a different word.
///
/// "USB-C" is NOT in the bundled `Shared/Resources/canonical-brands.txt` —
/// it is user-dictionary-only data this repo cannot see. Injected explicitly
/// here for a hermetic repro, mirroring the existing "C++"/"C#" injection
/// pattern in `BrandMatcherTests.testShortLetterNeverRewrittenToSymbolSuffixedCanonical`.
///
/// Kept BYTE-IDENTICAL in `macOS/DicticusTests/` and `iOS/DicticusTests/`.
@MainActor
final class BrandMatcherShortAcronymGuardTests: XCTestCase {

    private func makeMatcherWithUSBC() -> BrandMatcher {
        BrandMatcher.bundledLexiconMatcher(canonicals: BrandMatcherTests.canonicals + ["USB-C"])
    }

    private func makeMatcher() -> BrandMatcher {
        BrandMatcher.bundledLexiconMatcher(canonicals: BrandMatcherTests.canonicals)
    }

    // MARK: - Exact evidence regression (2026-08-30 debug log)

    func testFullEvidenceSentenceNeverRewritesBCAA() {
        let bm = makeMatcherWithUSBC()
        // The log's `post_swiss_num` shows the already-corrupted "...as USB-C."
        // — this is the RAW pre-corruption input the user actually said.
        let raw = "I want you to do a deep dive into creatine, L-carnitine, as BCAA."
        XCTAssertEqual(bm.apply(to: raw, language: "en"), raw)
    }

    func testBareAsBCAANeverRewritten() {
        let bm = makeMatcherWithUSBC()
        XCTAssertEqual(bm.apply(to: "as BCAA.", language: "en"), "as BCAA.")
    }

    func testBareBCAAAloneNeverRewritten() {
        // Already safe pre-fix (dl=4 exceeds every threshold) — pinned as a
        // non-regression control, not a repro of the bug itself.
        let bm = makeMatcherWithUSBC()
        XCTAssertEqual(bm.apply(to: "BCAA", language: "en"), "BCAA")
    }

    // MARK: - Adversarial breadth: other preposition/conjunction windows

    func testOtherFunctionWordWindowsAroundBCAANeverRewritten() {
        let bm = makeMatcherWithUSBC()
        let sentences = [
            "so BCAA.",
            "like BCAA.",
            "than BCAA.",
        ]
        for s in sentences {
            XCTAssertEqual(bm.apply(to: s, language: "en"), s, "false positive on: \(s)")
        }
    }

    // MARK: - Adversarial breadth: other short acronyms, same window shape

    func testOtherShortAcronymsWithAsPrefixNeverRewritten() {
        let bm = makeMatcherWithUSBC()
        let sentences = [
            "as ATM.",
            "as SQL.",
            "as RAM.",
            "as GPU.",
        ]
        for s in sentences {
            XCTAssertEqual(bm.apply(to: s, language: "en"), s, "false positive on: \(s)")
        }
    }

    // MARK: - German: "als" is already in FunctionWords.germanInsertable —
    // pinned as a non-regression control proving the DE side never had this
    // hole (no fix needed there).

    func testGermanAlsWindowAlreadySafe() {
        let bm = makeMatcherWithUSBC()
        let s = "als BCAA."
        XCTAssertEqual(bm.apply(to: s, language: "de"), s)
    }

    // MARK: - Co-occurring-trigger context gate (change 2)
    //
    // "Opus" is the shortest bundled canonical reachable via the orthoOk
    // path independent of `minDistinctiveChars` (that gate only checks
    // canonical length inside `phonOk`). "Oppus" clears orthoOk unconditionally
    // (jw≈0.947 >= strongOrthoThreshold 0.93, dl=1) so this isolates the new
    // context gate from the phonetic-encoder guesswork the other tests avoid.

    func testShortCanonicalNeverFiresWithoutTrigger() {
        let bm = makeMatcher()
        XCTAssertEqual(bm.apply(to: "Oppus", language: "en"), "Oppus")
        XCTAssertEqual(bm.apply(to: "I really enjoy this Oppus", language: "en"),
                       "I really enjoy this Oppus")
    }

    func testShortCanonicalFiresWithCoOccurringTrigger() {
        let bm = makeMatcher()
        XCTAssertEqual(bm.apply(to: "the new Oppus model is impressive", language: "en"),
                       "the new Opus model is impressive")
        XCTAssertEqual(bm.apply(to: "I asked Claude using the Oppus variant", language: "en"),
                       "I asked Claude using the Opus variant")
    }

    // MARK: - Accept-controls (must still pass after the fix — precision-only change)

    func testKnownTruePositivesStillRecoverAfterFix() {
        let bm = makeMatcherWithUSBC()
        XCTAssertEqual(bm.apply(to: "Sonat", language: "en"), "Sonnet")
        XCTAssertEqual(bm.apply(to: "Towry", language: "en"), "Tauri")
        XCTAssertEqual(bm.apply(to: "Versal", language: "en"), "Vercel")
        XCTAssertEqual(bm.apply(to: "Dicticos", language: "en"), "Dicticus")
        XCTAssertEqual(bm.apply(to: "Dicticous", language: "en"), "Dicticus")
        XCTAssertEqual(bm.apply(to: "Molido", language: "en"), "Moleido")
        XCTAssertEqual(bm.apply(to: "Swift bar", language: "en"), "SwiftBar")
        XCTAssertEqual(bm.apply(to: "ich nutze Sonat täglich", language: "de"),
                       "ich nutze Sonnet täglich")
    }
}
