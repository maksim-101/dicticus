# State of 61-lfm3-small-model-retry-spike
Slice: 61-lfm3-small-model-retry-spike (size set at brief)
Step: brief
Next: write BRIEF.md: the question (LFM3 with the stop string, an LFM-aware envelope and one prompt written for it, against Qwen on spike 022's 238 dictations plus its unscored holdout), the pass rule, and whether a phone is needed; then the owner's approval
Waiting on: nothing
Started: 2026-11-14T09:02:41Z
Baseline: no check command run yet
Base: branch point
Risk: none
Carried: none

## Decisions
- 2026-11-14 question (before the slice): the owner on retrying LFM3-1.7B for 6 GB phones: "you can give it a try".
- 2026-11-14 question (before the slice): the owner on spike 020 Stage 3: "the NemoTron spike could also go ahead" (item 62, planned, second in ROADMAP.md).

## History
- 2026-11-14 61 brief: opened from the owner's two answers; branch flow/61-lfm3-small-model-retry-spike from main. Item 62 created as planned. The two question lines left the root Carried list. Checked: the `</corrected_text>` stop string is in CleanupService.swift since 2026-10-31; `modelWantsReasoningPreclose` still matches qwen3 only; spike 022's scripts, data and gate build are on disk.
