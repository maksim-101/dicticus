---
id: 63
title: whisper-missing-speech
status: idea
size:
assignee: none
created: 2026-11-14
waiting_until:
shipped:
links:
---

# found and, if confirmed, fixed: why the macOS Whisper text is missing stretches of what was said, up to 21 words in one dictation

Merged at the adoption of 2026-11-15: `.planning/backlog/whisper-segment-seam-quality.md` (words dropped at decode-window seams; its no-speech part is item 89).

Found in slice 62 (2026-11-14). On 33 dictations of that day, compared with a second engine and judged by the owner's ear, the production text lacked words that were spoken in five passages across three recordings (21, 12, 10, 4 and 3 words; cards 1 to 4 and 6 of `.flow/62-nemotron-stage3-pause-phantoms-spike/evidence/result.md`). The app's discard log for the three recordings says `reason: pass`, no audio lost, every decoded segment listed, so no app filter removed speech: the words are missing from the decoder's text. By estimated positions four of the five passages lie within a few seconds of a boundary between Whisper's decode windows; that is an inference and the first thing to check. Since slice 60 the debug build keeps a week of audio, so the gaps can be reproduced.

Kept for this item on the owner's word (2026-11-14): the fixed copy of those 33 recordings with both engines' texts, in spike 020's cache outside the repo. Delete it when this item ends or is dropped. Usage fact that bounds any fix: the owner holds the hotkey through pauses, and no change may drop speech that follows one.
