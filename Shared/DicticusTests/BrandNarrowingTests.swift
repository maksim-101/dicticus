import XCTest
@testable import Dicticus

/// Quick task 261008-gb3: four narrowing guards on the fuzzy brand matcher,
/// each anchored on a corruption the 2026-10-08 debug-log audit found
/// (lens B, section 3): record #412 and #461 (WebUI -> eBay), #505 and #507
/// (YAML -> email), #473 (iPadOS -> iPad), #403 (Claude.ai -> Claude AI) and
/// #369 (a misheard dotted name left unrepaired).
///
/// Every matcher here is hermetic: `BrandMatcher.bundledLexiconMatcher` with a
/// fixed canonical list and a fixed live-target provider. Nothing reads
/// `DictionaryService` or UserDefaults. Carrier sentences are invented; the
/// asserted tokens are product names. Every assertion is an exact string.
///
/// Methods ending in `_RED` fail on the start commit of the task; the others
/// are controls that pass before and after.
@MainActor
final class BrandNarrowingTests: XCTestCase {

    private func matcher(bundled: [String] = [], live: [String] = []) -> BrandMatcher {
        let m = BrandMatcher.bundledLexiconMatcher(canonicals: bundled)
        m.liveDictionaryCanonicalProvider = { live }
        return m
    }

    // MARK: - G1: vowel-onset phonetic collisions at distance 3 or more

    func testG1_webUIStaysWithEBayLive_RED() {
        let key = DoubleMetaphone.encode("WebUI")
        XCTAssertEqual(key, DoubleMetaphone.encode("eBay"))
        XCTAssertTrue(key.hasPrefix("A"), "the shared key starts with the vowel-onset code")
        let input = "Open the WebUI for the new dashboard."
        XCTAssertEqual(matcher(live: ["eBay"]).apply(to: input, language: "en"), input)
    }

    func testG1_yamlStaysWithCasedEmailLive_RED() {
        XCTAssertEqual(DoubleMetaphone.encode("YAML"), DoubleMetaphone.encode("Email"))
        XCTAssertEqual(ColognePhonetic.encode("YAML"), ColognePhonetic.encode("Email"))
        XCTAssertTrue(ColognePhonetic.encode("YAML").hasPrefix("0"))
        let en = "Edit the YAML before the deploy."
        XCTAssertEqual(matcher(live: ["Email"]).apply(to: en, language: "en"), en)
        let de = "Bearbeite die YAML vor dem Deploy."
        XCTAssertEqual(matcher(live: ["Email"]).apply(to: de, language: "de"), de)
    }

    func testG1_distance3ControlsStillRepair() {
        let towry = matcher(bundled: ["Tauri"])
            .applyReportingRewrites(to: "Build it with Towry today.", language: "en")
        XCTAssertEqual(towry.output, "Build it with Tauri today.")
        XCTAssertGreaterThanOrEqual(towry.rewrites.first?.dl ?? 0, 3)

        let atacard = matcher(live: ["AdGuardHome"])
            .applyReportingRewrites(to: "Restart Atacard home on the router.", language: "en")
        XCTAssertEqual(atacard.output, "Restart AdGuardHome on the router.")
        XCTAssertGreaterThanOrEqual(atacard.rewrites.first?.dl ?? 0, 3)

        XCTAssertEqual(matcher(bundled: ["Dicticus"]).apply(to: "Try Tiktikus on the laptop.", language: "en"),
                       "Try Dicticus on the laptop.")
        XCTAssertEqual(matcher(bundled: ["Claude"]).apply(to: "Ask CLAWT about the plan.", language: "en"),
                       "Ask Claude about the plan.")
        XCTAssertEqual(matcher(bundled: ["Vercel"]).apply(to: "Deploy it to versile tonight.", language: "en"),
                       "Deploy it to Vercel tonight.")
        XCTAssertEqual(matcher(bundled: ["Claude Code"]).apply(to: "Start ClotCode in the repo.", language: "en"),
                       "Start Claude Code in the repo.")
    }

    // MARK: - G2: an all-lowercase dictionary word is not a brand target

    func testG2_lowercaseLexiconTargetIsNotABrand_RED() {
        let input = "Please send the Emial to the team."
        XCTAssertEqual(matcher(live: ["Email"]).apply(to: input, language: "en"),
                       "Please send the Email to the team.",
                       "precondition: a cased target repairs the near-spelling")
        XCTAssertEqual(matcher(live: ["email"]).apply(to: input, language: "en"), input)
    }

    func testG2_anchorYamlWithLowercaseEmail() {
        let input = "Edit the YAML before the deploy."
        XCTAssertEqual(matcher(live: ["email"]).apply(to: input, language: "en"), input)
    }

    func testG2_casedLexiconTargetKeepsReach() {
        XCTAssertEqual(matcher(live: ["Kagi"]).apply(to: "Try Kagee for the search.", language: "en"),
                       "Try Kagi for the search.")
    }

    // MARK: - G3: a window that spells the whole canonical plus more is not rewritten

    func testG3_iPadOSStaysWithIPadLive_RED() {
        let input = "Update to iPadOS next week."
        XCTAssertEqual(matcher(live: ["iPad"]).apply(to: input, language: "en"), input)
    }

    // MARK: - G4: a dotted name keeps its dot

    func testG4_dottedSurfaceKeptWhenSpacedSiblingLive_RED() {
        let input = "Open Claude.ai in the browser."
        XCTAssertEqual(matcher(live: ["Claude AI", "Claude.ai"]).apply(to: input, language: "en"), input)
    }

    func testG4_lowercaseDottedUnifiesToDottedSibling_RED() {
        XCTAssertEqual(
            matcher(live: ["Claude AI", "Claude.ai", "claude.ai"])
                .apply(to: "Visit claude.ai for the docs.", language: "en"),
            "Visit Claude.ai for the docs.")
    }

    func testG4_misheardDottedRepairsToDottedSibling_RED() {
        XCTAssertEqual(
            matcher(live: ["Claude AI", "Claude.ai"]).apply(to: "Open cloud.ai in the browser.", language: "en"),
            "Open Claude.ai in the browser.")
    }

    func testG4_spacedSurfaceStillReachesSpacedSibling() {
        XCTAssertEqual(
            matcher(live: ["Claude AI", "Claude.ai"]).apply(to: "Open Claude ai in the browser.", language: "en"),
            "Open Claude AI in the browser.")
    }
}
