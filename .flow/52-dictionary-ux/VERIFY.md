# Verify of 52-dictionary-ux

Code under test: ac93cfe (last code change), plus 1d0a773 (one test assertion). Evidence in `evidence/`. Fresh verifier (sonnet, criteria and evidence paths only): 1-6 true, 7 inconclusive (checksum clause), rechecked below.

| # | criterion | evidence | verdict |
|---|---|---|---|
| 1 | one row per spelling with chips; grouping test; live count | `c1-6-slice-tests-807ebb9.txt` (`testGroupingCollectsFormsPerExactSpelling` passed); `c1-live-count-2026-11-21.txt`: 311 entries, 188 groups (the brief's 183 from 306 was the 2026-11-14 state; the owner has added entries since; grouping key is the exact replacement, the same as `DictionaryService.groups(of:)`); layout in `render-dictionary-window.png` | pass |
| 2 | add / remove / rename / delete by row, `renameEntry` rules kept | `c1-6-slice-tests-807ebb9.txt` (`testAddHeardForm*`, `testRenameSpelling*`, `testRemoveHeardFormAndRemoveGroup`, refusal tests, `DictionaryEntryEditTests`) | pass |
| 3 | stored format unchanged | every group operation test asserts `loadGuarded` of the persisted blob equals the map (`DictionaryGroupTests.swift:26-27` and the asserts at 75-218); no migration code in `git diff d8f6410..HEAD` (verifier grep) | pass |
| 4 | pick in Raw, sheet, join an existing row | `WordPickTests` and `AddToDictionarySheetModelTests` in `c1-6-slice-tests-807ebb9.txt`; renders `render-history-pick.png`, `render-sheet-join.png`, re-rendered on the final code by the fix agent (render run with `TEST_RUNNER_RENDER_DIR`, 2 tests 0 failures, FIX.md); substitute: off-screen render for the VM screenshot, owner decision 2026-11-14 | pass |
| 5 | two warnings, non-blocking | `testEverydayWordAndExistingKeyWarnings` ("cloud", existing key) now also asserts `canAdd` stays true (1d0a773); passed in `c7-macos-suites-1d0a773.txt`; `render-sheet-warnings.png` | pass |
| 6 | takes effect on the next dictation | `AddToDictionarySheetModelTests.swift:35` (`applyWithTrace` after save) and `testAddHeardFormJoinsExistingSpellingAndAppliesOnNextDictation`, passed | pass |
| 7 | all suites green; live dictionary blob byte-identical | `c7-full-check-807ebb9.txt` (macOS 1992/0, 2074/0; iOS 1802/0 on the rerun); `c7-macos-suites-1d0a773.txt`: the `customDictionaryMetadata` blob's sha256 is identical before and after both macOS suites (51670d88…), Dicticus 1992/0; Recorder 2074 with 1 failure in `TextInjectorTests.testInjectText_frontmostChanged_fallsBackToClipboardWithoutPaste`, a clipboard/front-app test outside the slice (TextInjector untouched since d8f6410) that passed in the two full runs before on the same code; shared clipboard state while the owner worked (inferred), noted in item 68 | pass |

## For the owner

1. `[judge]` criterion 8, look and feel: `evidence/c8-compare.png` puts each chosen mockup next to the built screen (dictionary window; picking words in History; the sheet joining a spelling; the sheet's two warnings; the confirmation line). Built from invented entries, off-screen render of the code at ac93cfe.
2. Question from review (R4): with click-to-pick words in History's Raw view (variant A), Raw text can no longer be drag-selected to copy part of it; "Copy Raw" still copies the whole text, and Polished stays selectable. Default: accept as is. Option: add selection back behind a toggle (small change, one more fix round).
