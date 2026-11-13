# Task 4 tracer (2026-11-13, slice commit e1b4f52)

Harness: `.planning/spikes/024-warp-code-prompt-replay/` (gitignored). The `gate` executable is compiled from the slice's `Shared/` (rsync at e1b4f52), modes `prompt` and `gate`.

**(a) Items.** `build_items.py` over the audit's frozen logs, Warp, `mode = aiCleanup`, `lang_used = en`, 2026-10-29T04:22:14Z to 2026-11-09: **312 items**, key-list sha256 `8bc0e6b994067c1d57905026a4f8c5d28607aff29220056a6d1ce30f4c81cbdb` (`data/items.sha256`, written before any generation). 6 further records had no `llm_prompt`/`post_gate`: the six 20 s timeouts (10-31:48, 11-01:57/58/61/64/69), which never reached the LLM. So the brief's 312 stands; the plan's 318 counted those six.

**(b) Prompt identity.** `prompts.py`: `CleanupPrompt.build(context: .default, useSwissGerman: true, variant: .transcriptionist, reasoningPreclose: true)` on each item's `post_rules` text against the logged `llm_prompt.text`:

| Logged on | Items | Identical |
|---|---|---|
| 2026-10-29, 10-30 | 69 | 0 (logged before the installed build carried 752ddab's filler-list change) |
| 2026-10-31 to 11-09 | 243 | **243** |

Every item logged by the current prompt text reproduces byte for byte. Both arms (`prompt_D` default, `prompt_C` code) are built from the slice's code on the same `post_rules` text, so the 69 older items are compared on today's prompt text, as the route intends. `data/arms.jsonl` carries a `logged_identical` flag per item.

**(c) Timed sample.** Waits for AC power (heavy-gate refuses model slots on battery); recorded below when run.
