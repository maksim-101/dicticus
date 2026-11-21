---
id: 132
title: cleanup-keeps-dictated-quotes
status: planned
size:
assignee: none
created: 2026-11-21
why: a German cleanup strips every dictated quotation mark (5 dictations in the 11-09..21 audit, one shipped unbalanced); small, clear defect on both platforms
waiting_until:
shipped:
links: 94-editguard-small-residues
---

# Dictated quotation marks survive AI cleanup, also when the model writes German quotes

`Shared/Services/CleanupService.swift:1039-1044` keeps quotation marks only when each quote character's count equals the input's; when the German model turns `"` into `„`, the counts differ and every quote is removed, and EditGuard accepts that as a punctuation edit. Seen in the 2026-11-21 audit (`.planning/debug/audit-2026-11-21/SYNTHESIS.md` section 2; records #127, #319, #379, #431, #497). Fix direction: compare opening plus closing marks as one class (or normalise „“ to "" before the count). Ships on macOS and iOS together.
