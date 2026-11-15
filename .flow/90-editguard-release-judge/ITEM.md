---
id: 90
title: editguard-release-judge
status: idea
size:
assignee: none
created: 2026-11-15
why:
waiting_until:
shipped:
links: 57-cleanup-edit-list-spike
---

# EditGuard stops rejecting harmless edits, through finer reverts and a local judge model

Imported at the flow adoption of 2026-11-15 from the old GSD lists; inventory row in `.flow/ARCHIVE.md` under "Inventory at adoption 2026-11-15". Merges SEED-001 (sentence-level judge), SEED-002 (local decision model as arbiter), GSD 999.4 (light comma and function-word insertions over-reverted, mostly German) and spike 014's proposed order. Spike 015 killed a Qwen judge (memory note), so a new judge needs a new model.

Sources: .planning/seeds/SEED-001-realword-mishearing-judge.md; .planning/seeds/SEED-002-local-decision-model-arbiter.md; .planning/ROADMAP.md Phase 999.4; memory note 'Spike 014: EditGuard over-blocking'
