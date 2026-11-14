# Task 4(c)/5: replay of 312 Warp English AI dictations, default prompt vs code prompt (2026-11-13, slice commit e1b4f52)

Harness: `.planning/spikes/024-warp-code-prompt-replay/` (gitignored; dictation text stays there). Items: the 312 of `evidence/replay-tracer.md` (a), key-list sha256 `8bc0e6b9…`. Both arms' prompts built by the slice's `CleanupPrompt` on each item's rules-cleaned text (tracer (b)); arm D = `.default` context (what Warp got before this slice), arm C = `.code` (what the category rule gives it now). Generation: llama-server 0.9.0, the app's Qwen3.5-4B Q4_K_M file, `-c 4096 -ngl 99`, temperature 0, seed 16, `n_predict` 512, the app's stop strings, under heavy-gate slot `replay-54` on mains power, memory pressure normal, no other model job. Gate: the production `EditGuard.apply` with each item's logged dictionary-protected set, compiled from the slice's `Shared/` (the `BrandMatcher` lexicon warnings at start-up come from `DictionaryService`'s bundle resources, which the gate path does not use).

Run: timed sample projected 34.2 min; the full run took 16.4 min of generation (986 s), realised-to-sampled ratio 0.48 (the five sample items were above the median length). `metrics.py` output, `data/metrics.json`:

| metric | D (default prompt) | C (code prompt) |
|---|---|---|
| dictations | 312 | 312 |
| edits proposed by the LLM (gate's edit units) | 11987 | 11961 |
| rejected edits | 1087 | 780 |
| **rejected-edit rate** | **0.091** | **0.065** |
| dictations with at least one rejected edit | 143 | 114 |
| **rate of dictations with a rejection** | **0.458** | **0.365** |
| dictations through the gate with every edit accepted | 169 | 198 |
| **shipped change** (gated text differs from the rules-cleaned text) | **177** | **183** |
| LLM output differs from the rules-cleaned text (before the gate) | 240 | 231 |
| **failed closed** | **0** | **0** |
| truncated at 512 tokens | 0 | 0 |
| prompt tokens, median / p90 | 363 / 409 | 556 / 602 |
| wall per item, median / p90 (ms, replay machine) | 1290 / 2301 | 1465 / 2468 |
| gated text differs between the arms | 59 | |

Rejected edits by gate class:

| reject class | D | C |
|---|---|---|
| sentenceCoupledRevert | 452 | 367 |
| contentWordDeletion | 230 | 141 |
| contentWordIdentityChange | 151 | 92 |
| atomicGroupRevert | 117 | 65 |
| contentWordInsertion | 58 | 48 |
| unclassified | 43 | 35 |
| pronounPersonChange | 18 | 10 |
| pronounDeleted | 12 | 8 |
| clauseRelocation | 0 | 8 |
| derivationalSuffixChange | 4 | 3 |
| digitValueChange | 1 | 3 |
| acronymLoweredAfterDot | 1 | 0 |

Reading. Arm D reproduces the audit's figure for Warp (47 % of its English AI dictations had a rejected edit; here 45.8 % on the same items with today's prompt text). The code prompt lowers the rejected-edit rate by a quarter (0.091 → 0.065) and the share of dictations with a rejection from 45.8 % to 36.5 %, while shipping slightly more changes (183 vs 177) and failing closed on none. Its prompt is about 190 tokens longer, which costs about 175 ms per dictation on this machine (median). The two arms ship different text on 59 of 312 dictations; the other 253 end identical after the gate. Which of the 59 reads better is the owner's `[judge]` item (criterion 5): `data/judge-sample.md` in the spike folder holds 20 of them, arms shuffled per item as A/B (`random.Random(54)`), the key in `data/judge-key.json`.

Caveats. One machine, one seed, temperature 0: a different seed changes individual outputs, and the numbers are a point estimate on these 312 items, not a confidence interval. The gate's own thresholds have not been tuned on these items (the EditGuard code is main's at the branch point), so the items are out of sample for it. The 69 items from 2026-10-29/30 were logged under an older prompt text and are compared on today's text in both arms (tracer (b)).
