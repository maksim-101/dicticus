// CleanupBenchmark — on-device latency + peak-memory benchmark for the Phase 44
// Qwen2.5-vs-Qwen3.5 iOS decision (44-14 Task 1).
//
// WHY THIS EXISTS: the memory probe alone cannot answer the question that matters.
// llama.cpp mmaps the GGUF, so the weights are clean file-backed pages that do NOT
// count toward phys_footprint (the number jetsam kills on). The measured footprint
// therefore barely moves between a 1.93 GB and a 2.74 GB model — which means it is
// blind to the one way a bigger model could actually hurt a RAM-starved device:
// page-cache thrash, where mapped weight pages get evicted and re-faulted from disk
// every inference. That failure mode manifests as LATENCY, not as a crash.
//
// So latency is the second, independent measurement path. It is also SC#5's own
// acceptance criterion (~2-3 s budget).
//
// Inputs are invented strings shaped like post-rules text, spanning about 42-1290
// chars in both languages; the longest German case is the KV-cache worst case. Identical inputs across both models, so the comparison is controlled: unlike
// live dictation, ASR variance cannot contaminate it.
//
// Triggered only by the `-llmCleanupBenchmark 1` launch argument. Inert otherwise.
// Results are recorded through MemoryProbe, which is itself gated, so a reproduction
// run needs BOTH flags:
//
//   xcrun devicectl device process launch --device <udid> --terminate-existing \
//       com.dicticus.ios -- -memProbe 1 -llmCleanupBenchmark 1 \
//       [-llmModelFileOverride qwen3.5-4b-instruct-q4_k_m.gguf]
//
// then pull `Documents/memprobe.jsonl` with `devicectl device copy from`.

import Foundation

public enum CleanupBenchmark {

    /// Invented utterances shaped like post-rules text (pre-LLM), 4 DE + 4 EN, 42-1290 chars.
    static let cases: [(lang: String, text: String)] = [
        (lang: "de", text: "Also für das Sommerfest vom Turnverein habe ich mir überlegt, dass wir das dieses Jahr ein bisschen anders aufziehen als letztes Mal. Zuerst einmal würde ich gerne die Anmeldung über ein einfaches Formular machen, damit wir nicht wieder dreissig E-Mails mit unterschiedlichen Angaben bekommen und am Schluss niemand mehr weiss, wer jetzt einen Kuchen mitbringt und wer nicht. Dann bräuchten wir für den Grill mindestens zwei Leute, die sich abwechseln, und jemanden, der die Getränke koordiniert, also quasi schaut, dass genug Mineralwasser und Sirup da ist, und das Leergut am Abend wieder einsammelt. Bezüglich dem Programm war die Idee, dass die Kinder am Nachmittag einen kleinen Parcours machen können, und am Abend dann vielleicht eine Band oder zumindest jemand mit Gitarre, aber da bin ich mir noch nicht ganz sicher, ob das Budget dafür reicht. Ist das in Ordnung so? Hat jemand Einwände? Haben wir etwas vergessen? Und dann müssten wir noch klären, ob wir bei Regen in die Turnhalle ausweichen dürfen, da frage ich nächste Woche beim Hauswart nach, und ich würde vorschlagen, dass wir uns danach noch einmal kurz zusammensetzen, um die letzten offenen Punkte zu besprechen und die Aufgaben definitiv zu verteilen."),
        (lang: "de", text: "Ich weiss ehrlich gesagt nicht genau, welche Velowerkstätten in der Region Reparaturen noch am selben Tag machen. Kannst du zuerst einmal eine kleine Recherche machen, die Preise vergleichen und dann zwei gut bewertete Werkstätten auswählen, die in Frage kommen? Die nehmen wir dann als Grundlage für den Vergleich mit dem kleinen Laden bei uns im Dorf."),
        (lang: "de", text: "Im zweiten Abschnitt geht es um die Anreise, und da sollten wir den Begriff Treffpunkt durchgehend gleich verwenden. Sonst ist am Schluss niemand mehr sicher, wo wir uns treffen."),
        (lang: "de", text: "Erstelle eine Liste mit allen offenen Fragen."),
        (lang: "en", text: "So I finally managed to get through to someone at the appliance store who actually knew what they were talking about and she told me that they would take care of the dishwasher but first I would need to send them a photo of the serial number and the original receipt which I tried to find today and of course it was in the box with all the other paperwork in the basement and then one thing that she said that I want you to double check is that because the machine was delivered in March and not installed until May the warranty might actually be counted from the delivery date instead of the installation date which would mean that we are just outside the two year window and that they could refuse the repair or at least charge us for the technician's visit and her suggestion was that I should ask the installer for a written confirmation of the installation date because that is apparently what the manufacturer looks at when there is a dispute and if we have that confirmation then the warranty would still be valid and they would send someone next week so could you look through the emails from last spring and see if there is anything from the installer that mentions the date because I think they sent us an invoice but I am not completely sure whether it was by email or by post."),
        (lang: "en", text: "For the shared photo album it would be nice to keep two separate folders if that's possible, one for the pictures from the hike and one for the birthday dinner, because right now everything is mixed together and nobody can find anything."),
        (lang: "en", text: "Does the second option also cover my earlier question about booking not just the train but the hotel and the museum tickets in one go?"),
        (lang: "en", text: "okay that looks about right for the moment"),
    ]

    public static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "llmCleanupBenchmark")
    }

    public static var isOverflowProbeEnabled: Bool {
        UserDefaults.standard.bool(forKey: "llmOverflowProbe")
    }

    /// Walks the input up to and past the n_ctx/n_batch ceiling (2048), because the code's own
    /// comment says an over-long prompt "triggers GGML_ABORT inside llama_context::decode" —
    /// and GGML_ABORT calls abort(), i.e. it CRASHES rather than returning an error.
    ///
    /// Each length is logged BEFORE it is attempted and again after it survives, so if the app
    /// dies the last `overflow_try` line with no matching `overflow_ok` names the killer exactly.
    static func runOverflowProbe(using service: CleanupService, model: String) async {
        // An ordinary German sentence, repeated — keeps the token/char ratio realistic (~3.9 ch/tok).
        let unit = "Ich nehme den Zug um acht, nein, eigentlich um neun, und bin dann "
            + "gegen Mittag in Bern, falls unterwegs nichts dazwischenkommt. "

        for targetChars in [1_000, 2_000, 4_000, 6_000, 8_000, 12_000, 20_000] {
            var text = ""
            while text.count < targetChars { text += unit }

            await MemoryProbe.shared.mark(
                "overflow_try", model: model,
                note: "chars=\(text.count) est_tokens=\(text.count / 4)"
            )

            let start = Date()
            let out = await service.cleanup(text: text, language: "de", dictionaryContext: nil)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            let s = CleanupService.lastInferenceStats

            // unchanged == the D-19 fallback fired (empty/failed inference), i.e. cleanup silently
            // did nothing. truncated == the LLM returned materially less text than it was given.
            let unchanged = (out == text)
            let ratio = text.isEmpty ? 1.0 : Double(out.count) / Double(text.count)

            await MemoryProbe.shared.mark(
                "overflow_ok", model: model,
                note: "chars=\(text.count) ms=\(ms) ptok=\(s.promptTokens) gtok=\(s.generatedTokens) "
                    + "out_chars=\(out.count) ratio=\(String(format: "%.2f", ratio)) "
                    + "unchanged=\(unchanged) cancelled=\(s.cancelled)"
            )
        }

        await MemoryProbe.shared.mark("overflow_done", model: model, note: "survived all lengths")
    }

    /// Run every case `repetitions` times, recording latency and footprint per inference.
    /// Reports p50/p95 so a thrashing model is visible as a fat tail, not just a worse mean.
    static func run(using service: CleanupService, model: String, repetitions: Int = 3) async {
        await MemoryProbe.shared.mark("bench_start", model: model)

        var latenciesMs: [Double] = []

        for rep in 0..<repetitions {
            for (index, testCase) in cases.enumerated() {
                let start = Date()
                _ = await service.cleanup(
                    text: testCase.text,
                    language: testCase.lang,
                    dictionaryContext: nil
                )
                let elapsedMs = Date().timeIntervalSince(start) * 1000
                latenciesMs.append(elapsedMs)

                let s = CleanupService.lastInferenceStats
                await MemoryProbe.shared.mark(
                    "bench_case",
                    model: model,
                    note: "rep=\(rep) case=\(index) lang=\(testCase.lang) chars=\(testCase.text.count) "
                        + "ms=\(Int(elapsedMs)) ptok=\(s.promptTokens) gtok=\(s.generatedTokens) "
                        + "tokenize_ms=\(Int(s.tokenizeMs)) prefill_ms=\(Int(s.prefillMs)) "
                        + "decode_ms=\(Int(s.decodeMs)) stopcheck_ms=\(Int(s.stopCheckMs)) "
                        + "cancelled=\(s.cancelled)"
                )
            }
        }

        let sorted = latenciesMs.sorted()
        let p50 = percentile(sorted, 0.50)
        let p95 = percentile(sorted, 0.95)
        let summary = "n=\(sorted.count) p50_ms=\(Int(p50)) p95_ms=\(Int(p95)) max_ms=\(Int(sorted.last ?? 0))"

        await MemoryProbe.shared.mark("bench_summary", model: model, note: summary)
    }

    private static func percentile(_ sorted: [Double], _ q: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let rank = q * Double(sorted.count - 1)
        let lower = Int(rank.rounded(.down))
        let upper = Int(rank.rounded(.up))
        if lower == upper { return sorted[lower] }
        return sorted[lower] + (rank - Double(lower)) * (sorted[upper] - sorted[lower])
    }
}
