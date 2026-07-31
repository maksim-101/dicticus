import XCTest
@testable import Dicticus

/// Phase 36.6 Plan 04 (CLEANRD-03): grounding-lite deterministic backstops.
///
/// Covers the 0-harm contract (20-item clean-passthrough set from
/// `.planning/spikes/010-cleanup-redesign/eval_set.json`), positive leak-strip
/// fixtures (3 real leaking `llm` strings from
/// `.planning/debug/quality-hardening-260702/hallucination_cases.json`),
/// negative leak-strip fixtures (single-sentence + EN identity), and
/// letter-expansion guard positive/negative fixtures (eval_set.json
/// en-inve-030/032 + a genuine "C++" dictation).
///
/// Byte-identical with iOS/DicticusTests/GroundingLiteTests.swift per
/// cross-platform test convention (Shared/ changes ship macOS + iOS
/// together).
///
/// @MainActor: the leak-strip positive fixtures call `CleanupService.
/// stripPreamble`, which is MainActor-isolated (inherited from the
/// @MainActor CleanupService class), to simulate the real production
/// stripPreamble -> stripLeadingLeak pipeline order.
@MainActor
final class GroundingLiteTests: XCTestCase {

    // MARK: - 0-HARM: 20-item clean-passthrough set (eval_set.json)

    /// (language, gold_ideal) pairs for every `tag == "clean-passthrough"`
    /// item in eval_set.json. These are already-clean outputs — neither
    /// grounding-lite function may alter a single byte of any of them.
    private let cleanPassthrough: [(lang: String, text: String)] = [
        ("en", "Actually, I will hold off with verifying the work now and resume after a break. Could you please make sure we can just resume afterwards?"),
        ("en", "But I still can't log in with my Jellyfin credentials."),
        ("en", "But before you act on it, I want you to analyze the situation and get a holistic picture and then make a recommendation of what to change or how to change."),
        ("en", "What's your recommendation here and why?"),
        ("en", "It seems like you're not up to date with the current storage prices, which experienced quite the hike in the past few months and even years."),
        ("en", "Because I definitely would like to install Tailscale again, and then if possible Proton VPN as well, or at least some other VPN for travel or just being not at home."),
        ("en", "Because I clearly remember the senior support agent from Apple support telling me that the VPN configuration somehow might interfere with Apple's security protocols on their servers, which then might hinder network connectivity or something along those lines."),
        ("en", "So there's still a mistake in there. I currently have two Claude Code sessions open, but only one is shown."),
        ("de", "Also das klingt erst einmal spannend, diese Visual Document Retrieval, aber ich möchte auch klarstellen, dass die meisten Dokumente, auch PDF, nicht eingescannt sind. Also das sind keine Fotos von Dokumenten, sondern effektive Dokumente. Und ich weiss nicht, ob da OCR greift."),
        ("de", "Was du jeweils rechts vom Auftrag siehst, also wir haben eine Auftragsnummer, dann den Auftragstitel und dann ein blaues I-Symbol. Wenn ich da drauf klicke, geht ein Pop-Up auf, das mir den gesamten Auftrag anzeigt, also eine kleine Auftragsmaske, und was gestern noch aufkam, ist, dass die Auftragsnummer in dieser Journalliste wahrscheinlich nicht oder nur selten benötigt wird und dass die dann in der Journalliste verschwinden könnte und bei Bedarf über dieses I-Symbol aufgerufen werden könnte."),
        ("de", "Diese Klimaanlage ist anscheinend nur für 42 Quadratmeter geeignet."),
        ("de", "Wir sprechen dabei noch nicht von der Lösung, also eines fertigen Zielbildes und den daraus abgeleiteten operationalisierten Leitprinzipien, aber erst einmal eine Ergebnisaufbereitung und Auswertung."),
        ("de", "Aber seit neuestem beobachte ich zwei Dinge. Das eine ist, dass ich in der Texteingabe von Claude Code nun beliebig Text auswählen kann oder meinen Cursor setzen kann, wie in einem normalen Texteditor auch. Also nicht dieses normale Terminalverhalten. Und zudem gibt es auch wie einen Vollbildmodus von Claude Code selbst innerhalb des Terminalfensters, das durchaus angenehmer ist als die bisherige Erfahrung. Ist das ebenfalls möglich in"),
        ("de", "Ich glaube, die Richtung dieses Satzes stimmt. Doch kam hier natürlich auch die Frage auf, ob dann wirklich in jedem Fall, wenn das System, die KI, wer auch immer wirklich gut programmiert ist, der Mensch dann das besser weiss und wie einfach es ist, dem zu widersprechen. Ich glaube, es sollte keine Masterarbeit bedingen, um einem Maschinenvorschlag zu widersprechen, und trotzdem sollte man nicht einfach nur Nein klicken können oder nee, das passt mir jetzt nicht. Darum tue ich es nicht, so mit der Attitüde heranzugehen. Weisst du, was ich meine?"),
        ("en", "As for the orphaned code, you can delete it."),
        ("en", "Oh maybe I got the wrong moment. It's actually trying to initialize, but then it says failed setup."),
        ("en", "Is displayed. Can I delete this because I decommissioned all Aqara devices?"),
        ("de", "Und 10.000 Aufträge wurden ebenfalls erstellt. Davon wurden die meisten Aufträge des Auftragtyps in Tech. Also wenn jemand angerufen hat oder eine E-Mail geschrieben."),
        ("de", "Der Begriff KI kommt zu viel vor, sondern man merkt sofort, dass das von Claude oder einer anderen KI geschrieben wurde."),
        ("de", "Die KPI werden abgerundet mit einer abschliessenden Prüfvorlage, die vor allem für die Entscheidung bei neuen IT-Vorhaben gelten soll, die die Quintessenz der KPI, die vorhin aufgeführt worden, zusammenfasst in einer Frage."),
    ]

    func testZeroHarmOnCleanPassthroughSet() {
        XCTAssertEqual(cleanPassthrough.count, 20, "eval_set.json clean-passthrough count drifted — re-sync fixtures")

        var alteredCount = 0
        for (lang, text) in cleanPassthrough {
            let leakStripped = GroundingLite.stripLeadingLeak(text, language: lang)
            if leakStripped != text {
                alteredCount += 1
                XCTFail("stripLeadingLeak altered a clean-passthrough item (lang=\(lang)): \(text.prefix(60))...")
            }
            let letterGuarded = GroundingLite.guardLetterExpansion(input: text, output: text)
            if letterGuarded != text {
                alteredCount += 1
                XCTFail("guardLetterExpansion altered a clean-passthrough item (lang=\(lang)): \(text.prefix(60))...")
            }
            let knownTermsStripped = GroundingLite.stripLeakedKnownTerms(text)
            if knownTermsStripped != text {
                alteredCount += 1
                XCTFail("stripLeakedKnownTerms altered a clean-passthrough item (lang=\(lang)): \(text.prefix(60))...")
            }
        }
        XCTAssertEqual(alteredCount, 0, "Grounding-lite must alter 0/20 clean-passthrough outputs (no harm)")
    }

    // MARK: - POSITIVE: leak-strip on real hallucination_cases.json leaks

    /// The 3 real `llm` strings that leaked the full 8-line DE few-shot block
    /// (hallucination_cases.json). Feeding them through `CleanupService.
    /// stripPreamble` (removing the trailing `</corrected_text>` tag exactly
    /// as production does) then `GroundingLite.stripLeadingLeak` must yield
    /// the genuine body, byte-exact.
    private let leakCase1 = "Das Meeting ist um fünf. Meeting um neun, nein eigentlich um acht. Ich möchte einen Termin machen. Wir gehen ins Krankenhaus. Bitte prüfe, ob in der Zwischenzeit neue Rückmeldungen kamen. Für den Großteil. Ich habe drei Termine heute. Kannst du mir sagen, wie spät es ist? Das Ganze muss insgesamt klarer werden, besser verständlich, auf die Sprache der VDX abgestimmt, sowie auch möglichst konkret, und wahrscheinlich braucht es auch eine einleitende Präambel, die erläutert, um was es hier geht, weil zu Beginn der Vorstellung und auch Diskussionen zu diesem Zielbild da ging es dann ziemlich schnell mal darum, ja, welche Angebote dann wie geändert würden, etc. Und ich glaube, es braucht das Grundverständnis, dass wir hier von einer strategischen Ebene reden und eben auch strategische Leitprinzipien mitgeben, die dann für das operative relevant sind, das nachgelagert angegangen wird, auch in Form der Roadmap beispielsweise, die sie dann doch eher operativ oder taktisch und diese Leitprinzipien gelten dann für allgemeine Überlegungen oder auch Überprüfungen sowie auch für neue IT-Vorhaben.</corrected_text>"
    private let leakCase1Body = "Das Ganze muss insgesamt klarer werden, besser verständlich, auf die Sprache der VDX abgestimmt, sowie auch möglichst konkret, und wahrscheinlich braucht es auch eine einleitende Präambel, die erläutert, um was es hier geht, weil zu Beginn der Vorstellung und auch Diskussionen zu diesem Zielbild da ging es dann ziemlich schnell mal darum, ja, welche Angebote dann wie geändert würden, etc. Und ich glaube, es braucht das Grundverständnis, dass wir hier von einer strategischen Ebene reden und eben auch strategische Leitprinzipien mitgeben, die dann für das operative relevant sind, das nachgelagert angegangen wird, auch in Form der Roadmap beispielsweise, die sie dann doch eher operativ oder taktisch und diese Leitprinzipien gelten dann für allgemeine Überlegungen oder auch Überprüfungen sowie auch für neue IT-Vorhaben."

    private let leakCase2 = "Das Meeting ist um fünf. Meeting um neun, nein eigentlich um acht. Ich möchte einen Termin machen. Wir gehen ins Krankenhaus. Bitte prüfe, ob in der Zwischenzeit neue Rückmeldungen kamen. Für den Großteil. Ich habe drei Termine heute. Kannst du mir sagen, wie spät es ist? Wir sind bezüglich des Vorgehens so verblieben, dass ich das überarbeitete Zielbild in einem Word-Format in Zufügung stelle, damit Sie das noch einmal durchlesen und kommentieren können. Danach werde ich das nochmals überarbeiten oder Ihr Feedback einarbeiten und danach werde ich es zumindest bei der FK beantragen, alle Kader, die an der Direktionstagung teilgenommen haben, oder vielleicht insgesamt alle Kader anschreiben mit dem freiwilligen Aufruf, sich den aktuellen Entwurf anzusehen, anzuschauen und zu kommentieren. Ist das in Ordnung? Ist man irgendwo nicht einverstanden? Warum ging Ihnen etwas vergessen? Und man könnte beispielsweise auch einen Wettbewerb machen bezüglich Catchphrase. Also gestern war auch einer der Meinung, dass dieser Catchphrase eben nicht so gut ankommt, weil für ihn das Digitale nicht unbedingt im Hintergrund sein muss oder soll, sondern durchaus im Vordergrund. Und die Idee war, dass man dann das Zielbild, zumindest den aktuellen Stand, auf einem Miroboard oder ähnlich aufbereitet. Und da können dann alle, die wollen, kommentieren und Dinge hinzufügen etc. Also ein bisschen interaktiv, ein bisschen eine andere Art, als einfach nur im Word rumzuklicken oder einen Fragebogen zu versenden.</corrected_text>"
    private let leakCase2Body = "Wir sind bezüglich des Vorgehens so verblieben, dass ich das überarbeitete Zielbild in einem Word-Format in Zufügung stelle, damit Sie das noch einmal durchlesen und kommentieren können. Danach werde ich das nochmals überarbeiten oder Ihr Feedback einarbeiten und danach werde ich es zumindest bei der FK beantragen, alle Kader, die an der Direktionstagung teilgenommen haben, oder vielleicht insgesamt alle Kader anschreiben mit dem freiwilligen Aufruf, sich den aktuellen Entwurf anzusehen, anzuschauen und zu kommentieren. Ist das in Ordnung? Ist man irgendwo nicht einverstanden? Warum ging Ihnen etwas vergessen? Und man könnte beispielsweise auch einen Wettbewerb machen bezüglich Catchphrase. Also gestern war auch einer der Meinung, dass dieser Catchphrase eben nicht so gut ankommt, weil für ihn das Digitale nicht unbedingt im Hintergrund sein muss oder soll, sondern durchaus im Vordergrund. Und die Idee war, dass man dann das Zielbild, zumindest den aktuellen Stand, auf einem Miroboard oder ähnlich aufbereitet. Und da können dann alle, die wollen, kommentieren und Dinge hinzufügen etc. Also ein bisschen interaktiv, ein bisschen eine andere Art, als einfach nur im Word rumzuklicken oder einen Fragebogen zu versenden."

    private let leakCase3 = "Das Meeting ist um fünf. Meeting um neun, nein eigentlich um acht. Ich möchte einen Termin machen. Wir gehen ins Krankenhaus. Bitte prüfe, ob in der Zwischenzeit neue Rückmeldungen kamen. Für den Großteil. Ich habe drei Termine heute. Kannst du mir sagen, wie spät es ist? Also die Struktur ist nun viel klarer, die gefällt mir. Die behalten wir so bei. Doch in diesem Beispiel, gerade was das Prinzip, aber auch die Prüffrage betrifft. So sind diese für mich nach wie vor beispielhaft dafür, wie kompliziert und umständlich du gewisse Dinge formulierst. Wir müssen uns vor Augen halten, dass allerlei Personen dieses Zielbild und die Leitprinzipien lesen werden. Und es sollte so viele Leute wie nur möglich ansprechen. Und das heisst, dass wir eine einfach verständliche Sprache benutzen, die direkt ist und nicht über Umwege formuliert und beschreibt, was eigentlich gemeint ist. Mit einer einfach verständlichen Sprache meine ich aber nicht, und zwar ausdrücklich nicht leichte Sprache, davon halte ich nichts. Aber wir sollten von unnötig komplizierten Fachbegriffen Abstand nehmen und Sachverhalte, Zielzustände etc. so direkt wie nur möglich beschreiben.</corrected_text>"
    private let leakCase3Body = "Also die Struktur ist nun viel klarer, die gefällt mir. Die behalten wir so bei. Doch in diesem Beispiel, gerade was das Prinzip, aber auch die Prüffrage betrifft. So sind diese für mich nach wie vor beispielhaft dafür, wie kompliziert und umständlich du gewisse Dinge formulierst. Wir müssen uns vor Augen halten, dass allerlei Personen dieses Zielbild und die Leitprinzipien lesen werden. Und es sollte so viele Leute wie nur möglich ansprechen. Und das heisst, dass wir eine einfach verständliche Sprache benutzen, die direkt ist und nicht über Umwege formuliert und beschreibt, was eigentlich gemeint ist. Mit einer einfach verständlichen Sprache meine ich aber nicht, und zwar ausdrücklich nicht leichte Sprache, davon halte ich nichts. Aber wir sollten von unnötig komplizierten Fachbegriffen Abstand nehmen und Sachverhalte, Zielzustände etc. so direkt wie nur möglich beschreiben."

    func testLeakStripRemovesFullEightLineBlockCase1() {
        let stripped = CleanupService.stripPreamble(leakCase1)
        let result = GroundingLite.stripLeadingLeak(stripped, language: "de")
        XCTAssertEqual(result, leakCase1Body)
    }

    func testLeakStripRemovesFullEightLineBlockCase2() {
        let stripped = CleanupService.stripPreamble(leakCase2)
        let result = GroundingLite.stripLeadingLeak(stripped, language: "de")
        XCTAssertEqual(result, leakCase2Body)
    }

    func testLeakStripRemovesFullEightLineBlockCase3() {
        let stripped = CleanupService.stripPreamble(leakCase3)
        let result = GroundingLite.stripLeadingLeak(stripped, language: "de")
        XCTAssertEqual(result, leakCase3Body)
    }

    func testLeakStripIsSsTolerant() {
        // "Grossteil" (Swiss ss form) must match the constant "Für den Großteil."
        // exactly as the raw ß form does — ß/ss-tolerant per track-A §1.4.
        let output = "Für den Grossteil. Ich habe drei Termine heute. Das ist der echte Text."
        XCTAssertEqual(GroundingLite.stripLeadingLeak(output, language: "de"), "Das ist der echte Text.")
    }

    // MARK: - NEGATIVE: leak-strip must not over-reach

    func testLeakStripLeavesSingleLeadingCannedSentenceUntouched() {
        // >=2 rule: a single leading match must never be stripped.
        let output = "Ich habe drei Termine heute. Das ist ein völlig normaler Satz, den ein Nutzer sagen könnte."
        XCTAssertEqual(GroundingLite.stripLeadingLeak(output, language: "de"), output)
    }

    func testLeakStripIsIdentityForEnglish() {
        // DE-scoped: even a string starting with two of the known DE
        // constants must be left untouched when language != "de".
        let output = "Das Meeting ist um fünf. Meeting um neun, nein eigentlich um acht. Some genuine English text follows."
        XCTAssertEqual(GroundingLite.stripLeadingLeak(output, language: "en"), output)
    }

    // MARK: - POSITIVE: letter-expansion guard (eval_set.json en-inve-030/032)

    func testLetterGuardRevertsInventedHashOnBareLetter_enInve030() {
        let input = "Also, you talk about HDDD and C D D and then also K days."
        let output = "Also, you talk about HDDD and C# D D and then also K days."
        XCTAssertEqual(
            GroundingLite.guardLetterExpansion(input: input, output: output),
            "Also, you talk about HDDD and C D D and then also K days."
        )
    }

    func testLetterGuardRevertsInventedHashOnBareLetter_enInve032() {
        // Input dictates a lowercase "c" — matching is case-insensitive, and
        // the reversion preserves the OUTPUT's own casing (strips only the
        // suffix), matching the gold_ideal capitalization.
        let input = "Visually speaking, I liked your variants c, d and E the best."
        let output = "Visually speaking, I liked your variants C#, d and E the best."
        XCTAssertEqual(
            GroundingLite.guardLetterExpansion(input: input, output: output),
            "Visually speaking, I liked your variants C, d and E the best."
        )
    }

    func testLetterGuardRevertsPlusPlusSuffix() {
        let input = "My favorite letter is C."
        let output = "My favorite letter is C++."
        XCTAssertEqual(
            GroundingLite.guardLetterExpansion(input: input, output: output),
            "My favorite letter is C."
        )
    }

    // MARK: - NEGATIVE: letter-expansion guard must not over-reach

    func testLetterGuardLeavesGenuinelyDictatedPlusPlusUntouched() {
        // "C++" is present as a dictated token in the INPUT (not a bare "C")
        // — never revert a genuine dictation.
        let input = "I love programming in C++ and Python."
        let output = "I love programming in C++ and Python."
        XCTAssertEqual(GroundingLite.guardLetterExpansion(input: input, output: output), output)
    }

    func testLetterGuardIsIdentityWhenNothingToFix() {
        let text = "hello world, this has no single letters at all"
        XCTAssertEqual(GroundingLite.guardLetterExpansion(input: text, output: text), text)
    }

    // MARK: - POSITIVE: injected "Known terms" hint leak-strip (Phase 36.6 UAT 2026-07-03)

    /// Real on-device leak (cleanup-2026-07-03.jsonl entry 20): Qwen echoed the
    /// injected hint (paraphrased "EXACTLY"→"exactly", 1-space indent) ahead of a
    /// DE body. Must strip to the body byte-exact.
    func testKnownTermsLeakStrippedFromRealEntry20() {
        let leak = "Known terms — when these words or similar-sounding words appear, ensure they are spelled exactly as shown:\n GSD -> GSD\n\nUnd Hook Setup, vielleicht allfällige weitere Spezialkonfigurationen einer Person beschreiben, die mich nach meinen Erfahrungen mit GSD und Coding Agents fragt. Was sind hier vielleicht spezielle Dinge, die man als Tipps und Tricks hervorheben kann?"
        let body = "Und Hook Setup, vielleicht allfällige weitere Spezialkonfigurationen einer Person beschreiben, die mich nach meinen Erfahrungen mit GSD und Coding Agents fragt. Was sind hier vielleicht spezielle Dinge, die man als Tipps und Tricks hervorheben kann?"
        XCTAssertEqual(GroundingLite.stripLeakedKnownTerms(leak), body)
    }

    /// Verbatim injection header ("EXACTLY", 2-space indent) with multiple mapping
    /// lines → strips the whole block to the body.
    func testKnownTermsLeakStrippedVerbatimHeaderMultiMapping() {
        let leak = "Known terms — when these words or similar-sounding words appear, ensure they are spelled EXACTLY as shown:\n  clot code -> Claude Code\n  gsd -> GSD\n\nThis is the genuine dictated body."
        XCTAssertEqual(GroundingLite.stripLeakedKnownTerms(leak), "This is the genuine dictated body.")
    }

    /// Idempotent: a second pass is a no-op.
    func testKnownTermsStripIsIdempotent() {
        let leak = "Known terms — when these words or similar-sounding words appear, ensure they are spelled exactly as shown:\n gsd -> GSD\n\nBody text."
        let once = GroundingLite.stripLeakedKnownTerms(leak)
        XCTAssertEqual(GroundingLite.stripLeakedKnownTerms(once), once)
    }

    // MARK: - NEGATIVE: known-terms strip must not over-reach

    func testKnownTermsStripIdentityWhenNoHeader() {
        let text = "This is a normal sentence that happens to mention known terms in passing."
        XCTAssertEqual(GroundingLite.stripLeakedKnownTerms(text), text)
    }

    func testKnownTermsStripIdentityWhenHeaderNotLeading() {
        // Header signature only strips when it is the LEADING line.
        let text = "Here is my genuine intro. Known terms — when these words or similar-sounding words appear, ensure they are spelled exactly as shown:\n gsd -> GSD\n\ntail"
        XCTAssertEqual(GroundingLite.stripLeakedKnownTerms(text), text)
    }

    func testKnownTermsStripIdentityWhenNoBlankLineBoundary() {
        // Safe miss: header present but no blank-line separator → unchanged.
        let text = "Known terms — when these words or similar-sounding words appear, ensure they are spelled exactly as shown:\n gsd -> GSD\nbody glued without a blank line"
        XCTAssertEqual(GroundingLite.stripLeakedKnownTerms(text), text)
    }
}
