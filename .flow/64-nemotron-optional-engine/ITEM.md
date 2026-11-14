---
id: 64
title: nemotron-optional-engine
status: idea
size:
assignee: none
created: 2026-11-14
waiting_until:
shipped:
links:
---

# decided, and if yes built: Nemotron 3.5 Transcribe as an opt-in macOS engine for Macs with 32 GB or more

From slice 62 (2026-11-14), which ended spike 020. What is on record: German 3.74 against Whisper's 5.35 word errors per 100 words and an English tie (Stage 2); no words added after the speech on 114 padded clips, where Whisper added some on 3; on 33 real dictations the owner judged Nemotron right in five of seven disputed passages and found it better than Whisper overall. Against it: the strict pre-registered rule of slice 62 gave FAIL, because with the dictionary terms in the prompt it left out three words in one recording that is mostly pause, and wrote a spelled name out oddly in another; under the plain prompt the same two spots differ by two words and one word. The owner does not accept "fail" as the outcome ("overall it performed better; by the same definition, Whisper would have also failed the other cards"), so this stays an open idea for the owner to schedule or drop.

Costs measured on the owner's 48 GB Mac: 19.5 GB resident, about 5 GB of other apps pushed to swap at each load, and the host's resource gate refused or paused it under both of its normal rules. One whole-dictation fabrication in 114 clips (Stage 2, plain prompt) is unsized. The Stage 3 run produced no word timings, cause unknown. A first step, if scheduled: repeat the comparison on a full week of retained audio with a rule that measures both engines by the same bar. Model files (20 GB) are kept in spike 020's cache on the owner's word. Research: `.planning/spikes/020-nemotron-transcribe-macos/` (gitignored), `STAGE3-RESULTS.md`.
