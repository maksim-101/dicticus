# State of 52-dictionary-ux
Slice: 52-dictionary-ux (standard)
Step: build
Next: task 4 (on-screen check in mac-space), once the read-aloud session frees the VM
Waiting on: host: mac-space VM, held by the read-aloud-extension session until about 18:30 CET 2026-11-14 (it may offer a 30-minute gap around 16:30)
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

## History
- 2026-11-14 52 brief: opened from ROADMAP.md; branch flow/52-dictionary-ux from main 5ef4db7.
- 2026-11-14 52 mockup: two boards (dictionary-rows, history-pick) rendered headless without overflow; the owner chose A on both; folded into BRIEF.md.
- 2026-11-14 52 brief: approved by the owner; size standard, no risk trigger.
- 2026-11-14 52 plan: PLAN.md approved by the owner; four tasks, routes: grouping in the shared service by exact spelling, List with chips, wrapping word views in History.
- 2026-11-14 52 build: task 1 done (095b336), live count groups 183 entries 306; task 2 done (fd640b6); task 3 done (6ab10f1); 20 targeted tests 0 failures. Task 4 waits for mac-space.
- 2026-11-14 52 build: full check on 356c690 (no code change since 6ab10f1): macOS Dicticus 1980 tests 0 failures (10 skipped; the run took 7301 s because TranscriptionServiceTests and BrandRewriteTraceTests stalled for 15-18 minutes each under host load, while the same tests took 2-5 s in the Recorder run right after), Dicticus-Debug-Recorder 2062 tests 0 failures (9 skipped), iOS simulator 1796 tests 0 failures (11 skipped) on the rerun after the same "runner hung before establishing connection" as the baseline; simulator shut down; check-running-copy OK; com.dicticus.app.plist shasum identical before and after.
