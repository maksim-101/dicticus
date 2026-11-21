---
id: 68
title: test-suite-leftovers
status: idea
size:
assignee: none
created: 2026-11-15
why:
waiting_until:
shipped:
links: 
---

# The test suites have no always-skipping test, no invented fixtures and no stale TODO

Imported at the flow adoption of 2026-11-15 from the old GSD lists; inventory row in `.flow/ARCHIVE.md` under "Inventory at adoption 2026-11-15". HistoryServiceTests.testAppGroupAvailableFlagDefaultsTrue always skips in the simulator; the 2026-11-01 audit's remaining test tidy-ups (duplicated prompt.contains pins, invented fixtures, a push-to-talk cycle test that loads WhisperKit, iOS tests reading the real App Group suite) were not re-checked; iOS/DicticusTests/IOSModelDownloadServiceTests.swift:23 has a "once Wave 2 lands" TODO.

Two order- or environment-dependent failures in the full macOS run of 2026-11-21 (slice 52), both passing when run alone: EditGuardCompoundRepairTests.testR0_checkerSignalsOnThisMac asserts the Mac's live German spell checker lists "Komma" among its completions, which depends on AppleSpell's state; DebugRecorderFinalStageTests.testFinalStageCapturesPostCapitalizationMutation reads DebugRecorder.shared.lastRecordForTests after a 150 ms sleep and got another test's record.

Sources: root STATE.md Carried; .planning/notes/2026-11-01-codebase-audit.md section 5; .flow/52-dictionary-ux/STATE.md History 2026-11-21
