# Task 3: counts from `stage3_score.py` (lock hashes confirmed), 2026-11-14

Counts only; the passages' words are in the gitignored planning tree.

## Real recordings (33; 28 with a pause of 1 s or more), Nemotron against Whisper's raw text

| Arm | Loops | Passages only Nemotron has (3+ words more) | Passages only Whisper has | Of these, at a pause (estimated) |
|---|---|---|---|---|
| N0 (plain prompt) | 0 | 3 | 0 | 2 |
| N2 (with dictionary terms, the verdict arm) | 0 | 5 | 1 | 2 |

Distinct passages across both arms: 7 (limit 20), so the stage goes on to listening. By size of the surplus: 21 words (N0 only, English), 12 and 10 words (N2 only, English), 4 and 3 words (both arms, German), 3 words (N2 only, English), and one passage of 3 words that only Whisper has (N2, English). Three of the seven lie in one 71 s English recording.

## Padded twins (114), padded decode against the same engine's unpadded decode

| Engine and arm | Gained trailing words | Lost trailing words | Gained or lost | Loops |
|---|---|---|---|---|
| Whisper (October decodes) | 3 | 0 | 3 | 0 |
| Nemotron N0 | 0 | 1 (English) | 1 | 0 |
| Nemotron N2 | 0 | 1 (German) | 1 | 0 |

Nemotron added no words after the speech on any padded clip in either arm; Whisper did on 3. Each Nemotron arm lost trailing words on one clip. The twin condition of the strict rule (at most Whisper's 3) is met in the verdict arm.

## Verdict

`verdict: pending 7 passages`. The loop and twin conditions are met; the verdict now rests on the owner's labels for the passages of arm N2 (6 of the 7): PASS needs none labelled "Nemotron invented this" and none "Nemotron lost speech here".

## The listening page

`stage3/listen.html`, checked in headless Chromium: 7 cards, 3 buttons each, all 7 players load their recording (durations 9 to 74 s) and start at the estimated second, clicking three buttons produced the answer line `1=a 2=b 3=c`, and the page has no sideways scroll at 390 and 1,280 px. No screenshot is kept, because the page shows dictation text.
