---
id: 133
title: dictionary-common-word-guard
status: planned
size:
assignee: none
created: 2026-11-21
why: dictionary and brand rewrites corrupt ordinary speech ("what app" became "WhatsApp" twice, "a I mean" became "AI", the adjective "authentic" became "Authentik" in 5 dictations); every such hit damages a correct transcript
waiting_until:
shipped:
links: 58-learn-from-corrections-spike, 70-tech-term-mishearing-recovery
---

# Dictionary entries and brand matches no longer rewrite everyday words without a supporting context

From the 2026-11-21 audit (`.planning/debug/audit-2026-11-21/SYNTHESIS.md` section 3) and the dictionary analysis (`dictionary-patterns.md` in the same folder): the brand matcher turned "what app" into "WhatsApp" (#355, #365, the second inside the owner's own correction), the entry "A I" ate "a I mean" (#249), "authentic" became "Authentik" in 5 dictations, and 24 keys are single lexicon words, 63 multi-word keys use only common words, 17 keys have 3 characters or fewer (e.g. Jeff, cheers, "the set.", "this quote", cloud phrases). Direction: a risk lint on entries made of common words, and apply them only with a context cue (the code already has `shortCanonicalTriggers` and `ContextResolver`); brand matching skips phrases whose words are all dictionary words. KeyVox's matcher (MIT) requires clause-local support before overriding a common word (`.planning/research/competitors-2026-11-21/SUMMARY.md`). From 52's review (R20): the Mac footer "Add Entry" (`setReplacement`) can still store a spelling that is another entry's heard form; route it through `addHeardForm`. Also fix three data defects found there: one key containing a newline, two keys with stray quote characters.
