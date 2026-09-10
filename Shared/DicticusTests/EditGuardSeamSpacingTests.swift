import XCTest
@testable import Dicticus

/// EDITGUARD-01: regression net for `deriveSeamSpacing`, the seam-derived
/// spacing renderer that replaced `trailingFor`'s forced-space bridge and
/// `bindPunctuationLeft`. See `.planning/todos/pending/editguard-stray-space-before-surviving-emdash.md`
/// (folded into Phase 49.5) for the traced mechanism this fixes.
@MainActor
final class EditGuardSeamSpacingTests: XCTestCase {

    private func guardOut(_ baseline: String, _ llm: String, _ lang: String = "en") -> String {
        EditGuard.apply(rulesCleaned: baseline, llmOutput: llm, language: lang, lexicon: TestSpellLexicon.allKnown).text
    }

    /// The folded todo's exact record (same baseline/candidate as
    /// `EditGuardDanglingPunctuationTests.testNoCommaDashAdjacency_governmentLevels_2026_08_24`):
    /// baseline has a trailing comma after "municipal", candidate drops it in
    /// favor of an em-dash. Before this fix, `trailingFor`'s forced-space
    /// bridge stranded a space in front of the surviving em-dash
    /// ("municipal —as") — a sequence in NEITHER input. `deriveSeamSpacing`
    /// derives that seam from the candidate's own (glued) adjacency instead.
    func testNoStraySpaceBeforeSurvivingEmDash_2026_08_24() {
        let baseline = "please look for news from this year and if possible as recently as possible about failed or delayed projects either in government in Switzerland on either of the three levels of government, meaning federal, cantonal and municipal, as well as from the social sector."
        let candidate = "Please look for news from this year, as recently as possible, about failed or delayed projects in the government in Switzerland at either of the three levels of government—federal, cantonal, and municipal—as well as from the social sector."

        let out = guardOut(baseline, candidate, "en")
        XCTAssertTrue(out.contains("municipal—as well as"), "the surviving em-dash must bind exactly as the candidate wrote it: \(out)")
        XCTAssertFalse(out.contains("municipal —"), "a space before the surviving em-dash exists in NEITHER input: \(out)")
    }

    /// `deriveSeamSpacing` only ever writes `""` (glued) or `" "` (spaced) —
    /// never a newline, and never destroys an existing non-empty trailing.
    /// A dictated line break must survive verbatim.
    func testLineBreakSurvivesSeamDerivation() {
        let baseline = "erste Zeile\nzweite Zeile bitte"
        let candidate = "Erste Zeile\nzweite Zeile, bitte."
        let out = guardOut(baseline, candidate, "de")
        XCTAssertTrue(out.contains("\n"), "a dictated line break must never be flattened to a space nor invented/destroyed: \(out)")
    }

    /// Reimplements the "observed adjacency spacing" concept as TEST code
    /// (EditGuard.observedAdjacencySpacing is `private`, not reachable even
    /// via @testable import) and sweeps the whole corpus: for every output
    /// seam whose normalized token pair is UNANIMOUS across BOTH the
    /// baseline and candidate streams (every occurrence in each stream
    /// agrees, and both streams agree with each other), assert the output
    /// matches that unanimous spacing. This is the renderer's own contract,
    /// stronger than the P4 property (which abstains on ambiguous/absent
    /// pairs) because unanimous-in-both-inputs pairs are never ambiguous.
    func testUnanimousAdjacencySpacingIsPreserved_acrossCorpus() {
        func adjacencySpacing(_ tokens: [EditGuard.Token]) -> [String: Set<Bool>] {
            guard tokens.count > 1 else { return [:] }
            var result: [String: Set<Bool>] = [:]
            for i in 0..<(tokens.count - 1) {
                let key = tokens[i].normalized + "\u{0}" + tokens[i + 1].normalized
                result[key, default: []].insert(!tokens[i].trailing.isEmpty)
            }
            return result
        }

        struct Case { let id: String; let baseline: String; let candidate: String; let language: String }
        let cases: [Case] = EditGuardFixtures.all.map {
            Case(id: $0.id, baseline: $0.baseline, candidate: $0.candidate, language: $0.language)
        } + EditGuardFixtures.productionRecords.map {
            Case(id: $0.id, baseline: $0.baseline, candidate: $0.candidate, language: $0.language)
        }

        var checkedCount = 0
        var casesExercising = 0

        for c in cases {
            let out = guardOut(c.baseline, c.candidate, c.language)
            let baselineTokens = EditGuardTokenizer.tokenize(c.baseline)
            let candidateTokens = EditGuardTokenizer.tokenize(c.candidate)
            let outTokens = EditGuardTokenizer.tokenize(out)
            let baselineSpacing = adjacencySpacing(baselineTokens)
            let candidateSpacing = adjacencySpacing(candidateTokens)

            guard outTokens.count > 1 else { continue }
            var exercisedThisCase = false
            for i in 0..<(outTokens.count - 1) {
                let key = outTokens[i].normalized + "\u{0}" + outTokens[i + 1].normalized
                guard let b = baselineSpacing[key], b.count == 1,
                      let cd = candidateSpacing[key], cd.count == 1,
                      b == cd else { continue }
                let unanimous = b.first!
                let actual = !outTokens[i].trailing.isEmpty
                checkedCount += 1
                exercisedThisCase = true
                XCTAssertEqual(
                    actual, unanimous,
                    "[\(c.id)] seam '\(outTokens[i].text)|\(outTokens[i + 1].text)' rendered \(actual ? "SPACED" : "GLUED") but both inputs unanimously agree it is \(unanimous ? "SPACED" : "GLUED"): \(out)"
                )
            }
            if exercisedThisCase { casesExercising += 1 }
        }

        print("[seam-spacing] checkedCount=\(checkedCount) casesExercising=\(casesExercising) (of \(cases.count) cases)")
        XCTAssertGreaterThan(checkedCount, 0, "sweep must exercise at least one unanimous adjacency, or it proves nothing")
    }
}
