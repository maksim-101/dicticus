# State of 61-lfm3-small-model-retry-spike
Slice: 61-lfm3-small-model-retry-spike (size set at brief)
Step: plan
Next: flow:plan: read spike 022's PROTOCOL.md and scripts, write PLAN.md (protocol and hash lock, LFM3 envelope and one prompt on the dev set, holdout draw after 2026-10-29, decodes through the resource gate, blind labels, verdict by the 60 % rule), then the owner's approval
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

## History
- 2026-11-14 61 brief: opened from the owner's two answers; branch flow/61-lfm3-small-model-retry-spike from main. Item 62 created as planned. The two question lines left the root Carried list. Checked: the `</corrected_text>` stop string is in CleanupService.swift since 2026-10-31; `modelWantsReasoningPreclose` still matches qwen3 only; spike 022's scripts, data and gate build are on disk.
