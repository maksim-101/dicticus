# 54 fix

Source: review round 2 (REVIEW.md), the no-round-3 rule.

## Items

1. **R12 (WARNING), fix.** `AppCategoryReader.category(atBundleURL:)` reads only `Contents/Info.plist`, so a flat bundle (an iPhone or iPad app running on Apple Silicon keeps `Info.plist` at the bundle root) never yields its declared category; the `Bundle(url:)` call it replaced in review round 2 handled both layouts.
   - Reproduction: `AppCategoryReaderTests.testFlatBundleIsRead` builds a fixture bundle with `Info.plist` at its root and expects the category; fails on the round-2 reader (run recorded below).
   - Cause: the round-2 fix (2d5b2c1) hard-coded `Contents/Info.plist` in `AppCategoryReader.swift` because the dictionary read replaced `Bundle(url:)` without its layout lookup; evidence: the reproduction's failure line and the file's single path.
   - Fix: read `Contents/Info.plist`, then `Info.plist` at the bundle root; the first readable one wins. Same defect elsewhere: no other plist read of a foreign bundle in `macOS/` or `Shared/` (grep `Info.plist`, `infoDictionary`: only this reader and the app's own bundle).
2. **R14 (NIT), fix.** The R5 regression test covers a missing bundle only; a plist that exists but does not parse is untested.
   - Reproduction: `testCorruptPlistIsNotCached` writes garbage bytes to `Contents/Info.plist`, expects nil and a second read on the next lookup.
   - Cause: a test gap in 2d5b2c1, no code change expected (`NSDictionary(contentsOf:)` returns nil for an unparsable file).

## Status

- Item 1 (R12): **done**. Reproduction run (scheme Dicticus-Debug-Recorder, `-only-testing:DicticusTests/AppCategoryReaderTests`, before the fix): `testFlatBundleIsRead` failed on 3 assertions (nil category, nil again, 2 reads), 6 other tests passed. After the fix (`Contents/Info.plist`, then `Info.plist`): 7 tests, 0 failures. The regression test fails without the fix, as that run shows.
- Item 2 (R14): **done**. `testCorruptPlistIsNotCached` passed already on the round-2 reader in the reproduction run (`NSDictionary(contentsOf:)` returns nil for an unparsable file), so it pins the behaviour without a code change.

## Return

Fix diff: 1 production file (3 lines changed), 1 test file (+22 lines): under 50 lines, no risk trigger, so no correctness pass. Full check after the fix: see STATE.md History (the fix touches `macOS/` only, which the iOS target does not compile; the iOS suite's last run on this branch, 1776 tests 0 failures at review round 2, stands for the Shared code, unchanged since). Project gates: live DebugRecordings folder snapshot across both macOS runs, `scripts/check-running-copy.sh`; no mdfind (the reader reads two plist paths of the frontmost app's own bundle). Criteria touched: 2 (the macOS category read); the fix adds a second plist location and leaves the `Contents/` path the runtime evidence ran through unchanged.
