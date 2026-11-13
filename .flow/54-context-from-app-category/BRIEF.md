# 54 context-from-app-category (standard)

## Outcome

Dictating into any developer app (Warp, Orca, VS Code, Xcode, Claude desktop, or one installed next year) gets the code-safe cleanup prompt automatically. The decision comes from what the app declares about itself, not from a list someone keeps by hand.

## Problem

`ContextResolver.curatedMap` (`Shared/Services/ContextResolver.swift:15-27`) names eleven bundle IDs, and only five of them map to `.code`. Every other app falls to `.default`. When the owner moved from iTerm2 to Warp, the cleanup prompt changed without anyone choosing it.

The 2026-11-10 audit counted this:
- 312 of 323 English AI-cleanup dictations went to Warp on the default prompt, and 47 % of them had LLM edits rejected.
- iTerm2 on the code prompt was at 27 % in the audit before.
- Orca, also missing from the map, was at 57 % (7 records).

`.prose` and `.default` build the same prompt (`Shared/Models/CleanupPrompt.swift:181`), so `.code` is the only context that changes anything.

## For whom

The owner, and anyone running Dicticus on macOS, dictating into whatever app is in front. On iOS dictation runs from a Shortcut with no frontmost app; nothing changes there.

## Decided

- **Owner, 2026-11-11:** "the success of the context awareness feature or prompt shouldn't hinge on a hand curated list but rather function automatically based on whatever user is using or interacting with at that moment."
- **Owner, 2026-11-13, on scope:** the app category first. The code prompt goes to every app that declares developer tools. A short built-in list stays only for terminals that declare another category. The owner's overrides stay on top. A browser tab on GitHub keeps the normal prompt.
- **Checked 2026-11-13** (`LSApplicationCategoryType` in each app's Info.plist):
  - `public.app-category.developer-tools`: Warp, Orca, VS Code, Xcode, Claude desktop.
  - `public.app-category.utilities`: Terminal.
  - `public.app-category.productivity`: Safari, Mail, Obsidian.
  - `public.app-category.social-networking`: Messages.
  - iTerm2, Ghostty and Zed are not installed, so their categories are unchecked.
- Memory `project_context_mode_prose_ab` (2026-08-02 A/B) found the code prompt no worse on ordinary prose. Claude desktop, where the owner writes prose, therefore takes the code prompt. Criterion 4 re-measures this on current data.

## Done criteria

1. `[check]` `adapt`: resolution order becomes:
   1. disabled
   2. session pin
   3. the owner's overrides
   4. category `public.app-category.developer-tools` → `.code`
   5. the built-in terminal list (Terminal, iTerm2, Ghostty), for apps whose category says otherwise
   6. `.default`

   `ContextResolver.resolve` takes the category as an argument and stays free of AppKit (it compiles on iOS). Observed by `ContextResolverTests`, one case per step, including an override that beats the category and an unknown category falling to `.default`.
2. `[check]` `new`: at key-down, macOS reads the frontmost app's category from its own bundle: `NSRunningApplication.bundleURL` → `Bundle(url:)?.infoDictionary`. It never uses Spotlight or `mdfind`. Both press-time call sites in `HotkeyManager` (`:313` live label, `:485` key-down) use it. The debug record gains `app_category` beside `resolved_context`. Observed in two ways:
   - a test of the reader against an app bundle fixture;
   - the installed Debug-Recorder build's log, read back by the agent after the owner's next dictations in Warp, showing `resolved_context: code` and the Warp category.
3. `[check]` `adapt`: the Settings section "Built-in defaults (read-only)" (`macOS/Dicticus/Views/AiCleanupPane.swift:318`) states the category rule and lists only the fallback terminals, no longer the eleven bundle IDs. Observed by a headless screenshot of the pane in the agent VM.
4. `[check]` `new`: replay the logged English AI-cleanup dictations sent to Warp between 2026-10-29 and 11-09 (312 records) offline, through the production gate with the code prompt and with the default prompt. This uses the spike 022 harness pattern on the current main build. The report gives these figures per prompt: rejected-edit rate, dictations that shipped a change, and failed-closed count. The `[judge]` in criterion 5 reads its decision from these figures.
5. `[judge]`: the owner reads a blind sample of 20 dictations where the two prompts shipped different text, and says whether the code prompt's text is at least as good. The sample, its order and the side-by-side file are in the slice's evidence.

## Not in this slice

- Reading the focused text field, or the text near the cursor, to tell code from prose inside one app. The owner chose the category version (2026-11-13).
- Per-website context in browsers.
- Any change to the prompts themselves or to EditGuard.
- iOS behaviour.

## Constraints

- Privacy (CLAUDE.md): "all processing happens on-device". The category is read from a local Info.plist, and no network is involved.
- CLAUDE.local.md: "Neither `install-local.sh` nor the app calls mdfind any more (the popover's synchronous probe froze the app on every menu bar click)". The reader must not use Spotlight.
- Key-down latency: the read happens on the press-time path. One Info.plist read per key press, cached per bundle URL for the app's lifetime.
- `Shared/` stays platform-neutral. CLAUDE.md "Cleanup pipeline changes ship on macOS and iOS together" applies to the cleanup pipeline. Context resolution exists only on macOS, which has a frontmost app, and the resolver keeps compiling on iOS.
- The criterion 4 replay is a local model run. It goes through `heavy-gate acquire`, needs AC power, and has an estimated duration of about 20 min (312 × 2 prompts, Qwen3.5-4B, about 2 s each). The plan sets the ceiling.
- Debug-log dictation samples never enter a tracked file (CLAUDE.md "Public repo"). The replay data and the judge sample stay under the gitignored `.planning/`; the slice's evidence records only counts and paths.

## Size and risk

Standard: four build tasks plus the replay, two platforms to keep building, one model run. Risk: none (no trigger applies).

## Open

- Whether the focused-field detection gets a row of its own: decided after this slice's logs, if the owner asks.
