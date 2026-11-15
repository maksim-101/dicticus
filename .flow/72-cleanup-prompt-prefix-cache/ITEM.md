---
id: 72
title: cleanup-prompt-prefix-cache
status: idea
size:
assignee: none
created: 2026-11-15
why:
waiting_until:
shipped:
links: 55-llm-timeout-fallback
---

# AI cleanup reuses the encoded system prompt between calls, cutting latency with identical output

Imported at the flow adoption of 2026-11-15 from the old GSD lists; inventory row in `.flow/ARCHIVE.md` under "Inventory at adoption 2026-11-15". Deferred on 2026-07-15 in favour of quality; CleanupService still clears the KV cache on every call. Same latency theme as 55, a different fix.

Sources: .planning/backlog/cleanup-prompt-prefix-kv-cache.md; .planning/milestones/v2.5-phases/44-cleanup-fidelity-guard/44-14-SUMMARY.md
