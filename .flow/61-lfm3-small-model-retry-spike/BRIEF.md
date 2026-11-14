# Brief 61: LFM3-1.7B retried as the cleanup model for 6 GB iPhones

## Outcome
The owner knows, from a pre-registered measurement on dictations the model has not been tuned on, whether LFM3-1.7B can do AI Cleanup well enough to be offered on 6 GB iPhones, which have no AI Cleanup today. The number read at verify, per language: good edits shipped by LFM3 against Qwen3.5-4B, and harmful ones, on the holdout.

## Problem
AI Cleanup needs the 2.7 GB Qwen3.5-4B model and is limited to 8 GB devices (threshold 6.5 GiB, standing decision of 2026-11-04). Spike 022 (2026-10-31) tried LFM3-1.7B at Q4_K_M as a drop-in on the Mac, replaying 238 logged dictations through the real gate, and failed it: good edits German 7 against 17, English 18 against 51. What it shipped was good about as often as Qwen's (German 7 of 12 against 17 of 31, English 18 of 24 against 51 of 63); it lost on volume, for three reasons:
1. It kept writing after `</corrected_text>`; 45 of 238 outputs failed closed. The app has stopped at that tag since 2026-10-31 (`CleanupService.swift`), after the spike.
2. The envelope was only mapped: the reasoning preclose and BOS are chosen by `modelWantsReasoningPreclose`, which knows qwen3 only.
3. In English it rewrote more than the gate allows under a prompt written for Qwen (rejected edits 286 against 538).

So the first trial measured a model in a harness built for another one. It did not measure what LFM3 can do with the stop string, its own envelope and a prompt written for it.

## For whom
The owner, deciding whether a small-model build for 6 GB phones is worth a slice. Testers with 6 GB iPhones are the eventual users.

## Done criteria
1. `[check]` `adapt` A protocol is written and hash-locked before any holdout decode: arms, data, labelling, pass rule. Arms: Q (Qwen, production prompt and envelope), L1 (LFM3, production prompt, stop string, LFM3's own envelope), L2 (LFM3, one prompt written for it). Observed: the protocol file's hash recorded in `evidence/` before the first holdout output exists.
2. `[check]` `adapt` L1 and L2 are developed only on spike 022's 238 dev dictations; L2's prompt is frozen (hash in the protocol) before the holdout is decoded. Observed: file times and hashes in `evidence/`.
3. `[check]` `new` The holdout is drawn from AI-cleanup dictations logged after 2026-10-29 (none of them in spike 022's dev set), up to 119 per language at random with a recorded seed. A language with fewer than 40 items is reported as insufficient and gets no verdict.
4. `[check]` `adapt` Fidelity holds before the arms are compared: the gate build replays logged outputs to the logged result on at least 99 % of holdout records, and each model decodes deterministically (3 of 3 repeats).
5. `[check]` `adapt` Every distinct shipped text of the holdout is labelled blind (better, equal, mixed, worse) by two labellers from different vendors with spike 022's rubric; disagreements are adjudicated in writing, and a sample of the agreed labels is read by a third, fresh reader, since the 50.1 review showed a single fast pass misses defects.
6. `[check]` `new` The verdict per language follows the pass rule the owner chooses at approval, with no change to an arm after the holdout is decoded. Latency (median and p90 per request) is measured for Q and the better L arm on a machine with load under 4, or reported as not measured.
7. `[check]` `new` A counts-only summary is in `evidence/`; a pass creates a `planned` item for the iOS build (model download, family-aware envelope, memory and speed on a real 6 GB iPhone); a fail records why and closes the question with the owner's standing answer for 6 GB phones unchanged.
8. `[judge]` The owner reads ten holdout dictations, chosen at random with the seed, as raw text, Qwen's result and LFM3's result side by side, and says whether LFM3's cleanup is worth having on a phone.

## Not in this slice
- Any change to shipped code, on either platform. The envelope and prompt for LFM3 live in the spike folder.
- Anything on a phone: memory footprint, speed and battery on a 6 GB iPhone belong to the follow-on build, and need such a device.
- Other small models. One candidate, the one the owner asked about.
- German-specific tuning beyond what L2's one prompt does.

## Constraints
- CLAUDE.md: "Dictation samples from the debug logs never enter a tracked file." All texts, outputs and labels stay in the gitignored spike folder.
- CLAUDE.md: "Cleanup pipeline changes ship on macOS and iOS together" binds the follow-on build, not this measurement.
- The second labeller is agy (Gemini), as in spikes 017 and 022: dictation texts leave the Mac for labelling. The owner approved this for 50.1 today; it is asked again here.
- Local model runs go through the host's resource gate, on mains power, one model at a time; the Nemotron run (item 62) does not overlap.
- Memory note from spike 022: "don't re-propose LFM3-1.7B as a drop-in". This slice does not: it tests the two prerequisites that note names and a prompt of its own.
- The LFM3 file (sha256 prefix `3793e1e6e2266919` in spike 022's protocol) is no longer on disk and is downloaded again, about 1.1 GB; 66 GB are free.

## Size and risk
Standard: six tasks at most, no shipped code, no risk trigger. External: Hugging Face for the model file, agy for labels.

## Pass rule (the owner, 2026-11-14)
Per language on the holdout: LFM3's better arm passes with at least 60 % of Qwen's good edits (shipped texts labelled better) and no more harmful ones (mixed or worse) than Qwen. A pass leads to a build that offers LFM3 only on devices that cannot run Qwen; 8 GB devices and the Mac keep Qwen.

## Open
- Whether German AI cleanup is worth offering at all (Qwen: 17 good, 7 harmful of 119) stays open from spike 021.
