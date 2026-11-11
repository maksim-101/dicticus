# 53 probe-test-isolation (quick)

## Brief

**Outcome:** A test run leaves the live debug logs untouched, so every audit counts only real dictations.

**Problem:** Ten diagnostics writers build the path `~/Library/Application Support/Dicticus/DebugRecordings` themselves. Quick task 261031-nil added `DebugRecorder.directoryOverrideForTesting`, which `Shared/DicticusTests/DicticusTestBootstrap.swift:52` sets, but only `DebugRecorder` and `FilenameMangleProbe` read it. The other eight still write to the live folder during tests:

- `Shared/Diagnostics/DiscardProbe.swift`
- `Shared/Diagnostics/AudioCaptureProbe.swift`
- `Shared/Diagnostics/MediaPauseProbe.swift`
- `macOS/Dicticus/Diagnostics/PasteProbe.swift`
- `macOS/Dicticus/Diagnostics/OverlayProbe.swift`
- `macOS/Dicticus/Diagnostics/PostEditProbe.swift`
- `macOS/Dicticus/Diagnostics/LlmLifecycleProbe.swift`
- `macOS/Dicticus/Diagnostics/PreviewFlagRecorder.swift`

Three test runs on 2026-10-31 put 30 fake rows into the live logs, and the 2026-11-10 audit had to exclude them by hand.

**For whom:** the owner and the agents that audit the debug logs. They run the test suite on the same Mac where real dictations are logged.

**Done criteria:**
1. `[check]` `new`: all ten writers get their folder from one resolver. That resolver returns the override when one is set and the live folder otherwise. Observed by grep: outside tests, the string `"DebugRecordings"` is built in exactly one place.
2. `[check]` `new`: a regression test sets the override and asserts that each of the eight probes resolves inside the override folder. Observed by the test passing. Reverting one probe back to the old code once must make the test fail.
3. `[check]` `adapt`: a full macOS test run, with `-derivedDataPath build` as CLAUDE.local.md requires, adds no row to the live folder. Observed by a list of files and line counts taken before and after the run. Any growth is checked against dictation timestamps, since the installed app may log a real dictation during the run.
4. `[check]` `exists`: the iOS simulator suite still passes, because the change touches `Shared/`.

**Not in this slice:** removing the 30 fake rows already in the live logs. The 14-day retention purges the 2026-10-31 files by 2026-11-14, and the audit copy marks them excluded. Also left out are the other audit fix candidates: Warp context, silent clips, timeout logging.

**Constraints:**
- "Never run the test suite from `~/Library/Developer/Xcode/DerivedData`" (CLAUDE.local.md). After the run, `scripts/check-running-copy.sh` must print OK.
- Diagnostics code stays behind `#if DEBUG_RECORDER`. All ten writers already are.
- No dependency on another project.

**Size and risk:** quick: two tasks, one session, no new dependency. Risk: none.

**Open:** none.

Approved by the owner 2026-11-11.

## Plan

**Route:** one resolver, `DebugRecorder.recordingsDirectory()`. It returns `directoryOverrideForTesting` when that is set and the live Application Support path otherwise. All ten writers call it in their `init`; PreviewFlagRecorder appends `preview-flags` to the result. Rejected: copying FilenameMangleProbe's four-line override check into each of the eight probes. That makes eight copies, and the next probe written would copy the leaky version, which is how these happened. Early signal: the canary test from task 1, run alone, fails on main for every probe and passes on the branch.

### Task 1: one resolver, ten writers, canary per probe
- **Goal:** every diagnostics writer resolves its folder through `DebugRecorder.recordingsDirectory()`. `TestIsolationCanaryTests` asserts that each of the eight probes resolves to `DicticusTestBootstrap.recorderDirectory`.
- **Files:**
  - `Shared/Diagnostics/DebugRecorder.swift`: the resolver; `init` uses it.
  - `Shared/Diagnostics/FilenameMangleProbe.swift`
  - `Shared/Diagnostics/DiscardProbe.swift`, `AudioCaptureProbe.swift`, `MediaPauseProbe.swift`
  - `macOS/Dicticus/Diagnostics/PasteProbe.swift`, `OverlayProbe.swift`, `PostEditProbe.swift`, `LlmLifecycleProbe.swift`, `PreviewFlagRecorder.swift`
  - In the seven actor probes, `private let directoryURL` becomes `nonisolated let directoryURL` so the test can read it. PreviewFlagRecorder exposes the same as a read-only property.
  - `Shared/DicticusTests/TestIsolationCanaryTests.swift`: the shared probes go in the existing `#if DEBUG_RECORDER` test; the five macOS probes in an `#if os(macOS)` test inside it.
- **Affects:** the production path only through the resolver's fallback, which builds the same URL as today. `PreviewFlagRecorderTests` still injects its own directory through `init(directoryURL:)`, which is unchanged. iOS compiles without DEBUG_RECORDER, so all of this is compiled out there. No other test asserts on the probes' path construction: `DebugRecordings` appears in tests only in the canary and the bootstrap.
- **Verify:**
  - `grep -rn '"DebugRecordings"' Shared macOS iOS | grep '\.swift:' | grep -v Tests` prints exactly one line, in `DebugRecorder.swift`.
  - `cd macOS && xcodegen generate >/dev/null && xcodebuild -project Dicticus.xcodeproj -scheme Dicticus-Debug-Recorder -derivedDataPath build -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' -only-testing:DicticusTests/TestIsolationCanaryTests test` prints `TEST SUCCEEDED`.
  - Once, put the old path back in `PasteProbe`, rerun the same command and see `TEST FAILED` on the PasteProbe assertion, then restore it.
- **Depends on:** none.

End-of-build gates (build step 3), covering criteria 3 and 4:
- Take a snapshot before and after the full macOS suite: `wc -l` of the live `DebugRecordings/*.jsonl` plus a listing of `preview-flags/`. Check any new row's `ts` against the app's real dictations.
- Run the full macOS suite with the config test command (scheme `Dicticus`) and again with scheme `Dicticus-Debug-Recorder`, which is the only one that compiles the probes and their canary, without `-only-testing`. It is expected to print `TEST SUCCEEDED`, with 7 skips when the screen is on.
- Run `scripts/check-running-copy.sh`, which must print OK.
- Run the iOS simulator suite: `cd iOS && xcodegen generate >/dev/null && xcodebuild -project Dicticus.xcodeproj -scheme Dicticus -derivedDataPath build/DerivedData -destination 'platform=iOS Simulator,name=iPhone 18 Pro' CODE_SIGNING_ALLOWED=NO test`. It must print `TEST SUCCEEDED`.

### Departures from the brief
None.
