# Task 2: LFM3 on the dev set with the app's stop string (2026-11-14)

238 dev dictations of spike 022 (119 German, 119 English), temperature 0, gate built from main. Counts only; outputs are in the gitignored spike folder. LFM3 decodes deterministically (`generate.py L1 dev determinism`: `True` three times). Decode time: L1 287 s, L2v1 270 s, L2v2 262 s (Qwen 432 s).

## Early signal: failed

`python3 -I early_signal.py` → `L1 dev: failed closed 44 (spike 022: 45, bound 20); shipped a change 38 (spike 022: 36, bound 50)`, exit 1.

Stopping at `</corrected_text>` changes almost nothing. The plan's assumption, that spike 022's discarded outputs were commentary after the closing tag, is wrong for the cases that matter: the text LFM3 writes before the tag is already not a cleanup.

## Why the outputs are discarded

Of L1's 44 failed-closed items, 32 are stopped by the gate's prefilter and 12 by its alignment check. Their output is a median 4.1 times as long as the dictation (158 tokens against 19 words); the items that pass have a ratio of 1.0. Reading the shortest of them shows the mechanism: LFM3 treats the dictation as a message to itself. It answers the question in it, says it cannot help, or carries out the request, although the prompt forbids that in its third paragraph. The gate discards these, so nothing harmful ships, and no edit ships either.

## All arms (per language: German / English)

| | Qwen | L1 production prompt | L2v1 minimal-edit block added | L2v2 copy-and-correct task |
|---|---|---|---|---|
| failed closed | 0 / 0 | 25 / 19 | 19 / 8 | 13 / 9 |
| of these prefilter | 0 / 0 | 21 / 11 | 19 / 6 | 11 / 6 |
| gate pass | 42 / 86 | 61 / 49 | 75 / 82 | 87 / 99 |
| rejected edits | 502 / 286 | 248 / 517 | 145 / 193 | 106 / 92 |
| model changed the text | 90 / 79 | 68 / 81 | 53 / 60 | 37 / 33 |
| shipped a change | 31 / 63 | 13 / 25 | 11 / 32 | 7 / 15 |
| hit the 512-token cap | 0 / 0 | 4 / 1 | 9 / 0 | 8 / 1 |

Reading against the owner's bar (60 % of Qwen's good edits; on these items spike 022 labelled Qwen's good edits at 17 German and 51 English, so about 11 and 31): the best variant so far, L2v1, ships 11 German and 32 English changes of any quality, and in spike 022 about 58 to 75 % of LFM3's shipped changes were good. Unlabelled estimate: about 7 German and 24 English good edits, under the bar in both languages. The prompts that make LFM3 more careful also make it change less.

Two of the plan's five prompt variants are used. GPU time so far: about 21 minutes of the 3-hour ceiling.
