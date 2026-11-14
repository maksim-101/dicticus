# State of 61-lfm3-small-model-retry-spike
Slice: 61-lfm3-small-model-retry-spike (size set at brief)
Step: done
Next: nothing for this slice. The item is dropped at the early signal. The next item in ROADMAP.md is 62-nemotron-stage3-pause-phantoms-spike, briefed when the owner asks (the go for it is recorded in its ITEM.md).
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
- 2026-11-14 question (build, early signal failed): the owner chose "Stop here": close the item as failed on the development data, 6 GB iPhones stay without AI Cleanup, move on to the Nemotron pause test.

## History
- 2026-11-14 61 brief: opened from the owner's two answers; branch flow/61-lfm3-small-model-retry-spike from main. Item 62 created as planned. The two question lines left the root Carried list. Checked: the `</corrected_text>` stop string is in CleanupService.swift since 2026-10-31; `modelWantsReasoningPreclose` still matches qwen3 only; spike 022's scripts, data and gate build are on disk.
- 2026-11-14 61 brief: approved with the 60 % rule. 61 plan: PLAN.md written from spike 022's protocol and scripts; holdout pool counted from the frozen logs of 2026-10-30 to 11-12: English 300, German 59, none in the dev set; the LFM3 file is no longer on disk. Waiting for plan approval.
- 2026-11-14 61 build: task 1 done: harness copied to spike 025 with the app's nine stop strings, gate rebuilt from main, both model hashes equal spike 022's protocol (LFM3 still on disk, no download), Qwen deterministic and equal to spike 022 on 238 of 238 dev outputs, gate fidelity 237 of 238 (evidence/setup.md). Qwen's 238 decodes took 432 s. LFM3 dev decodes started in the background.
- 2026-11-14 61 build: task 2: early signal failed. With the stop string LFM3 still fails closed on 44 of 238 dev items (bound 20) and ships a change on 38 (bound 50); the discarded outputs are LFM3 answering or obeying the dictation, not commentary after the tag. L2v1 and L2v2 were decoded in the same run: fewer discards (27, 22) and far fewer rejected edits, but shipped changes of 11/32 and 7/15 (German/English) against Qwen's 31/63 (evidence/dev-envelope.md). Both servers stopped; about 21 minutes of GPU time used. Put to the owner before more prompt work, as the plan says.
- 2026-11-14 61 closed: dropped on the owner's decision at the early signal. Tasks 3 to 6 were not run: no protocol lock, no holdout, no labels, no latency, no review and no verify, since there is no verdict to check and no code. ITEM.md dropped with the result, ROADMAP line removed, root file back to Slice: none. No tag, no deploy. About 21 minutes of model time used (Qwen 432 s, LFM3 819 s).
