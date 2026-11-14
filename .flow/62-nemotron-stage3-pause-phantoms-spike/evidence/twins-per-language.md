# Criterion 3: padded twins per arm and language

Computed 2026-11-14 after the owner's labels, at the branch head, with the locked scorer's functions (`trailing_gained`, `trailing_lost`, `is_loop`) over the same 114 clip ids on both sides. Whisper: October decodes, padded untrimmed (`C-sil50`) against unpadded (`A`). Nemotron: Stage 3 padded decode against the Stage 2 unpadded decode of the same arm. Counts are clips.

| Engine and arm | Language | Clips | Gained trailing words | Lost trailing words | Loops |
|---|---|---|---|---|---|
| Whisper | English | 55 | 2 | 0 | 0 |
| Whisper | German | 59 | 1 | 0 | 0 |
| Nemotron N0 | English | 55 | 0 | 1 | 0 |
| Nemotron N0 | German | 59 | 0 | 0 | 0 |
| Nemotron N2 | English | 55 | 0 | 0 | 0 |
| Nemotron N2 | German | 59 | 0 | 1 | 0 |

The sums equal `whisper-twins.json` (3, 0, 0) and `result.json` (N0: 0, 1, 0; N2: 0, 1, 0).

What "paired with Stage 2" rests on: every twin is compared with the Stage 2 decode of its own unpadded clip (114 pairs per arm). That those October decodes are still what this build, model and prompt produce was shown on a sample: three unpadded originals per language and arm decoded again in the Stage 3 batches, 12 of 12 byte-identical.
