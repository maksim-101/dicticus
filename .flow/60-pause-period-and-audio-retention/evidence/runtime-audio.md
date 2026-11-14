# Criteria 3 and 4, runtime part: the installed build keeps the audio and links it (2026-11-14)

Build under test: Debug-Recorder build of 46348f5 (version 1.4.1), installed by `scripts/install-local.sh` at 06:40Z; `check-running-copy.sh`: OK (pid 1611). Source: the owner's live `DebugRecordings/audio` folder and `cleanup-2026-11-14.jsonl`, read with a script that prints names, booleans and durations only.

The owner's first two dictations on the build, both AI cleanup in Warp:

| cleanup record `ts` | `audio_file` | file exists | WAV duration | raw text had a pause period | shipped text has one |
|---|---|---|---|---|---|
| 06:56:45Z | `2026-11-14T06-56-44.009Z.wav` | yes | 8.1 s | no | no |
| 06:57:23Z | `2026-11-14T06-57-21.128Z.wav` | yes | 27.2 s | no | no |

Format (`afinfo`): 16 000 Hz, 1 channel, 16-bit integer PCM, as the probe writes it. The file name carries the moment the transcription finished, one to two seconds before the record's `ts`, which is written after the LLM. The pause-period rule was not exercised by these two dictations (no pause period in their raw text); its evidence is the unit tests and the replay in `evidence/pause-period-replay.md`.
