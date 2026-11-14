---
id: 61
title: lfm3-small-model-retry-spike
status: active
size:
assignee: agent
created: 2026-11-14
waiting_until:
shipped:
links:
---

# measured: whether LFM3-1.7B, with its envelope losses removed, cleans up as well as Qwen3.5-4B, so AI Cleanup could reach 6 GB iPhones

The owner said on 2026-11-14 "you can give it a try" to the question open since 2026-11-04. Spike 022 (2026-10-31, on the Mac, replaying 238 logged dictations) failed LFM3 as a drop-in: good edits German 7 against Qwen's 17, English 18 against 51. Two of its three losses were on the app side and one is fixed since: the `</corrected_text>` stop string shipped on 2026-10-31 (CleanupService.swift). Still open: a model-family-aware reasoning preclose and BOS (`modelWantsReasoningPreclose` matches qwen3 only) and the English over-rewriting, which the production prompt provokes. Research: `.planning/spikes/022-lfm3-cleanup-model/README.md` (gitignored).
