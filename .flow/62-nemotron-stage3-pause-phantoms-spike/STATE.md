# State of 62-nemotron-stage3-pause-phantoms-spike
Slice: 62-nemotron-stage3-pause-phantoms-spike (quick)
Step: verify
Next: on the owner's answer line from the listening page (for example `1=a 2=c … x1=c`): run `stage3_listen.py --apply "<line>"`, then `stage3_score.py` for the verdict; write `STAGE3-RESULTS.md` in the planning tree, the Verify section of SLICE.md, the memory note and the item (PASS: a planned engine item; FAIL: spike 020 closed), then ship
Waiting on: the owner: listen to the 7 passages and 2 extra ones on `stage3/listen.html` (gitignored planning tree) and send the answer line
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
- 2026-11-14 question (build, the gate paused the run 40 minutes after batch 1 on its 2 GB swap-growth rule, which Nemotron's load always exceeds): the owner chose "Raise the limit to 8 GB for this run": the remaining three batches run back to back with the gate's `HEAVY_GATE_SWAP_GROWTH_MB=8192`, the limit the owner set for this model in October; the run's watchdog still aborts at 8 GB of swap growth.
- 2026-11-14 verify (remark, not yet the labels): the owner on the listening page: "I don't get your NemoTron pause test, but overall, based on what you're showing me, NemoTron performs significantly better than Whisper." No answer line was given; the agent explained the test and asked whether Nemotron's words were what was said on every card.
- 2026-11-14 verify (finding on the page, partial judgment): the owner did not look at every card, because it was unclear what to look at and where in the audio ("what's the duration and position"); "of those that I looked at, NemoTron was always better and/or right". Not a full set of labels. The page was rebuilt: ten words of context around the marked words, the recording's length and the passage's clock position, three plain instructions.
- 2026-11-14 question (another session asked for disk space; free disk 42 GB): the owner: "keep nemotron". The 20 GB of model files in the spike's cache stay.
- 2026-11-14 verify (the owner's labels from the rebuilt listening page): `1=c 2=c 3=c 4=c 5=a 6=c 7=b` (a = Nemotron invented this, b = Nemotron lost speech here, c = Whisper was wrong). The extra cards x1 and x2 were not answered.

## History
- 2026-11-14 62 brief: opened by the owner's /flow:next; branch flow/62-nemotron-stage3-pause-phantoms-spike from main.
- 2026-11-14 62 brief: SLICE.md Brief written. Checked: the October twins are trailing-only (118 per level); 33 retained recordings, 28 with a pause of 1 s or more (10 leading, 20 interior, 7 trailing); model files, runtime (`nemo-speech 0.2.0`) and Stage 2 decodes on disk; mains power on. Waiting for the owner's approval.
- 2026-11-14 62 brief: approved with the strict rule and the sample that exists at the freeze. Step plan.
- 2026-11-14 62 plan: Plan section written (three tasks). Checked: all 33 recordings have a log record with language and Whisper raw text (18 English, 15 German); the October Whisper decodes hold 118 rows for each of arms A and C-sil50; `nemo-speech transcribe --help` matches Stage 2's flags; the resource gate's usage read. Waiting for plan approval.
- 2026-11-14 62 plan: approved, run now. Step build.
- 2026-11-14 62 review: one round on the verdict code by a fresh agent (opus): no blocker; a gap in the frozen rule (split or equal-length rewrites) checked on the data and covered by 2 extra cards outside the verdict; `--apply` hardened; twin sets confirmed equal (SLICE.md Review). Step verify: the page (9 cards) rechecked headless; waiting for the owner's labels.
- 2026-11-14 62 build: task 2 done: four batches, 804 s of decoding (ceiling 1,620 s), 12 of 12 pairing texts identical to Stage 2, no sockets, mains power in all 366 samples; two gate stalls of about 40 minutes each, ended by the owner's two decisions (evidence/run.md). Task 3: scored under the lock: no loops; twins: Nemotron gained trailing words on 0 of 114 and lost on 1 per arm, Whisper gained on 3; real recordings: 7 distinct passages (N2: 5 only Nemotron has, 1 only Whisper has), verdict pending the owner's labels; listening page built and checked headless (evidence/result.md). The outputs carry no word timings, so passage times are estimates. An independent reviewer (opus) is reading the scorer's logic before the page goes to the owner.
- 2026-11-14 62 build: task 1 done: 33 real recordings copied and scanned (28 with a pause), 114 twins and 6 originals laid out, pre-registration, thresholds, scorer, sample list and Whisper's twin counts (3 gained, 0 lost) hash-locked; self-test passed and was seen failing at run length 2; both model hashes match (evidence/freeze.md). Task 2: the run script was started in the background; the resource gate refused a 21 GB slot (memory pressure 2, projected free -6 %), so the script waits at the gate.
