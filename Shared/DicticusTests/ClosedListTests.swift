import XCTest
@testable import Dicticus

/// Phase 44 Plan 03 Task 2: ship-list lock tests for `FunctionWords`,
/// `PronounPersonMap`, and `FiniteVerbCues` — the three closed,
/// hand-curated tables the D-04 mood-lock, D-04 pronoun-lock, and D-06
/// insertion-lock stand on. Mirrors the ship-list convention established by
/// `FillerWordRemover`'s `testGermanFillerShipList` /
/// `testEnglishFillerShipList`: assert the EXACT expected set, so widening
/// a list is a deliberate, reviewed edit, not a silent drift.
final class ClosedListTests: XCTestCase {

    // MARK: - testFunctionWordsContainNoPronouns

    /// A real bug class, not a formality — `ihr`, `sie`, `es`, `her`,
    /// `its` all look like determiners at a glance. If D-06's insertion
    /// allowlist ever silently absorbed a pronoun, the guard could accept
    /// an LLM-inserted pronoun (which is a content-word-adjacent insertion
    /// D-06 forbids) as if it were a harmless article.
    func testFunctionWordsContainNoPronouns() {
        let germanOverlap = FunctionWords.germanInsertable
            .intersection(Set(PronounPersonMap.german.keys))
        XCTAssertTrue(
            germanOverlap.isEmpty,
            "German function words must not contain pronouns: \(germanOverlap.sorted())"
        )

        let germanSubOverlap = FunctionWords.germanSubstitutable
            .intersection(Set(PronounPersonMap.german.keys))
        XCTAssertTrue(
            germanSubOverlap.isEmpty,
            "German substitutable function words must not contain pronouns: \(germanSubOverlap.sorted())"
        )

        let englishOverlap = FunctionWords.englishInsertable
            .intersection(Set(PronounPersonMap.english.keys))
        XCTAssertTrue(
            englishOverlap.isEmpty,
            "English function words must not contain pronouns: \(englishOverlap.sorted())"
        )

        let englishSubOverlap = FunctionWords.englishSubstitutable
            .intersection(Set(PronounPersonMap.english.keys))
        XCTAssertTrue(
            englishSubOverlap.isEmpty,
            "English substitutable function words must not contain pronouns: \(englishSubOverlap.sorted())"
        )
    }

    // MARK: - testFunctionWordsContainNoContentWords

    /// Pins the six invented tokens from the real 2026-07-12 car record and
    /// the D-02 blocked-derivation examples out of every `FunctionWords`
    /// set. If this test fails on first run, the fix is to remove the
    /// content word from `FunctionWords`, never to weaken the test.
    func testFunctionWordsContainNoContentWords() {
        let inventedContentWords = ["gefahren", "teile", "anderes", "regelung", "wahrscheinlich", "bereits"]

        for word in inventedContentWords {
            XCTAssertFalse(FunctionWords.germanInsertable.contains(word), "'\(word)' must not be in germanInsertable")
            XCTAssertFalse(FunctionWords.germanSubstitutable.contains(word), "'\(word)' must not be in germanSubstitutable")
            XCTAssertFalse(FunctionWords.englishInsertable.contains(word), "'\(word)' must not be in englishInsertable")
            XCTAssertFalse(FunctionWords.englishSubstitutable.contains(word), "'\(word)' must not be in englishSubstitutable")

            XCTAssertFalse(FunctionWords.isInsertable(word, language: "de"), "isInsertable('\(word)', de) must be false")
            XCTAssertFalse(FunctionWords.isInsertable(word, language: "en"), "isInsertable('\(word)', en) must be false")
        }
    }

    // MARK: - Dual-role lock (Phase 44 Plan 14 — the class fix)

    /// The DUAL-ROLE CRITERION, locked: no token with a productive
    /// lexical-content reading may be blanket-insertable. This is the class
    /// the Plan 14 fresh-corruption audit found the guard leaking through
    /// (German `"sein"` inserted as the COPULA — the whole asserted
    /// predicate — not as an auxiliary), and the class the earlier `"before"`
    /// fix belonged to without anyone noticing.
    ///
    /// If this test fails, the fix is to remove the token from the insertable
    /// set — NEVER to weaken the test. A missed repair is safe; an invented
    /// content word is not.
    func testDualRoleTokensAreNotInsertable() {
        for word in FunctionWords.germanDualRole {
            XCTAssertFalse(
                FunctionWords.germanInsertable.contains(word),
                "DUAL-ROLE '\(word)' must not be in germanInsertable — it has a lexical-content reading"
            )
            XCTAssertFalse(
                FunctionWords.isInsertable(word, language: "de"),
                "isInsertable('\(word)', de) must be false — dual-role"
            )
        }
        for word in FunctionWords.englishDualRole {
            XCTAssertFalse(
                FunctionWords.englishInsertable.contains(word),
                "DUAL-ROLE '\(word)' must not be in englishInsertable — it has a lexical-content reading"
            )
            XCTAssertFalse(
                FunctionWords.isInsertable(word, language: "en"),
                "isInsertable('\(word)', en) must be false — dual-role"
            )
        }

        // The two specific, corpus-evidenced leaks this class was found
        // through — pinned by name so a future widening cannot silently
        // re-open either one.
        XCTAssertFalse(
            FunctionWords.isInsertable("sein", language: "de"),
            "'sein' is the COPULA as well as an auxiliary — the live Qwen3.5 leak (44-AUDIT-FRESH-CORRUPTION.md)"
        )
        XCTAssertFalse(
            FunctionWords.isInsertable("before", language: "en"),
            "'before' is a bare temporal ADVERB as well as a preposition (44-FIDELITY-REPLAY.md SC#3 adjudication)"
        )
        XCTAssertFalse(
            FunctionWords.isInsertable("after", language: "en"),
            "'after' shares 'before''s exact preposition/adverb dual role"
        )
    }

    /// The dual-role split is an INSERTION-ONLY fix. A function<->function
    /// SUBSTITUTION replaces a token the speaker actually said, so it cannot
    /// invent an assertion out of nothing — the dual-role tokens are unioned
    /// straight back into the substitution sets, whose contents must
    /// therefore be UNCHANGED by the split.
    ///
    /// This is the hard cross-check on the fix's blast radius: it pins the
    /// claim that `functionWordSubstitution` yield cannot move, so any
    /// measured yield delta in the corpus replay is attributable to
    /// `functionWordInsertion` alone.
    func testSubstitutableSetsAreUnchangedByTheDualRoleSplit() {
        XCTAssertTrue(
            FunctionWords.germanInsertable.isDisjoint(with: FunctionWords.germanDualRole),
            "germanInsertable and germanDualRole must partition the old list, not overlap"
        )
        XCTAssertTrue(
            FunctionWords.englishInsertable.isDisjoint(with: FunctionWords.englishDualRole),
            "englishInsertable and englishDualRole must partition the old list, not overlap"
        )

        // Every dual-role token is still SUBSTITUTABLE (the split moved them,
        // it did not delete them).
        for word in FunctionWords.germanDualRole {
            XCTAssertTrue(
                FunctionWords.isSubstitutable(word, language: "de"),
                "dual-role '\(word)' must remain substitutable (de) — the fix is insertion-only"
            )
        }
        for word in FunctionWords.englishDualRole {
            XCTAssertTrue(
                FunctionWords.isSubstitutable(word, language: "en"),
                "dual-role '\(word)' must remain substitutable (en) — the fix is insertion-only"
            )
        }

        // `"before"` is the ONE exception: its removal from BOTH sets already
        // shipped and was already measured (functionWordSubstitution 36 -> 35,
        // 44-FIDELITY-REPLAY.md). Silently restoring it here would reverse a
        // closed decision.
        XCTAssertFalse(
            FunctionWords.isSubstitutable("before", language: "en"),
            "'before' stays out of englishSubstitutable — that removal already shipped and was measured"
        )
        XCTAssertEqual(
            FunctionWords.englishDualRoleAlsoNotSubstitutable, ["before"],
            "the not-even-substitutable set is exactly {before} — any addition needs its own measurement"
        )
    }

    // MARK: - testGermanPronounShipList / testEnglishPronounShipList

    func testGermanPronounShipList() {
        let expected: Set<String> = [
            // 1st person
            "ich", "mich", "mir", "wir", "uns", "unser",
            // 2nd person
            "du", "dich", "dir", "ihr", "euch",
            // 3rd person (includes formal sie/ihnen — see PronounPersonMap KNOWN GAP)
            "er", "ihn", "ihm", "sie", "es", "ihnen", "sich"
        ]
        XCTAssertEqual(Set(PronounPersonMap.german.keys), expected)
    }

    func testEnglishPronounShipList() {
        let expected: Set<String> = [
            // 1st person
            "i", "me", "we", "us", "my", "our",
            // 2nd person
            "you", "your", "yours",
            // 3rd person
            "he", "him", "she", "her", "it", "they", "them", "his", "their", "its"
        ]
        XCTAssertEqual(Set(PronounPersonMap.english.keys), expected)
    }

    // MARK: - testMoodLockCuesShipList

    func testMoodLockCuesShipList() {
        let expectedGerman: Set<String> = [
            // Modal finite forms
            "kann", "kannst", "könnt", "können",
            "muss", "musst", "müsst", "müssen",
            "soll", "sollst", "sollt", "sollen",
            "will", "willst", "wollt", "wollen",
            "darf", "darfst", "dürft", "dürfen",
            "mag", "magst", "mögt", "mögen",
            // Auxiliary finite forms
            "ist", "bist", "sind", "seid", "bin",
            "war", "warst", "waren", "wart",
            "hat", "hast", "habt", "haben",
            "hatte", "hattest", "hatten",
            "wird", "wirst", "werdet", "werden",
            "wurde", "wurden"
        ]
        XCTAssertEqual(FiniteVerbCues.germanModalsAndAuxiliaries, expectedGerman)

        let expectedEnglish: Set<String> = [
            "can", "could", "must", "should", "shall", "will", "would", "may", "might",
            "is", "are", "am", "was", "were",
            "do", "does", "did",
            "have", "has", "had"
        ]
        XCTAssertEqual(FiniteVerbCues.englishModalsAndAuxiliaries, expectedEnglish)
    }

    // MARK: - testFixturePreconditions

    /// A fixture/mechanism drift lock: for every `EditGuardFixtures.all`
    /// fixture tagged `.pronoun` or `.functionWord`, the token that drives
    /// the fixture's classification must be recognized by the lookup that
    /// mechanism (`PronounPersonMap` / `FunctionWords` / `FiniteVerbCues`
    /// for the mood-lock cell) is supposed to serve. This is the link that
    /// stops the tables and the fixtures drifting apart — this task builds
    /// only the closed tables, not the full edit classifier (plan 44-10),
    /// so this test checks the LOOKUP precondition each fixture assumes,
    /// not the fixture's full accept/reject verdict.
    ///
    /// One row per fixture id, hand-picked (not parsed from prose) so the
    /// mapping is exact and reviewable.
    private struct Precondition {
        let fixtureID: String
        let mechanism: Mechanism
        let tokens: [String]

        enum Mechanism {
            case pronoun
            case functionWord
            case finiteVerbCue
        }
    }

    private static let preconditions: [Precondition] = [
        // MARK: pronoun-class fixtures (8) — PronounPersonMap.isPronoun precondition
        Precondition(fixtureID: "fx-sub-pronoun-de-personflip", mechanism: .pronoun, tokens: ["du", "ich"]),
        Precondition(fixtureID: "fx-sub-pronoun-en-genderflip", mechanism: .pronoun, tokens: ["him", "her"]),
        Precondition(fixtureID: "fx-del-pronoun-en-sentenceinitial", mechanism: .pronoun, tokens: ["you"]),
        Precondition(fixtureID: "fx-del-pronoun-de-interior", mechanism: .pronoun, tokens: ["wir"]),
        Precondition(fixtureID: "fx-ins-pronoun-de", mechanism: .pronoun, tokens: ["ihn"]),
        Precondition(fixtureID: "fx-ins-pronoun-en", mechanism: .pronoun, tokens: ["him"]),
        Precondition(fixtureID: "fx-mov-pronoun-de", mechanism: .pronoun, tokens: ["er"]),
        Precondition(fixtureID: "fx-mov-pronoun-en", mechanism: .pronoun, tokens: ["he"]),

        // MARK: functionWord-class fixtures — FunctionWords.isSubstitutable / isInsertable precondition
        //
        // NOTE: "fx-req-punctcasing-de"/"-en" are deliberately EXCLUDED from
        // this table (see `excludedFixtureIDs` below) — their expectedClass
        // is `punctuationOrCasing`, a classification EditGuard (plan 44-10)
        // derives independently of these three tables. The EN half's token
        // ("this") is a demonstrative determiner, not one of D-06's
        // articles/prepositions/auxiliaries/conjunctions, so asserting
        // `FunctionWords` membership for it would be testing the wrong
        // mechanism, not locking a real precondition.
        Precondition(fixtureID: "fx-sub-func-de-der-das", mechanism: .functionWord, tokens: ["der", "das"]),
        Precondition(fixtureID: "fx-sub-func-en-a-an", mechanism: .functionWord, tokens: ["a", "an"]),
        Precondition(fixtureID: "fx-del-func-de", mechanism: .functionWord, tokens: ["in"]),
        Precondition(fixtureID: "fx-del-func-en", mechanism: .functionWord, tokens: ["to"]),
        Precondition(fixtureID: "fx-ins-func-de", mechanism: .functionWord, tokens: ["des"]),
        Precondition(fixtureID: "fx-ins-func-en", mechanism: .functionWord, tokens: ["to"]),
        Precondition(fixtureID: "fx-mov-func-de-wordorder", mechanism: .functionWord, tokens: ["werden"]),
        Precondition(fixtureID: "fx-mov-func-en-interior", mechanism: .functionWord, tokens: ["can"]),

        // MARK: functionWord-class fixtures whose real mechanism is the
        // mood-lock's FiniteVerbCues, not FunctionWords — both are tagged
        // `moodLockSentenceInitialVerb`, the class that only exists via the
        // sentence-initial finite/modal check, and per Task 1's own
        // acceptance criteria the "can"/"You can push" precondition is
        // `FiniteVerbCues.isFiniteOrModal`. "kommt" is additionally not a
        // function word at all — it's a full finite verb (irregular), not
        // an auxiliary/modal/article/preposition/conjunction.
        Precondition(fixtureID: "fx-mov-func-en-moodlock", mechanism: .finiteVerbCue, tokens: ["can"]),
        Precondition(fixtureID: "fx-mov-func-de-moodlock", mechanism: .finiteVerbCue, tokens: ["kommt"])
    ]

    func testFixturePreconditions() {
        let fixturesByID = Dictionary(uniqueKeysWithValues: EditGuardFixtures.all.map { ($0.id, $0) })

        // Sanity: every precondition row must reference a real fixture that
        // is actually tagged with the token class the row assumes.
        for precondition in Self.preconditions {
            guard let fixture = fixturesByID[precondition.fixtureID] else {
                XCTFail("Precondition references unknown fixture id '\(precondition.fixtureID)'")
                continue
            }
            XCTAssertTrue(
                fixture.tokenClass == .pronoun || fixture.tokenClass == .functionWord,
                "'\(precondition.fixtureID)' must be tagged .pronoun or .functionWord, got \(fixture.tokenClass)"
            )

            switch precondition.mechanism {
            case .pronoun:
                for token in precondition.tokens {
                    XCTAssertTrue(
                        PronounPersonMap.isPronoun(token, language: fixture.language),
                        "\(fixture.id): '\(token)' must be recognized as a pronoun (\(fixture.language))"
                    )
                }
            case .functionWord:
                for token in precondition.tokens {
                    XCTAssertTrue(
                        FunctionWords.isSubstitutable(token, language: fixture.language),
                        "\(fixture.id): '\(token)' must be recognized as a function word (\(fixture.language))"
                    )
                }
                if fixture.editKind == .insert {
                    for token in precondition.tokens {
                        XCTAssertTrue(
                            FunctionWords.isInsertable(token, language: fixture.language),
                            "\(fixture.id): '\(token)' must be D-06 insertable (\(fixture.language))"
                        )
                    }
                }
            case .finiteVerbCue:
                for token in precondition.tokens {
                    XCTAssertTrue(
                        FiniteVerbCues.isFiniteOrModal(token, language: fixture.language),
                        "\(fixture.id): '\(token)' must be recognized as finite-or-modal (\(fixture.language))"
                    )
                }
            }
        }

        // Confirm we actually exercised every pronoun/functionWord fixture in
        // the corpus except the explicitly-documented exclusions — a drift
        // lock that catches a fixture silently added (or removed) without a
        // matching precondition row being added (or retired) here.
        let excludedFixtureIDs: Set<String> = [
            "fx-req-punctcasing-de", "fx-req-punctcasing-en"
        ]
        let pronounAndFunctionWordFixtures = EditGuardFixtures.all.filter {
            ($0.tokenClass == .pronoun || $0.tokenClass == .functionWord)
                && !excludedFixtureIDs.contains($0.id)
        }
        XCTAssertEqual(
            Set(pronounAndFunctionWordFixtures.map(\.id)),
            Set(Self.preconditions.map(\.fixtureID)),
            "Every non-excluded .pronoun/.functionWord fixture must have exactly one precondition row, and vice versa."
        )
        XCTAssertGreaterThanOrEqual(
            Self.preconditions.count, 8,
            "testFixturePreconditions must iterate at least 8 fixtures per plan acceptance criteria."
        )
    }

    // MARK: - testSieAmbiguityIsDocumented

    /// Pins the decided disambiguation (`PronounPersonMap`'s KNOWN GAP doc
    /// comment) so a later agent cannot flip `sie`/`ihnen` back to a
    /// formal-2nd-person reading without a reviewed change.
    func testSieAmbiguityIsDocumented() {
        XCTAssertEqual(PronounPersonMap.person(of: "sie", language: "de"), .third)
        XCTAssertEqual(PronounPersonMap.person(of: "ihnen", language: "de"), .third)
        XCTAssertNil(
            PronounPersonMap.german["Sie"],
            "Lookup is lowercased internally; the map itself only stores lowercase keys."
        )
    }
}
