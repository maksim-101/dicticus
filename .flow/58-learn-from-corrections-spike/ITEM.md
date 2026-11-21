---
id: 58
title: learn-from-corrections-spike
status: planned
size:
assignee: none
created: 2026-11-11
why: the owner gave the go on 2026-11-21; SEED-003's trigger (3 or more recurring mishearing pairs a week) is met, and 311 hand-made entries show the dictionary does not scale by hand
waiting_until:
shipped:
links:
---

# recurring post-paste corrections become dictionary suggestions; tested on the post-edit logs

Merged at the adoption of 2026-11-15: `.planning/seeds/SEED-003-dictionary-suggestion-miner.md` (recurring mishearings in the logs as a second source; every entry needs the owner's approval), the cleanup-hint tiers of `.planning/backlog/history-correction-feedback.md`, fix 6 of `.planning/debug/audit-2026-11-10/SYNTHESIS.md`, and the one-week reading of the post-paste edit logs in `.planning/quick/261003-jvq-*/261003-jvq-SUMMARY.md`.

Added 2026-11-21 (owner go for the spike):
- Trigger met in the 2026-11-09..21 audit on exact raw strings: "grogbot" 5 dictations, "volt" (for Vault) 4, "catty" (for Caddy) 3 (`.planning/debug/audit-2026-11-21/SYNTHESIS.md` section 5). The owner: the product name is "Grok Bot" (xAI), with a space; the glued "Grokbot" needs a split or its own entry.
- Dictionary analysis (`.planning/debug/audit-2026-11-21/dictionary-patterns.md`): 311 entries, 189 phonetic, 76 spacing/joining; 28 spellings carry 125 keys (Claude alone 29); 48 differ only in the first letter; 238 keys can never reach the fuzzy matcher; no hit counter exists, so dead entries are unknown. Proposed: variant matching per target spelling with German phonetic classes, a generic joiner/splitter, and a hit counter.
- The post-edit signal is blind in Orca (346 of 352 rows `no-text-value`), the app most dictations went to this week; the watcher needs a route for Electron fields.
- Reusable MIT code (`.planning/research/competitors-2026-11-21/SUMMARY.md`): Amical's `EditWatchService.swift` and `candidates.ts` (post-paste watcher and 1-2 word candidate extraction), KeyVox's `DictionaryMatcher`/`PhoneticEncoder`/`ReplacementScorer`. Wispr Flow and Granola learn from edits with an Undo toast; every entry here still needs the owner's approval.
