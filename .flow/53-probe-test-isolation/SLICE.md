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
