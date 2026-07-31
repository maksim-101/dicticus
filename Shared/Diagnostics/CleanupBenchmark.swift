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
// Inputs are real post-rules strings from the frozen 44-01 corpus snapshot, spanning
// 43-1248 chars in both languages — the longest German case is the KV-cache worst
// case. Identical inputs across both models, so the comparison is controlled: unlike
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

    /// Real corpus utterances (post-rules text, pre-LLM), 4 DE + 4 EN.
    static let cases: [(lang: String, text: String)] = [
        (lang: "de", text: "Wir sind bezüglich dem Vorgeh so verblieben, dass ich die das überarbeitete Zielbild in einem Word-Format in Zufügung stelle, damit Sie das noch einmal durchlesen und kommentieren können. Danach werde ich das nochmals überarbeiten oder Ihr Feedback einarbeiten und danach werde ich so werde ich es zumindest bei der fk beantragen alle kader, die an der Direktionstagung teilgenommen haben, oder vielleicht insgesamt alle Kader, anschreiben mit dem freiwilligen Aufruf, sich den aktuellen Entwurf anzusehen, anzuschauen und zu kommentieren. Ist das in Ordnung? Ist man irgendwo nicht einverstanden? Warum ging Ihnen etwas vergessen? Und man könnte beispielsweise auch einen Wettbewerb machen bezüglich Catchphrase. Also gestern war auch einer der Meinung, dass dieser Catchphrase eben nicht so gut ankommt, weil für ihn das Digitale nicht unbedingt im Hintergrund sein muss oder soll, sondern durchaus im Vordergrund. Und die Idee war, dass man dann das Zielbild, zumindest den aktuellen Stand, auf einem Miroboard oder ähnlich, aufbereitet. Und da können dann alle, die wollen, kommentieren und Dinge hinzufügen, etc. Also ein bisschen interaktiv, ein bisschen eine andere Art, als einfach nur im Word rumzuklicken oder einen Fragebogen zu versenden."),
        (lang: "de", text: "Ehrlich gesagt weiss ich nicht, welche BSP-Anbieter auf dem Schweizer Markt tätig sind. Da möchte ich, dass du erst einmal eine Anbieterrecherche machst, einen Anbietervergleich und dann selbstständig zwei gut dokumentierte und vielversprechende in Frage kommende Anbieter auswählst und diese dann quasi als Grundlage nimmst für den Vergleich mit NoxWork und Taskly."),
        (lang: "de", text: "Danach folgt das Prinzip, weil wir sprechen ja von Leitprinzipen, dann sollten wir also nicht gleich wieder einen neuen Begriff einführen. In diesem Prinzip wird beschrieben, um was es geht."),
        (lang: "de", text: "Erstelle eine Version 5 für die Änderungen."),
        (lang: "en", text: "So I finally was able to be connected to a senior engineer manager or something along these lines from Apple and she told me that they're going to take care of this but first I would need to get a mobile data analysis from my carrier that is Swisscom which I called today and one of the engineers there called me back and we went through my settings and all of that and then one thing that he said that I want you to verify is because my region is set to the United States instead of Switzerland this might actually be causing some issues since the frequency bands where we have you know different frequency bands between regions is actually not a hardware thing but rather a iOS thing so if I'm set to at the United States but have a Swiss sim as the main sim this actually is kind of like I'm abroad or like it's roaming from Apple's point of view and that if I were to set the region to Switzerland this kind of would change the iOS setting or base where I would then access different frequency bands and his hypothesis was that because of frequency incompatibilities or frequency differences these interruptions might actually occur because I'm on a frequency band that's not supported in Switzerland."),
        (lang: "en", text: "And as for the GitHub repo it actually would be nice to have two distinct versions if possible that is one for a local setup like we had initially as well as one for this remote setup with Docker image and remote remote connection like we have now."),
        (lang: "en", text: "Does option 2 play into my previous question about having not just a meeting tracker but other apps and services available on the path five?"),
        (lang: "en", text: "but in terms of size this is now adequate"),
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
        // A real German sentence, repeated — keeps the token/char ratio realistic (~3.9 ch/tok).
        let unit = "Ich muss mich hier korrigieren, denn eigentlich ist es ein grosser Monitor "
            + "und ein kleiner Monitor, und der kleine zählt fast nicht dazu. "

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
