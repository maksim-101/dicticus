# Task 1: the sample and the rule, frozen 2026-11-14 before any Stage 3 decode

All files named here are in the gitignored planning tree (`.planning/spikes/020-nemotron-transcribe-macos/stage3/`) or the spike's cache outside the repo. This note holds counts and hashes only.

## Sample (output of `stage3_freeze.py`)

- Real recordings: 33 (18 English, 15 German), each with a cleanup log record giving its language and Whisper's raw text.
- With a pause of 1 s or more: 28; by position: 10 leading, 20 interior, 7 trailing.
- Padded twins at -50 dBFS: 114 (55 English, 59 German); three unpadded originals per language for the pairing check.
- Input files: 153; audio per arm: 2,451 s English, 1,566 s German (twins and real recordings).
- Whisper on the same 114 twins (October decodes, padded untrimmed against unpadded): 3 twins gained trailing words, 0 lost, 3 gained or lost, 0 loops. The strict rule therefore allows Nemotron's verdict arm at most 3 such twins.

## Lock (`shasum -a 256 -c STAGE3-LOCK.sha256`: six lines OK)

```
3282a82cb316ae0d73384c5838f12fd9d16187d8e3c34bf3adfd9d2c215346b9  STAGE3-PREREG.md
c80f8c1621fd906b4cf8ff0b8e57e85c988769d53fe32b05eeb79230b8ff70a8  stage3-thresholds.json
6b25e4a9b045b22f47daf2e7c674a499c5f462922840ffd868cfb639263f101d  stage3_score.py
1bb0bc6528e792870df7f70144212efa5238c43e1190d409fccbca4842dfac26  stage3-sample.json
ccb71eea48dcf06823527668ebd7df02d3077019fa0f21199d78f730066a60bb  whisper-twins.json
2e214b3ce3356e494fec1e8482b346ea4f6d333df4ddbc65a7081c3ee8db3594  ../stage2-lists.json
```

## Scorer and preflight

- `stage3_score.py --self-test`: `self-test: all passed`. Seen failing once with the run length set to 2 (`AssertionError: a two-word surplus must not count`), then restored to 3 before the lock.
- A disputed passage is defined in the pre-registration as a stretch without an equal word in which one engine has three or more words more than the other; equal-length substitutions are ordinary mishearings and are not counted. This is the precise form of the brief's "runs of three or more consecutive words that only one engine has".
- Model files: both match the hashes recorded in Stage 1 (decoder 19,678,656,672 bytes, encoder 1,670,410,080 bytes). Runtime: `nemo-speech 0.2.0`.
- Nemotron's JSON output carries a start and end time per word, so each passage is located in time from the decode itself.
