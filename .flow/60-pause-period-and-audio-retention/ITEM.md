---
id: 60
title: pause-period-and-audio-retention
status: shipped
size: quick
assignee: none
created: 2026-11-14
waiting_until:
shipped: 2026-11-14 (no tag: release batched under CHANGELOG Unreleased; the Debug-Recorder build of 46348f5 is installed on the owner's Mac)
links:
---

# A thinking pause no longer ships as a sentence break in AI cleanup, and the debug build keeps one week of dictation audio so a transcript can be checked against what was said

From the owner's report of 2026-11-14 (AI cleanup "restructuring some of my sentences in a bad way that actually changes the meaning") and the investigation that followed: across the 154 AI-cleanup dictations of 2026-11-07 to 11-14 the LLM and gate shipped no clause move and no deletion or insertion of three or more words; the meaning changes sit in Whisper's low-confidence spans, which no log can check without audio (the capture probe stopped writing audio on 2026-08-27); and a period Whisper writes at a thinking pause ("sentences. in a bad way") survived into 7 of the 154 shipped texts. The owner chose (a) one week of local, debug-only audio retention and (c) a deterministic pause-period fix before the LLM; declined (b) marking low-confidence words in the paste ("the paste should be clean").
