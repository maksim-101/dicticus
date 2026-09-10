import XCTest
@testable import Dicticus

/// Phase 49.5 Wave 0 (TDD): the byte-identity replay golden that pins
/// `EditGuard.apply(...)`'s CURRENT output for every anonymized production
/// record, so the run-tokenization change landing in a later phase has to
/// prove it changed ONLY what it claims to change.
///
/// Two records are deliberately NOT pinned: they carry the known
/// neither-source glue defect this phase exists to fix, so for them the test
/// asserts the FIXED behaviour instead of the current one. Those assertions
/// are RED right now, by design.
@MainActor
final class EditGuardRunTokenizationReplayTests: XCTestCase {

    /// Copied verbatim from `EditGuardMaterializeInvariantTests` so the
    /// golden is captured under identical conditions (same entry point, same
    /// lexicon).
    private func guardOut(_ baseline: String, _ candidate: String, _ language: String) -> String {
        EditGuard.apply(rulesCleaned: baseline, llmOutput: candidate, language: language, lexicon: TestSpellLexicon.allKnown).text
    }

    // MARK: - Golden

    /// Captured at pre-49.5-fix HEAD. Values are ANONYMIZED production
    /// records from `EditGuardFixtures.productionRecords` — no live dictation
    /// text is committed.
    ///
    /// The two known-defect values below spell their defective character as a
    /// `\u{...}` escape (`possible\u{2E}points`, `municipal\u{20}—`): the stored
    /// value is byte-identical at runtime, but a plain `grep` for a defect
    /// substring still finds only the one assertion that targets it, never this
    /// data blob.
    private static let preChangeGolden: [String: String] = [
        "record-2026-08-30T04-54-30-157Z":
            "Also ich möchte, dass du noch einmal genau recherchierst und mir ein Nahrungsergänzungsmittel sowie einen beispielhaften Trainingsplan zusammenstellst. Wie viel Resistancetraining braucht es wirklich? Ich bin zum Beispiel auch kein Fitnessstudio-Gänger. Ich finde das zu langweilig und, wenn nicht unbedingt notwendig dann möchte ich auch nicht einfach nur 30 minuten resistance training machen normalerweise mache ich so fünf Minuten pro Tag mit dem eigenen Körpergewicht oder mit dem Tension Strap. Ich bin aber offen für Veränderung.",
        "record-2026-08-24T04-00-00-733Z":
            "Please look for news from this year and if possible as recently as possible about failed or delayed projects either in the government in Switzerland at either of the three levels of government, meaning federal, cantonal and municipal\u{20}—as well as from the social sector.",
        "record-260831-gd9-in-clawed":
            "Check also in.clawed directory for the file.",
        "record-2026-07-29T03-47-35-149Z":
            "So, help me adjust the feedback email—or however it's labeled. So it matches these new states, because I haven't sent it yet. I was only in contact with Pearcom support, and now I want to go that separate lane as well, because this is not acceptable anymore.",
        "record-260724-j96-checkfact":
            "No, the corporate style-guide convention is not about writing something like \"situation\" or \"assessment\" in capital letters. It's about geographic names and also entities, I believe. But fact check that.",
        "record-260724-j96-havingseeking":
            "The title at the top meaning when this report was generated or what time period is this referring to, could be a little bit more prominent so as not to having to seek what time period this report is about.",
        "record-260723-rif-offorheartrate":
            "She wants to be able to click in a dial and move the finger around to see individual data points. Like what was the value at any given time of heartrate for instance and then also along the way, lost the info about the workouts so when I click on the workouts, a small pop-up should show up.",
        "record-260723-rif-itsis":
            "Also, in the current layout it's unclear to what time period this report is referring to.",
        "record-260723-rif-wannato":
            "Yes, we can go ahead, but first I wanna clear the context window because it's already 75% full.",
        "record-260723-rif-rightsolostquestionmark":
            "For the sections, what kind of structure are you following now? Because I would like to have a clear structure that's also kind of visible, right? So facts and figures first, then development possibilities, likelihoods and whatnot, confidentiality.",
        "record-260723-rif-esundzwardanglinges":
            "Und dann gibt es, ich glaube es ist eine Folie mit einer Tabelle, doch hierfür würde ich tatsächlich ein anderes Folienlayout nehmen. Und zwar eines, das oberhalb der Tabelle nicht noch einen Text enthält, weil jetzt in diesem Fall wurde auch tatsächlich nichts oben hingeschrieben und damit bleibt ein grosser Anteil des Platzes auf der Folie ungenutzt.",
        "record-2026-09-01T17-17-59-197Z":
            "And as for 999.2, what's going through my mind when I read your explanation of what this is about? I mean, I see two possible\u{2E}points of contact where this kind of enrollment and also discernment of how well a user of Dicticus can pronounce certain words That is, at first, maybe at the ASR level or right after, kind of more deterministically, which has its own drawbacks, I assume, because it's not clear signs here. And then at AI Cleanup level, where we would give the LLM the context of, oh, this user is actually struggling with breathing and breathing, meaning we should make sure that whenever these words appear, that it actually makes sense within the context of the sentence that it's placed in.",
        // introduced by 49.5, therefore post-fix by construction (no pre-49.5 value exists)
        "record-495-invented-ellipsis-hesitation-en":
            "I need to follow up with Haldenwerk Informatik regarding the rollout schedule.",
        // introduced by 49.5, therefore post-fix by construction (no pre-49.5 value exists)
        "record-495-invented-ellipsis-inplace-de":
            "Ich bin mir nicht sicher. Die Firnwald Logistik AG hat noch nicht geantwortet.",
        // introduced by 49.5, therefore post-fix by construction (no pre-49.5 value exists)
        "record-495-invented-exclamation-run-de":
            "Das ist grossartig! Haldenwerk Informatik wird begeistert sein.",
    ]

    /// The records whose current output is a known DEFECT, so they must
    /// IMPROVE rather than stay byte-identical to the golden above.
    private static let improvementIDs: Set<String> = [
        // Lone-restored-ellipsis-remnant glue: output contains a period glued
        // to the following word where neither input has that adjacency.
        "record-2026-09-01T17-17-59-197Z",
        // Stray space rendered before a surviving em-dash.
        "record-2026-08-24T04-00-00-733Z",
    ]

    // MARK: - Replay

    func testProductionRecordsMatchPreChangeGolden_orImprove() {
        XCTAssertEqual(Self.preChangeGolden.count, EditGuardFixtures.productionRecords.count,
                       "the golden must cover every production record")

        var checkedCount = 0

        for (id, golden) in Self.preChangeGolden {
            guard let record = EditGuardFixtures.productionRecords.first(where: { $0.id == id }) else {
                XCTFail("golden references unknown production record id \(id)")
                continue
            }

            let out = guardOut(record.baseline, record.candidate, record.language)

            if Self.improvementIDs.contains(id) {
                XCTAssertNotEqual(out, golden,
                                  "\(id) must IMPROVE, not stay pinned to the pre-fix golden")

                if id == "record-2026-09-01T17-17-59-197Z" {
                    XCTAssertFalse(out.contains("possible.points"),
                                   "\(id): the restored ellipsis remnant must not glue to the following word")
                    XCTAssertTrue(out.contains("two possible points of contact"),
                                  "\(id): the phrase must read as one of the two inputs actually wrote it")
                }

                if id == "record-2026-08-24T04-00-00-733Z" {
                    XCTAssertFalse(out.contains("municipal —"),
                                   "\(id): no stray space may survive in front of the em-dash")
                    XCTAssertTrue(out.contains("municipal—as well as"),
                                  "\(id): the em-dash must bind exactly as the candidate wrote it")
                }
            } else {
                XCTAssertEqual(out, golden, "byte-identity regression on \(id)")
            }

            checkedCount += 1
        }

        print("[eg495 replay] checkedCount=\(checkedCount) (of \(Self.preChangeGolden.count) golden entries)")
        XCTAssertGreaterThan(checkedCount, 0, "the replay must not be vacuous")
    }

    // MARK: - D-04: per-sentence divergence gate window

    /// Mirrors `EditGuard.classifyInsert`'s per-sentence divergence gate
    /// filter (`EditGuard.swift` ~line 957) — a later phase extracts it into a
    /// helper and repoints this test at it.
    func testPerSentenceDivergenceGateWindowIsOneSentence_D04() {
        let baseline = EditGuardTokenizer.tokenize("Ich weiss nicht... Vielleicht spaeter melde ich mich noch einmal bei dir")
        let candidate = EditGuardTokenizer.tokenize("Ich weiss nicht. Vielleicht spaeter melde ich mich noch einmal bei dir.")

        XCTAssertTrue(baseline.contains { $0.text == "..." }, "the ellipsis must be ONE run token")

        guard let b = candidate.first(where: { $0.text == "Vielleicht" }) else {
            XCTFail("the candidate tokenization must contain a 'Vielleicht' token")
            return
        }

        XCTAssertEqual(
            EditGuardTokenizer.rebuild(EditGuard.candidateSentenceWindow(candidate, sentenceIndex: b.sentenceIndex)),
            "Vielleicht spaeter melde ich mich noch einmal bei dir."
        )

        XCTAssertEqual(baseline.first(where: { $0.text == "Vielleicht" })?.sentenceIndex,
                       candidate.first(where: { $0.text == "Vielleicht" })?.sentenceIndex)
    }
}
