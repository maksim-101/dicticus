# State of 61-lfm3-small-model-retry-spike
Slice: 61-lfm3-small-model-retry-spike (size set at brief)
Step: build
Next: flow:build, task 2: when the background LFM3 decodes of the dev set finish (L1, L2v1, L2v2 into .planning/spikes/025-lfm3-retry/data/out-dev-*.jsonl; the decode script resumes where a file stops), gate them, run metrics.py dev Q L1 and early_signal.py; then task 3
Waiting on: nothing
Started: 2026-11-14T09:02:41Z
Baseline: no check command run yet
Base: branch point
Risk: none
Carried: none

## Decisions
- 2026-11-14 question (before the slice): the owner on retrying LFM3-1.7B for 6 GB phones: "you can give it a try".
- 2026-11-14 question (before the slice): the owner on spike 020 Stage 3: "the NemoTron spike could also go ahead" (item 62, planned, second in ROADMAP.md).
- 2026-11-14 brief: approved by the owner with the pass rule "Good enough for 6 GB": per language, LFM3 passes with at least 60 % of Qwen's good edits and no more harmful ones than Qwen; a pass means a later build offers it only on phones that cannot run Qwen, while 8 GB devices and the Mac keep Qwen. agy (Gemini) labels blind, as in 50.1.
- 2026-11-14 plan: approved by the owner ("approved"); the approval is the go for the local decoding up to 3 hours of GPU time and the 1.1 GB download.

## History
- 2026-11-14 61 brief: opened from the owner's two answers; branch flow/61-lfm3-small-model-retry-spike from main. Item 62 created as planned. The two question lines left the root Carried list. Checked: the `</corrected_text>` stop string is in CleanupService.swift since 2026-10-31; `modelWantsReasoningPreclose` still matches qwen3 only; spike 022's scripts, data and gate build are on disk.
- 2026-11-14 61 brief: approved with the 60 % rule. 61 plan: PLAN.md written from spike 022's protocol and scripts; holdout pool counted from the frozen logs of 2026-10-30 to 11-12: English 300, German 59, none in the dev set; the LFM3 file is no longer on disk. Waiting for plan approval.
- 2026-11-14 61 build: task 1 done: harness copied to spike 025 with the app's nine stop strings, gate rebuilt from main, both model hashes equal spike 022's protocol (LFM3 still on disk, no download), Qwen deterministic and equal to spike 022 on 238 of 238 dev outputs, gate fidelity 237 of 238 (evidence/setup.md). Qwen's 238 decodes took 432 s. LFM3 dev decodes started in the background.
