# State of 62-nemotron-stage3-pause-phantoms-spike
Slice: 62-nemotron-stage3-pause-phantoms-spike (quick)
Step: build
Next: task 2: the decode run. `stage3/stage3-run.sh` was started in the background on 2026-11-14 about 10:45 UTC and waits at the resource gate (up to 4 hours) until memory is free; when it exits, run its Verify (watch.log batch lines, sockets.log empty, power.log all AC, `stage3_score.py --check-pairing`), then task 3. If the session ended meanwhile: check `watch.log`; with no batch line the run never started and is started again the same way.
Waiting on: host: the other session's test VM (mac-space) ending, about 12:45 UTC, then the gate admitting a 21 GB model slot at the 10 % floor the owner allowed. The script (restarted about 11:35 UTC) waits for both by itself; the VM queue's coordinator holds the next VM until this run's slot is released or 13:25 UTC
Started: 2026-11-14T09:52:09Z
Baseline: not run: the slice changes nothing outside `.flow/` and the gitignored planning tree, so the app's test suite cannot move
Base: branch point
Risk: none
Carried: none

## Decisions
- 2026-11-14 question (before the slice): the owner on spike 020 Stage 3: "the NemoTron spike could also go ahead".
- 2026-11-14 brief: approved by the owner. Pass rule "Strict": PASS only with zero confirmed invented passages and zero confirmed lost passages (three or more words) on the real dictations, no runaway output, and no more trouble on the padded clips than Whisper has; a PASS only creates a planned engine item, a FAIL closes spike 020. Sample "What exists now": every recording kept at the moment the rule is frozen; the owner listens to at most 20 disputed passages.
- 2026-11-14 plan: approved by the owner, "Approve, run now": the go for about 18 minutes of GPU decoding, ceiling 27 minutes, on mains power through the resource gate; more than 20 disputed passages stops the slice before any listening.
- 2026-11-14 question (build, the resource gate refused the 21 GB slot under its 30 % rule for 40 minutes): the owner chose "Yes, 10 % floor after the VM ends": this one run may be admitted with the gate's documented `--min-free 10`, once the other session's test VM is gone (about 13:30 CET) and memory pressure is normal; the run's own watchdog stays.

## History
- 2026-11-14 62 brief: opened by the owner's /flow:next; branch flow/62-nemotron-stage3-pause-phantoms-spike from main.
- 2026-11-14 62 brief: SLICE.md Brief written. Checked: the October twins are trailing-only (118 per level); 33 retained recordings, 28 with a pause of 1 s or more (10 leading, 20 interior, 7 trailing); model files, runtime (`nemo-speech 0.2.0`) and Stage 2 decodes on disk; mains power on. Waiting for the owner's approval.
- 2026-11-14 62 brief: approved with the strict rule and the sample that exists at the freeze. Step plan.
- 2026-11-14 62 plan: Plan section written (three tasks). Checked: all 33 recordings have a log record with language and Whisper raw text (18 English, 15 German); the October Whisper decodes hold 118 rows for each of arms A and C-sil50; `nemo-speech transcribe --help` matches Stage 2's flags; the resource gate's usage read. Waiting for plan approval.
- 2026-11-14 62 plan: approved, run now. Step build.
- 2026-11-14 62 build: task 1 done: 33 real recordings copied and scanned (28 with a pause), 114 twins and 6 originals laid out, pre-registration, thresholds, scorer, sample list and Whisper's twin counts (3 gained, 0 lost) hash-locked; self-test passed and was seen failing at run length 2; both model hashes match (evidence/freeze.md). Task 2: the run script was started in the background; the resource gate refused a 21 GB slot (memory pressure 2, projected free -6 %), so the script waits at the gate.
