# 60 pause-period-and-audio-retention (quick)

## Brief

**Outcome.** In AI cleanup, a period that Whisper writes at a thinking pause ("some of my sentences. in a bad way") no longer ships as a sentence break: the count of shipped texts with a period followed by a lowercase word goes from 7 of 154 dictations (2026-11-07 to 11-14) to 0 on the same input. And the Debug-Recorder build keeps the last seven days of dictation audio on this Mac, so a transcript the owner doubts can be re-transcribed and compared with what was said.

**Problem.** The owner's report of 2026-11-14: AI cleanup "restructuring some of my sentences in a bad way that actually changes the meaning". The investigation (54's STATE.md Decisions, 2026-11-14) over the 154 AI-cleanup dictations of that week found no clause move and no deletion or insertion of three or more words shipped by the LLM and gate; the meaning changes sit in Whisper's low-confidence spans (word probabilities 0.15 to 0.49 in the dictation the owner named), which nothing on disk can check: the capture probe stopped writing audio on 2026-08-27 (quick 260827-81z). Separately, Whisper writes a period at a thinking pause and continues in lowercase; the LLM merges it (gate class `pauseSplitMerge`) only when its whole output passes, which it did not in 73 of 154 dictations, so 7 pause periods shipped. Since October: 30 pause periods after an ordinary word in the raw transcripts, against 11 legitimate period-plus-lowercase cases (`bzw.`, `etc.`) and a few ellipses.

**For whom.** The owner, dictating with the push-to-talk key held through thinking pauses (CLAUDE.local.md, 2026-10-18), on macOS, in AI cleanup mode; the audio retention is for the owner's own debugging on the Debug-Recorder build only.

**Done criteria.**
1. `[check]` `new`: `RulesCleanupService.clean` (AI mode's deterministic stage, before the LLM) turns `<word>. <lowercase word>` into `<word>, <lowercase word>` when the token before the period is an ordinary word (not an abbreviation from a short list: `bzw`, `etc`, `usw`, `ca`, `vs`, `z.B`, `e.g`, `i.e`, `d.h`, `evtl`, `ggf`, `inkl`, `Nr`, `Dr`; not a number), the mark is a single period (not `...`), and the next token starts with a lowercase letter. Question and exclamation marks, capitalised continuations and plain mode are untouched. Observed by `RulesCleanupServiceTests` (synthetic cases for each clause, English and German) and by an offline run of the rule over the raw texts of 2026-11-07 to 11-14 printing counts only: every ordinary-word pause period converted (8 records in the 170 of the run; the brief's 14 counted legitimate cases and question marks too, see the evidence file), 0 of the abbreviation, number and ellipsis cases changed (`evidence/pause-period-replay.md`).
2. `[check]` `exists`: the EditGuard baseline stays the rules-cleaned text, so the comma is part of what the LLM must preserve; the full check (both macOS schemes, iOS simulator) stays green.
3. `[check]` `new`: the Debug-Recorder build writes one WAV per completed macOS dictation, both modes, to `DebugRecordings/audio/<ISO timestamp>.wav` (16 kHz mono PCM16, the buffer handed to Whisper), through `DebugRecorder.recordingsDirectory()` so the test override of slice 53 redirects it; files older than 7 days are purged once per launch; the Dicticus scheme compiles none of it (`#if DEBUG_RECORDER`, as every probe). Observed by a unit test of the writer (RIFF header, sample count, purge of a file dated 8 days back), the isolation canary extended to the new writer, a `strings` count of the writer's name in the Dicticus scheme's build product (0), and the owner's first dictations on the installed build: one WAV per dictation whose duration matches the dictation.
4. `[check]` `new`: the cleanup record names its audio: `DebugCleanupRecord.audio_file` carries the WAV's file name (nil in older JSONL and in builds without the probe), threaded from the transcription result through `HotkeyManager` to `TextProcessingService.process`. Observed by the codable tests and the owner's first dictations (the record's `audio_file` names an existing file).

**Not in this slice.** Marking low-confidence words in the paste or overlay (declined 2026-11-14). The same pause-period rule for plain mode. Any ASR change. iOS. Re-transcribing the retained audio (that is the week's analysis, once audio exists).

**Constraints.** Privacy (CLAUDE.md): "all processing happens on-device; no audio or text goes to any server": the audio stays under Application Support on this Mac, written only by the Debug-Recorder build. The probe header rule: "COMPILED OUT unless built with -D DEBUG_RECORDER … Never present in the public Release / GitHub artifact." Slice 53: every diagnostics writer honours the test directory. The owner holds the hotkey through pauses; the rule changes text, not audio (CLAUDE.local.md). Public repo: tests use synthetic sentences; evidence holds counts. Disk: a 36 s dictation is about 1.2 MB as PCM16; this week's volume (about 20 dictations a day) is about 25 MB a day, under 200 MB for the rolling week (83 GB free).

**Size and risk.** Quick: two tasks, one session, no new dependency. Risk: none.

**Open.** Plain mode's pause periods (same rule, separate decision). Switching the audio retention off after the analysis week: the owner says when, and the probe goes the way of the 2026-08-27 change.

## Plan

**Route.** The pause mark: comma (chosen) against deleting the period (a run-on where the pause was a real boundary, and the LLM then has no mark to keep) and capitalising the next word (keeps the false break the owner complained about); the comma is the neutral mark for a pause inside an utterance and the LLM may still turn it into a period, which the gate accepts as punctuation. The audio: a new `AudioRetentionProbe` actor (chosen) against re-enabling `AudioCaptureProbe`'s dump, which fires only on the clip signature and conflates two purposes. Fragile assumption: the rule's abbreviation list is complete for the owner's speech; the offline replay over the week's raw texts is the early signal (0 legitimate cases changed), and a miss is one list entry.

### Task 1: pause-period rule
- **Goal:** criterion 1.
- **Files:** `Shared/Services/RulesCleanupService.swift` (a `static func joinPausePeriods(_:)` applied in `clean` after the filler and self-correction steps, before the whitespace collapse), `Shared/DicticusTests/RulesCleanupServiceTests.swift`.
- **Affects:** `clean` is called only in the aiCleanup branch (`TextProcessingService.swift:241`), so plain mode is unchanged; the EditGuard baseline is the rules text, so a comma the rule inserts is baseline, not an LLM edit; `SelfCorrectionResolver` runs before it and looks for comma-anchored connectors, so the rule runs after it, not before.
- **Verify:** `cd macOS && xcodegen generate >/dev/null && xcodebuild -project Dicticus.xcodeproj -scheme Dicticus -derivedDataPath build -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' -only-testing:DicticusTests/RulesCleanupServiceTests test` prints `TEST SUCCEEDED`; the offline replay (a scratch script that calls the same rule logic over the week's raw texts and prints counts) writes `evidence/pause-period-replay.md` with converted 14, legitimate cases changed 0.
- **Depends on:** none.

### Task 2: audio retention and the record link
- **Goal:** criteria 3 and 4.
- **Files:** new `Shared/Diagnostics/AudioRetentionProbe.swift` (`#if DEBUG_RECORDER`, WAV writer modelled on the pre-260827 `writeWav16`, 7-day purge modelled on `DebugRecorder.purgeIfNeeded`, directory `recordingsDirectory()/audio`); `macOS/Dicticus/Services/TranscriptionService.swift` (write after `combinedText` is known, next to the capture probe call; the file name goes into `DicticusTranscriptionResult` as `var audioFileName: String? = nil` in `Shared/Models/TranscriptionResult.swift`, so every existing initialiser call, iOS included, compiles unchanged); `macOS/Dicticus/Services/HotkeyManager.swift` (pass it to `process`); `Shared/Services/TextProcessingService.swift` (`audioFile: String? = nil` → record); `Shared/Diagnostics/DebugRecorder.swift` (`audio_file` field, keys, init, tolerant decode); `Shared/DicticusTests/TestIsolationCanaryTests.swift` (the new writer's directory), new `Shared/DicticusTests/AudioRetentionProbeTests.swift`, `Shared/DicticusTests/DebugCleanupRecordCodableTests.swift` (round trip and tolerant decode).
- **Affects:** iOS compiles `TextProcessingService` and `DebugRecorder` (the default `nil` keeps every caller); the Dicticus scheme has no `DEBUG_RECORDER`, so the probe is absent there; slice 53's live-folder gate (tests write to the test directory only).
- **Verify:** scheme `Dicticus-Debug-Recorder`, same flags, `-only-testing:DicticusTests/AudioRetentionProbeTests -only-testing:DicticusTests/TestIsolationCanaryTests -only-testing:DicticusTests/DebugCleanupRecordCodableTests` prints `TEST SUCCEEDED`; `strings macOS/build/Build/Products/Debug/Dicticus.app/Contents/MacOS/Dicticus | grep -c AudioRetentionProbe` prints 0 after a Dicticus-scheme build; the runtime part at verify: after `scripts/install-local.sh`, the owner's next dictation leaves `DebugRecordings/audio/<ts>.wav` and a cleanup record whose `audio_file` names it (read back by the agent, counts and names only).
- **Depends on:** none (disjoint files from task 1).

**End-of-build gates:** full macOS check on both schemes with the live DebugRecordings snapshot unchanged, iOS simulator suite, `scripts/check-running-copy.sh` OK, install of the Debug-Recorder build.

## Review

One round (quick): `code-review` at low on `3ddc4de..HEAD`, code files only, with the data rule (no dictation text from the logs or the planning tree). Working rules checked by the main loop: no Spotlight; audio and text stay on this Mac; the probe is `#if DEBUG_RECORDER` like every probe; tests use synthetic sentences; every xcodebuild used `-derivedDataPath build`.

| id | severity | finding | disposition |
|---|---|---|---|
| R1 | WARNING | The abbreviation exclusion was list-only, so a dotted token outside the list ("U.S.A. in", "a.m. in") would have shipped as "U.S.A, in". Claim checked: the regex captures `U.S.A` as the token and the old conditions let it through. | **fix**: a token that contains a dot is never joined (covers every dotted abbreviation and the ellipsis); two cases added to `testPausePeriod_abbreviationsNumbersAndEllipsesStay`; RulesCleanupServiceTests 11 tests 0 failures. |
| R2 | NIT | Two dictations in the same timestamp would share a WAV name and the second write would replace the first. | **won't fix**: `DebugRecorder.iso8601Timestamp` formats with `.withFractionalSeconds` (millisecond), and dictations are sequential on one hotkey; two cannot end in the same millisecond. |

No open BLOCKER or WARNING after the round.

## Verify

Commit handed over: 46348f5. Build on the owner's Mac: Debug-Recorder build of that commit, installed by `scripts/install-local.sh` (see STATE.md History for the time and `check-running-copy.sh` result).

| # | criterion | evidence | verdict |
|---|---|---|---|
| 1 | `[check]` pause period becomes a comma before the LLM; abbreviations, numbers, ellipses, capitalised continuations and plain mode untouched | `evidence/unit-tests.md`: RulesCleanupServiceTests 11 passed (four pause-period tests: lowercase continuation in English and German, capitalised continuation stays, abbreviations/numbers/ellipses/question mark/U.S.A./a.m. stay, idempotent; 3 failures with the rule removed); `evidence/pause-period-replay.md`: 8 records converted, 0 of 8 legitimate cases changed; plain mode: `clean` runs only in the aiCleanup branch (`TextProcessingService.swift:241`) | **pass** |
| 2 | `[check]` EditGuard baseline is the rules text; full check green | `evidence/unit-tests.md`: EditGuardPipelineTests 15 passed including `testPausePeriodBecomesCommaBeforeTheGate`; full check on f841f7c: macOS Dicticus 1960 tests 0 failures, Dicticus-Debug-Recorder 2042 tests 0 failures, iOS simulator 1780 tests 0 failures; the review fix touched the rule's exclusion only and reran its class | **pass** |
| 3 | `[check]` Debug-Recorder build writes one WAV per dictation under `DebugRecordings/audio`, 16 kHz mono PCM16, through `recordingsDirectory()`, 7-day purge, nothing in the Dicticus scheme; runtime: the owner's first dictations leave one WAV each | unit part: `evidence/unit-tests.md`: AudioRetentionProbeTests 3 passed (RIFF header, 16 000 Hz, mono, 44 + 2n bytes; empty buffer writes nothing; 8-day-old WAV purged, fresh WAV and a .txt kept), TestIsolationCanaryTests 6 passed with the new writer's directory under the test folder; `nm` 0 symbols in the Dicticus scheme's debug dylib against 62 in the Recorder host. Runtime part: `evidence/runtime-audio.md`: the owner's first two dictations on the installed build (46348f5) left `2026-11-14T06-56-44.009Z.wav` (8.1 s) and `2026-11-14T06-57-21.128Z.wav` (27.2 s), 16 000 Hz, 1 channel, Int16 | **pass** |
| 4 | `[check]` the cleanup record names its WAV in `audio_file` | unit part: DebugCleanupRecordCodableTests 10 passed (round trip with `audio_file`, legacy JSON decodes with nil). Runtime part: `evidence/runtime-audio.md`: both records carry `audio_file` naming an existing file | **pass** |

Working rules: no Spotlight (grep over `macOS/Dicticus`, `Shared`: comments only); audio and text stay on this Mac (the probe writes under Application Support, no network code touched); `#if DEBUG_RECORDER` on the probe and its tests; tests use synthetic sentences and a synthetic sine buffer; every xcodebuild used `-derivedDataPath build`; `check-running-copy.sh` OK after each run and install; simulator shut down; `.flow` records written with Edit/Write (the evidence files by the commands that produced them).

No `[judge]` criterion: the owner had nothing to judge; the runtime rows closed on the owner's ordinary dictations of 06:56Z and 06:57Z.

Signed off: 2026-11-14, no `[judge]` item to sign; criteria 1-4 `[check]` pass with the evidence above. Slice 60 ships.
