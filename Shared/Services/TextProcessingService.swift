import Foundation

/// Central orchestrator for the text processing pipeline.
///
/// Phase 20 D-02 pipeline shape:
///   Step 1   — Dictionary replacements
///   Step 2   — Rule-based ITN
///   Step 2b  — Swiss German ß → ss (Helvetisms, gated on useSwissGerman)
///   Step 2c  — RulesCleanupService (filler / self-correction / currency-fold)
///              [snapshot `rulesCleanedText` here for the Step 3a gate]
///   Step 3   — LLM cleanup (only when mode == .aiCleanup AND provider loaded)
///   Step 3a  — Levenshtein verification gate against the Step 2c snapshot
///              (only when the LLM call succeeded — D-19 fallback path is
///              additive: a thrown LLM returns its input unchanged, which
///              equals `rulesCleanedText`, so the gate is the identity).
///   Step 3b  — Swiss number formatter (post-pass canonicalization)
///   Step 4   — HistoryService.save (D-38 — `text` post-pipeline,
///              `rawText` pre-pipeline)
///
/// Cross-platform parity (CLAUDE.md memory `feedback_cleanup_cross_platform_parity`):
/// every change ships on macOS and iOS together via `Shared/`.
///
/// Phase 25-02 (2026-05-16) — plain-mode logging parity:
/// The `#if DEBUG_RECORDER` write block at the bottom of `process(...)` is
/// scope-level (NOT inside the `if mode == .aiCleanup` branch), so it
/// emits one JSONL record per call regardless of mode. For plain-mode
/// records, `steps.llm_prompt`, `steps.llm_raw`, `steps.post_gate` are
/// all nil (no LLM ran), `dictionary_context_keys` is `[]` (plain mode
/// never builds the targeted context), and `steps.post_rules` equals
/// `steps.post_swiss` (plain mode skips the rules-cleanup branch at
/// L114-120). Mode discrimination happens via the top-level `mode`
/// field, which carries `DictationMode.plain.rawValue == "plain"` or
/// `aiCleanup`. Same daily file (`cleanup-YYYY-MM-DD.jsonl`), same 14-day
/// retention — plain and aiCleanup records interleave in one stream.
/// Enables Phase 25-04's capture-window v2 to do plain-vs-AI A/B from
/// production data without a second log path.
///
/// Phase 25.1-01 (2026-05-17) — telemetry parity:
/// The `DebugCleanupRecord` now carries `lang_used` (mirror of `lang`) and
/// `emission_counter` (DebugRecorder-actor-monotonic per process). Both close
/// the 25-04 telemetry gaps (`jq` for `lang_used` returned null because the
/// field didn't exist; plain-mode emission near-zero couldn't be distinguished
/// from "user dictates AI mode only" without a monotonic counter). No
/// detection-layer change: TranscriptionService.detectLanguage (D-13) is
/// still the sole source — Parakeet TDT v3 emits no language code per
/// `macOS/Dicticus/Services/TranscriptionService.swift:395`.
@MainActor
class TextProcessingService: ObservableObject {

    private let dictionaryService: DictionaryService
    private let cleanupService: CleanupProvider?
    private let historyService: HistoryService
    /// Phase 20 D-02 — deterministic rules-first cleanup. Defaulted so
    /// existing call sites (DicticusApp, DictationViewModel) compile
    /// without modification.
    private let rulesCleanupService: RulesCleanupService
    /// Phase 36.5 Step 1b — hybrid fuzzy/phonetic brand matcher. Defaulted so
    /// existing call sites (DicticusApp, DictationViewModel) compile unchanged.
    private let brandMatcher: BrandMatcher

    /// Initialize with required services.
    init(
        dictionaryService: DictionaryService = .shared,
        cleanupService: CleanupProvider?,
        historyService: HistoryService = .shared,
        rulesCleanupService: RulesCleanupService = RulesCleanupService(),
        brandMatcher: BrandMatcher = .shared
    ) {
        self.dictionaryService = dictionaryService
        self.cleanupService = cleanupService
        self.historyService = historyService
        self.rulesCleanupService = rulesCleanupService
        self.brandMatcher = brandMatcher
        // Step 1b (Phase 36.5): supply the matcher's canonical list with the
        // user's LOCAL dictionary replacement targets at runtime (personal brands
        // stay local — never the repo seed). Wired here so BrandMatcher stays
        // decoupled from DictionaryService and compiles standalone.
        brandMatcher.liveDictionaryCanonicalProvider = {
            DictionaryService.shared.dictionary.values.map { $0.replacement }
        }
    }

    /// Process the transcribed text based on the mode and language.
    ///
    /// Phase 38 Plan 01 (CTXFMT-01/CTXFMT-02): `context` is the
    /// `DictationContext` resolved at hotkey press-time from the frontmost
    /// app's bundle ID (`HotkeyManager` + `ContextResolver`); `detectedBundleID`
    /// is the raw bundle ID that produced it, threaded through only for
    /// DEBUG_RECORDER telemetry. Both default so every pre-existing call site
    /// (5 test files, `EditGuardPipelineTests`, iOS) compiles and behaves
    /// unchanged. `context` only reaches the Step 3a.6 finishing-capitalization
    /// gate when `mode == .aiCleanup` — the plain path always sees `.default`
    /// (D-01 byte-identical-plain-path).
    func process(
        text: String,
        language: String,
        mode: DictationMode,
        confidence: Double = 1.0,
        context: DictationContext = .default,
        detectedBundleID: String? = nil
    ) async -> String {
        #if DEBUG_RECORDER
        if let cs = cleanupService as? CleanupService {
            cs.lastDebugTrace = nil
        }
        #endif

        let rawText = text

        #if DEBUG_RECORDER
        let dbgRawStart = Date()
        let dbgRawText = text
        #endif

        // Step 1: Dictionary replacements.
        // applyWithTrace is unconditional so dictTrace.replacements can be threaded
        // into gateContentWords as dictProtected (Step 3a). apply(to:) is a thin
        // wrapper anyway — no overhead difference (DictionaryService D-08).
        let dictTrace = dictionaryService.applyWithTrace(to: text)
        var processedText = dictTrace.text
        #if DEBUG_RECORDER
        var dbgReplacements = dictTrace.replacements
        var dbgBlocked = dictTrace.blocked
        let dbgPostDict = processedText
        let dbgPostDictMs = Date().timeIntervalSince(dbgRawStart) * 1000.0
        let dbgItnStart = Date()
        #endif

        // Step 1b (Phase 36.5): fuzzy/phonetic brand matcher — distinctive tokens
        // only. Runs after the dictionary pass and before acronym collapse, in
        // BOTH plain and AI mode (like the dictionary and ITN passes — NOT gated
        // on mode). Recovers misheard distinctive brand tokens the exact-match
        // dictionary misses; common-word brand homophones stay with the
        // dictionary's anchored entries (the hybrid split). BMATCH-03.
        processedText = brandMatcher.apply(to: processedText, language: language)

        // Step 1.5: Acronym fragment collapse + spoken-letter lexicon
        processedText = ITNUtility.collapseAcronymRun(to: processedText)

        // Step 1.5b: Spoken punctuation collapse (Phase 32 PUNCT-01/PUNCT-02)
        processedText = ITNUtility.collapseSpokenPunctuation(to: processedText)

        // Step 2: Rule-based ITN
        processedText = ITNUtility.applyITN(to: processedText, language: language)

        // Step 2a: Identifier–number punctuation collapse (Phase 32 PUNCT-02 extension).
        // Runs after ITN so model-name patterns like "mt minus 24" → "mt-24"
        // collapse once the number-word is a digit. Precision-gated; never touches
        // prose subtraction or number–number arithmetic.
        processedText = ITNUtility.collapseIdentifierNumberPunctuation(to: processedText)

        // Step 2a.5 (Phase 36.4 D-07/D-08): word-form decimal/version normalizer.
        // Converts "cardinal-word point cardinal-word" → "N.M" (e.g. "four point eight" →
        // "4.8", "two point five point one" → "2.5.1"). Runs pre-LLM and pre-snapshot so
        // NumberRevert's baseline already carries the normalized decimal form (D-10).
        processedText = ITNUtility.applyNumericStructuralWords(to: processedText, language: language)

        #if DEBUG_RECORDER
        let dbgPostItn = processedText
        let dbgPostItnMs = Date().timeIntervalSince(dbgItnStart) * 1000.0
        let dbgSwissStart = Date()
        // Phase 36.4-04 D-11: filename/date-string mangling probe.
        // Positioned after Step 2a.5 so the probe sees the full production post-ITN form.
        // Fire-and-forget (actor dispatch); never blocks the text path.
        await FilenameMangleProbe.shared.record(raw: rawText, postItn: processedText)
        #endif

        // Step 2b: Swiss German ß → ss (D-16) — runs on both plain AND AI-cleanup
        // paths whenever the useSwissGerman toggle is ON. Intentionally applies
        // regardless of language so users who dictate mixed de/en don't have
        // rogue Eszett slip through when Swiss orthography is selected.
        if DicticusDefaults.suite.bool(forKey: "useSwissGerman") {
            processedText = ITNUtility.applySwissITN(to: processedText)
        }

        #if DEBUG_RECORDER
        let dbgPostSwiss = processedText
        let dbgPostSwissMs = Date().timeIntervalSince(dbgSwissStart) * 1000.0
        let dbgRulesStart = Date()
        #endif

        // Step 2c (Phase 20 D-02): rules-first deterministic cleanup.
        // Filler removal, self-correction (comma-prefixed connectors only),
        // currency-fold.
        //
        // 2026-05-03 fix: Only apply rules-cleanup in AI mode. Plain dictation
        // should remain raw (except for ITN/Dictionary) per user feedback.
        //
        // 2026-05-06 fix: In AI mode, RUN the SelfCorrectionResolver again.
        //
        // The 2026-05-04 disable was based on the (incorrect) assumption that
        // pre-collapsing self-corrections would "defeat the V5 prompt
        // contract." In practice the inverse holds: V5 is strict-verbatim, so
        // the LLM is a passthrough — pre-collapsing here means the LLM gets
        // a clean phrase to capitalize/punctuate, no paraphrase risk. This
        // restores the auto-resolve behavior ("8 o'clock, no actually 7" →
        // "7 o'clock") without inheriting V4's over-generalization (V4
        // collapsed "I would say, and..." and "and so in between..." because
        // the model itself was tasked with the resolution; the rules
        // resolver is much narrower — comma-anchored connector + 3-token
        // backward window cap + abort-on-pronoun).
        if mode == .aiCleanup {
            // Phase 39/D-07: user-facing runtime toggle for the scratch-command
            // voice-edit feature. Default-ON-when-unset idiom (nil-check
            // `object(forKey:)` before `bool(forKey:)`) — a bare `bool(forKey:)`
            // returns `false` for an unset key, which would ship the feature
            // OFF for every existing user. This is a UX escape hatch, NOT the
            // safety mechanism — the compile-time gate flags in
            // SelfCorrectionResolver govern shipping independently of it.
            let enableVoiceCommands = DicticusDefaults.suite.object(forKey: "enableVoiceCommands") == nil
                ? true
                : DicticusDefaults.suite.bool(forKey: "enableVoiceCommands")
            processedText = rulesCleanupService.clean(
                processedText,
                language: language,
                skipSelfCorrection: false,
                enableVoiceCommands: enableVoiceCommands
            )
        }

        // Snapshot for the Step 3a Levenshtein gate. Capturing here means
        // the gate's reference baseline is the rules-cleaned text (in AI mode)
        // or the ITN-processed text (in Plain mode). A deliberate scratch-
        // command deletion above (Phase 39/D-08) is already inside this
        // baseline — the gate cannot revert it as content-loss.
        let rulesCleanedText = processedText

        #if DEBUG_RECORDER
        let dbgPostRules = processedText
        let dbgPostRulesMs = Date().timeIntervalSince(dbgRulesStart) * 1000.0
        var dbgGateEntry: DebugCleanupRecord.GateEntry? = nil
        var dbgDictKeys: [String] = []
        #endif

        // Step 3: AI Cleanup
        // D-08/MLANG-03 (Phase 42-02): a detected language other than German or English
        // skips the LLM cleanup stage entirely — processedText stays rulesCleanedText,
        // matching the existing plain-mode contract.
        if mode == .aiCleanup, let cleanupService = cleanupService, cleanupService.isLoaded,
           language == "de" || language == "en" {
            let lowerText = processedText.lowercased()

            // 2026-05-06 fix: Targeted-only dictionary context.
            //
            // Was: Phase 20.08 D-21 "adaptive phonetic matching" — every
            // dictionary REPLACEMENT target was included unconditionally as a
            // Known Term on every cleanup call. Intent: let Gemma recover
            // phonetic variants not explicitly listed (e.g. "Phasern" → ?).
            //
            // Cost: ~70 brand-name targets shipped on every prompt as a
            // substitution menu. Empirically (harness V5 vs V5T, 2026-05-06,
            // F46-F47), this caused the model to substitute *unfamiliar*
            // input tokens with plausibly-shaped menu entries —
            // "lm cleanup" → "AI Cleanup", "GSD" → "AI Cleanup", etc. —
            // exactly the over-eager substitution the user reported.
            //
            // Now: only surface a known term when its literal mishearing
            // KEY appears in the input. The dictionary still pre-passes
            // (Step 1) and deterministically replaces variants there;
            // the LLM gets a clean input plus a *targeted* hint only when
            // an explicit dictionary key matched. With the buffet gone the
            // model relies on context, which empirically recovers common
            // tech acronyms (LLM/API/etc.) better than the menu did.
            let filteredContext = dictionaryService.dictionary.reduce(into: [String: String]()) { result, pair in
                let original = pair.key
                let replacement = pair.value.replacement
                if lowerText.contains(original.lowercased()) {
                    result[original] = replacement
                }
            }

            #if DEBUG_RECORDER
            dbgDictKeys = Array(filteredContext.keys).sorted()
            #endif

            // Phase 38 Plan 01 (CTXFMT-01, approved scope extension): this
            // branch is already `mode == .aiCleanup`-gated, so `context` is
            // the live resolved context — this is the actual LLM call, not
            // just telemetry. The plain path never reaches this branch at
            // all, so D-01 byte-identical-plain-path is untouched by
            // construction.
            processedText = await cleanupService.cleanup(
                text: processedText,
                language: language,
                dictionaryContext: filteredContext,
                context: context
            )

            #if DEBUG_RECORDER
            let dbgGateStart = Date()
            #endif

            // Step 3a: Edit-level fidelity guard (D-01, Phase 44 Plan 11).
            //
            // Order is PINNED and load-bearing — do not reorder (see
            // testStep3aOrdering in EditGuardPipelineTests.swift):
            //   1. Reasoning-leak discard (44-09/T-44-25 defense layer c).
            //      CleanupService.cleanup() already runs this internally on
            //      the real implementation, but a `<think>` preamble must be
            //      structurally incapable of reaching the paste regardless of
            //      which CleanupProvider produced `processedText` — running
            //      it again here is idempotent on already-clean text and
            //      closes that gap for any provider that doesn't strip
            //      internally. `leaked == true` discards the whole output.
            //   2. CleanupService.prefilterLLMOutput (D-07): whole-output
            //      pre-filter — scaffolding leaks, imperative-input/
            //      assistant-voice injection, and a runaway length ratio all
            //      discard the LLM output wholesale, before the edit guard
            //      ever sees it (defense in depth alongside the guard's own
            //      internal prefilter call — two independent nets, D-07).
            //   3. The edit guard (D-01, `EditGuard`'s public entry point,
            //      called below): diffs the LLM output against the
            //      rules-cleaned baseline, classifies every edit against
            //      D-02..D-06, and rebuilds the output from the baseline plus
            //      ONLY the accepted edits. Replaces the THREE legacy
            //      whole-output/whole-window PASS/FAIL gates this Step used
            //      to call here — exactly the inverted-gate architecture D-01
            //      exists to replace (44-CONTEXT.md: the shipped gate
            //      rejected 12/19 good German repairs while passing 7 real
            //      corruptions). Those three are retired in
            //      CleanupService.swift (44-11 Task 2) — do NOT re-add them
            //      alongside the guard (D-01 is explicit on this).
            //   4. Step 3a.5 (below, unchanged): the deterministic number-form
            //      layer. It owns number FORM; the guard above owns VALUE
            //      (D-03). The guard never rewrites a digit — it only
            //      accepts or rejects the LLM's edit — so a same-value form
            //      change (`10` -> `zehn`) is ACCEPTED (`numberFormChange`)
            //      precisely so the form layer can normalize it back to
            //      `10`, while a value change (`10,011` -> `10,111`) is
            //      REJECTED so the form layer never sees it. No
            //      double-revert is possible.
            let (reasoningStrippedText, reasoningLeaked) = CleanupService.stripReasoningBlock(processedText)
            let guardResult: EditGuard.GuardResult
            if reasoningLeaked {
                guardResult = EditGuard.GuardResult(
                    text: rulesCleanedText, edits: [], failedClosed: true, failClosedReason: "reasoningLeak"
                )
            } else if !CleanupService.prefilterLLMOutput(rulesCleaned: rulesCleanedText, llmOutput: reasoningStrippedText) {
                guardResult = EditGuard.GuardResult(
                    text: rulesCleanedText, edits: [], failedClosed: true, failClosedReason: "prefilter"
                )
            } else {
                guardResult = EditGuard.apply(
                    rawText: rawText,
                    rulesCleaned: rulesCleanedText,
                    llmOutput: reasoningStrippedText,
                    language: language,
                    dictProtected: Set(dictTrace.replacements.map { $0.to })
                )
            }
            processedText = guardResult.text

            #if DEBUG_RECORDER
            let dbgGateMs = Date().timeIntervalSince(dbgGateStart) * 1000.0
            let verdict: String = (!guardResult.failedClosed && guardResult.edits.allSatisfy { $0.accepted })
                ? "passed" : "rejected"
            var dbgAcceptedByClass: [String: Int] = [:]
            var dbgRejectedByClass: [String: Int] = [:]
            for e in guardResult.edits {
                if e.accepted, let c = e.acceptClass { dbgAcceptedByClass[c, default: 0] += 1 }
                if !e.accepted, let c = e.rejectClass { dbgRejectedByClass[c, default: 0] += 1 }
            }
            dbgGateEntry = DebugCleanupRecord.GateEntry(
                text: processedText,
                verdict: verdict,
                edit_distance: nil,
                ms: dbgGateMs,
                edits: guardResult.edits.map {
                    DebugCleanupRecord.EditRecord(
                        kind: $0.kind, from: $0.from, to: $0.to,
                        accepted: $0.accepted, accept_class: $0.acceptClass, reject_class: $0.rejectClass
                    )
                },
                fail_closed_reason: guardResult.failClosedReason,
                accepted_by_class: dbgAcceptedByClass.isEmpty ? nil : dbgAcceptedByClass,
                rejected_by_class: dbgRejectedByClass.isEmpty ? nil : dbgRejectedByClass
            )
            #endif

            // Step 3a.5: the deterministic number-form layer. Reverts any
            // digit↔word FORM changes the LLM introduced vs. the ITN
            // baseline. rulesCleanedText is the post-ITN/rules snapshot;
            // language is already in scope.
            processedText = NumberRevert.apply(
                baseline: rulesCleanedText,
                output: processedText,
                language: language
            ).text
        }

        // Step 3a.6 (42-07/MLANG-01): deterministic post-gate capitalization.
        // Runs AFTER the Step 3a divergence gate (and NumberRevert) for EVERY
        // mode — plain and AI-cleanup — so a gate revert to the (often
        // lowercase ASR) rules baseline can never leave the pasted output
        // uncapitalized (42-05 UAT #21/#26/#15: "of course…", "and also…",
        // "what did i do" all landed lowercase because the gate reverted the
        // LLM's own capitalization). Pure + idempotent: already-correct text
        // passes through unchanged.
        // Phase 38 Plan 01 (D-01/D-03): only the aiCleanup branch may pass a
        // live (non-default) context into the finishing-capitalization gate
        // — plain mode ALWAYS passes `.default`, so a resolved code context
        // can never change plain-mode output (D-01 byte-identical guarantee).
        processedText = TextProcessingService.applyFinalCapitalization(
            processedText,
            language: language,
            context: mode == .aiCleanup ? context : .default
        )

        #if DEBUG_RECORDER
        let dbgSwissNumStart = Date()
        #endif

        // Step 3b: Swiss number formatting (D-C2/D-C3) — runs AFTER any
        // LLM cleanup so Gemma's German-decimal output (e.g. "2,5 Kilo",
        // "1.250,70") gets normalized to Swiss form. Runs whenever the toggle
        // is ON regardless of cleanup mode, so:
        //   • plain dictation also gets `1.250 → 1250` and `2,5 → 2.5`
        //   • LLM timeout / failure (CleanupService returns raw text on catch)
        //     does not silently lose Swiss number formatting
        // Phase 20.08: thousands grouping was struck (year-bug fix).
        // Idempotent on already-Swiss output, so a future re-introduction of
        // the post-LLM call inside CleanupService would not double-format.
        if DicticusDefaults.suite.bool(forKey: "useSwissGerman") {
            processedText = SwissNumberFormatter.format(processedText)
        }

        #if DEBUG_RECORDER
        let dbgPostSwissNumMs = Date().timeIntervalSince(dbgSwissNumStart) * 1000.0
        let dbgPostSwissNum = processedText
        #endif

        // Step 4: Save to History (UX-02)
        let entry = TranscriptionEntry(
            text: processedText,
            rawText: rawText,
            language: language,
            mode: mode.rawValue,
            confidence: confidence
        )
        historyService.save(entry)

        #if DEBUG_RECORDER
        // Phase 25-02: this record-assembly block runs for BOTH `mode == .plain`
        // AND `mode == .aiCleanup`. For plain-mode records: `cleanupTrace` is
        // nil (LLM never ran), so `llm_prompt`/`llm_raw` resolve to nil; the
        // `dbgGateEntry` variable stays at its outer-scope default of `nil`
        // (the AI branch above is the only thing that overwrites it), so
        // `post_gate` is nil too. `dbgDictKeys` stays `[]` (only the AI
        // branch populates it from the targeted dictionary context). The
        // resulting record carries `mode: "plain"` and the three LLM-section
        // keys are absent/null when JSON-encoded — exactly the schema Plan
        // 25-04's capture-window v2 expects for plain-vs-AI A/B.
        //
        // Capture trace from CleanupService (populated in cleanup() under
        // DEBUG_RECORDER). May be nil if mode != .aiCleanup, the model
        // wasn't loaded, or cleanup() threw before recording.
        let cleanupTrace: CleanupServiceTrace?
        if let cs = cleanupService as? CleanupService {
            cleanupTrace = cs.lastDebugTrace
        } else {
            cleanupTrace = nil
        }

        let llmPromptEntry: DebugCleanupRecord.LLMPromptEntry?
        let llmRawEntry: DebugCleanupRecord.LLMRawEntry?
        if let t = cleanupTrace {
            llmPromptEntry = DebugCleanupRecord.LLMPromptEntry(
                text: t.prompt,
                tokens_est: max(1, t.prompt.count / 4)
            )
            llmRawEntry = DebugCleanupRecord.LLMRawEntry(text: t.llmRaw, ms: t.llmMs)
        } else {
            llmPromptEntry = nil
            llmRawEntry = nil
        }

        let degenerateCollapse: Bool = {
            guard let raw = llmRawEntry else { return false }
            return raw.text.count < 5 && dbgRawText.count > 30
        }()
        let veryShort: Bool = processedText.count < 5 && dbgRawText.count > 30
        let emissionCounter = await DebugRecorder.shared.nextEmissionCounter()

        // Phase 28 R3 / WR-02: thread prompt_version explicitly from the
        // CleanupPrompt.currentVersion single source of truth so any future
        // version bump (V19E etc) carries through to JSONL without a silent
        // init-default drift.
        //
        // Phase 38 Plan 01 (D-10): prompt_version now buckets by resolved
        // context — a `.code`-context aiCleanup run tags itself `-code` via
        // CleanupPrompt.version(for:context:). Gated on `mode == .aiCleanup`
        // (mirrors the Step 3a.6 gate above) so a plain-mode record — which
        // never actually built an LLM prompt — is never mistagged with a
        // context suffix.
        let promptVersion = CleanupPrompt.version(
            for: .transcriptionist,
            context: mode == .aiCleanup ? context : .default
        )
        let record = DebugCleanupRecord(
            ts: DebugRecorder.iso8601Timestamp(),
            session_id: UUID().uuidString,
            lang: language,
            lang_used: language,    // Phase 25.1-01: alias of `lang` so jq queries against either field name produce correct results (closes 25-04 §Gap 1)
            mode: mode.rawValue,
            model: DebugCleanupRecord.ModelInfo(
                name: cleanupTrace?.modelName ?? "n/a",
                sha256_prefix: nil
            ),
            sampler: DebugCleanupRecord.SamplerInfo(
                temp: cleanupTrace?.samplerTemp ?? 0.1,
                top_k: cleanupTrace?.samplerTopK ?? 40,
                top_p: cleanupTrace?.samplerTopP ?? 0.9,
                max_tokens: cleanupTrace?.samplerMaxTokens ?? 512,
                seed: nil
            ),
            steps: DebugCleanupRecord.Steps(
                raw: .init(text: dbgRawText, ms: 0),
                post_dict: .init(text: dbgPostDict, ms: dbgPostDictMs),
                post_itn: .init(text: dbgPostItn, ms: dbgPostItnMs),
                post_swiss: .init(text: dbgPostSwiss, ms: dbgPostSwissMs),
                post_rules: .init(text: dbgPostRules, ms: dbgPostRulesMs),
                llm_prompt: llmPromptEntry,
                llm_raw: llmRawEntry,
                post_gate: dbgGateEntry,
                post_swiss_num: .init(text: dbgPostSwissNum, ms: dbgPostSwissNumMs)
            ),
            dictionary_context_keys: dbgDictKeys,
            dictionary_replacements: dbgReplacements.map { DebugCleanupRecord.DictionaryReplacementEntry(key: $0.key, from: $0.from, to: $0.to) },
            dictionary_blocked: dbgBlocked.map { DebugCleanupRecord.DictionaryBlockedEntry(key: $0.key, from: $0.from, to: $0.to, ratio: $0.ratio) },
            anomaly: DebugCleanupRecord.Anomaly(
                degenerate_collapse: degenerateCollapse,
                very_short_output: veryShort
            ),
            emission_counter: emissionCounter,   // Phase 25.1-01: monotonic per process — multi-day capture can prove dual-emission fired on every cycle (closes 25-04 §Gap 2)
            prompt_version: promptVersion,   // Phase 28 WR-02 / Phase 38 Plan 01 (D-10): context-aware version tag
            detected_bundle_id: detectedBundleID,   // Phase 38 Plan 01 (CTXFMT-02): local-only, never sent to any network endpoint
            // WR-02 fix: gated identically to promptVersion above — context only
            // ever reaches the pipeline (LLM prompt + finishing-capitalization gate)
            // when mode == .aiCleanup. Emitting the raw resolved context unconditionally
            // made a plain-mode record in a curated .code app claim "resolved_context":"code"
            // even though that context had zero effect on the record's text.
            resolved_context: (mode == .aiCleanup ? context : .default).rawValue   // Phase 38 Plan 01 (D-10)
        )
        await DebugRecorder.shared.record(record)
        #endif

        return processedText
    }

    // MARK: - Post-gate capitalization (42-07/MLANG-01)

    /// Deterministic post-gate capitalization: the first alphabetic
    /// character of `text`, plus (English only) the standalone pronoun "I"
    /// and its contractions (I'm, I've, I'll, I'd). `nonisolated` + `static`
    /// so it is a pure, MainActor-independent transform — directly testable
    /// without actor hops, matching the style of `SelfCorrectionResolver`.
    ///
    /// Idempotent and non-destructive: already-correct text passes through
    /// byte-identical. Never touches a letter mid-word (no acronym
    /// mangling), and never touches German "ich" (the English-"I" pass only
    /// runs when `language` starts with "en").
    ///
    /// Phase 38 Plan 01 (D-01/D-03, CTXFMT-01): `context` defaults to
    /// `.default`, reproducing today's behavior exactly for every existing
    /// call site. Only `context == .code` changes anything: a sentence-
    /// initial technical identifier (camelCase / snake_case / dotted-path /
    /// CLI-flag / version string — see `looksLikeTechnicalIdentifier`) is
    /// left uncapitalized instead of being forced upper-case.
    ///
    /// WR-04 (accepted, documented limitation): `capitalizeEnglishIPronoun`
    /// below is NOT gated on `context`. `.code`'s identifier-safe scope is
    /// deliberately limited to camelCase/snake_case/dotted-path/CLI-flag/
    /// version-string tokens (per `looksLikeTechnicalIdentifier`) — it does
    /// not extend to bare single-letter identifiers, so a dictated loop
    /// variable ("for i in range") still gets its standalone "i" forced to
    /// "I". Fixing this would require a new heuristic to distinguish a
    /// single-letter code identifier from the English pronoun with no
    /// syntactic marker to key off of — exactly the class of ad-hoc,
    /// unvalidated heuristic this project's measurement-discipline rules
    /// (R3/R6, project CLAUDE.md) warn against introducing into the
    /// capitalization pipeline without a corpus-grounded fixture set. Left
    /// as an accepted gap rather than a silent one.
    nonisolated static func applyFinalCapitalization(_ text: String, language: String, context: DictationContext = .default) -> String {
        guard !text.isEmpty else { return text }
        var result = capitalizeFirstAlphabeticCharacter(text, context: context)
        result = capitalizeSentenceInitials(result, context: context)
        if language.hasPrefix("en") {
            result = capitalizeEnglishIPronoun(result)
        }
        return result
    }

    /// Uppercase the first alphabetic character in `text`, leaving
    /// everything else (including any leading punctuation/quotes) untouched.
    /// A no-op if `text` has no alphabetic character, or if that character
    /// is already uppercase.
    ///
    /// Phase 38 Plan 01 (D-03): in `context == .code`, a no-op if the leading
    /// whitespace-delimited token looks like a technical identifier.
    nonisolated private static func capitalizeFirstAlphabeticCharacter(_ text: String, context: DictationContext) -> String {
        guard let idx = text.firstIndex(where: { $0.isLetter }) else { return text }
        if context == .code, looksLikeTechnicalIdentifier(leadingToken(of: text)) {
            return text
        }
        var result = text
        result.replaceSubrange(idx...idx, with: String(result[idx]).uppercased())
        return result
    }

    /// The first whitespace-delimited token in `text` (from the very start,
    /// independent of where the first letter falls) — includes any leading
    /// punctuation (`"editGuard`, `--verbose`) so `looksLikeTechnicalIdentifier`
    /// sees CLI-flag dashes and other leading marks intact.
    nonisolated private static func leadingToken(of text: String) -> String {
        var result = ""
        for c in text {
            if c.isWhitespace { break }
            result.append(c)
        }
        return result
    }

    /// Phase 38 Plan 01 (D-03, CTXFMT-01): true when `token` looks like a
    /// technical identifier — camelCase, snake_case, a dotted path/version
    /// string, or a CLI flag — that must NOT be sentence-capitalized in the
    /// `.code` context. Deliberately conservative: a false positive (skipping
    /// a capitalization that should have happened) is far cheaper than a
    /// false negative (mangling a real identifier), matching this file's
    /// `sentenceAbbreviationDenylist` philosophy. Used only when
    /// `context == .code` — never affects `.default`/`.prose` output.
    nonisolated static func looksLikeTechnicalIdentifier(_ token: String) -> Bool {
        guard !token.isEmpty else { return false }
        // CLI flag: "-verbose", "--verbose".
        if token.hasPrefix("-") { return true }
        // snake_case: internal underscore.
        if token.contains("_") { return true }
        // Dotted path / version string: "v3.6", "Shared/Services/x.swift".
        // Skip index 0 so a token starting with "." isn't misread (not a
        // shape this heuristic needs to handle).
        if token.dropFirst().contains(".") { return true }
        // camelCase: an uppercase letter preceded by a lowercase letter,
        // anywhere after the first character.
        let chars = Array(token)
        for i in 1..<chars.count where chars[i].isUppercase && chars[i - 1].isLowercase {
            return true
        }
        return false
    }

    /// D-10: closes the sentence 2..N capitalization gap that was previously
    /// only handled by the LLM, so the plain (rules-only) path loses nothing
    /// on capitalization relative to AI cleanup. Conservative — skip on any
    /// ambiguous case (zero-corruption over recall) rather than risk
    /// mis-capitalizing abbreviations, decimals, or ellipses.
    ///
    /// Members are NORMALIZED (lowercased, all `.` removed) so `p.m.` matches
    /// as `pm`. Criterion (R3 — written before the list): a token that, as
    /// the last word before a period, is a conventional abbreviation that
    /// does NOT end a sentence.
    nonisolated private static let sentenceAbbreviationDenylist: Set<String> = [
        // EN
        "eg", "ie", "etc", "vs", "cf", "al", "no", "mr", "mrs", "ms", "dr", "prof", "st", "am", "pm", "us", "uk",
        // DE
        "zb", "dh", "ua", "usw", "bzw", "vgl", "ca", "nr", "abs", "sog", "evtl", "inkl", "ggf", "str"
    ]

    /// Uppercase the sentence-initial letter after every `.`/`!`/`?` (DE +
    /// EN), i.e. sentences 2..N — `capitalizeFirstAlphabeticCharacter` only
    /// handles sentence 1. Conservative and idempotent: a terminator only
    /// fires when a closer run + single whitespace + a currently-lowercase
    /// letter follow it, ruling out decimals/versions (`4.8`, no whitespace
    /// after the dot), ellipses (a `.` immediately preceded by another `.`),
    /// already-capitalized text, and — for `.` only — abbreviations in
    /// `sentenceAbbreviationDenylist`.
    ///
    /// Phase 38 Plan 01 (D-03): in `context == .code`, a candidate
    /// sentence-initial token that looks like a technical identifier
    /// (`looksLikeTechnicalIdentifier`) is skipped instead of capitalized.
    nonisolated private static func capitalizeSentenceInitials(_ text: String, context: DictationContext = .default) -> String {
        var chars = Array(text)
        let closers: Set<Character> = ["\"", "'", ")", "]", "}", "\u{201D}", "\u{2019}", "\u{00BB}", "\u{203A}"]

        var i = 0
        while i < chars.count {
            let c = chars[i]
            guard c == "." || c == "!" || c == "?" else {
                i += 1
                continue
            }

            if c == "." && i > 0 && chars[i - 1] == "." {
                i += 1
                continue
            }

            if c == "." {
                var start = i
                while start > 0 && !chars[start - 1].isWhitespace {
                    start -= 1
                }
                let token = String(chars[start..<i]).lowercased().replacingOccurrences(of: ".", with: "")
                if sentenceAbbreviationDenylist.contains(token) {
                    i += 1
                    continue
                }
            }

            var j = i + 1
            while j < chars.count && closers.contains(chars[j]) {
                j += 1
            }
            guard j < chars.count, chars[j].isWhitespace else {
                i += 1
                continue
            }

            var k = j
            while k < chars.count && chars[k].isWhitespace {
                k += 1
            }
            guard k < chars.count else {
                i += 1
                continue
            }

            let candidate = chars[k]
            guard candidate != "ß", candidate.isLowercase else {
                i += 1
                continue
            }

            if context == .code {
                var end = k
                while end < chars.count && !chars[end].isWhitespace {
                    end += 1
                }
                let token = String(chars[k..<end])
                if looksLikeTechnicalIdentifier(token) {
                    i = end
                    continue
                }
            }

            let upper = candidate.uppercased()
            guard upper.count == 1, let upperChar = upper.first else {
                i += 1
                continue
            }
            chars[k] = upperChar
            i = k + 1
        }

        return String(chars)
    }

    /// Capitalize the standalone English pronoun "i" and its contractions
    /// ("i'm", "i've", "i'll", "i'd") as WHOLE tokens only — `\b` word
    /// boundaries mean "sit" / "kim" / a typo like "im" (no apostrophe) are
    /// never touched. Already-capitalized occurrences are skipped (the
    /// token's first character must be lowercase "i" to be rewritten), so
    /// this is idempotent on already-correct text.
    ///
    /// WR-04: runs unconditionally regardless of `context` — see the
    /// `applyFinalCapitalization` doc comment for why `.code`'s
    /// identifier-safe scope deliberately does not extend here.
    nonisolated private static func capitalizeEnglishIPronoun(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: "\\bi('m|'ve|'ll|'d)?\\b",
            options: [.caseInsensitive]
        ) else {
            return text
        }
        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return text }

        var result = text
        for match in matches.reversed() {
            guard let r = Range(match.range, in: result) else { continue }
            let token = String(result[r])
            guard token.first == "i" else { continue }  // already "I…" — idempotent skip
            let capitalized = "I" + token.dropFirst()
            result.replaceSubrange(r, with: capitalized)
        }
        return result
    }
}
