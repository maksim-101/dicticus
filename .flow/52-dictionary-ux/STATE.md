# State of 52-dictionary-ux
Slice: 52-dictionary-ux (standard)
Step: build
Next: build step 3 again: rerun the macOS Dicticus and Dicticus-Debug-Recorder suites on 2e48ccf (task 4 changed HistoryView and the sheet after the recorded full check; Shared and iOS unchanged since), then review from diff base 5ef4db7
Waiting on: nothing
Started: 2026-11-14T14:07:19Z
Baseline: at 04395b4 in a throwaway worktree: macOS Dicticus 1960 tests 0 failures (8 skipped), Dicticus-Debug-Recorder 2042 tests 0 failures (10 skipped); iOS simulator first run "test runner hung before establishing connection" (environment), rerun 1780 tests 0 failures (11 skipped)
Base: branch point
Risk: none
Carried: none

## Decisions
- 2026-11-14 question: teaching route is "Fix from history" only (select a misheard word in a past dictation, type the correct spelling); the "say it again" panel and a spoken command were not chosen.
- 2026-11-14 question: "Mac first"; the iPhone/iPad screens become a follow-up item.
- 2026-11-14 mockup: dictionary-rows board, variant A (table with chips): "I like option A the best".
- 2026-11-14 mockup: history-pick board, variant A (click words, shift-click to extend): "option A".
- 2026-11-14 brief: approved by the owner ("approved").
- 2026-11-14 plan: approved by the owner ("approve").
- 2026-11-14 question (build, task 4): screenshots by "Render headless on this Mac" (an off-screen test renders both windows with invented data); no VM run, no answer to the VM's microphone prompt.

## History
- 2026-11-14 52 brief: opened from ROADMAP.md; branch flow/52-dictionary-ux from main 5ef4db7.
- 2026-11-14 52 mockup: two boards (dictionary-rows, history-pick) rendered headless without overflow; the owner chose A on both; folded into BRIEF.md.
- 2026-11-14 52 brief: approved by the owner; size standard, no risk trigger.
- 2026-11-14 52 plan: PLAN.md approved by the owner; four tasks, routes: grouping in the shared service by exact spelling, List with chips, wrapping word views in History.
- 2026-11-14 52 build: task 1 done (095b336), live count groups 183 entries 306; task 2 done (fd640b6); task 3 done (6ab10f1); 20 targeted tests 0 failures. Task 4 waits for mac-space.
- 2026-11-14 52 build: full check on 356c690 (no code change since 6ab10f1): macOS Dicticus 1980 tests 0 failures (10 skipped; the run took 7301 s because TranscriptionServiceTests and BrandRewriteTraceTests stalled for 15-18 minutes each under host load, while the same tests took 2-5 s in the Recorder run right after), Dicticus-Debug-Recorder 2062 tests 0 failures (9 skipped), iOS simulator 1796 tests 0 failures (11 skipped) on the rerun after the same "runner hung before establishing connection" as the baseline; simulator shut down; check-running-copy OK; com.dicticus.app.plist shasum identical before and after.
- 2026-11-14 52 build: task 4 partly run in mac-space (reset from base that evening; the outage was another app's container network capturing the VM subnet; cua reached through a loopback relay). Release build of 8cc79b5 built in the guest, `vm-seed.sh seed` loaded the 12 fixture entries (popover shows "12 entries", evidence/vm-popover-12-entries.png; readback entries 12) and 3 fixture dictations. Then macOS asked for microphone access for Dicticus; the prompt refuses synthetic clicks and Escape (evidence/vm-microphone-prompt-blocks.png), so neither window could be opened. The 30-minute slot ended; the app was quit, the VM left running and handed to the mac-automations session. Not yet observed: the grouped window, the History pick and the sheet.
- 2026-11-14 52 build: task 4 done (2e48ccf) by off-screen rendering: evidence/render-dictionary-window.png, render-history-pick.png, render-history-confirmation.png, render-sheet-join.png, render-sheet-warnings.png. The first render run crashed the test host (an NSWindow made in code freed twice on close; isReleasedWhenClosed = false fixed it) and put a crash dialog on the owner's screen; the render also showed a double chevron on the sheet's spelling menu, fixed. A separate, older crash at test-host exit (llama Metal teardown) went to the root Carried list.
