# State of 52-dictionary-ux
Slice: 52-dictionary-ux (standard)
Step: build
Next: task 2 (grouped Manage Dictionary window); code drafted, verify after the iOS baseline rerun
Waiting on: nothing
Started: 2026-11-14T14:07:19Z
Baseline: at 04395b4 in a throwaway worktree: macOS Dicticus 1960 tests 0 failures (8 skipped), Dicticus-Debug-Recorder 2042 tests 0 failures (10 skipped); iOS simulator first run "test runner hung before establishing connection" (environment), rerun pending
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
