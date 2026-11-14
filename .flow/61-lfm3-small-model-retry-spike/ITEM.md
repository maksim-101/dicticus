---
id: 61
title: lfm3-small-model-retry-spike
status: dropped
size: standard
assignee: agent
created: 2026-11-14
waiting_until:
shipped:
links:
---

# LFM3-1.7B as the cleanup model for 6 GB iPhones: retried, stopped at the early signal, not shipped

Dropped by the owner on 2026-11-14 ("Stop here") after the plan's early signal failed on the 238 development dictations of spike 022. No holdout verdict was taken, so this is a development-set result with an unlabelled estimate, not a pre-registered verdict.

What was measured (evidence/dev-envelope.md, evidence/setup.md):
- The harness is faithful: Qwen3.5-4B reproduces spike 022 on 238 of 238 outputs; the gate replays the logged result on 237 of 238.
- The app's stop at `</corrected_text>` does not rescue LFM3: 44 outputs are still discarded by the gate (spike 022: 45). The cause is not commentary after the tag. LFM3 treats the dictation as a message to itself and answers or obeys it, against the prompt's explicit rule; the discarded outputs are a median 4.1 times as long as the dictation.
- Two prompts written for LFM3 reduce the discards to 27 and 22 and the rejected edits by more than half, but the model then changes less: the better one ships a change on 11 German and 32 English dictations against Qwen's 31 and 63. Estimated good edits about 7 and 24, where the owner's bar (60 % of Qwen's) needs about 11 and 31.

Standing decision unchanged: AI Cleanup needs 8 GB (threshold 6.5 GiB). A later small model is worth a trial only if it keeps to an editing task when the text contains questions and requests; spike 025's harness (`.planning/spikes/025-lfm3-retry/`, gitignored) measures that in about five minutes per model on the development set.
