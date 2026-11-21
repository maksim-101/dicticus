---
id: 139
title: editguard-repair-instead-of-revert
status: idea
size:
assignee: none
created: 2026-11-21
why:
waiting_until:
shipped:
links: 90-editguard-release-judge, 91-editguard-post-revert-punctuation, 81-llm-gated-self-correction
---

# A drifted span in the LLM's cleanup is repaired on its own, so the rest of the good cleanup ships

The 2026-11-21 audit: English 26 % and German 72 % of AI dictations rejected, 25 rejected records were good losses and 41 mixed; sentence-coupled and atomic-group reverts discard whole sentences, and 11 of 24 unmarked self-corrections were fixed by the LLM and reverted. KeyVox (MIT) reconciles numbers, money, addresses and punctuation against the original and reverts only the drifted span (`Packages/KeyVoxStyleRewrite/.../OutputRepair/`). Idea: test repair-instead-of-revert on the replay corpus; allow deletions before an explicit correction marker. Sources: `.planning/debug/audit-2026-11-21/lens-gate.md`, `.planning/research/competitors-2026-11-21/SUMMARY.md`.
