# Fix of 52-dictionary-ux (review round 2 findings, 2026-11-21)

1. R14 BLOCKER, fix: adding a heard form to, picking, or merging into a spelling that a case-variant key already maps to is refused ("github" → "GitHub"). Cause: `spellingClashReason` (`Shared/Services/DictionaryService.swift:550-554`) refuses whenever `existingKey(spelling)` finds a key outside `allowed`, without checking that the key already maps to that same spelling, where the exact pass is idempotent (read in code; reviewer trace).
2. R15 WARNING, fix: renaming "Cloud" to "Claude" is refused when the row holds "claude". Cause: the own-forms check in `renameSpelling` (`:588`) compares case-insensitively since 6a32001; a form equal to the new spelling up to case maps onto itself idempotently, so only exact equality must be refused (read in code).
3. R16 WARNING, fix: the confirmation line shows the failed style whenever `lastModel` is nil, so the render test (built with a confirmation and no model) shows a failure. Cause: `HistoryView.swift:315-318` keys the style on `lastModel == nil` instead of a separate "undo failed" state (read in code).
4. R17 NIT, fix: Escape in a row's add-form field leaves the row warning. Cause: `cancelAdd` in `DictionaryGroupRow.swift:122-126` does not call `onMessage(nil)` (read in code).
Status 2026-11-21 (mechanical-edit agent, sonnet; slice tests 47 executed, 0 failures, 3 skipped; render test run with TEST_RUNNER_RENDER_DIR, 2 tests 0 failures):
- 1 done: regression tests failed before (`DictionaryGroupTests.swift:123`, `:130`; `AddToDictionarySheetModelTests.swift:97-98`), pass after.
- 2 done: `DictionaryGroupTests.swift:137` failed before, passes after; the exact-equality refusal test passes both ways.
- 3 done: separate `undoFailed` state; evidence `evidence/R16-render-history-confirmation.png` (green checkmark, no failure style); all five renders refreshed.
- 4 done, 5 done (view one-liners, compiled, not exercised on screen).

5. R18 NIT, fix: a whitespace-only footer original enables Add. Cause: `DictionaryView.swift:171` checks the untrimmed `newOriginal.isEmpty` (read in code).
