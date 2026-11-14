# Task 2: the decode run, 2026-11-14

Source: `watch.log`, `power.log`, `sockets.log` in the gitignored planning tree (`stage3/`). Counts only.

## Batches (one model load each)

| Arm | Language | Inputs | Outputs | Decode time | Peak footprint | Exit |
|---|---|---|---|---|---|---|
| N0 | German | 77 | 77 | 159 s | 18.4 GB | rc=0, reason=ok |
| N0 | English | 76 | 76 | 187 s | 19.5 GB | rc=0, reason=ok |
| N2 | German | 77 | 77 | 205 s | 19.5 GB | rc=0, reason=ok |
| N2 | English | 76 | 76 | 253 s | 19.5 GB | rc=0, reason=ok |

Decode time in total: 804 s, against the estimate of about 18 minutes and the ceiling of 1,620 s. The timed sample (first batch) projected 815 s.

## Checks

- Pairing: `stage3_score.py --check-pairing` printed `12 of 12 identical` (three unpadded originals per language and arm, byte-identical to their Stage 2 decodes), exit 0. The twin comparison against Stage 2 therefore stands.
- Network: `sockets.log` is 0 bytes across all four batches.
- Power: 366 samples, all `AC Power`; no thermal or performance warning recorded in any sample.
- Order: `STAGE3-LOCK.sha256` was written at 11:02 local time; the first decode output was written after the model was admitted at about 13:30.
- Swap: 12.1 GB at the first batch's start, 15.8 GB at the end of the run; the run's own watchdog (abort above 8 GB of growth) did not fire.

## How the run went (three interruptions, none inside a batch)

1. The resource gate refused the 21 GB slot under its 30 % free-memory rule for about 40 minutes; the owner allowed the gate's 10 % floor for this run, after another session's test VM had ended.
2. The run was admitted once that VM was gone and finished the first batch.
3. The gate's check then paused the run for about 40 minutes on its rule of 2 GB swap growth under a model slot (loading the model had moved about 5.6 GB). The owner raised that limit to 8 GB for this run; the script was restarted, kept the finished batch and ran the other three back to back. Decoding is deterministic (shown again by the pairing check), so the kept batch is valid.

## One departure in the output

None of the Stage 3 outputs carries word timings; the runtime logged `word timestamps unavailable: SentencePiece could not encode the transcript` for every clip, which it did not do in Stage 2 with the same binary and command. The texts are unaffected (pairing check). The scorer's fallback applies: a passage's time is estimated by spreading the words evenly over the recording, so the "at a pause" marks and the listening page's start seconds are estimates. The mark does not enter the verdict. Cause not found.
