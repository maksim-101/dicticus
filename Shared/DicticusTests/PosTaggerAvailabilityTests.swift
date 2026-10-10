import XCTest
@testable import Dicticus

/// `PosTagger.isFunctionWord` must return `nil` ("no opinion") when the tagger
/// is unavailable or the token is absent, never `true`. Split out of
/// `PosTaggerProbeTests` (2026-10-10), which is kept local-only with its
/// fixture and so cannot carry a test that clean clones must run.
final class PosTaggerAvailabilityTests: XCTestCase {

    /// A language with no `.lexicalClass` German/English asset available
    /// must return `nil` ("no opinion") — never `true`. `NLLanguage`
    /// accepts any BCP-47 string; a fabricated/unsupported tag exercises
    /// the `availableTagSchemes` early-return without needing to stub
    /// `NLTagger` internals.
    @MainActor
    func testTaggerUnavailableIsNotSilentlyTreatedAsFunction() {
        let verdict = PosTagger.isFunctionWord("xyzzy", in: "xyzzy plugh", language: "zz-Unsupported-FANTASY")
        XCTAssertNil(verdict, "An unsupported/unavailable tagger language must yield nil, never true.")

        // Also: a token that genuinely does not occur in the sentence must
        // be nil, not silently coerced.
        let notFound = PosTagger.isFunctionWord("nichtvorhanden", in: "Der Hund läuft schnell.", language: "de")
        XCTAssertNil(notFound, "A token absent from the sentence must yield nil, never true.")
    }
}
