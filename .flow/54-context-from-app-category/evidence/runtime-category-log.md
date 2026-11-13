# Criterion 2, runtime part: the installed build logs the app category and the resolved context (2026-11-13)

Build under test: Debug-Recorder build 74af322 (version 1.4.1), installed at 17:20Z via `scripts/install-local.sh`; `scripts/check-running-copy.sh` OK after the install. Source: the owner's live `cleanup-2026-11-13.jsonl` in the DebugRecordings folder, read with a script that prints counts and field values only (no dictation text).

Records with `mode = aiCleanup`, grouped by `detected_bundle_id`, `app_category`, `resolved_context`:

| when | app | `app_category` | `resolved_context` | records |
|---|---|---|---|---|
| before the install (16:28Z to 17:11Z, old build) | Warp (per the postedit log) | field absent | `default` | 17 |
| after the install (17:27Z to 18:48Z) | `dev.warp.Warp-Stable` | `public.app-category.developer-tools` | `code` | 9 |
| after the install (same window) | `com.stablyai.orca` | `public.app-category.developer-tools` | `code` | 3 |

Every dictation made in the installed build resolved through the category rule to `.code`; none fell back to `default`, and no record is missing the new field. Warp and Orca are two of the four developer-tools apps the brief checked live (brief, Constraints). The owner made these dictations as normal work, not as a test run.
