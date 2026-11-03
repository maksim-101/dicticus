import XCTest
@testable import Dicticus

/// Phase 36.5-04 — designed-corpus tests for `BrandMatcher` (the spike-009
/// 16-positive / 20-negative eval corpus, ported verbatim).
///
/// The matcher is built with the EXPLICIT brands.json canonical list (hermetic —
/// independent of the live user dictionary) but the COMPREHENSIVE lexicon loaded
/// from the app bundle (`lexicon-en.txt` / `lexicon-de.txt`), so the precision
/// gate exercises the real guard.
///
/// Two gates:
///   - RECALL: distinctive misheard tokens map to their canonical brand; the
///     hybrid split leaves common-word brand homophones to DictionaryService.
///   - PRECISION (load-bearing): 0 of the 20 adversarial negatives is rewritten
///     (the `could→Claude` failure mode the comprehensive lexicon prevents).
///
/// This file is kept BYTE-IDENTICAL in `macOS/DicticusTests/` and
/// `iOS/DicticusTests/` (cross-platform parity).
@MainActor
final class BrandMatcherTests: XCTestCase {

    /// brands.json: 30 distinct live-dictionary replacement targets + 6 public
    /// brands the audit found unfixed. Injected explicitly for hermeticity.
    static let canonicals: [String] = [
        "Antigravity CLI", "Aqara", "Cellguard", "Claude", "Claude Code", "Claude Desktop",
        "Dicticus", "Dockge", "Dokku", "GSD", "Gemini", "Gemma", "Govee", "LiteLLM",
        "MacWhisper", "MedWiki", "Moleido", "NGINX", "Ollama", "Reolink", "Swissfolio",
        "Swissquote", "TabularisDB", "Tailscale", "TrueNAS", "Xcode", "Zed", "Zigbee",
        "MüraX", "Andrej Karpathy",
        "Sonnet", "Tauri", "SwiftBar", "Vercel", "Opus", "Antigravity"
    ]

    private func makeMatcher() -> BrandMatcher {
        BrandMatcher.bundledLexiconMatcher(canonicals: BrandMatcherTests.canonicals)
    }

    /// Same NFC-preserving normalization the matcher uses, for substring checks.
    private func norm(_ s: String) -> String {
        let lowered = s.lowercased().precomposedStringWithCanonicalMapping
        return String(lowered.filter {
            ("a"..."z").contains($0) || ("0"..."9").contains($0) || "äöüß".contains($0)
        })
    }

    // MARK: - Comprehensive lexicon actually loaded

    func testLexiconLoadedFromBundle() {
        // If the bundle resources were missing the precision gate would pass
        // vacuously (empty guard still blocks nothing distinctive). Prove the
        // comprehensive guard is present by confirming a common word survives in
        // a context that would otherwise fuzzy-match a brand.
        let bm = makeMatcher()
        XCTAssertEqual(bm.apply(to: "please review the code", language: "en"),
                       "please review the code")
    }

    // MARK: - RECALL (distinctive positives → canonical)

    func testRecallDistinctivePositives() {
        let bm = makeMatcher()
        XCTAssertEqual(bm.apply(to: "Sonat", language: "en"), "Sonnet")       // p03
        XCTAssertEqual(bm.apply(to: "Towry", language: "en"), "Tauri")        // p05
        XCTAssertEqual(bm.apply(to: "Mollaido", language: "en"), "Moleido")   // p08
        XCTAssertEqual(bm.apply(to: "Molido", language: "en"), "Moleido")     // p09
        XCTAssertEqual(bm.apply(to: "Versal", language: "en"), "Vercel")      // p14
        XCTAssertEqual(bm.apply(to: "Dicticos", language: "en"), "Dicticus")  // p15
        XCTAssertEqual(bm.apply(to: "Dicticous", language: "en"), "Dicticus") // p16
        XCTAssertEqual(bm.apply(to: "Swift bar", language: "en"), "SwiftBar") // p06 near-exact compound
    }

    /// Recall floor over the full positive set. The matcher (distinctive tokens
    /// only) recovers ≥ 8 of 16; the remaining positives are common-word brands
    /// (hybrid: DictionaryService) or out-of-canonical/≤3-char (designed misses).
    func testRecallFloorOverDesignedPositives() {
        let bm = makeMatcher()
        let positives: [(id: String, token: String, expect: String, lang: String)] = [
            ("p01", "the Gravity", "Antigravity", "en"),
            ("p02", "Gravity CLI", "Antigravity CLI", "en"),
            ("p03", "Sonat", "Sonnet", "en"),
            ("p04", "Towery", "Tauri", "en"),
            ("p05", "Towry", "Tauri", "en"),
            ("p06", "Swift bar", "SwiftBar", "en"),
            ("p07", "GoV", "Govee", "en"),
            ("p08", "Mollaido", "Moleido", "en"),
            ("p09", "Molido", "Moleido", "en"),
            ("p10", "querverleich", "Quervergleich", "de"),
            ("p11", "clot code", "Claude Code", "en"),
            ("p12", "cloud code", "Claude Code", "en"),
            ("p13", "clawed code", "Claude Code", "en"),
            ("p14", "Versal", "Vercel", "en"),
            ("p15", "Dicticos", "Dicticus", "en"),
            ("p16", "Dicticous", "Dicticus", "en")
        ]
        var hits = 0
        for c in positives {
            let got = bm.apply(to: c.token, language: c.lang)
            if got != c.token && norm(got).contains(norm(c.expect)) { hits += 1 }
        }
        XCTAssertGreaterThanOrEqual(hits, 8, "matcher recall floor on designed positives")
    }

    // MARK: - Hybrid split (common-word brands stay with DictionaryService)

    func testHybridSplitLeavesCommonWordBrandsUntouched() {
        let bm = makeMatcher()
        // These are real positives (the Gravity→Antigravity, *code→Claude Code)
        // but contain only common words — the matcher MUST NOT rewrite them; they
        // are recovered by DictionaryService anchored exact entries.
        XCTAssertEqual(bm.apply(to: "the Gravity", language: "en"), "the Gravity")
        XCTAssertEqual(bm.apply(to: "Gravity CLI", language: "en"), "Gravity CLI")
        XCTAssertEqual(bm.apply(to: "clot code", language: "en"), "clot code")
        XCTAssertEqual(bm.apply(to: "cloud code", language: "en"), "cloud code")
        XCTAssertEqual(bm.apply(to: "clawed code", language: "en"), "clawed code")
    }

    func testShortTokenNeverFires() {
        // GoV is 3 normalized chars — below the distinctiveness floor.
        XCTAssertEqual(makeMatcher().apply(to: "GoV", language: "en"), "GoV")
    }

    // MARK: - PRECISION (0 / 20 — the load-bearing gate)

    func testPrecisionDesignedNegatives() {
        let bm = makeMatcher()
        let negatives: [(id: String, token: String, context: String, lang: String)] = [
            ("n01", "gravity", "the gravity of the situation was clear", "en"),
            ("n02", "gravity", "objects fall due to gravity", "en"),
            ("n03", "set", "let's set up the meeting for tomorrow", "en"),
            ("n04", "set", "a complete chess set", "en"),
            ("n05", "set", "set the table please", "en"),
            ("n06", "tower", "the tower of London", "en"),
            ("n07", "tower", "the cell tower lost signal", "en"),
            ("n08", "swift", "a swift response is needed", "en"),
            ("n09", "swift", "the swift flew past", "en"),
            ("n10", "cloud", "cloud computing is everywhere", "en"),
            ("n11", "cloud", "upload it to cloud storage", "en"),
            ("n12", "cloud", "files synced to iCloud", "en"),
            ("n13", "bar", "the bar was crowded that night", "en"),
            ("n14", "sent", "he was sent home early", "en"),
            ("n15", "code", "please review the code", "en"),
            ("n16", "opus", "a magnum opus of literature", "en"),
            ("n17", "vergleich", "ein Vergleich zwischen zwei Optionen", "de"),
            ("n18", "satz", "der erste Satz war klar", "de"),
            ("n19", "gemini", "born under the gemini star sign", "en"),
            ("n20", "claude", "the author claude levi-strauss", "en")
        ]
        var falsePositives: [String] = []
        for c in negatives {
            let got = bm.apply(to: c.context, language: c.lang)
            // FALSE-POS = the protected token was rewritten (no longer present).
            if !norm(got).contains(norm(c.token)) {
                falsePositives.append("\(c.id):\(c.token) → '\(got)'")
            }
        }
        XCTAssertTrue(falsePositives.isEmpty,
                      "Designed-negative false positives (must be 0/20): \(falsePositives)")
    }

    // MARK: - Invariants

    func testIdempotent() {
        let bm = makeMatcher()
        let once = bm.apply(to: "Sonat ist gut", language: "en")
        XCTAssertEqual(once, "Sonnet ist gut")
        XCTAssertEqual(bm.apply(to: once, language: "en"), once)
    }

    func testGermanCommonWordUntouched() {
        let bm = makeMatcher()
        XCTAssertEqual(bm.apply(to: "ein Vergleich zwischen zwei Optionen", language: "de"),
                       "ein Vergleich zwischen zwei Optionen")
        XCTAssertEqual(bm.apply(to: "der erste Satz war klar", language: "de"),
                       "der erste Satz war klar")
    }

    func testEmptyAndNoMatchReturnsUnchanged() {
        let bm = makeMatcher()
        XCTAssertEqual(bm.apply(to: "", language: "en"), "")
        XCTAssertEqual(bm.apply(to: "the quick brown fox", language: "en"),
                       "the quick brown fox")
    }

    // MARK: - Symbol-stripped near-exact hole (260724-iw4)
    //
    // "C++"/"C#" normalize (strip [^a-z0-9äöüß]) to a bare single letter
    // ("c"). A canonical pool containing such an entry let a short input
    // token ("C") score jw=1.0/dl=0 against the stub and bypass the
    // `minDistinctiveChars` gate via the `nearExact` window-admission path
    // — corrupting "how do I get from A to C" into "...A to C++". The fix
    // additionally requires the near-exact window itself to clear
    // `minDistinctiveChars` after normalization.

    private func makeMatcherWithCPlusPlus() -> BrandMatcher {
        BrandMatcher.bundledLexiconMatcher(canonicals: BrandMatcherTests.canonicals + ["C++", "C#"])
    }

    func testShortLetterNeverRewrittenToSymbolSuffixedCanonical() {
        let bm = makeMatcherWithCPlusPlus()
        XCTAssertEqual(bm.apply(to: "how do I get from A to C", language: "en"),
                       "how do I get from A to C")
        XCTAssertEqual(bm.apply(to: "how do I get from A to C.", language: "en"),
                       "how do I get from A to C.")
        XCTAssertEqual(bm.apply(to: "how do I get from A to c", language: "en"),
                       "how do I get from A to c")
    }

    func testShortLetterNeverRewrittenToCSharpCanonical() {
        let bm = makeMatcherWithCPlusPlus()
        XCTAssertEqual(bm.apply(to: "how do I get from A to C", language: "en"),
                       "how do I get from A to C")
    }

    /// Adversarial positive (36.5 suite, p06): a real near-exact COMPOUND
    /// admission — "Swift bar" → SwiftBar (normalized window length 8) —
    /// must still fire after the `minDistinctiveChars` guard is added to
    /// the near-exact path.
    func testNearExactCompoundStillRewritesAfterFix() {
        let bm = makeMatcherWithCPlusPlus()
        XCTAssertEqual(bm.apply(to: "Swift bar", language: "en"), "SwiftBar")
    }

    // MARK: - Sonnet-5 digit-drop guard (debug session sonnet5-digit-drop-itn)
    //
    // `normalize()` strips whitespace but KEEPS digit characters, so a 2-word
    // window like "Sonnet 5" normalized to "sonnet5" — scoring jw≈0.97/dl=1
    // against canonical "Sonnet", clearing both the near-exact and
    // strong-ortho accept gates and silently eating the trailing digit
    // ("Sonnet 5" -> "Sonnet", "opus 5" -> "Opus", "Gemma 4" -> "Gemma").
    // No canonical brand contains digits, so a bare-numeric token can never
    // legitimately be part of a real brand-name correction; the fix rejects
    // any fuzzy-match window containing one outright. Exact-string
    // regression against the live-log evidence strings (debug file Evidence
    // section) plus adversarial positives that must keep their digits.

    func testDigitDropRegressionExactEvidenceStrings() {
        let bm = makeMatcher()
        XCTAssertEqual(bm.apply(to: "Sonnet 5", language: "en"), "Sonnet 5")
        XCTAssertEqual(bm.apply(to: "Sonnet 5", language: "de"), "Sonnet 5")
        XCTAssertEqual(bm.apply(to: "opus 5", language: "en"), "opus 5")
        XCTAssertEqual(bm.apply(to: "dictating Sonnet 5 but", language: "en"),
                       "dictating Sonnet 5 but")
        XCTAssertEqual(
            bm.apply(to: "dropping the 5 in Sonnet 5. I'm clearly", language: "en"),
            "dropping the 5 in Sonnet 5. I'm clearly")
    }

    /// Adversarial positives (fix constraints): a canonical-matching brand
    /// followed by a digit ("Gemma 4") must keep its digit exactly like a
    /// non-canonical brand followed by a digit ("Fable 5" — "Fable" is not
    /// in canonical-brands.txt, so it was never at risk, but both must
    /// round-trip unchanged).
    func testDigitDropAdversarialPositivesKeepDigits() {
        let bm = makeMatcher()
        XCTAssertEqual(bm.apply(to: "Gemma 4", language: "en"), "Gemma 4")
        XCTAssertEqual(bm.apply(to: "Fable 5", language: "en"), "Fable 5")
    }

    /// The numeric-window guard must not regress the existing near-exact
    /// compound recall (no digits involved) or the plain single-token
    /// recall positives.
    func testDigitDropGuardDoesNotRegressExistingRecall() {
        let bm = makeMatcher()
        XCTAssertEqual(bm.apply(to: "Swift bar", language: "en"), "SwiftBar")
        XCTAssertEqual(bm.apply(to: "Sonat", language: "en"), "Sonnet")
    }
}
