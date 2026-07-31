import SwiftUI
import LlamaSwift
import os.log

/// Local LLM cleanup service using Qwen2.5-3B-Instruct via llama.cpp.
///
/// Phase 36.6 Plan 03 (2026-07-02, CLEANRD-01): swapped from Gemma 4 E2B to
/// Qwen2.5-3B-Instruct. Qwen uses ChatML (`<|im_start|>{role}\n…<|im_end|>`)
/// rather than Gemma's raw-completion format — `stopSequences` and
/// `stripPreamble` below are ChatML-aware. `runInference`'s EOG check
/// (`llama_vocab_is_eog`) is vocab-based and was already model-agnostic.
///
/// Per D-12: @MainActor ObservableObject following established service pattern.
/// Per D-05: llama.cpp Metal backend for Apple Silicon GPU acceleration.
/// Per D-06: No network calls during inference — fully local (AICLEAN-04).
/// Per D-17: 4-second total latency target (ASR ~1s + LLM ~3s).
/// Per D-18: 5-second timeout on LLM inference — fallback to raw text.
/// Per D-19: On any failure, return raw ASR text (never lose dictation).
///
/// Lifecycle: initialized during warmup (Plan 03), kept warm, cleanup() called per invocation.
/// KV cache cleared between calls to prevent context bleed (Pitfall 5 from RESEARCH.md).
/// Memory is cleared via llama_memory_clear(llama_get_memory(ctx), false) which is the
/// current llama.cpp API replacing the deprecated llama_kv_cache_clear.
///
/// Swift/C type mapping for llama.cpp:
///   - llama_model* → OpaquePointer (forward-declared struct)
///   - llama_context* → OpaquePointer (forward-declared struct)
///   - llama_sampler* → UnsafeMutablePointer<llama_sampler> (fully defined struct)
///   - llama_vocab* → OpaquePointer (forward-declared struct)
///   - llama_memory_t → OpaquePointer (typedef of llama_memory_i*, forward-declared)
@MainActor
class CleanupService: ObservableObject, CleanupProvider {

    /// Cleanup pipeline state. Observed by DicticusApp for icon state (D-14, D-15).
    enum State: Equatable, Sendable {
        case idle
        case cleaning
    }

    @Published var state: State = .idle

    /// Whether the LLM model is loaded and ready for inference.
    /// Set to true after successful loadModel() call.
    /// nonisolated(unsafe): loadModel runs off-MainActor (see Phase 20.06 fix —
    /// llama_model_load_from_file is a synchronous ~30s C call that previously
    /// blocked the UI when invoked via MainActor.run). Reads from cleanup()
    /// (MainActor) happen long after warmup completes — race window is benign.
    nonisolated(unsafe) private(set) var isLoaded = false

    // MARK: - llama.cpp resources (kept warm between calls)

    /// llama_model pointer — loaded once during warmup, freed in deinit.
    /// llama_model is forward-declared only in llama.h → OpaquePointer in Swift.
    /// nonisolated(unsafe): deinit is nonisolated in Swift 6, so non-Sendable C pointer
    /// properties must be marked nonisolated(unsafe) to be accessible from deinit.
    private nonisolated(unsafe) var model: OpaquePointer?
    /// llama_context pointer — created once during warmup, freed in deinit.
    /// llama_context is forward-declared only in llama.h → OpaquePointer in Swift.
    private nonisolated(unsafe) var context: OpaquePointer?
    /// Sampler chain — created once, reset between calls.
    /// llama_sampler is a fully-defined struct in llama.h → UnsafeMutablePointer<llama_sampler> in Swift.
    private nonisolated(unsafe) var sampler: UnsafeMutablePointer<llama_sampler>?

    /// Filename of the loaded GGUF model — captured during loadModel.
    /// Originally DEBUG_RECORDER-only (debug-trace consumption); Phase 44
    /// Plan 09 (T-44-25) widened this to always compile because
    /// `modelWantsReasoningPreclose(self.loadedModelName)` must be
    /// evaluatable in every build configuration, not just DEBUG_RECORDER.
    private nonisolated(unsafe) var loadedModelName: String = "unknown"

    #if DEBUG_RECORDER
    /// Trace from the most recent cleanup() invocation. TextProcessingService
    /// reads this immediately after awaiting cleanup() to assemble the JSONL
    /// record. Single-writer/single-reader — no lock needed.
    public nonisolated(unsafe) var lastDebugTrace: CleanupServiceTrace?
    #endif

    // MARK: - Configuration

    /// Maximum output tokens for cleanup. Dictation cleanup output is always
    /// shorter than or equal to input length, so 512 tokens is generous.
    /// Configurable per-platform via init (default matches macOS/iOS behavior).
    private let maxOutputTokens: Int32

    /// LLM inference timeout in seconds (per D-04 iOS, D-18 macOS).
    /// If exceeded, cleanup returns raw ASR text as fallback.
    /// Platform defaults diverge: iOS uses 8.0 s (Neural Engine is slower),
    /// macOS passes 5.0 s explicitly at call-site to preserve v1.x behavior.
    private let inferenceTimeoutSeconds: TimeInterval

    // MARK: - Initialization

    /// Platform-agnostic initializer. iOS uses the default 8 s timeout (D-04);
    /// macOS passes `inferenceTimeoutSeconds: 5.0` explicitly to preserve the
    /// tighter pre-extraction behavior.
    ///
    /// - Parameters:
    ///   - inferenceTimeoutSeconds: Per-call inference timeout before falling
    ///     back to raw ASR text. Default 8.0 (D-04, iOS-tuned).
    ///   - maxOutputTokens: Upper bound on generated tokens. Default 512 —
    ///     dictation outputs are always ≤ input length so 512 is generous.
    /// nonisolated so the warmup pipeline can construct the service from a
    /// background `Task.detached`, avoiding a MainActor hop just to allocate
    /// a couple of stored properties.
    nonisolated init(inferenceTimeoutSeconds: TimeInterval = 8.0, maxOutputTokens: Int32 = 512) {
        self.inferenceTimeoutSeconds = inferenceTimeoutSeconds
        self.maxOutputTokens = maxOutputTokens
    }

    /// Initialize the llama.cpp backend.
    /// Must be called once before loadModel(). Called during app warmup.
    /// nonisolated so the warmup pipeline can call it from a `Task.detached`
    /// without bouncing through MainActor.
    nonisolated static func initializeBackend() {
        llama_backend_init()
    }

    /// Load the GGUF model and create the inference context.
    ///
    /// Called once during warmup (ModelWarmupService Step 4).
    /// After this returns successfully, cleanup() can be called.
    ///
    /// - Parameter modelPath: File path to the cached GGUF model
    /// - Throws: CleanupError if model file cannot be loaded or context creation fails
    ///
    /// nonisolated: `llama_model_load_from_file` is a synchronous C call that
    /// takes ~30s on iOS for a 3 GB GGUF. Calling it on MainActor freezes the
    /// UI (Phase 20.06 hotfix — black-screen reproduce). All mutated state is
    /// either `nonisolated(unsafe)` (model/context/sampler/isLoaded) or `let`
    /// (config), so it's safe to run from a detached background task.
    nonisolated func loadModel(from modelPath: String) throws {
        // Model parameters: offload all layers to Metal GPU (D-05)
        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = 99  // All layers on Metal GPU

        guard let loadedModel = llama_model_load_from_file(modelPath, modelParams) else {
            throw CleanupError.modelLoadFailed
        }
        self.model = loadedModel

        // Context parameters for dictation cleanup
        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = Self.contextTokens    // Context window (prompt + output)
        // n_batch must accommodate the full prompt — runInference submits the
        // entire prompt as one llama_decode call (no chunking). Plan 20.08-05's
        // German variant (g15) prompt + a 250-token utterance crosses 512 tokens
        // and triggers GGML_ABORT inside llama_context::decode. Match n_batch to
        // n_ctx so any prompt fitting the context window decodes in one batch.
        //
        // ⚠️ Raising n_batch is what Phase 20.08 did, and it only MOVED the wall: the same
        // GGML_ABORT recurred at 2048 (verified on device, Phase 44 Plan 14 — an ~8000-char
        // dictation crashed the app with SIGABRT). The wall is now guarded in runInference
        // rather than merely relocated. Do not "fix" a future crash by bumping this number.
        ctxParams.n_batch = Self.contextTokens  // Batch size for prompt processing
        ctxParams.n_threads = 4                 // CPU threads (Metal handles matrix ops)

        guard let ctx = llama_init_from_model(loadedModel, ctxParams) else {
            llama_model_free(loadedModel)
            self.model = nil
            throw CleanupError.contextCreationFailed
        }
        self.context = ctx

        // Phase 44 Plan 09 (T-44-25): unconditional (was DEBUG_RECORDER-only)
        // — modelWantsReasoningPreclose needs this in every build config.
        self.loadedModelName = (modelPath as NSString).lastPathComponent

        // Phase 44 Plan 14: the weights are resident from here on, so this mark is
        // the constant floor every later peak sits on top of.
        let loadedName = self.loadedModelName
        Task { await MemoryProbe.shared.mark("llm_loaded", model: loadedName) }

        // Sampler chain: conservative settings for text cleanup (AICLEAN-02).
        // Phase 20.08: chain order matches llama-server's conventional order
        // (top_k → top_p → temp → dist). Earlier macOS code applied temp first,
        // which peaks the distribution before filtering and can collapse into
        // degenerate token loops on long inputs (observed on F4 in spike). The
        // /tmp/spike-harness path uses the conventional order and produces
        // clean output on identical params; aligning macOS removes the
        // divergence and unblocks long-sentence cleanup.
        let samplerChain = llama_sampler_chain_init(llama_sampler_chain_default_params())
        // Top-K 40: limit vocabulary to top candidates
        llama_sampler_chain_add(samplerChain, llama_sampler_init_top_k(40))
        // Top-P 0.9: nucleus sampling
        llama_sampler_chain_add(samplerChain, llama_sampler_init_top_p(0.9, 1))
        // Phase 20 D-01: temperature reduced from 0.2 → 0.1 to reduce hallucination rate.
        // Levenshtein gate (CleanupService.gateLLMOutput, plan 20.02) is the fail-safe.
        llama_sampler_chain_add(samplerChain, llama_sampler_init_temp(0.1))
        // Distribution sampling with random seed
        llama_sampler_chain_add(samplerChain, llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max)))
        self.sampler = samplerChain

        isLoaded = true
    }

    // MARK: - Cleanup

    /// Whether inference is currently running. Guards against concurrent cleanup calls
    /// that would race on the shared llama.cpp C pointers (model, context, sampler).
    private var isInferring = false

    /// ChatML turn markers (CLEANRD-01, Qwen2.5-Instruct) plus off-topic
    /// scaffold markers, applied both mid-generation (runInference's
    /// incremental check) and as a final post-strip. "In:"/"Original:"/
    /// "ORIGINAL:" (the v20 few-shot-frame stops) were dropped in Phase 36.6
    /// Plan 03 — the v-next prompt is few-shot-free, so those markers no
    /// longer bound a completion and could otherwise truncate legitimate
    /// dictation that happens to start that way.
    ///
    /// Phase 44 Plan 09 (T-44-25): "<think>" / "</think>" added as layer (b)
    /// of the three-deep reasoning-leak defense — an EARLY-STOP net against a
    /// Qwen3.5 reasoning preamble. If the model starts a `<think>` block,
    /// generation halts immediately rather than burning the token budget on
    /// a hidden reasoning pass a later strip would have to discard anyway.
    /// Harmless for the currently-shipping Qwen2.5: these two strings are
    /// ordinary text there and never appear in its output, so the stop check
    /// never fires — zero behaviour change for the shipping model.
    // nonisolated: read from inside the detached inference Task (Pitfall 7 —
    // same reasoning as the unsafeModel/unsafeContext/unsafeSampler captures
    // above). A `let` array of Sendable Strings is safe to read from any
    // isolation domain.
    nonisolated static let stopSequences: [String] = [
        "<|im_end|>", "<|im_start|>",
        "Please provide", "Based on", "Glossary:", "Examples:",
        "<think>", "</think>"
    ]

    /// Phase 44 Plan 09 (T-44-25): model-gated decision for
    /// `CleanupPrompt.build(..., reasoningPreclose:)`. Fires only for the
    /// Qwen3 family — verified against the on-disk Qwen3.5-4B GGUF
    /// (.planning/phases/44-cleanup-fidelity-guard/44-QWEN35-SMOKE.md) to
    /// have native `<think>`/`</think>` special tokens and a chat template
    /// that pre-closes the reasoning block by default. MUST return `false`
    /// for Qwen2.5: it has no `<think>` special token, so emitting the
    /// literal string would enter its context as ordinary text and could be
    /// echoed back verbatim.
    nonisolated static func modelWantsReasoningPreclose(_ modelName: String) -> Bool {
        modelName.lowercased().contains("qwen3")
    }

    /// Phase 44 Plan 09 (T-44-25): layer (c) of the three-deep reasoning-leak
    /// defense — the fail-closed backstop for anything layers (a) preclose
    /// and (b) stop-sequence miss.
    ///
    /// Removes every COMPLETE `<think>…</think>` span (non-greedy,
    /// dot-matches-newline). If a bare `<think>` or a stray `</think>`
    /// survives removal, this function does NOT attempt to salvage the
    /// text — it returns the ORIGINAL, UNCHANGED input with `leaked: true`.
    /// The caller must discard the whole output rather than paste a
    /// half-stripped reasoning fragment; a false-positive leak flag would
    /// discard every good LLM output, so this only fires on a genuine
    /// unclosed/stray tag, never on ordinary text (see
    /// `testStripReasoningBlockIsIdentityOnCleanText`).
    nonisolated static func stripReasoningBlock(_ s: String) -> (text: String, leaked: Bool) {
        guard let regex = try? NSRegularExpression(
            pattern: "<think>.*?</think>",
            options: [.dotMatchesLineSeparators]
        ) else {
            return (s, false)
        }
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        let stripped = regex.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "")
        if stripped.contains("<think>") || stripped.contains("</think>") {
            return (s, true)
        }
        return (stripped.trimmingCharacters(in: .whitespacesAndNewlines), false)
    }

    /// Clean up transcribed text using the local LLM.
    ///
    /// Per D-01: Conservative cleanup — grammar, punctuation, capitalization, filler removal.
    /// Per D-13: Language auto-selected from DicticusTranscriptionResult.language.
    /// Per D-18: 5-second timeout — returns raw text on timeout.
    /// Per D-19: On any failure, returns original text (never lose dictation).
    ///
    /// - Parameters:
    ///   - text: The text to clean up
    ///   - language: Detected language code
    ///   - dictionaryContext: Optional dictionary entries to guide the LLM
    ///   - context: Phase 38 Plan 01 (CTXFMT-01, approved scope extension):
    ///     the `DictationContext` resolved at hotkey press-time, threaded
    ///     straight into `CleanupPrompt.build(context:)` below. Defaults to
    ///     `.default` so this remains byte-identical to pre-Phase-38 output
    ///     for any caller that doesn't resolve a context. Internal name
    ///     `dictationContext` (external label stays `context` for
    ///     `CleanupProvider` conformance) — `self.context` is already the
    ///     llama.cpp `OpaquePointer` inference context; reusing that name
    ///     locally would shadow it.
    /// - Returns: Cleaned text, or original text on failure/timeout
    func cleanup(text: String, language: String, dictionaryContext: [String: String]? = nil, context dictationContext: DictationContext = .default) async -> String {
        let log = Logger(subsystem: "com.dicticus", category: "cleanup")

        guard isLoaded, let model = model, let context = context, let sampler = sampler else {
            log.warning("cleanup: model not loaded, returning raw text")
            Self.lastCleanupOutcome = .notLoaded
            return text  // D-19: Fallback to raw text
        }

        // Reject concurrent calls — C pointers are not thread-safe
        guard !isInferring else {
            log.warning("cleanup: inference already in progress, returning raw text")
            Self.lastCleanupOutcome = .alreadyRunning
            return text
        }

        isInferring = true
        state = .cleaning
        let inferenceModelName = self.loadedModelName
        defer {
            state = .idle
            isInferring = false
            // Phase 44 Plan 14: fires after inference, when the KV cache is at its
            // widest — the app's true high-water mark for this utterance.
            Task { await MemoryProbe.shared.mark("cleanup_done", model: inferenceModelName) }
        }

        // WR-03 fix (Phase 19.5): Snapshot the Swiss-toggle decision exactly
        // ONCE at the top of cleanup() and pass that same value to both the
        // prompt builder and the post-LLM Swiss formatting pass. Without this
        // snapshot, a user toggling the setting during the 0.5-8 s inference
        // window could cause prompt/post-pass disagreement (prompt instructs
        // Swiss output but post-pass skips formatting, or vice versa).
        let useSwissGerman = DicticusDefaults.suite.bool(forKey: "useSwissGerman")

        let prompt = CleanupPrompt.build(
            text: text,
            language: language,
            dictionaryContext: dictionaryContext,
            useSwissGerman: useSwissGerman,
            // Phase 38 Plan 01 (CTXFMT-01, approved scope extension): the
            // resolved context now reaches the ACTUAL prompt sent to the
            // LLM, not just the isolated build()/version() call surface.
            // .code/.prose still alias .default's body this plan (38-02
            // authors the real identifier-safe bodies) — but the seam is
            // live end-to-end.
            context: dictationContext,
            // Phase 44 Plan 09 (T-44-25): model-gated — fires only when
            // loadedModelName indicates a Qwen3 family model (never for the
            // currently-shipping Qwen2.5).
            reasoningPreclose: Self.modelWantsReasoningPreclose(self.loadedModelName)
        )
        log.info("Prompt (\(prompt.count, privacy: .public) chars, lang=\(language, privacy: .public)): \(prompt.prefix(500), privacy: .public)")

        // OUTPUT-BUDGET GUARD (Phase 44 Plan 14). Cleanup REWRITES the utterance, so the output
        // is about as long as the input. If the input needs more tokens than `maxOutputTokens`,
        // generation hits the cap mid-sentence and returns a TRUNCATED rewrite — which then
        // replaces the user's text. Measured on device: a 4002-char dictation came back at 57%
        // of its length; a 6072-char one at 6%.
        //
        // The prompt-side crash guard in runInference does NOT catch this: that 4002-char case
        // used only 1499 prompt tokens, comfortably under the context wall. The two limits are
        // independent, and this is the one that bites first.
        // The margin is load-bearing, not decoration. A cleaned utterance is usually a little
        // LONGER than its input (restored punctuation, expanded contractions), so a bare
        // `textTokens > maxOutputTokens` check still truncates at the boundary: on device, a
        // 2070-char utterance tokenized to ~511 — under the 512 cap — and generation then hit
        // the cap anyway and was cut mid-text.
        let textTokens = Self.tokenCount(text: text, model: model)
        let projectedOutputTokens = Int(Double(textTokens) * Self.outputGrowthMargin)
        if projectedOutputTokens > Int(maxOutputTokens) {
            log.error("""
                cleanup: utterance is \(textTokens, privacy: .public) tokens; projected output \
                \(projectedOutputTokens, privacy: .public) exceeds the generation cap \
                \(self.maxOutputTokens, privacy: .public) — the LLM cannot reproduce it in full and \
                would return TRUNCATED text. Skipping LLM, returning rules-cleaned text.
                """)
            Self.lastInferenceStats = InferenceStats(promptTokens: textTokens, exceededContext: true)
            Self.lastCleanupOutcome = .skippedTooLong
            return text
        }

        // Run inference in a detached task with timeout (D-04 iOS / D-18 macOS)
        // nonisolated(unsafe) for C pointer access in detached context (Pitfall 7)
        nonisolated(unsafe) let unsafeModel = model
        nonisolated(unsafe) let unsafeContext = context
        nonisolated(unsafe) let unsafeSampler = sampler
        let maxTokens = maxOutputTokens
        // Capture timeout locally for Sendable safety inside the task group closure.
        let timeout = self.inferenceTimeoutSeconds

        #if DEBUG_RECORDER
        let llmStart = Date()
        // Reset before each call so a thrown/timed-out path leaves no stale trace.
        self.lastDebugTrace = nil
        #endif

        do {
            let result = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    // Timeout task — honors the parameterized inferenceTimeoutSeconds
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    throw CleanupError.timeout
                }

                group.addTask {
                    // Inference task — checks Task.isCancelled between tokens
                    return Self.runInference(
                        prompt: prompt,
                        model: unsafeModel,
                        context: unsafeContext,
                        sampler: unsafeSampler,
                        maxTokens: maxTokens,
                        stopSequences: Self.stopSequences
                    )
                }

                // Return whichever finishes first
                guard let firstResult = try await group.next() else {
                    log.warning("cleanup: task group returned nil")
                    return text
                }
                group.cancelAll()
                return firstResult
            }

            #if DEBUG_RECORDER
            let llmMs = Date().timeIntervalSince(llmStart) * 1000.0
            self.lastDebugTrace = CleanupServiceTrace(
                prompt: prompt,
                llmRaw: result,
                llmMs: llmMs,
                modelName: self.loadedModelName,
                samplerTemp: 0.1,
                samplerTopK: 40,
                samplerTopP: 0.9,
                samplerMaxTokens: Int(self.maxOutputTokens)
            )
            #endif

            // Post-process: strip any preamble the model might add (Pitfall 4)
            log.info("LLM raw (\(result.count, privacy: .public) chars): \(result.prefix(500), privacy: .public)")

            // Phase 44 Plan 09 (T-44-25): layer (c), fail-closed reasoning-leak
            // backstop. Runs on the RAW LLM output, before stripPreamble's
            // envelope extraction — a <think> block sitting outside
            // <corrected_text> would otherwise be mis-parsed by
            // extractEnvelopeOrFallback. leaked==true discards the entire LLM
            // output and falls back to `text` (the rules-cleaned baseline this
            // function was called with) — the same D-19 "any failure -> raw
            // text" pattern already used for timeout/model-not-loaded above,
            // so a reasoning preamble is structurally incapable of reaching
            // stripPreamble, the gates, or the pasteboard.
            let (reasoningStripped, reasoningLeaked) = Self.stripReasoningBlock(result)
            if reasoningLeaked {
                log.warning("cleanup: <think> reasoning block survived stripReasoningBlock — discarding LLM output, returning rules-cleaned baseline (T-44-25 fail-closed)")
                return text
            }

            var cleaned = Self.stripPreamble(reasoningStripped)
            log.info("After strip (\(cleaned.count, privacy: .public) chars): \(cleaned.prefix(500), privacy: .public)")

            // Phase 36.6 Plan 04 (CLEANRD-03): grounding-lite deterministic backstops.
            // Hard guarantee behind the soft v-next prompt — only ever removes/reverts
            // toward the input, never invents or rewrites (see GroundingLite.swift).
            //
            // Leak-strip runs BEFORE Swiss ß→ss conversion (below) so it matches the
            // model's raw ß form of the known few-shot constants (track-A §1.4).
            cleaned = GroundingLite.stripLeadingLeak(cleaned, language: language)

            // Phase 36.6 UAT (2026-07-03): strip a leaked "Known terms — …" dictionary
            // hint the model sometimes regurgitates ahead of the real output. Runs BEFORE
            // the gate so the gate never sees (and passes) the injected block. Language-
            // agnostic — the injected hint is English even for DE dictation.
            cleaned = GroundingLite.stripLeakedKnownTerms(cleaned)

            // Letter-expansion guard: `text` is the pipeline's post-ITN/rules input to
            // the LLM — the correct reference for "was this letter bare in the input".
            cleaned = GroundingLite.guardLetterExpansion(input: text, output: cleaned)

            // D-B1c (Phase 19.5): Currency anti-flip post-LLM revert. Fires on
            // language == "de" regardless of Swiss toggle (per D-B2). Reverts any
            // model-substituted currency labels (e.g., EUR ← CHF) using positional
            // best-match against the input. Numeric values stay as the model wrote
            // them — only the currency LABEL is corrected. Graceful-degradation:
            // utility returns its `output` argument unchanged on any unexpected shape.
            if language == "de" {
                cleaned = CurrencyAntiFlip.revertCurrencyFlip(input: text, output: cleaned)
            }

            // D-19: Post-LLM Swiss ß→ss safety-net — catch any ß the LLM slipped in
            // despite the D-18 prompt instruction. WR-03 fix (Phase 19.5):
            // gated on the SAME `useSwissGerman` snapshot taken at the top of
            // cleanup(); a mid-inference toggle change cannot desync prompt
            // intent and post-pass formatting.
            //
            // Phase 19.5 follow-up: SwissNumberFormatter no longer runs here —
            // it moved to TextProcessingService Step 3b so it also fires for
            // plain dictation and for LLM timeout/failure paths (which return
            // the raw input text from this catch block).
            if useSwissGerman {
                cleaned = ITNUtility.applySwissITN(to: cleaned)
            }

            // Phase 28 Plan 03 — VARIANT-A-WINNER (per harness results/contraction_matrix_winner.md):
            // No post-LLM contraction gate. The V19D K2-contraction few-shot (Plan 28-01) alone
            // satisfied D-14 acceptance criteria. The harness runner remains in-tree
            // (.planning/debug/harness/run_contraction_matrix.py) for future re-runs.

            Self.lastCleanupOutcome = .applied
            return cleaned.isEmpty ? text : cleaned

        } catch CleanupError.timeout {
            log.error("cleanup timed out after \(timeout, privacy: .public)s — returning raw text")
            Self.lastCleanupOutcome = .timedOut
            return text
        } catch {
            log.error("cleanup error: \(error.localizedDescription, privacy: .public)")
            Self.lastCleanupOutcome = .failed
            // D-19: Any failure -> return raw text
            return text
        }
    }

    // MARK: - Inference (nonisolated for detached task execution)

    /// Run the llama.cpp inference loop.
    ///
    /// This is a pure function operating on C pointers — no actor isolation needed.
    /// The llama.cpp context window (prompt + generated tokens), and — because the whole prompt
    /// is submitted in one `llama_decode` — also the batch size. Single source of truth: the
    /// crash guard in `runInference` is derived from it, so the two cannot drift apart.
    nonisolated static let contextTokens: UInt32 = 2048

    /// How much longer a cleaned utterance can be than its input. Cleanup restores punctuation
    /// and expands contractions, so the output routinely exceeds the input by a few percent;
    /// without this headroom the output-budget guard truncates exactly at the boundary (measured:
    /// a ~511-token utterance passed a bare `> 512` check and was then cut mid-text at the cap).
    nonisolated static let outputGrowthMargin = 1.15

    /// Token count of `text` under the loaded model's vocabulary. Returns 0 when no model is
    /// loaded, which callers treat as "no constraint" — cleanup already bails earlier in that case.
    nonisolated static func tokenCount(text: String, model: OpaquePointer?) -> Int {
        guard let model else { return 0 }
        let vocab = llama_model_get_vocab(model)
        return tokenize(text: text, vocab: vocab, addSpecial: false, parseSpecial: false).count
    }

    /// Why a `cleanup()` call did (or did not) apply the LLM. The caller reads
    /// `lastCleanupOutcome` after an AI-cleanup invocation to surface an HONEST message when the
    /// text was inserted WITHOUT cleanup — instead of silently pasting raw text (the user pressed
    /// the AI-cleanup hotkey deliberately and must know it didn't run).
    enum CleanupOutcome: Sendable {
        case applied          // the LLM cleaned the text
        case skippedTooLong   // output-budget guard: utterance longer than the model can reproduce
        case timedOut         // inference exceeded inferenceTimeoutSeconds
        case notLoaded        // model not loaded / still warming
        case alreadyRunning   // a concurrent cleanup was in progress
        case failed           // any other inference error
    }

    /// Single-threaded by construction: `cleanup()` rejects concurrent calls (`isInferring`),
    /// so there is never a concurrent writer. Reset at each `cleanup()` return path.
    nonisolated(unsafe) static var lastCleanupOutcome: CleanupOutcome = .applied

    /// Phase 44 Plan 14: per-inference timing breakdown, published by `runInference` and read
    /// by `CleanupBenchmark`. Attributes latency to prefill vs decode rather than inferring it.
    struct InferenceStats: Sendable {
        var promptTokens: Int = 0
        var generatedTokens: Int = 0
        var tokenizeMs: Double = 0
        var prefillMs: Double = 0
        var decodeMs: Double = 0
        var stopCheckMs: Double = 0
        var cancelled: Bool = false
        /// The utterance was too long to clean; the LLM was skipped, not run and truncated.
        var exceededContext: Bool = false
    }

    /// Single-threaded by construction: `cleanup()` rejects concurrent calls (`isInferring`).
    nonisolated(unsafe) static var lastInferenceStats = InferenceStats()

    /// Called from a detached task inside cleanup().
    ///
    /// Steps:
    ///   1. Clear KV cache (Pitfall 5: prevent context bleed between calls)
    ///      Uses llama_memory_clear(llama_get_memory(ctx), false) — current API
    ///      replacing the removed llama_kv_cache_clear from older llama.cpp versions.
    ///   2. Reset sampler state
    ///   3. Tokenize prompt (via llama_vocab* from llama_model_get_vocab)
    ///   4. Decode prompt tokens (batch processing)
    ///   5. Sample output tokens until EOS or max_tokens
    ///   6. Detokenize output
    private nonisolated static func runInference(
        prompt: String,
        model: OpaquePointer,
        context: OpaquePointer,
        sampler: UnsafeMutablePointer<llama_sampler>,
        maxTokens: Int32,
        stopSequences: [String] = []
    ) -> String {
        // Step 1: Clear KV cache between calls (Pitfall 5)
        // llama_kv_cache_clear was removed; use llama_memory_clear instead.
        // llama_get_memory returns llama_memory_t (typedef for llama_memory_i*).
        // llama_memory_i is forward-declared only → OpaquePointer in Swift.
        let memory = llama_get_memory(context)
        llama_memory_clear(memory, false)

        // Step 2: Reset sampler state
        llama_sampler_reset(sampler)

        // Step 3: Tokenize prompt
        // vocab functions take llama_vocab* obtained from llama_model_get_vocab.
        // llama_vocab is forward-declared only → OpaquePointer in Swift.
        let vocab = llama_model_get_vocab(model)
        let tokenizeStart = Date()
        let promptTokens = tokenize(text: prompt, vocab: vocab, addSpecial: true, parseSpecial: true)
        let tokenizeMs = Date().timeIntervalSince(tokenizeStart) * 1000
        guard !promptTokens.isEmpty else { return "" }

        // CRASH GUARD (Phase 44 Plan 14). llama_decode does not RETURN an error when the batch
        // exceeds n_batch — it calls GGML_ABORT, which calls abort(). Verified on device: an
        // ~8000-character dictation produced SIGABRT through
        // ggml_abort <- llama_context::decode <- llama_decode <- runInference.
        //
        // Reserve room for generation too: the KV cache must hold prompt + generated tokens, or
        // llama_decode starts failing mid-loop and returns a truncated rewrite of the user's text.
        //
        // Returning "" routes into the existing D-19 fallback (`cleaned.isEmpty ? text : cleaned`),
        // so an over-long utterance degrades to rules-only text instead of killing the app.
        let capacity = Int(Self.contextTokens) - Int(maxTokens)
        guard promptTokens.count <= capacity else {
            let log = Logger(subsystem: "com.dicticus", category: "cleanup")
            log.error("""
                cleanup: prompt \(promptTokens.count, privacy: .public) tokens exceeds usable context \
                \(capacity, privacy: .public) (n_ctx \(Self.contextTokens, privacy: .public) − \
                maxTokens \(maxTokens, privacy: .public)) — skipping LLM, returning rules-cleaned text. \
                Calling llama_decode here would GGML_ABORT and crash the app.
                """)
            Self.lastInferenceStats = InferenceStats(
                promptTokens: promptTokens.count,
                exceededContext: true
            )
            return ""
        }

        // Step 4: Decode prompt tokens in a batch
        var batch = llama_batch_init(Int32(promptTokens.count), 0, 1)
        defer { llama_batch_free(batch) }

        batch.n_tokens = Int32(promptTokens.count)
        for (i, token) in promptTokens.enumerated() {
            batch.token[i] = token
            batch.pos[i] = Int32(i)
            batch.n_seq_id[i] = 1
            batch.seq_id[i]![0] = 0
            // Only compute logits for the last token in the prompt batch
            batch.logits[i] = (i == promptTokens.count - 1) ? 1 : 0
        }

        // PREFILL: the whole prompt — system prompt included — is decoded here, every call.
        // Timed separately because Phase 44 Plan 14 found a ~1.5 s floor on iOS even for a
        // 41-character input, which generation cannot explain.
        let prefillStart = Date()
        guard llama_decode(context, batch) == 0 else { return "" }
        let prefillMs = Date().timeIntervalSince(prefillStart) * 1000

        // Step 5: Sample output tokens
        // Reuse a single batch for token-by-token generation (avoids alloc/free per token)
        var outputTokens: [llama_token] = []
        var currentPos = Int32(promptTokens.count)
        var nextBatch = llama_batch_init(1, 0, 1)
        defer { llama_batch_free(nextBatch) }

        let decodeStart = Date()
        var stopCheckMs: Double = 0
        var cancelled = false

        while outputTokens.count < maxTokens {
            // Check for cooperative cancellation (timeout task fired)
            if Task.isCancelled { cancelled = true; break }

            let newToken = llama_sampler_sample(sampler, context, -1)

            // Check for end of generation using vocab-based EOG check
            if llama_vocab_is_eog(vocab, newToken) { break }

            outputTokens.append(newToken)

            // Check for stop sequences in the current output.
            // NOTE: this re-detokenizes and re-joins the ENTIRE output on every token —
            // O(n^2) in output length. Timed separately to size the cost before touching it.
            if !stopSequences.isEmpty {
                let stopStart = Date()
                let currentText = outputTokens.map { tokenToPiece(token: $0, vocab: vocab) }.joined()
                var shouldStop = false
                for stop in stopSequences {
                    if currentText.contains(stop) {
                        shouldStop = true
                        break
                    }
                }
                stopCheckMs += Date().timeIntervalSince(stopStart) * 1000
                if shouldStop { break }
            }

            // Prepare next batch with single token (reuse allocated batch)
            nextBatch.n_tokens = 1
            nextBatch.token[0] = newToken
            nextBatch.pos[0] = currentPos
            nextBatch.n_seq_id[0] = 1
            nextBatch.seq_id[0]![0] = 0
            nextBatch.logits[0] = 1

            guard llama_decode(context, nextBatch) == 0 else { break }
            currentPos += 1
        }

        let decodeMs = Date().timeIntervalSince(decodeStart) * 1000

        // Phase 44 Plan 14: publish the prefill/decode split so the benchmark can attribute
        // latency instead of guessing at it.
        Self.lastInferenceStats = InferenceStats(
            promptTokens: promptTokens.count,
            generatedTokens: outputTokens.count,
            tokenizeMs: tokenizeMs,
            prefillMs: prefillMs,
            decodeMs: decodeMs,
            stopCheckMs: stopCheckMs,
            cancelled: cancelled
        )

        // Step 6: Detokenize output
        var finalResult = outputTokens.map { tokenToPiece(token: $0, vocab: vocab) }.joined()
        
        // Final cleanup of stop sequences
        for stop in stopSequences {
            if let range = finalResult.range(of: stop) {
                finalResult = String(finalResult[..<range.lowerBound])
            }
        }
        
        return finalResult
    }

    // MARK: - Tokenization helpers

    /// Convert text to llama tokens.
    ///
    /// Uses llama_vocab* (not llama_model*) as required by the current llama.cpp API.
    /// llama_vocab is forward-declared only → OpaquePointer in Swift.
    private nonisolated static func tokenize(
        text: String,
        vocab: OpaquePointer?,
        addSpecial: Bool,
        parseSpecial: Bool
    ) -> [llama_token] {
        guard let vocab else { return [] }
        let utf8Count = text.utf8.count
        let upperBound = Int32(utf8Count) + 128  // Extra space for special tokens
        var tokens = [llama_token](repeating: 0, count: Int(upperBound))
        let nTokens = llama_tokenize(
            vocab,
            text,
            Int32(utf8Count),
            &tokens,
            upperBound,
            addSpecial,
            parseSpecial
        )
        guard nTokens >= 0 else { return [] }
        return Array(tokens.prefix(Int(nTokens)))
    }

    /// Convert a single token to its string representation.
    ///
    /// Uses llama_vocab* (not llama_model*) as required by the current llama.cpp API.
    /// llama_vocab is forward-declared only → OpaquePointer in Swift.
    private nonisolated static func tokenToPiece(token: llama_token, vocab: OpaquePointer?) -> String {
        guard let vocab else { return "" }
        var buffer = [CChar](repeating: 0, count: 256)
        let nChars = llama_token_to_piece(vocab, token, &buffer, 256, 0, false)
        guard nChars > 0 else { return "" }
        // Convert exactly nChars bytes to a Swift String — do NOT append a null
        // terminator. String(decoding:as:) includes ALL bytes, so an appended \0
        // becomes a Unicode NULL (U+0000) embedded in the string, causing invisible
        // gaps that render as double spaces.
        return String(decoding: buffer.prefix(Int(nChars)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    // MARK: - Post-processing

    /// Strip common LLM preamble patterns from output (Pitfall 4 from RESEARCH.md).
    ///
    /// Gemma 3 1B may prepend conversational text despite explicit "output ONLY"
    /// instructions. This strips known patterns and normalizes whitespace from
    /// token-by-token detokenization (leading spaces per token → double spaces).
    ///
    /// Phase 25.1-02: envelope extraction runs first (paper §6.2 Class D mitigation).
    static func stripPreamble(_ text: String) -> String {
        // Phase 25.1-02 — paper §6.2 XML envelope extraction (Class D mitigation).
        // When both <corrected_text> and </corrected_text> tags are present, extract
        // contents and apply <unk> stripping. Falls back to the original input when
        // either tag is missing (quantized models drop the closing tag on long outputs
        // — paper §6.2 documented risk). Existing pipeline then normalizes `working`.
        let working = extractEnvelopeOrFallback(text)

        // Step 0: Replace all Unicode whitespace variants with ASCII space.
        var result = working.unicodeScalars.reduce(into: "") { str, scalar in
            if scalar.value == 0 {
                return
            } else if scalar.properties.isWhitespace && scalar != "\n" {
                str.append(" ")
            } else if scalar == "\u{2581}" {
                str.append(" ")
            } else {
                str.append(Character(scalar))
            }
        }
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        // Step 0.5: Strip leaked chat-template fragments and 'response' markers.
        // Phase 36.6 Plan 03 (CLEANRD-01): extended for Qwen ChatML — matches a
        // bare `<|im_start|>` / `<|im_end|>` marker, and (when a role word
        // immediately follows the opening marker) consumes that role word too
        // so "<|im_start|>assistant" leaves no dangling "assistant" text behind.
        // Gemma's `<start_of_turn>`/`<end_of_turn>` markers are kept alongside
        // for defense-in-depth (e.g. stale cached prompts, harness comparisons).
        if let chatTemplateRegex = try? NSRegularExpression(
            pattern: #"<\|im_start\|>\s*(?:system|user|assistant)?\s*|<\|im_end\|>|</?(?:start_of_turn|end_of_turn)>(?:\s*(?:model|user))?|<bos>|<eos>|<\|endoftext\|>|_?response>|<response>|OUTPUT:|KORRIGIERT:"#,
            options: [.caseInsensitive]
        ) {
            let r = NSRange(result.startIndex..<result.endIndex, in: result)
            result = chatTemplateRegex.stringByReplacingMatches(
                in: result, options: [], range: r, withTemplate: ""
            )
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Step 1: Normalize whitespace and fix contractions
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        
        // Fix contractions artifact (tokenizer artifacts like "don ' t")
        let contractionRegex = try? NSRegularExpression(pattern: "([a-zA-Z]) ' ?([stdmveSTDMLVR])\\b", options: [])
        let range = NSRange(result.startIndex..<result.endIndex, in: result)
        result = contractionRegex?.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1'$2") ?? result

        // Fix spaces before punctuation (tokenizer artifact: "Hello , world" → "Hello, world").
        // The lookahead (?=\s|$|["')\]]) is load-bearing: it prevents " .claude" (dot followed
        // by a letter) from collapsing to ".claude", so dot-prefixed names survive (Pitfall 5).
        let punctSpaceRegex = try? NSRegularExpression(
            pattern: #"\s+([.,!?;:])(?=\s|$|["')\]])"#)
        let punctRange = NSRange(result.startIndex..<result.endIndex, in: result)
        result = punctSpaceRegex?.stringByReplacingMatches(
            in: result, options: [], range: punctRange, withTemplate: "$1") ?? result

        // Step 2: Strip surrounding double quotation marks and non-standard quotes (CLEAN-01)
        let doubleQuotes = CharacterSet(charactersIn: "\"“”„«»")
        result = result.components(separatedBy: doubleQuotes).joined()

        // Strip surrounding single quotes if they wrap the whole result
        if (result.hasPrefix("'") && result.hasSuffix("'")) ||
           (result.hasPrefix("‘") && result.hasSuffix("’")) {
            result = String(result.dropFirst().dropLast())
        }

        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }

        // Phase 36.4-02 D-06: Final-stage closed-list residue scrub.
        // Removes any scaffold tags that survived envelope extraction and earlier steps.
        // CLOSED LIST ONLY — never a generic `<[^>]+>` strip, so user-dictated
        // angle-bracket content (e.g. `<div>`) and dot-prefixed names (e.g. `.claude`)
        // are never clobbered. Placed AFTER the space-before-punct fix (Pitfall 2) so
        // the scrub itself cannot create " ." before dotted names.
        // The list covers: corrected_text open/close, output open/close.
        let scaffoldPatterns = [
            #"<\s*corrected_text\s*>"#,
            #"<\s*/\s*corrected_text\s*>"#,
            #"<\s*output\s*>"#,
            #"<\s*/\s*output\s*>"#,
        ]
        for pattern in scaffoldPatterns {
            if let rx = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let r = NSRange(result.startIndex..<result.endIndex, in: result)
                result = rx.stringByReplacingMatches(in: result, options: [], range: r, withTemplate: "")
            }
        }
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }

        return result
    }

    /// Phase 25.1-02 — extract content from the `<corrected_text>...</corrected_text>`
    /// envelope AND strip `<unk>` ASR-leak sentinels. Pure function.
    ///
    /// Handles four shapes of model output:
    ///   1. Full envelope:  `<corrected_text>X</corrected_text>`  → `X`
    ///   2. Opening only:   `<corrected_text>X`                    → `X`  (model truncated)
    ///   3. Closing only:   `X</corrected_text>`                   → `X`
    ///      (V18C/V19C pattern — opening tag pre-filled in the prompt as a
    ///      completion anchor at `CleanupPrompt.swift:202`, so the model
    ///      only emits content + closing tag)
    ///   4. No envelope:    `X`                                    → `X`  (passthrough)
    ///
    /// `<unk>` ASR sentinels are stripped in all four cases.
    ///
    /// Phase 36.4-02 (D-06): tag matching is whitespace-tolerant — `< corrected_text >` and
    /// `</ corrected_text >` (with spaces inside the angle brackets) are treated identically
    /// to the compact forms. This prevents whitespace-mangled scaffold tags from leaking
    /// to the output when BPE tokenization introduces inter-token spaces.
    ///
    /// Note: case (3) was treated as a fallback in 25.1-02's original implementation
    /// (closing tag passed through verbatim, deferred to Plan 06's NLD/Jaccard
    /// safety net). Plan 25.1-04 (V18C, 2026-05-18) and Plan 25.1-05 (V19C) made
    /// pre-fill the *normal* output shape, so this is now the dominant path —
    /// stripping the closing tag is required, not optional.
    private static func extractEnvelopeOrFallback(_ text: String) -> String {
        // Whitespace-tolerant tag patterns (D-06). Spaces are permitted inside angle
        // brackets so that BPE-mangled forms like "< corrected_text >" are recognised.
        let openPattern = #"<\s*corrected_text\s*>"#
        let closePattern = #"<\s*/\s*corrected_text\s*>"#
        let options: NSRegularExpression.Options = [.caseInsensitive]

        guard
            let openRegex = try? NSRegularExpression(pattern: openPattern, options: options),
            let closeRegex = try? NSRegularExpression(pattern: closePattern, options: options)
        else {
            // Regex compile failure (should never happen with literal patterns) — passthrough.
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        var inner: String

        if let openMatch = openRegex.firstMatch(in: text, options: [], range: fullRange) {
            let contentStart = openMatch.range.upperBound
            let afterOpen = NSRange(location: contentStart, length: nsText.length - contentStart)
            if let closeMatch = closeRegex.firstMatch(in: text, options: [], range: afterOpen) {
                inner = nsText.substring(with: NSRange(
                    location: contentStart,
                    length: closeMatch.range.location - contentStart
                ))                                                              // Case 1
            } else {
                inner = nsText.substring(from: contentStart)                   // Case 2
            }
        } else if let closeMatch = closeRegex.firstMatch(in: text, options: [], range: fullRange) {
            inner = nsText.substring(to: closeMatch.range.location)            // Case 3
        } else {
            inner = text                                                        // Case 4
        }

        // Class D mitigation: strip <unk> ASR sentinels (case-sensitive — only the
        // lowercase ASR-emitted form, NOT any user-typed <UNK> or similar).
        inner = inner.replacingOccurrences(of: "<unk>", with: "")
        return inner.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Resource deallocation

    deinit {
        if let sampler { llama_sampler_free(sampler) }
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
        // Note: llama_backend_free() is NOT called here — it's a global resource
        // that should only be freed at app termination, not when a service is deallocated.
    }
}

// MARK: - Errors

/// Errors specific to the LLM cleanup pipeline.
enum CleanupError: Error, Sendable {
    /// GGUF model file could not be loaded by llama.cpp
    case modelLoadFailed
    /// llama_context could not be created from the loaded model
    case contextCreationFailed
    /// LLM inference exceeded the 5-second timeout (D-18)
    case timeout
}

// MARK: - Phase 20 Levenshtein verification gate (D-01)

extension CleanupService {

    /// Single tunable knob — surfaces in CONTEXT.md as the UAT calibration target.
    /// Increase to be MORE permissive of LLM edits (the gate accepts more);
    /// decrease to reject MORE aggressively. Downstream code MUST reference this
    /// constant by name and never magic-number 0.30 inline.
    public static let levenshteinGateThreshold: Double = 0.45

    /// Pure helper. Returns `llmOutput` if it is plausibly a light edit of
    /// `rulesCleaned`; otherwise returns `rulesCleaned` (LLM is rejected as
    /// hallucination / over-rewrite).
    ///
    /// Distance is computed over normalized forms (lowercased, whitespace-collapsed,
    /// soft punctuation `, . ! ? : ; '` stripped) so reorderings like
    /// `"15 CHF"` vs `"CHF 15"` and casing/punctuation-only edits do not
    /// register as wholesale rewrites.
    ///
    /// Currency symbols are NOT stripped — the rules pass already canonicalized
    /// currency, and a missing symbol is a real semantic loss the gate should
    /// catch (defense-in-depth alongside `CurrencyAntiFlip.revertCurrencyFlip`).
    ///
    /// - Parameters:
    ///   - rulesCleaned: deterministic Swift-side cleanup output (rules pass).
    ///   - llmOutput: post-stripPreamble LLM output.
    ///   - threshold: normalized-distance ceiling. Defaults to
    ///     `levenshteinGateThreshold` (0.45) — pass an explicit value only for
    ///     calibration / testing.
    /// - Returns: `llmOutput` when normalizedDistance ≤ threshold, else
    ///   `rulesCleaned`.
    @available(*, deprecated, message: "Superseded by EditGuard (Phase 44). Retained for the 44-12 A/B replay and historical tests. Do not call from production.")
    public static func gateLLMOutput(rulesCleaned: String,
                                     llmOutput: String,
                                     threshold: Double = levenshteinGateThreshold) -> String {
        let lhs = normalizeForGate(rulesCleaned)
        let rhs = normalizeForGate(llmOutput)
        let dist = LevenshteinDistance.normalizedDistance(lhs, rhs)
        return dist > threshold ? rulesCleaned : llmOutput
    }

    /// Lowercase + soft-punctuation strip + whitespace-collapse. Keeps
    /// currency symbols, digits, and letters intact.
    private static func normalizeForGate(_ s: String) -> String {
        let lowered = s.lowercased()
        // Collapse whitespace runs to single space, strip soft punctuation.
        let stripped = lowered
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "!", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: ";", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")  // typographic apostrophe
        return stripped.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

// MARK: - Phase 20.08 Dialect-suppression gate (D-06..D-08)

extension CleanupService {

    /// Phase 20.08 D-06..D-08. Pre-Levenshtein dialect-suppression gate.
    /// Returns `llmOutput` if it introduces zero unsolicited Swiss dialect
    /// forms relative to `rulesCleaned`; otherwise returns `rulesCleaned`
    /// (LLM rejected as Swiss-ifier).
    ///
    /// "Unsolicited" = present in the LLM output AND in `SwissDialectForms.tokens`
    /// AND NOT present in the rules-cleaned baseline.
    ///
    /// Threshold = strict >= 1 (D-07). Aligned to the threat model: this user
    /// does not dictate Swiss German, so any unsolicited dialect form is
    /// rejected. The "speaker actually said it" exception is honoured by the
    /// `!baseline.contains(tok)` clause.
    ///
    /// Graceful degradation contract: empty inputs, zero matches, and any
    /// other unexpected shape return `llmOutput` unchanged (no demotion).
    /// Mirrors the CurrencyAntiFlip safety contract.
    ///
    /// - Parameters:
    ///   - rulesCleaned: deterministic Swift-side cleanup output (rules pass).
    ///   - llmOutput: post-stripPreamble LLM output.
    /// - Returns: `llmOutput` when delta == 0; else `rulesCleaned`.
    @available(*, deprecated, message: "Superseded by EditGuard (Phase 44). Retained for the 44-12 A/B replay and historical tests. Do not call from production.")
    public static func gateLLMDialect(rulesCleaned: String,
                                      llmOutput: String) -> String {
        let baseline = Set(tokenizeForDialectGate(rulesCleaned))
        let candidate = tokenizeForDialectGate(llmOutput)
        let dialectSet = Set(SwissDialectForms.tokens)
        for tok in candidate where dialectSet.contains(tok) && !baseline.contains(tok) {
            #if DEBUG
            os_log("gateLLMDialect: demoted on token '%{public}@'", log: .default, type: .info, tok)
            #endif
            return rulesCleaned
        }
        return llmOutput
    }

    /// Word-level tokenization tuned for dialect-form detection.
    /// Differs from `normalizeForGate` (which collapses to a single string for
    /// distance comparison): this returns an array of lowercased word tokens
    /// suitable for set membership.
    ///
    /// Edge cases (per RESEARCH.md §3 table):
    /// - Case mismatch -> lowercased before split
    /// - Trailing punctuation -> stripped via separators charset
    /// - Apostrophes inside word (s'het, d'Mueter) -> preserved as single token
    /// - Hyphenated words -> split on hyphen (per SwissHelvetisms convention)
    ///
    /// Internal (not private) so tests can verify tokenization edge cases.
    static func tokenizeForDialectGate(_ s: String) -> [String] {
        let lowered = s.lowercased()
        let separators = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: ".,!?;:\"„“”«»()[]{}—–-"))
        return lowered.unicodeScalars
            .split { separators.contains($0) }
            .map { String(String.UnicodeScalarView($0)) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Phase 34 V19E content-word-preservation gate (SC2)

extension CleanupService {

    /// Minimal EN+DE stop-word set for gateContentWords.
    ///
    /// Precision-first: over-inclusion is the only risk because this gate is a
    /// backstop. A word on this list that the LLM drops will silently pass the
    /// gate even if its absence changes meaning. Keep the list tight.
    ///
    /// Only ≥4-char function words are relevant — the ≥4-char content-word filter
    /// already excludes shorter tokens, so entries shorter than 4 chars would be
    /// dead code.
    public static let contentWordStopWords: Set<String> = [
        // English function words (≥4 chars) that the LLM may legitimately rephrase/drop
        "that", "this", "with", "from", "have", "will", "your", "they", "them",
        "then", "than", "what", "when", "which", "would", "could", "should",
        "about", "just", "like",
        // German function words (≥4 chars)
        "dass", "dies", "dieser", "eine", "einen", "oder", "aber", "auch",
        "nicht", "schon", "noch", "wenn", "dann", "sich", "mehr"
    ]

    /// Closed set of known identifier stems the LLM may legitimately contract
    /// (e.g. "gpt" in multi-token context). Single-letter stems are already
    /// excluded by the ≥4-char rule, so only multi-char acronyms belong here.
    public static let contentWordStemAllowlist: Set<String> = [
        "gpt", "ios"
    ]

    /// Spelled-out English cardinal and ordinal number-words (≥4 chars) that
    /// the LLM may legitimately promote to a digit form (e.g. "M three" → "M3").
    /// Excluding these from "required content words" prevents the gate from
    /// reverting a legitimate promotion when the only dropped token is a
    /// number-word (WR-01). Does NOT weaken R8 detection because the R8 bug
    /// cases drop a non-number content word ("kink", "King") — those still trip
    /// the gate.
    public static let contentWordNumberWords: Set<String> = [
        "zero", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
        "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",
        "seventeen", "eighteen", "nineteen", "twenty", "thirty", "forty",
        "fifty", "sixty", "seventy", "eighty", "ninety", "hundred", "thousand",
        "first", "second", "third", "fourth", "fifth", "sixth", "seventh",
        "eighth", "ninth", "tenth"
    ]

    /// Extended number-word set for V2.1 gate (ported from Matrix005.swift GateV2.extraNumberWords).
    /// Covers EN ordinals not in contentWordNumberWords, DE cardinals/ordinals, and numeric
    /// connectors — prevents gate from reverting legitimate ITN promotions of these forms.
    private static let contentWordGateExtraNumbers: Set<String> = [
        "point", "comma",
        "eleventh", "twelfth", "thirteenth", "fourteenth", "fifteenth",
        "sixteenth", "seventeenth", "eighteenth", "nineteenth", "twentieth",
        "thirtieth", "fortieth", "fiftieth", "sixtieth", "seventieth",
        "eightieth", "ninetieth", "hundredth",
        "eins", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht",
        "neun", "zehn", "zwölf", "zwanzig", "dreissig", "dreißig", "vierzig",
        "fünfzig", "sechzig", "siebzig", "achtzig", "neunzig", "hundert",
        "tausend", "komma", "punkt",
        "erste", "ersten", "erster", "erstes", "zweite", "zweiten", "dritte",
        "dritten", "vierte", "vierten", "fünfte", "fünften", "sechste",
        "sechsten", "siebte", "siebten", "achte", "achten", "neunte",
        "neunten", "zehnte", "zehnten"
    ]

    /// Trailing discourse markers that the LLM may legitimately drop.
    /// These are media-bleed / filler artifacts, not content words.
    private static let contentWordGateDiscourseArtifacts: Set<String> = ["yeah", "okay", "mhm"]

    /// Optimal-string-alignment (Damerau-OSA) distance: like Levenshtein but
    /// adjacent transpositions cost 1 — "clawed"→"claude" scores 2, while
    /// "schema"→"Gemma" stays ≥3. Do NOT replace with LevenshteinDistance.swift
    /// (plain Levenshtein scores schema→Gemma as 2, causing false passes).
    /// Ported verbatim from Matrix005.swift GateV2.damerauOSA (lines 120–137).
    private static func damerauOSA(_ a: String, _ b: String) -> Int {
        let aa = Array(a), bb = Array(b)
        if aa.isEmpty { return bb.count }
        if bb.isEmpty { return aa.count }
        var d = [[Int]](repeating: [Int](repeating: 0, count: bb.count + 1), count: aa.count + 1)
        for i in 0...aa.count { d[i][0] = i }
        for j in 0...bb.count { d[0][j] = j }
        for i in 1...aa.count {
            for j in 1...bb.count {
                let cost = aa[i - 1] == bb[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, aa[i - 1] == bb[j - 2], aa[i - 2] == bb[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }
        return d[aa.count][bb.count]
    }

    /// Case-preserving tokenizer using the same separator charset as
    /// tokenizeForDialectGate — for the ALLCAPS-preservation clause.
    /// Ported verbatim from Matrix005.swift GateV2.caseTokens (lines 141–147).
    private static func caseTokens(_ s: String) -> [String] {
        // Same base separators as tokenizeForDialectGate, plus "/" for paths.
        let separators = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: ".,!?;:/"))
            .union(CharacterSet(charactersIn: "\""))
            .union(CharacterSet(charactersIn: "\u{201E}\u{201C}\u{201D}\u{AB}\u{BB}"))
            .union(CharacterSet(charactersIn: "()[]{}"))
            .union(CharacterSet(charactersIn: "\u{2014}\u{2013}-"))
        return s.unicodeScalars.split { separators.contains($0) }
            .map { String(String.UnicodeScalarView($0)) }
            .filter { !$0.isEmpty }
    }

    /// Content-word-preservation gate V2.1. Returns `rulesCleaned` (fallback) if
    /// `llmOutput` drops any required content word present in `rulesCleaned`.
    ///
    /// V2.1 adds five PASS clauses (repetition, merge/substring, Damerau-OSA ≤2,
    /// extended number-words, discourse artifacts) and two TIGHTEN clauses
    /// (ALLCAPS preservation, dictProtect). Reduces wrong rejections from ~74 to
    /// ~21 of 782 records while keeping all true-hallucination rejections.
    ///
    /// Graceful degradation: empty `rulesCleaned` or empty `llmOutput` → returns
    /// `llmOutput` unchanged (mirrors `gateLLMDialect` contract).
    ///
    /// Phase 44 Plan 11 (D-01/T-44-34): the Damerau-OSA ≤2 near-miss-respelling
    /// PASS clause ("clawed"→"Claude" accepted, distance 2) is REMOVED — this is
    /// the confirmed leak: the SAME leniency lets `wohnst`→`wohne` and
    /// `Führungsrhythmus`→`Führungsrythmus` (an introduced typo) through
    /// unchanged. `damerauOSA` itself survives (a pure distance metric with
    /// other legitimate uses); only its use as a content-word PASS clause is
    /// gone. `EditGuard` (Step 3a) does not use string-distance classification
    /// at all — see `testDamerauOSAIsNeverUsedInEditGuard`.
    ///
    /// - Parameters:
    ///   - rulesCleaned: deterministic Swift-side cleanup output (rules pass).
    ///   - llmOutput: post-stripPreamble LLM output.
    ///   - dictProtected: dictionary-replacement values that must survive verbatim.
    /// - Returns: `llmOutput` when all content words are present; else `rulesCleaned`.
    @available(*, deprecated, message: "Superseded by EditGuard (Phase 44). Retained for the 44-12 A/B replay and historical tests. Do not call from production.")
    public static func gateContentWords(
        rulesCleaned: String,
        llmOutput: String,
        dictProtected: Set<String> = []
    ) -> String {
        guard !rulesCleaned.isEmpty, !llmOutput.isEmpty else { return llmOutput }

        // tokenizeForDialectGate lowercases and splits on whitespace + punctuation.
        let baselineTokens = tokenizeForDialectGate(rulesCleaned)
        let outputTokens = tokenizeForDialectGate(llmOutput)
        let outputTokenSet = Set(outputTokens)

        // ALLCAPS preservation (Matrix005 lines 163–174):
        // An all-uppercase token (≥2 chars, has letters) in the baseline must survive
        // in exact casing — catches HIN→hin, dropped acronyms, symbol mangling.
        let outCase = Set(caseTokens(llmOutput))
        for t in caseTokens(rulesCleaned)
        where t.count >= 2 && t == t.uppercased() && t != t.lowercased() && !outCase.contains(t) {
            // exception 1: merged into a larger ALLCAPS token (G SD → GSD)
            if outCase.contains(where: { $0 != t && $0 == $0.uppercased() && $0.contains(t) }) { continue }
            // exception 2: recased but keeps ≥1 uppercase (IOS → iOS); pure lowercasing (HIN → hin) still rejects
            if outCase.contains(where: { $0.lowercased() == t.lowercased() && $0 != $0.lowercased() }) { continue }
            return rulesCleaned
        }

        // dictProtect (Matrix005 lines 179–183):
        // A token from a dictionary replacement must survive exactly — user chose that spelling.
        for prot in dictProtected {
            for t in tokenizeForDialectGate(prot)
            where t.count >= 3 && baselineTokens.contains(t) && !outputTokenSet.contains(t) {
                return rulesCleaned
            }
        }

        // youKnow bigram detection (Matrix005 lines 186–191):
        // Both halves of "you know" are removable discourse filler.
        var youKnow = false
        if baselineTokens.count >= 2 {
            for i in 0..<(baselineTokens.count - 1)
            where baselineTokens[i] == "you" && baselineTokens[i + 1] == "know" { youKnow = true }
        }

        // Per-token PASS-clause loop (Matrix005 lines 193–226):
        for (idx, tok) in baselineTokens.enumerated() {
            guard tok.count >= 4,
                  !contentWordStopWords.contains(tok),
                  !contentWordStemAllowlist.contains(tok),
                  !contentWordNumberWords.contains(tok),
                  !contentWordGateExtraNumbers.contains(tok),
                  !contentWordGateDiscourseArtifacts.contains(tok),
                  !(tok == "know" && youKnow),
                  !outputTokenSet.contains(tok) else { continue }

            // (a) adjacent repetition / prefix false-start in the baseline
            let prev = idx > 0 ? baselineTokens[idx - 1] : ""
            let next = idx + 1 < baselineTokens.count ? baselineTokens[idx + 1] : ""
            if prev == tok || next == tok { continue }
            if next.count >= 4, next.hasPrefix(tok) || tok.hasPrefix(next) { continue }
            if prev.count >= 4, prev.hasPrefix(tok) || tok.hasPrefix(prev) { continue }

            // (b) merge/substring vs output tokens (anal⊂analysis, checked⊃check)
            if outputTokens.contains(where: {
                $0.contains(tok) || (tok.count >= 6 && $0.count >= 4 && tok.contains($0))
            }) { continue }

            return rulesCleaned
        }
        return llmOutput
    }
}

// MARK: - Phase 44 Plan 10 (D-07 hoist): whole-output pre-filter for EditGuard

extension CleanupService {

    /// Phase 44 Plan 10, Part A: hoists D-07's whole-output pre-filter out of
    /// `gateSentenceWindow`'s per-window scope so it runs ONCE over the
    /// entire `llmOutput`, in front of `EditGuard.apply`. Reuses
    /// `scaffoldingBlacklist`, `imperativeInputCues`, `assistantVoiceCues`,
    /// and `gatePerSentenceLengthRatio` VERBATIM — this function only widens
    /// scope, it does not retune any threshold. `gatePerSentence` /
    /// `gateSentenceWindow` themselves are left untouched by this plan (44-11
    /// retires them).
    ///
    /// - Returns: `false` when the LLM output must be discarded wholesale
    ///   (scaffolding leak, an imperative-input dictation answered in
    ///   assistant voice, or a runaway length ratio); `true` otherwise.
    public static func prefilterLLMOutput(rulesCleaned: String, llmOutput: String) -> Bool {
        guard !rulesCleaned.isEmpty, !llmOutput.isEmpty else { return true }

        // 1. Scaffolding blacklist (cheap, first).
        let lowerOutput = llmOutput.lowercased()
        if scaffoldingBlacklist.contains(where: { lowerOutput.contains($0) }) {
            return false
        }

        // 2. Imperative-input / assistant-voice-output pairing — both cues
        // must match, mirroring `gateSentenceWindow`'s exact clause.
        let lowerBaseline = rulesCleaned.trimmingCharacters(in: .whitespaces).lowercased()
        if imperativeInputCues.contains(where: { lowerBaseline.hasPrefix($0) }),
           assistantVoiceCues.contains(where: { lowerOutput.contains($0) }) {
            return false
        }

        // 3. Length-ratio runaway guard, over the WHOLE output.
        let baselineTokens = tokenizeForDialectGate(rulesCleaned)
        let outputTokens = tokenizeForDialectGate(llmOutput)
        if !baselineTokens.isEmpty {
            let ratio = Double(outputTokens.count) / Double(baselineTokens.count)
            if ratio > gatePerSentenceLengthRatio {
                return false
            }
        }

        return true
    }
}

// MARK: - Phase 36.6 Rethink R-02 shared injection/scaffolding constants
//
// Phase 44 Plan 11 (D-01): the per-sentence phonetic gate that used to live
// in this extension (`gatePerSentence` / `gateSentenceWindow`, plus the
// `gatePerSentenceRetentionFloor` constant it alone consumed) has been
// RETIRED — see `TextProcessingService.swift` Step 3a, which now calls
// `EditGuard.apply` instead. The four constants below SURVIVE unmodified:
// `prefilterLLMOutput` (D-07 hoist, Plan 10) still consumes them verbatim as
// the edit guard's whole-output pre-filter.

extension CleanupService {

    /// Closed EN+DE scaffolding/assistant-boilerplate phrase list (case-insensitive
    /// substring match). Backstops the P1 leak class (Qwen regurgitating prompt
    /// scaffolding, e.g. a paraphrased "Known terms" block) regardless of
    /// paraphrase drift — a content check inside the gate, not just the narrow
    /// header-match `GroundingLite.stripLeakedKnownTerms` performs upstream.
    ///
    /// [ASSUMED A3] seed list per 36.6-RESEARCH.md Pattern 2 item 1 — a single
    /// reviewable constant so future leak variants get added in ONE place.
    static let scaffoldingBlacklist: [String] = [
        "here is the corrected", "here's the corrected", "i have corrected",
        "as an ai", "as a language model", "i cannot", "corrected text:",
        "known terms",
        "hier ist der korrigierte", "ich habe korrigiert", "als ki",
        "korrigierter text:", "bekannte begriffe"
    ]

    /// [ASSUMED A2] Length-ratio guard: an output window whose word count
    /// exceeds this multiple of the baseline window's word count reverts
    /// (runaway rewrite / hallucinated elaboration). Per 36.6-RESEARCH.md
    /// Pattern 2 item 2 ("1.3-1.5x", pending calibration) — pinned at 1.4x.
    static let gatePerSentenceLengthRatio = 1.4

    /// [Q2/D-05] Closed EN+DE imperative-input cue prefixes — checked against
    /// the START of the baseline window. Mirrors the `scaffoldingBlacklist`
    /// pattern: a small, reviewable, hand-curated list, not a general
    /// command classifier. Backstops the July-5 "Gib mir noch ein paar
    /// Hashtags." incident class — a dictated command answered as a chatbot
    /// reply instead of edited. Only meaningful paired with
    /// `assistantVoiceCues` (both must match — see `prefilterLLMOutput`).
    static let imperativeInputCues: [String] = [
        "give me", "write", "list", "create", "generate", "make a",
        "gib mir", "gebe mir", "schreib", "erstelle", "liste", "mach mir"
    ]

    /// [Q2/D-05] Closed EN+DE assistant-voice-output cue substrings —
    /// checked anywhere in the output window (case-insensitive substring
    /// match, same style as `scaffoldingBlacklist`). Paired with
    /// `imperativeInputCues`: only BOTH matching together triggers a
    /// revert, keeping false-positive risk near zero.
    static let assistantVoiceCues: [String] = [
        "here are", "here is", "i understand", "sure,", "certainly",
        "hier sind", "hier ist", "ich verstehe", "gerne", "klar,", "bitte gib mir"
    ]
}

// MARK: - Phase 20.08 Spike harness helpers (DEBUG-only, D-02/D-03)

#if DEBUG
extension CleanupService {

    /// DEBUG-only helper for the Phase 20.08 prompt-spike harness.
    ///
    /// Bypasses `CleanupPrompt.build(...)` and feeds an arbitrary pre-built
    /// prompt string directly to the same inference loop used by `cleanup(...)`.
    /// Mirrors the production isInferring guard, state transition, and
    /// task-group timeout structure from cleanup() lines 178-242 — the only
    /// difference is the prompt source (caller-supplied vs CleanupPrompt.build).
    ///
    /// Returns the post-stripPreamble LLM output, or empty string on
    /// model-not-loaded / concurrent-call / timeout / inference failure.
    ///
    /// CONCURRENCY: callers MUST invoke this sequentially. The shared
    /// `isInferring` guard (CleanupService.swift line 155, 178-181) rejects
    /// concurrent calls. The spike harness UI loops
    /// `for input in inputs { for variant in variants { let out = await ... } }`.
    func cleanupWithExplicitPrompt(_ prompt: String, timeoutSeconds: TimeInterval? = nil) async -> String {
        let log = Logger(subsystem: "com.dicticus", category: "cleanup-spike")

        guard isLoaded, let model = model, let context = context, let sampler = sampler else {
            log.warning("cleanupWithExplicitPrompt: model not loaded")
            return ""
        }

        guard !isInferring else {
            log.warning("cleanupWithExplicitPrompt: inference already in progress")
            return ""
        }

        isInferring = true
        state = .cleaning
        defer {
            state = .idle
            isInferring = false
        }

        // Mirror cleanup() lines 207-242 verbatim: capture nonisolated(unsafe)
        // C-pointer aliases, then run a throwing task group with a sleep-throw
        // timeout task + the static inference task. Return whichever finishes
        // first; cancel the loser.
        nonisolated(unsafe) let unsafeModel = model
        nonisolated(unsafe) let unsafeContext = context
        nonisolated(unsafe) let unsafeSampler = sampler
        let maxTokens = maxOutputTokens
        let timeout = timeoutSeconds ?? self.inferenceTimeoutSeconds

        do {
            let result = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    throw CleanupError.timeout
                }

                group.addTask {
                    return Self.runInference(
                        prompt: prompt,
                        model: unsafeModel,
                        context: unsafeContext,
                        sampler: unsafeSampler,
                        maxTokens: maxTokens
                    )
                }

                guard let firstResult = try await group.next() else {
                    return ""
                }
                group.cancelAll()
                return firstResult
            }

            log.info("Spike LLM raw (\(result.count, privacy: .public) chars)")
            return Self.cleanSpikeOutput(result)
        } catch {
            log.error("cleanupWithExplicitPrompt error: \(error.localizedDescription, privacy: .public)")
            return ""
        }
    }

    /// Spike-specific post-processor.
    ///
    /// Gemma 4 E2B at temp 0.1 sometimes (a) emits markdown-blockquote `>` line
    /// prefixes and (b) keeps generating past `<end_of_turn>` when that token
    /// is not flagged EOG by `llama_vocab_is_eog`, producing duplicate
    /// paragraphs. Production cleanup() doesn't hit this because its prompt
    /// shape and post-strip pipeline differ. For spike comparison we want a
    /// single clean answer per cell: truncate at the first chat-template
    /// marker or blank-line break, then strip leading `>` per line.
    private nonisolated static func cleanSpikeOutput(_ raw: String) -> String {
        var out = raw
        // Include closing-tag variants (e.g. `</start_of_turn>`) — Gemma 4 E2B
        // occasionally emits these as stray tokens; substring matching on
        // `<start_of_turn>` does not catch them due to the leading `/`.
        for marker in [
            "</start_of_turn>", "</end_of_turn>",
            "<end_of_turn>", "<start_of_turn>",
            "<eos>", "<|endoftext|>",
            // Phase 36.6 Plan 03 (CLEANRD-01): Qwen ChatML markers — the harness
            // `batch` path replays the same runInference loop and needs these
            // cut cleanly too.
            "<|im_end|>", "<|im_start|>",
        ] {
            if let r = out.range(of: marker) { out = String(out[..<r.lowerBound]) }
        }
        if let r = out.range(of: "\n\n") { out = String(out[..<r.lowerBound]) }
        // Strip stray output-template prefixes Gemma 4 E2B emits when primed
        // by a structural-looking prompt trailer. Observed Wave A artifacts:
        // "_response>", "<response>", "OUTPUT:". Match case-insensitively at
        // the start of the trimmed output only.
        let trimmedLeading = out.drop(while: { $0.isWhitespace })
        for prefix in ["_response>", "<response>", "OUTPUT:", "Output:", "output:"] {
            if trimmedLeading.lowercased().hasPrefix(prefix.lowercased()) {
                if let r = out.range(of: prefix, options: .caseInsensitive) {
                    out = String(out[r.upperBound...])
                }
                break
            }
        }
        // Phase 20.08: BPE-fragmented chat-template leak. When Gemma emits
        // `<end_of_turn>` mid-decode, the leading `<...of_` portion is sometimes
        // truncated by upstream marker stripping (line 794-800) while the
        // SentencePiece-rendered tail `▁turn>` / `_turn>` / `turn>` survives at
        // the start. Catch any dangling chat-template tail at the leading edge.
        if let regex = try? NSRegularExpression(
            pattern: #"^\s*[_▁<]?(?:(?:start|end)_of_)?turn>\s*"#,
            options: [.caseInsensitive]
        ) {
            let nsOut = out as NSString
            let range = NSRange(location: 0, length: nsOut.length)
            out = regex.stringByReplacingMatches(in: out, options: [], range: range, withTemplate: "")
        }
        out = out
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                var s = String(line)
                // Strip leading quote-marker, whitespace, and stray
                // punctuation (":" / "," / ";") that Gemma sometimes emits
                // as a structural opener before the actual cleaned text.
                while let first = s.first,
                      first == ">" || first == " " || first == "\t" ||
                      first == ":" || first == "," || first == ";" {
                    s.removeFirst()
                }
                return s
            }
            .joined(separator: "\n")
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// DEBUG-only sampler-seed override for spike reproducibility (D-03).
    ///
    /// Tears down the current sampler chain (`llama_sampler_free`) and
    /// rebuilds it VERBATIM from CleanupService.loadModel lines 136-146
    /// with `seed` substituted for the random `UInt32.random(in: ...)` in
    /// `llama_sampler_init_dist`. All other chain nodes (temperature 0.1,
    /// top-K 40, top-P 0.9) are reconstructed identically so spike output
    /// matches production sampler behavior except for determinism.
    ///
    /// Pass `nil` (or call again with a fresh random seed) to restore
    /// non-deterministic sampling. Production code never calls this — the
    /// `#if DEBUG` wrap guarantees the symbol does not exist in Release.
    ///
    /// PRECONDITION: `loadModel()` has completed (isLoaded == true). Calling
    /// this before warmup is a no-op (logged warning).
    func setSamplerSeed(_ seed: UInt32?) {
        let log = Logger(subsystem: "com.dicticus", category: "cleanup-spike")

        guard isLoaded else {
            log.warning("setSamplerSeed: called before loadModel completed — no-op")
            return
        }

        guard !isInferring else {
            log.warning("setSamplerSeed: inference in progress — refusing to mutate sampler")
            return
        }

        // Tear down the existing sampler chain (allocated in loadModel via
        // llama_sampler_chain_init). llama_sampler_free walks the chain and
        // releases all child samplers added with llama_sampler_chain_add.
        if let oldSampler = sampler {
            llama_sampler_free(oldSampler)
            sampler = nil
        }

        // Rebuild the chain to match loadModel — Phase 20.08 conventional
        // order (top_k → top_p → temp → dist). Must stay in lockstep with
        // loadModel's chain or seeded reproducibility breaks.
        let resolvedSeed: UInt32 = seed ?? UInt32.random(in: 0...UInt32.max)
        let samplerChain = llama_sampler_chain_init(llama_sampler_chain_default_params())
        llama_sampler_chain_add(samplerChain, llama_sampler_init_top_k(40))
        llama_sampler_chain_add(samplerChain, llama_sampler_init_top_p(0.9, 1))
        llama_sampler_chain_add(samplerChain, llama_sampler_init_temp(0.1))
        llama_sampler_chain_add(samplerChain, llama_sampler_init_dist(resolvedSeed))
        sampler = samplerChain

        log.info("setSamplerSeed: rebuilt sampler chain with seed \(resolvedSeed, privacy: .public)")
    }
}
#endif
