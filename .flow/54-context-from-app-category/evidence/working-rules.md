# Working-rule checks for slice 54 (verify, 2026-11-13, commit 4ecc40e)

| rule (CLAUDE.md / CLAUDE.local.md) | check | result |
|---|---|---|
| Public repo: dictation samples from the debug logs never enter a tracked file | a script (prints counts only) collected every text field of 12+ characters from the replay's 312 items (1090 snippets) and searched the slice folder's tracked text files | 9 files checked, **0 hits** |
| Public repo: pii-scan at commit | every slice commit passed the pre-commit, commit-msg and pre-push scanners (no override used) | pass |
| Never Spotlight / `mdfind` in app code | `grep -rn "mdfind\|MDQuery\|MDItem\|NSMetadataQuery" macOS/Dicticus Shared scripts/install-local.sh` | 3 hits, all comments (PopoverRoot.swift:17, AppCategoryReader.swift:8, install-local.sh:11); the reader reads the frontmost app's own `Info.plist` (`Contents/` layout, then the bundle root) as a dictionary |
| Tests always with `-derivedDataPath build`; `check-running-copy.sh` prints OK after every run and install | every xcodebuild in the slice used `-derivedDataPath build` (macOS) or `build/DerivedData` (iOS); `check-running-copy.sh` printed `OK: only /Applications/Dicticus.app is running` after each run and after the install | pass |
| Never `-configuration Debug-Recorder` on `xcodebuild test` | the Recorder runs used `-scheme Dicticus-Debug-Recorder` without a configuration flag | pass |
| iOS simulator shut down after every run | `xcrun simctl shutdown` after each run; `simctl list devices booted` counted 0 | pass |
| Model runs through `heavy-gate acquire`, AC only | the replay ran under slot `replay-54` on mains power (evidence/replay-tracer.md (c)); no model run since | pass |
| `.flow` records edited with Edit or Write only | BRIEF, PLAN, REVIEW, FIX, VERIFY, STATE: Edit/Write. Two files were created by commands that copy lines, as flow's conversion procedure allows: `.flow/54-context-from-app-category/STATE.md` at the 0.9.0 layout conversion (header and History lines copied from the branch's old root file) and the evidence files, which the rule exempts | pass |
| Shared/ stays platform-neutral; iOS keeps building | `ContextResolver.resolve(bundleID:category:…)` takes the category as a string; iOS simulator suite 1776 tests 0 failures at review round 2 on the slice's final Shared code (unchanged since, `git diff e1b4f52..HEAD -- Shared/Services Shared/Models Shared/Diagnostics` empty) | pass |
