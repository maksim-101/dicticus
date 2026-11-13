# Task 4 tracer (2026-11-13, slice commit e1b4f52)

Harness: `.planning/spikes/024-warp-code-prompt-replay/` (gitignored). The `gate` executable is compiled from the slice's `Shared/` (rsync at e1b4f52), modes `prompt` and `gate`.

**(a) Items.** `build_items.py` over the audit's frozen logs, Warp, `mode = aiCleanup`, `lang_used = en`, 2026-10-29T04:22:14Z to 2026-11-09: **312 items**, key-list sha256 `8bc0e6b994067c1d57905026a4f8c5d28607aff29220056a6d1ce30f4c81cbdb` (`data/items.sha256`, written before any generation). 6 further records had no `llm_prompt`/`post_gate`: the six 20 s timeouts (10-31:48, 11-01:57/58/61/64/69), which never reached the LLM. So the brief's 312 stands; the plan's 318 counted those six.

**(b) Prompt identity.** `prompts.py`: `CleanupPrompt.build(context: .default, useSwissGerman: true, variant: .transcriptionist, reasoningPreclose: true)` on each item's `post_rules` text against the logged `llm_prompt.text`:

| Logged on | Items | Identical |
|---|---|---|
| 2026-10-29, 10-30 | 69 | 0 (logged before the installed build carried 752ddab's filler-list change) |
| 2026-10-31 to 11-09 | 243 | **243** |

Every item logged by the current prompt text reproduces byte for byte. Both arms (`prompt_D` default, `prompt_C` code) are built from the slice's code on the same `post_rules` text, so the 69 older items are compared on today's prompt text, as the route intends. `data/arms.jsonl` carries a `logged_identical` flag per item.

**(c) Timed sample.** Run 2026-11-13 16:55Z under heavy-gate slot `replay-54` (mains power, memory pressure normal; the first launch at 16:50Z aborted before the sample and was relaunched with a warm-up request), llama-server 0.9.0, the app's model file (sha256 prefix 00fe7986), `-c 4096 -ngl 99 --seed 16 -np 1`, temperature 0, `cache_prompt` off. Five items per arm:

| Arm | Mean wall per item |
|---|---|
| D (default prompt) | 3139 ms |
| C (code prompt) | 3446 ms |

Projection for 312 × 2 items: **34.2 min**, under the plan's 45 min ceiling, so the full run started at once (`data/timing.json`). The 022 estimate was 2.8 s/item; realised-to-sampled ratio is recorded with the run's wall time below.
