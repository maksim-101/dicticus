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

## After the owner's labels (same day; `stage3_listen.py --apply`, then `stage3_score.py` under the lock)

The owner's answer line: `1=c 2=c 3=c 4=c 5=a 6=c 7=b` (a = Nemotron invented this, b = Nemotron lost speech here, c = Whisper was wrong). `labels written: 7 of 7; extras: 0 of 2`.

| Card | Surplus | Arms | Language | Label |
|---|---|---|---|---|
| 1 | Nemotron +21 words | N0 | English | Whisper was wrong |
| 2 | Nemotron +12 | N2 | English | Whisper was wrong |
| 3 | Nemotron +10 | N2 | English | Whisper was wrong |
| 4 | Nemotron +4 | N0, N2 | German | Whisper was wrong |
| 5 | Nemotron +3 | N2 | English | Nemotron invented this |
| 6 | Nemotron +3 | N0, N2 | German | Whisper was wrong |
| 7 | Whisper +3 | N2 | English | Nemotron lost speech here |

Scorer output: `confirmed_in_verdict_arm: whisper_wrong 4, nemotron_invented 1, nemotron_lost 1`, **`verdict: FAIL`**. The loop and twin conditions are met; the verdict falls on cards 5 and 7.

Checks made after the labels, counts and flags only:

- Card 7: the words shown on the page for both engines appear verbatim in each engine's raw text. The recording is 9.0 s long with a 4.6 s leading pause and a 1.6 s interior pause. At the spot Whisper has 4 words, N2 has 1 and N0 has 2, so the plain prompt loses two of the words too, under the rule's threshold of three. This card alone fails the strict rule.
- Card 5: Nemotron's words on the page appear verbatim in its raw text; Whisper's did not, because the page showed text without punctuation and Whisper wrote the spot as one hyphenated name. At the spot Whisper has 1 word, N2 has 4 and N0 has 2; none of Nemotron's words is a dictionary term. Read by the agent: the owner spelled a name, and Nemotron wrote the spoken hyphen out as a word and misheard the last letter. That is a rendering of something spoken, of a different kind than text invented in silence. The owner's label stands as given; the verdict does not depend on it.
- The five passages labelled "Whisper was wrong" lie in three recordings. The app's own discard log for these three says `reason: pass`, no audio lost, no restart, and lists every decoded segment (3, 4 and 2 segments), so no app filter removed speech there; the words are missing from the decoder's text. By their estimated positions, four of the five lie within a few seconds of a boundary between Whisper's decode windows (inferred from estimated positions, not verified).

## The listening page

The owner found the first version unclear (no context around the differing words, no position in the recording) and it was rebuilt before the labels above were given: ten words of context around the marked words, the recording's length and the passage's clock position, three plain instructions, and two extra cards outside the rule; rechecked headless with 9 cards. The page has no way to send clicks back, so the owner pasted the answer line. First version:

`stage3/listen.html`, checked in headless Chromium: 7 cards, 3 buttons each, all 7 players load their recording (durations 9 to 74 s) and start at the estimated second, clicking three buttons produced the answer line `1=a 2=b 3=c`, and the page has no sideways scroll at 390 and 1,280 px. No screenshot is kept, because the page shows dictation text.
