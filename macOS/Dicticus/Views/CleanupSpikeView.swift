#if DEBUG
import SwiftUI

/// DEBUG-only spike harness for Phase 20.08 prompt evaluation.
///
/// Wave B (variant g15): 6 fixtures x 1 variant. g15 is the production
/// candidate from /tmp/spike-harness — minimal-umlaut-fix variant of g12,
/// with the Phase 20.08 apostrophe-strike applied (no thousands-separator
/// rule in the prompt, no apostrophes in the few-shot examples). g15
/// passes all 7 harness fixtures and the F3 muessen drift is 0/8 across
/// seeds vs. 8/8 on g12.
///
/// Wave A (variant g) and earlier variants e/f are preserved in
/// SpikeFixtures for historical reference but are no longer rendered.
/// Pinned sampler seed (0xDEADBEEF) for reproducibility. User picks
/// pass/fail per fixture against criteria P1-P7 in
/// 20.08-VARIANT-G-RATIONALE.md and records outcomes in
/// 20.08-SPIKE-RESULTS.md.
///
/// CONCURRENCY: inferences run sequentially due to CleanupService.isInferring
/// guard. UI shows a per-cell loading indicator while each inference runs.
struct CleanupSpikeView: View {

    @EnvironmentObject var cleanupService: CleanupService

    @State private var rows: [SpikeRow] = []
    @State private var isRunning: Bool = false
    @State private var progress: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Phase 20.08 Cleanup Spike")
                    .font(.headline)
                Spacer()
                if isRunning {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text(progress).font(.caption)
                }
                Button("Run Spike") {
                    Task { await runSpike() }
                }
                .disabled(isRunning || !cleanupService.isLoaded)
            }
            .padding()

            ScrollView {
                Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        Text("Input").bold()
                        Text("Variant (g15)\nFew-shot, apostrophe-strike\n(de + Swiss orth.)").bold()
                    }
                    Divider().gridCellColumns(2)
                    ForEach(rows) { row in
                        GridRow {
                            Text(row.input)
                                .font(.caption)
                                .frame(maxWidth: 320, alignment: .topLeading)
                                .textSelection(.enabled)
                            ForEach(row.outputs.indices, id: \.self) { idx in
                                Text(row.outputs[idx])
                                    .font(.caption)
                                    .frame(maxWidth: 360, alignment: .topLeading)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    private func runSpike() async {
        isRunning = true
        defer { isRunning = false }
        rows = []
        defer { cleanupService.setSamplerSeed(nil) }

        let fixtures = SpikeFixtures.inputs   // 6 fixtures (Wave A)
        for (i, fixture) in fixtures.enumerated() {
            progress = "Input \(i + 1)/\(fixtures.count)..."
            // Re-seed before each fixture so every cell is independently
            // reproducible — without this, sampler state cascades across
            // calls and a prompt change on fixture N shifts outputs for
            // N+1, N+2... (observed run-5 F6 "regression").
            cleanupService.setSamplerSeed(0xDEADBEEF)
            // Mirror production Step 2: deterministic ITN runs BEFORE the LLM,
            // so cardinals ≥10 ("zwanzig", "hundertfünfzig") are digit-form
            // by the time Gemma sees them. Without this, the spike feeds the
            // LLM word-form numerals that g15 was never designed to handle —
            // making the spike a misleading preview of production output.
            let preprocessed = ITNUtility.applyITN(to: fixture.text, language: fixture.language)
            let prompt: String
            switch fixture.language {
            case "de":
                prompt = SpikeFixtures.buildVariantG15(preprocessed)
            case "en":
                prompt = SpikeFixtures.buildVariantGEnglish(preprocessed)
            default:
                prompt = SpikeFixtures.buildVariantG15(preprocessed)
            }
            // Spike timeout is 30s vs. production 5s. Few-shot prompts are
            // long (~4 examples × ~120 chars + the input) so prefill+decode
            // for fixtures like the multi-clause "Zürich/hotel/150%" case
            // routinely exceed the production budget. The spike is a dev
            // evaluation tool — it should wait long enough to actually
            // observe the model's output rather than silently report empty.
            let llmOut = await cleanupService.cleanupWithExplicitPrompt(prompt, timeoutSeconds: 30.0)
            // Mirror production Step 3b: post-LLM SwissNumberFormatter pass.
            // This is what folds "1250 Franken 20" → "1250.20 Franken" via
            // Bridge-2, and normalizes German-decimal "2,5" → Swiss "2.5".
            // Always-on in the spike (the spike's whole point is Swiss-orth.
            // evaluation); production gates this on the useSwissGerman toggle.
            let out = fixture.language == "de"
                ? SwissNumberFormatter.format(llmOut)
                : llmOut
            rows.append(SpikeRow(id: UUID(), input: fixture.text, outputs: [out]))
        }
        progress = "Done"
    }
}

struct SpikeRow: Identifiable {
    let id: UUID
    let input: String
    let outputs: [String]
}

struct SpikeFixture {
    let text: String
    let language: String  // "de" | "en"
}

/// Fixture inputs (6 in Wave A) + variant prompt-builder helpers.
/// Each fixture carries a language tag so the spike can dispatch the
/// matching prompt (variant g for de, base-default for en).
/// F1/F3/F4 carry the dense-failure / Phase-20.06 anchors. F2 + F6
/// exercise broken-grammar reconstruction in two distinct patterns.
/// F5 is a long English utterance to verify variant g doesn't degrade
/// the English path.
enum SpikeFixtures {
    static let inputs: [SpikeFixture] = [
        // 1) Dense multi-failure-point fixture: lowercase nouns, year (2026
        //    must NOT get a thousands separator), big number (1250 — toggle
        //    behaviour under RULE 2), spelled currency ("vier Franken
        //    fünfzig" — must stay spelled per ITN backlog), numeric currency
        //    (850 Franken), Swiss orthography (strasse — must stay ss, must
        //    capitalize), missing clause-boundary punctuation, "natürlich"
        //    (known dialect-translation trigger from variants a/b/c/d).
        SpikeFixture(
            text: "im jahr 2026 hat unsere abteilung etwa 1250 franken zwanzig für die neue strasse ausgegeben das war ungefähr vier franken fünfzig pro meter und natürlich teurer als die geplanten 850 franken aus dem vorjahr.",
            language: "de"
        ),
        // 2) Grammar-stress German: cascading gender/case errors + Anglicism
        //    nouns + dropped auxiliary clause boundary. Probes whether
        //    variant g's "Fix grammar errors" clause is strong enough to
        //    correct article/case errors that aren't mishears (run-3 F2
        //    showed it left "Die Meeting" and "mit der Kunde" uncorrected).
        //    Expected fixes: der email→die E-Mail, die team→das Team,
        //    dem chef→meinem Chef, auf einem meeting→in einem Meeting,
        //    mit der investor→mit dem Investor, plus auxiliary cleanup
        //    "weil er war"→"weil er ... war" (V2/V-final).
        SpikeFixture(
            text: "gestern habe ich der email an die team geschickt aber die antwort von dem chef war noch nicht gekommen weil er war auf einem meeting mit der investor.",
            language: "de"
        ),
        // 3) Code-switched German+English: tests that English technical
        //    terms stay in English (NOT translated), get noun-capitalized
        //    per German orthography, while German grammar/punctuation get
        //    cleaned. Realistic dictation pattern in tech contexts.
        //    Expected: product owner → Product Owner, deadline → Deadline,
        //    release → Release, "nicht realistic" stays English-adjective.
        SpikeFixture(
            text: "ich habe heute mit dem product owner gesprochen über die deadline für das release und er meinte das ist nicht realistic also müssen wir einen workaround finden.",
            language: "de"
        ),
        // 4) Long multi-clause dictation (~10 clauses) — closer to
        //    real-world utterance length. Embeds Phase-20.06 hooks:
        //    spelled currency ("dreihundert franken"), spelled percentage
        //    ("hundertfünfzig prozent"), year-as-non-thousands (2026),
        //    Swiss orthography (strasse, grossen), known dialect-trigger
        //    word ("natürlich"), and a proper noun (Bahnhofstrasse).
        //    Probes long-context coherence + per-clause decision quality.
        SpikeFixture(
            text: "ich war letzte woche in zürich auf einer konferenz und das hotel hat ungefähr dreihundert franken pro nacht gekostet was natürlich völlig überteuert ist aber ich konnte nichts billigeres finden weil im jahr 2026 alle hotels in der innenstadt um die hundertfünfzig prozent teurer geworden sind seit der grossen renovation der bahnhofstrasse.",
            language: "de"
        ),
        // 5) Long English utterance — verifies variant g (de path) doesn't
        //    bleed into the English base-default path. Run-on, no
        //    punctuation, missing apostrophes (i wasnt, im).
        SpikeFixture(
            text: "so yesterday i went to the office and there was this big meeting about the q3 numbers but to be honest i wasnt really paying attention because im super tired this week and i think i need to take some time off soon maybe next month or something.",
            language: "en"
        ),
        // 6) Non-native broken grammar — tests grammatical reconstruction +
        //    gap filling. Per 20.08-VARIANT-G-RATIONALE.md §5.
        SpikeFixture(
            text: "Ich gestern gehen Markt und kaufen viele Apfel weil ich brauchen für Kuchen.",
            language: "de"
        )
    ]

    /// Variant (e): single-rule "Standard High German + Swiss orthography only".
    /// New contract per user 2026-04-28: do NOT preserve Swiss vocabulary at all
    /// (drop helvetism reference list, drop dialect-form trap list). Cleanup
    /// goal is plain Standard High German with only orthographic adaptation.
    /// The Plan 02 helvetism-delta gate catches any dialect leakage.
    static func buildVariantE(_ input: String) -> String {
        return """
        <start_of_turn>user
        INSTRUCTION: Edit the following German dictation for grammar, punctuation, and capitalization. Do not paraphrase. Do not substitute any word with a different word.
        LANGUAGE: de
        RULE 1: Output Standard High German words and grammar exactly as dictated.
        RULE 2: Apply Swiss orthography only — write ss instead of ß; write thousands as 1'250 not 1.250.
        INPUT: \(input)
        OUTPUT:<end_of_turn>
        <start_of_turn>model
        """
    }

    /// Variant (f): variant (e) + non-biasing few-shot.
    /// Each example demonstrates one rule (ß→ss, identity preservation,
    /// thousands separator) with diverse content so the model cannot copy
    /// any specific phrase — sidesteps the variant (d) collapse where
    /// few-shot examples bled into outputs.
    static func buildVariantF(_ input: String) -> String {
        return """
        <start_of_turn>user
        INSTRUCTION: Edit the following German dictation for grammar, punctuation, and capitalization. Do not paraphrase. Do not substitute any word with a different word.
        LANGUAGE: de
        RULE 1: Output Standard High German words and grammar exactly as dictated.
        RULE 2: Apply Swiss orthography only — write ss instead of ß; write thousands as 1'250 not 1.250.
        EXAMPLES:
        INPUT: das war groß und teuer
        OUTPUT: das war gross und teuer
        INPUT: ich gehe morgen einkaufen
        OUTPUT: ich gehe morgen einkaufen
        INPUT: 1.250 Franken sind genug
        OUTPUT: 1'250 Franken sind genug
        INPUT: \(input)
        OUTPUT:<end_of_turn>
        <start_of_turn>model
        """
    }

    /// Variant (g) English path: same INSTRUCTION shell as the German path
    /// but without RULE 2 (Swiss orthography only applies to de). Mirrors
    /// what the production CleanupPrompt would emit when language == "en":
    /// the LANGUAGE tag flips and the Swiss-only rule is dropped, so the
    /// model has no German bias. RULE 1 keeps the model anchored to
    /// Standard English so it doesn't drift into translation.
    static func buildVariantGEnglish(_ input: String) -> String {
        return """
        <start_of_turn>user
        INSTRUCTION: Clean up the following English dictation. Fix grammar errors. Capitalize and punctuate correctly. Fill in obvious gaps in broken or incomplete speech. If a word is clearly wrong because the speech recognizer misheard it or the speaker mispronounced it, replace it with the correct word. Do not replace words that have a valid meaning in context, even when alternatives are possible. Preserve the speaker's intent. Do not rewrite or rephrase what is already clean.
        LANGUAGE: en
        RULE 1: Output Standard English.
        TEXT: \(input)<end_of_turn>
        <start_of_turn>model
        """
    }

    /// Variant (g): cleanup contract per 20.08-VARIANT-G-RATIONALE.md §3
    /// Draft 3. Replaces variant (e)'s identity-preservation contract
    /// with permitted cleanup (grammar, capitalization, punctuation,
    /// gap-filling, contextual mishear repair) while keeping the
    /// anti-dialect output and Swiss-orthography rules. RULE 1 carries
    /// no negative-particle list — Plan 02's helvetism-delta gate is the
    /// runtime backstop. RULE 2 corresponds to the Swiss-toggle ON path
    /// in production (the toggle gates ONLY orthography per A2).
    ///
    /// Prompt shape: aligns with production CleanupPrompt.swift (TEXT:
    /// trailer, no OUTPUT: pseudo-completion line). The earlier
    /// INPUT/OUTPUT framing inherited from variants (e)/(f) caused
    /// Gemma to emit stray structural prefixes (":", ",", "_response>")
    /// when the dangling OUTPUT: primed it to start with a marker.
    ///
    /// Mishear clause hardened: "does not fit" → "clearly wrong /
    /// makes no sense" to stop the model from swapping valid words for
    /// alternatives (e.g. "ausgeflogen" → "ausgefallen" in Wave A run 1).
    ///
    /// Draft 4 (Wave A run 5): two tightenings from run 4 failures.
    /// (A) Anti-translation for code-switched English: "realistic" was
    /// translated to "realistisch" in F3 — same failure class as the
    /// Phase 20.06 anti-Swiss-translation pattern, transposed en→de.
    /// (B) Sentence-initial capitalization: "Capitalize and punctuate
    /// correctly" was too soft — F3 left "ich" lowercase at sentence
    /// start. Made the rule explicit: first letter of every sentence
    /// + all German nouns.
    ///
    /// Draft 5 (Wave A run 6): tweak A failed in run 5 — model still
    /// translated "realistic" → "realistisch". Strengthening to a named
    /// failure mode + concrete example, scoped narrowly enough that it
    /// won't pollute outputs the way variant (d)'s broader few-shot did.
    ///
    /// Draft 6 (Wave A run 7): three changes from run 6 critique.
    /// (D) Preservation guard relaxed: scoped "do not rewrite" to
    /// already-correct-and-natural text, with explicit permission to
    /// restructure unnatural/anglicized word order or broken non-native
    /// German. Rationale: runs 5/6 saw F6 (pidgin) frozen verbatim and
    /// F3 (anglicized "gesprochen über die Deadline") un-restructured —
    /// the longer prompt was over-firing the preservation rule.
    /// (E) New RULE 3: spelled cardinals ≥13 → digits, with the
    /// currency-rappen idiom ("vier Franken fünfzig") carved out so the
    /// rule doesn't break partial-amount patterns.
    /// (F) Year carve-out in RULE 2: years (1000-2999) keep no thousands
    /// separator. Mirrors the deterministic-Swift backlog rule but moves
    /// it into the LLM contract since RULE 3 will produce more numbers
    /// for the formatter to potentially mis-fold.
    static func buildVariantG(_ input: String) -> String {
        return """
        <start_of_turn>user
        INSTRUCTION: Clean up the following German dictation. Fix grammar errors. Capitalize the first letter of every sentence and all German nouns. Punctuate correctly. Fill in obvious gaps in broken or incomplete speech. If a word is clearly wrong because the speech recognizer misheard it or the speaker mispronounced it, replace it with the correct word. Do not replace words that have a valid meaning in context, even when alternatives are possible. Anglicisms (English words used in German) must stay in their English form — for example, "realistic" stays "realistic", not "realistisch". Preserve the speaker's intent. Do not rewrite or rephrase text that is already grammatically correct and natural. If the word order is unnatural or anglicized, or if the German is broken or non-native, restructure it into fluent Standard High German.
        LANGUAGE: de
        RULE 1: Output Standard High German.
        RULE 2: Apply Swiss orthography — write ss instead of ß; write thousands as 1'250 not 1.250. Years stay without a thousands separator (write 2026, not 2'026).
        RULE 3: Numbers spoken as words should be written as digits when they are 13 or higher — for example, "dreihundert" becomes "300", "hundertfünfzig" becomes "150". Exception: in currency amounts with a rappen or cent suffix (like "vier Franken fünfzig"), keep both numbers spelled out.
        TEXT: \(input)<end_of_turn>
        <start_of_turn>model
        """
    }

    /// Variant (g15) — production candidate from /tmp/spike-harness, ported
    /// for in-app UAT. Origin: g12 (off-Dicticus harness) with a six-token
    /// addition to the orthography clause (`Umlaute ä/ö/ü bleiben`) that
    /// kills the F3 muessen drift while keeping the prompt-shape identical
    /// to g12. g14 — which used a verbose 4-pair umlaut anchor — was
    /// disqualified because the bloated header caused F2 catastrophic
    /// prompt-leak and Deadline→Frist on F3.
    ///
    /// Multi-seed verification on F3 (post-ITN realistic input):
    ///   - g12: 8/8 muessen ASCII-fold drift (deterministic failure)
    ///   - g15: 0/8 muessen drift (fixed)
    /// Full sweep: 7/7 fixtures pass at the production sampler
    /// (temp 0.1, top-k 40, top-p 0.9, seed 0xDEADBEEF).
    ///
    /// Phase 20.08 apostrophe-strike: no thousands-separator clause in the
    /// prompt and no apostrophe in the third example. Deterministic Swift
    /// (`SwissNumberFormatter`) emits ungrouped integers, so any apostrophe
    /// the LLM might insert would be redundant noise.
    ///
    /// Shape note: this variant uses the few-shot ORIGINAL/KORRIGIERT frame
    /// (4 examples), NOT the variant-g instruction-only frame. The harness
    /// found few-shot stabilises Gemma 4 E2B at temp 0.1 when each example
    /// demonstrates a distinct rule (anglicism preservation, broken-grammar
    /// reconstruction, currency cents preservation, dialect-anti-drift).
    static func buildVariantG15(_ input: String) -> String {
        return """
        <start_of_turn>user
        Bereinige die folgende deutsche Sprachaufnahme. Schreibe Standard-Hochdeutsch mit Schweizer Rechtschreibung (ss statt ß, Umlaute ä/ö/ü bleiben). Verwende KEINEN Schweizerdeutsch-Dialekt — schreibe "Woche" nicht "Wuche", "Zürich" nicht "Züri", "ich gehe" nicht "i gang". Etablierte englische Fachbegriffe bleiben Englisch (Deadline, Meeting, Workaround, E-Mail, Team, Product Owner, Release). Untypische englische Adjektive oder Verben in deutschen Sätzen ins Deutsche übertragen — "realistic" → "realistisch", "awesome" → "toll", "appreciate" → "schätzen". Gib genau eine bereinigte Version aus, sonst nichts.

        ORIGINAL: ich habe heute mit dem product owner gesprochen über die deadline und er meinte das ist nicht realistic.
        KORRIGIERT: Ich habe heute mit dem Product Owner über die Deadline gesprochen, und er meinte, das ist nicht realistisch.

        ORIGINAL: ich gestern gehen markt und kaufen viele apfel weil ich brauchen für kuchen.
        KORRIGIERT: Ich bin gestern auf den Markt gegangen und habe viele Äpfel gekauft, weil ich sie für den Kuchen brauche.

        ORIGINAL: das hotel hat ungefähr 1250 franken 20 gekostet und das war zu viel.
        KORRIGIERT: Das Hotel hat ungefähr 1250 Franken 20 gekostet, und das war zu viel.

        ORIGINAL: letzte woche war ich in zürich auf einer grossen konferenz.
        KORRIGIERT: Letzte Woche war ich in Zürich auf einer grossen Konferenz.

        ORIGINAL: \(input)
        KORRIGIERT:<end_of_turn>
        <start_of_turn>model
        """
    }
}
#endif
