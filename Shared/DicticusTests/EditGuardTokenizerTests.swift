import XCTest
@testable import Dicticus

/// Phase 44 Plan 05 (D-03): TDD suite for `EditGuardTokenizer` — proves
/// numeric-token atomicity, lossless reconstruction, casing preservation,
/// and the FORM-vs-VALUE numeric predicate that closes the D-03 digit
/// blindspot. Every behavior bullet in `44-05-PLAN.md` has a corresponding
/// test here.
final class EditGuardTokenizerTests: XCTestCase {

    // MARK: - Helpers

    /// Convenience: tokenize a single bare word/number and return its only
    /// token, for numericValue/isDigitBearing tests that don't care about
    /// sentence context.
    private func token(_ s: String) -> EditGuard.Token {
        let tokens = EditGuardTokenizer.tokenize(s)
        XCTAssertEqual(tokens.count, 1, "Helper expects a single-token input, got \(tokens.count) for '\(s)'.")
        return tokens[0]
    }

    // MARK: - The blindspot regression (the fixture that proves this plan happened)

    /// `10,011` must tokenize as ONE atomic `.numeric` token — and the OLD
    /// tokenizer must still split it, pinning exactly why the new one exists.
    @MainActor
    func testDigitFlankedCommaStaysAtomic() {
        let tokens = EditGuardTokenizer.tokenize("Die Latenz war 10,011 ms.")
        let numericTokens = tokens.filter { $0.kind == .numeric }
        XCTAssertEqual(numericTokens.count, 1, "Expected exactly one numeric token.")
        XCTAssertEqual(numericTokens.first?.text, "10,011")

        // Pin the OLD behaviour so this test fails loudly if the guard is
        // ever "helpfully" pointed back at the old tokenizer.
        let oldTokens = CleanupService.tokenizeForDialectGate("10,011 ms")
        XCTAssertEqual(oldTokens, ["10", "011", "ms"],
            "tokenizeForDialectGate must still split '10,011' — this is the confirmed D-03 blindspot the new tokenizer exists to close.")
    }

    func testDigitFlankedCommaTokenizeIsolated() {
        let tokens = EditGuardTokenizer.tokenize("10,011 ms")
        XCTAssertEqual(tokens.map(\.text), ["10,011", "ms"])
        XCTAssertEqual(tokens.first?.kind, .numeric)
    }

    // MARK: - Atomicity behavior bullets

    func testGermanGroupingAndDecimalComma() {
        let tokens = EditGuardTokenizer.tokenize("1.250,70 Franken")
        XCTAssertEqual(tokens.map(\.text), ["1.250,70", "Franken"])
        XCTAssertEqual(tokens.first?.kind, .numeric)
    }

    func testEnglishDecimalPoint() {
        let tokens = EditGuardTokenizer.tokenize("3.14")
        XCTAssertEqual(tokens.map(\.text), ["3.14"])
        XCTAssertEqual(tokens.first?.kind, .numeric)
    }

    func testVersionNumberVsSentenceFinalPeriod() {
        let tokens = EditGuardTokenizer.tokenize("Version 2.5.")
        XCTAssertEqual(tokens.map(\.text), ["Version", "2.5", "."])
        XCTAssertEqual(tokens[1].kind, .numeric)
        XCTAssertEqual(tokens[2].kind, .punctuation)
    }

    func testPeriodFollowedBySpaceIsABoundary() {
        let tokens = EditGuardTokenizer.tokenize("Ende. 10 Uhr")
        XCTAssertEqual(tokens.map(\.text), ["Ende", ".", "10", "Uhr"])
    }

    func testGermanOrdinalPeriodIsNotDigitFlanked() {
        let tokens = EditGuardTokenizer.tokenize("4.")
        XCTAssertEqual(tokens.map(\.text), ["4", "."])
        XCTAssertEqual(tokens[0].kind, .numeric)
        XCTAssertEqual(tokens[1].kind, .punctuation)
    }

    func testEMailHyphenStaysIntact() {
        // Letter-flanked hyphen must NOT split — a hyphen split would make
        // E-Mail -> E Mail an invisible edit.
        let tokens = EditGuardTokenizer.tokenize("E-Mail")
        XCTAssertEqual(tokens.map(\.text), ["E-Mail"])
    }

    func testApostropheInsideWordStaysIntact() {
        let tokens = EditGuardTokenizer.tokenize("s'het")
        XCTAssertEqual(tokens.map(\.text), ["s'het"])
    }

    // MARK: - Losslessness

    func testLosslessRebuildOnBehaviorExamples() {
        let examples = [
            "Die Latenz war 10,011 ms.",
            "1.250,70 Franken",
            "3.14",
            "Version 2.5.",
            "Ende. 10 Uhr",
            "4.",
            "E-Mail",
            "s'het",
            "  leading and trailing whitespace  ",
            "",
            "Multiple   spaces\tand\nnewlines.",
            "Nur ein Wort"
        ]
        for s in examples {
            XCTAssertEqual(EditGuardTokenizer.rebuild(EditGuardTokenizer.tokenize(s)), s,
                "Lossless round-trip failed for: '\(s)'")
        }
    }

    /// Every fixture baseline/candidate/expectedText in `EditGuardFixtures.all`
    /// must round-trip exactly.
    func testLosslessRebuildAcrossFixtureCorpus() {
        var checked = 0
        for fixture in EditGuardFixtures.all {
            for text in [fixture.baseline, fixture.candidate, fixture.expectedText] {
                XCTAssertEqual(EditGuardTokenizer.rebuild(EditGuardTokenizer.tokenize(text)), text,
                    "Lossless round-trip failed for fixture '\(fixture.id)': '\(text)'")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 0)
    }

    /// Corpus-snapshot losslessness loop (44-05-PLAN.md <verification>): runs
    /// the round-trip over every `raw`/`post_rules` text in the real
    /// `.planning/phases/44-cleanup-fidelity-guard/corpus-snapshot/` JSONL
    /// files. `.planning/` is gitignored (local-only asset) — the test
    /// resolves the path relative to its own source file via `#filePath` and
    /// skips gracefully (does not fail) when the snapshot isn't present on
    /// the machine running the test, e.g. a fresh clone.
    func testLosslessnessAcrossCorpusSnapshot() throws {
        let thisFile = URL(fileURLWithPath: #filePath)
        // .../Shared/DicticusTests/EditGuardTokenizerTests.swift -> project root
        let projectRoot = thisFile
            .deletingLastPathComponent() // .../Shared/DicticusTests
            .deletingLastPathComponent() // .../Shared
            .deletingLastPathComponent() // .../dicticus (project root)
        let corpusDir = projectRoot
            .appendingPathComponent(".planning/phases/44-cleanup-fidelity-guard/corpus-snapshot")

        guard let allFiles = try? FileManager.default.contentsOfDirectory(
            at: corpusDir, includingPropertiesForKeys: nil
        ) else {
            throw XCTSkip("Corpus snapshot not present at \(corpusDir.path) — gitignored local-only asset, skipping.")
        }
        let jsonlFiles = allFiles.filter { $0.pathExtension == "jsonl" }
        guard !jsonlFiles.isEmpty else {
            throw XCTSkip("Corpus snapshot directory present but contains no .jsonl files — skipping.")
        }

        var checked = 0
        var failures: [(String, String)] = []

        for file in jsonlFiles {
            guard let data = try? Data(contentsOf: file),
                  let content = String(data: data, encoding: .utf8) else { continue }
            for line in content.split(separator: "\n") {
                guard let lineData = line.data(using: .utf8),
                      let record = try? JSONDecoder().decode(CorpusRecord.self, from: lineData) else { continue }
                let texts = [record.steps.raw?.text, record.steps.post_rules?.text].compactMap { $0 }
                for text in texts {
                    let rebuilt = EditGuardTokenizer.rebuild(EditGuardTokenizer.tokenize(text))
                    checked += 1
                    if rebuilt != text {
                        failures.append((text, rebuilt))
                    }
                }
            }
        }

        XCTAssertGreaterThan(checked, 0, "Corpus snapshot loop found no raw/post_rules texts to check.")
        for (original, rebuilt) in failures.prefix(5) {
            XCTFail("Losslessness failed. original='\(original)' rebuilt='\(rebuilt)'")
        }
        // swiftlint:disable:next no_direct_standard_out_logs
        print("EditGuardTokenizer losslessness: \(checked - failures.count)/\(checked) corpus texts round-tripped exactly.")
    }

    private struct CorpusRecord: Decodable {
        struct Step: Decodable { let text: String? }
        struct Steps: Decodable {
            let raw: Step?
            let post_rules: Step?
        }
        let steps: Steps
    }

    // MARK: - Casing preserved

    func testCasingPreservedOnTextNormalizedOnNormalized() {
        let tokens = EditGuardTokenizer.tokenize("Weil Die")
        XCTAssertEqual(tokens.map(\.text), ["Weil", "Die"])
        XCTAssertEqual(tokens.map(\.normalized), ["weil", "die"])
    }

    func testCaseOnlySubstitutionIsDetectableViaNormalized() {
        let from = token("push")
        let to = token("Push")
        XCTAssertEqual(from.normalized, to.normalized)
        XCTAssertNotEqual(from.text, to.text)
    }

    // MARK: - Value resolution

    func testDigitAndWordFormResolveToSameValue() {
        XCTAssertEqual(EditGuardTokenizer.numericValue(token("10"), language: "de"), 10)
        XCTAssertEqual(EditGuardTokenizer.numericValue(token("zehn"), language: "de"), 10)
        XCTAssertEqual(EditGuardTokenizer.numericValue(token("ten"), language: "en"), 10)
    }

    func testLocaleSensitiveButConsistentUnderFixedLanguage() {
        // DE: '.' groups, ',' is decimal -> 10,011 reads as 10.011
        XCTAssertEqual(EditGuardTokenizer.numericValue(token("10,011"), language: "de"), Decimal(string: "10.011"))
        // EN: ',' groups, '.' is decimal -> 10,011 reads as 10011
        XCTAssertEqual(EditGuardTokenizer.numericValue(token("10,011"), language: "en"), Decimal(10011))
    }

    func testTheD03CorpusExampleIsAValueChangeUnderEitherReading() {
        let deA = EditGuardTokenizer.numericValue(token("10,011"), language: "de")
        let deB = EditGuardTokenizer.numericValue(token("10,111"), language: "de")
        XCTAssertNotEqual(deA, deB, "10,011 -> 10,111 must differ under the DE reading.")

        let enA = EditGuardTokenizer.numericValue(token("10,011"), language: "en")
        let enB = EditGuardTokenizer.numericValue(token("10,111"), language: "en")
        XCTAssertNotEqual(enA, enB, "10,011 -> 10,111 must differ under the EN reading.")
    }

    func testNonNumericWordHasNoValue() {
        XCTAssertNil(EditGuardTokenizer.numericValue(token("ms"), language: "de"))
        XCTAssertNil(EditGuardTokenizer.numericValue(token("ms"), language: "en"))
    }

    func testAlphanumericIdentifierHasNoNumericValue() {
        XCTAssertNil(EditGuardTokenizer.numericValue(token("M3"), language: "en"))
    }

    // MARK: - isDigitBearing

    func testIsDigitBearing() {
        XCTAssertTrue(EditGuardTokenizer.isDigitBearing("10,011"))
        XCTAssertTrue(EditGuardTokenizer.isDigitBearing("M3"))
        XCTAssertFalse(EditGuardTokenizer.isDigitBearing("Format"))
    }

    // MARK: - Ownership boundary: this tokenizer must never call the old one

    func testSourceNeverCallsTokenizeForDialectGate() throws {
        let sourceFile = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Utilities/EditGuardTokenizer.swift")
        let source = try String(contentsOf: sourceFile, encoding: .utf8)
        XCTAssertFalse(source.contains("tokenizeForDialectGate"),
            "EditGuardTokenizer.swift must not reference tokenizeForDialectGate — its separator set includes ',' and '.', the confirmed D-03 blindspot.")
    }
}
