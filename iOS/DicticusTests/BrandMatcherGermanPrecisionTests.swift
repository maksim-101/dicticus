import XCTest
@testable import Dicticus

/// Phase 36.5-05 / Task 2 — BROAD adversarial GERMAN precision gate for
/// `BrandMatcher` (language "de", Kölner-Phonetik encoder).
///
/// DEVIATION (synthetic-by-necessity — declared): unlike the EN gate (Task 1,
/// `Brand009`), which REPLAYS the matcher over the real debug-log transcript
/// corpus, this German gate uses a SYNTHETIC ≥40-item adversarial corpus. There
/// is no German live/debug-log corpus to replay: live captures skew English
/// because they come from Claude Code sessions (memory
/// `project_usage_pattern_english_dominant`). This is an INTENTIONAL, justified
/// deviation, NOT a coverage gap — German regression suites are the source of
/// truth for German per that memory, and the spike (009) had no German gate at
/// all (its `/usr/share/dict/words` guard was English-only). Where real German
/// records DO exist they are additionally routed through `Brand009` with
/// `language:"de"` under the same subset-of-expected-brands gate (Task 2).
///
/// The corpus is deliberately BROAD (memory
/// `feedback_spike_corpus_adversarial_breadth`: a 7-case corpus once shipped a
/// false "zero-corruption" pass). It covers ordinary German words, compounds, and
/// inflected surface forms that phonetically/orthographically resemble a canonical
/// brand (Sonne↔Sonnet, Turm/Tour↔Tauri, Wolke↔cloud/Claude, Ferse/Versal↔Vercel,
/// Zürich/Züri↔MüraX, Quote↔Swissquote, Tabelle↔TabularisDB, Oper/Opa↔Opus,
/// gemein↔Gemini/Gemma …). Every input MUST be returned unchanged (DE precision:
/// 0 rewrites). The German VALUE of this phase is precision; recall positives are
/// limited to a couple of distinctive non-word sanity checks so the pass is not
/// vacuous.
///
/// Kept BYTE-IDENTICAL in `macOS/DicticusTests/` and `iOS/DicticusTests/`.
@MainActor
final class BrandMatcherGermanPrecisionTests: XCTestCase {

    /// brands.json canonical list (identical to BrandMatcherTests / Brand009 /
    /// scale_test.py CANON). Injected explicitly for hermeticity.
    static let canonicals: [String] = [
        "Antigravity CLI", "Aqara", "Cellguard", "Claude", "Claude Code", "Claude Desktop",
        "Dicticus", "Dockge", "Dokku", "GSD", "Gemini", "Gemma", "Govee", "LiteLLM",
        "MacWhisper", "MedWiki", "Moleido", "NGINX", "Ollama", "Reolink", "Swissfolio",
        "Swissquote", "TabularisDB", "Tailscale", "TrueNAS", "Xcode", "Zed", "Zigbee",
        "MüraX", "Andrej Karpathy",
        "Sonnet", "Tauri", "SwiftBar", "Vercel", "Opus", "Antigravity"
    ]

    private func makeMatcher() -> BrandMatcher {
        BrandMatcher.bundledLexiconMatcher(canonicals: BrandMatcherGermanPrecisionTests.canonicals)
    }

    /// NFC-preserving normalization (matches BrandMatcher.normalize — keeps umlauts).
    private func norm(_ s: String) -> String {
        let lowered = s.lowercased().precomposedStringWithCanonicalMapping
        return String(lowered.filter {
            ("a"..."z").contains($0) || ("0"..."9").contains($0) || "äöüß".contains($0)
        })
    }

    // MARK: - Guard is actually loaded (non-vacuous precision)

    /// If the bundled German lexicon were missing, the precision gate could pass
    /// vacuously. Prove the comprehensive DE guard is present.
    func testGermanLexiconLoadedFromBundle() {
        let bm = makeMatcher()
        XCTAssertEqual(bm.apply(to: "ein Vergleich zwischen zwei Optionen", language: "de"),
                       "ein Vergleich zwischen zwei Optionen")
    }

    // MARK: - PRECISION: single adversarial German words (resemble a brand)

    func testGermanSingleWordNegativesNeverRewritten() {
        let bm = makeMatcher()
        XCTAssertEqual(bm.apply(to: "Sonne", language: "de"), "Sonne")               // ↔Sonnet
        XCTAssertEqual(bm.apply(to: "Sonnenschein", language: "de"), "Sonnenschein") // ↔Sonnet
        XCTAssertEqual(bm.apply(to: "Sonntag", language: "de"), "Sonntag")           // ↔Sonnet
        XCTAssertEqual(bm.apply(to: "Turm", language: "de"), "Turm")                 // ↔Tauri/tower
        XCTAssertEqual(bm.apply(to: "Türme", language: "de"), "Türme")               // ↔Tauri
        XCTAssertEqual(bm.apply(to: "Tour", language: "de"), "Tour")                 // ↔Tauri
        XCTAssertEqual(bm.apply(to: "teuer", language: "de"), "teuer")               // ↔Tauri
        XCTAssertEqual(bm.apply(to: "Wolke", language: "de"), "Wolke")               // ↔cloud/Claude
        XCTAssertEqual(bm.apply(to: "Wolken", language: "de"), "Wolken")             // ↔cloud
        XCTAssertEqual(bm.apply(to: "Ferse", language: "de"), "Ferse")              // ↔Vercel
        XCTAssertEqual(bm.apply(to: "Versalien", language: "de"), "Versalien")       // ↔Vercel
        XCTAssertEqual(bm.apply(to: "Vergebung", language: "de"), "Vergebung")       // ↔Vercel
        XCTAssertEqual(bm.apply(to: "Zürich", language: "de"), "Zürich")             // ↔MüraX
        XCTAssertEqual(bm.apply(to: "Schweiz", language: "de"), "Schweiz")           // ↔Swissquote
        XCTAssertEqual(bm.apply(to: "Quote", language: "de"), "Quote")              // ↔Swissquote
        XCTAssertEqual(bm.apply(to: "Folie", language: "de"), "Folie")              // ↔Swissfolio
        XCTAssertEqual(bm.apply(to: "Tabelle", language: "de"), "Tabelle")          // ↔TabularisDB
        XCTAssertEqual(bm.apply(to: "Tafel", language: "de"), "Tafel")             // ↔TabularisDB
        XCTAssertEqual(bm.apply(to: "Oper", language: "de"), "Oper")               // ↔Opus
        XCTAssertEqual(bm.apply(to: "gemeinsam", language: "de"), "gemeinsam")       // ↔Gemini/Gemma
        XCTAssertEqual(bm.apply(to: "Gemüse", language: "de"), "Gemüse")            // ↔Gemma
        XCTAssertEqual(bm.apply(to: "Region", language: "de"), "Region")           // ↔Reolink
        XCTAssertEqual(bm.apply(to: "Reise", language: "de"), "Reise")            // ↔Reolink
        XCTAssertEqual(bm.apply(to: "Zelle", language: "de"), "Zelle")             // ↔Cellguard
        XCTAssertEqual(bm.apply(to: "Decke", language: "de"), "Decke")            // ↔Dockge/Dokku
        XCTAssertEqual(bm.apply(to: "andocken", language: "de"), "andocken")        // ↔Dockge
        XCTAssertEqual(bm.apply(to: "Schwert", language: "de"), "Schwert")          // ↔Swift
        XCTAssertEqual(bm.apply(to: "Garten", language: "de"), "Garten")
        XCTAssertEqual(bm.apply(to: "Grafik", language: "de"), "Grafik")
        XCTAssertEqual(bm.apply(to: "Quelle", language: "de"), "Quelle")
    }

    // MARK: - PRECISION: inflected forms / compounds

    func testGermanInflectionsAndCompoundsNeverRewritten() {
        let bm = makeMatcher()
        XCTAssertEqual(bm.apply(to: "Quervergleich", language: "de"), "Quervergleich")
        XCTAssertEqual(bm.apply(to: "Vergleiche", language: "de"), "Vergleiche")
        XCTAssertEqual(bm.apply(to: "vergleichen", language: "de"), "vergleichen")
        XCTAssertEqual(bm.apply(to: "Sätze", language: "de"), "Sätze")
        XCTAssertEqual(bm.apply(to: "Satzung", language: "de"), "Satzung")
        XCTAssertEqual(bm.apply(to: "Seiten", language: "de"), "Seiten")
        XCTAssertEqual(bm.apply(to: "Turmuhr", language: "de"), "Turmuhr")
        XCTAssertEqual(bm.apply(to: "Sonnenblume", language: "de"), "Sonnenblume")
        XCTAssertEqual(bm.apply(to: "Wolkenkratzer", language: "de"), "Wolkenkratzer")
        XCTAssertEqual(bm.apply(to: "Tabellenkalkulation", language: "de"), "Tabellenkalkulation")
    }

    // MARK: - PRECISION: full adversarial German sentences (app-faithful)

    func testGermanSentenceNegativesNeverRewritten() {
        let bm = makeMatcher()
        XCTAssertEqual(bm.apply(to: "der erste Satz war klar", language: "de"),
                       "der erste Satz war klar")
        XCTAssertEqual(bm.apply(to: "die Sonne scheint heute hell", language: "de"),
                       "die Sonne scheint heute hell")
        XCTAssertEqual(bm.apply(to: "wir machen eine Tour durch die Stadt", language: "de"),
                       "wir machen eine Tour durch die Stadt")
        XCTAssertEqual(bm.apply(to: "der Turm steht seit dem Mittelalter", language: "de"),
                       "der Turm steht seit dem Mittelalter")
        XCTAssertEqual(bm.apply(to: "eine Wolke zog über den Himmel", language: "de"),
                       "eine Wolke zog über den Himmel")
        XCTAssertEqual(bm.apply(to: "ich wohne seit Jahren in Zürich", language: "de"),
                       "ich wohne seit Jahren in Zürich")
        XCTAssertEqual(bm.apply(to: "die Quote der Schweiz ist hoch", language: "de"),
                       "die Quote der Schweiz ist hoch")
        XCTAssertEqual(bm.apply(to: "wir brauchen einen Quervergleich der Optionen", language: "de"),
                       "wir brauchen einen Quervergleich der Optionen")
        XCTAssertEqual(bm.apply(to: "die Tabelle zeigt alle Werte", language: "de"),
                       "die Tabelle zeigt alle Werte")
        XCTAssertEqual(bm.apply(to: "das war ein teurer Garten", language: "de"),
                       "das war ein teurer Garten")
    }

    // MARK: - Non-vacuity: distinctive non-word German positives still recover

    /// A handful of distinctive (non-word) brand mishearings must still recover in
    /// a German context — proves the gate is not vacuously returning everything
    /// unchanged. These are distinctive tokens, never common German words.
    func testGermanDistinctivePositivesStillRecover() {
        let bm = makeMatcher()
        XCTAssertEqual(bm.apply(to: "ich nutze Sonat täglich", language: "de"),
                       "ich nutze Sonnet täglich")
        XCTAssertEqual(bm.apply(to: "wir testen Dicticos heute", language: "de"),
                       "wir testen Dicticus heute")
    }
}
