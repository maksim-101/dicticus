# Changelog

All notable changes to Dicticus (macOS + iOS). This is a high-level history — when things were added, changed, or fixed — consolidated from git history, tags, GitHub releases, and `.planning/` milestone records. Day-to-day fixes are rolled up into their release.

Dicticus is a fully local, on-device dictation app (ASR via WhisperKit/Whisper large-v3-turbo on macOS, FluidAudio/Parakeet TDT v3 on iOS; AI cleanup via llama.cpp/Qwen3.5-4B) for macOS and iOS. Versioning note: the product milestone line (v1.0 → v2.3) and the macOS release-tag line (`v0.1.0` … `macos-v1.2.0`) evolved separately; both are shown where they apply.

---

## Unreleased

- **Fixed: correctly spelled words are no longer swapped for a similar-looking dictionary entry** — the dictionary's near-match correction could turn a real word such as "safeguard" into an unrelated entry two letters away; words in Dicticus's bundled English and German word lists are now never near-match-corrected, while misspellings such as "Tailscele" still correct to Tailscale. macOS + iOS.
- **Fixed: the closing period or question mark could disappear after AI cleanup** — whenever EditGuard reverted a sentence around a rejected content edit, the mark the AI had added at the very end of your dictation was reverted along with it, even though nothing else in the sentence depended on it. Replayed against two weeks of real dictations, the share of AI-cleaned dictations missing a closing mark dropped from 12.9% to 4.5%; the rest of that sentence still reverts as before. macOS + iOS.
- **Fixed: a closing mark after an abbreviation such as "etc." is no longer dropped** — when the AI ended a dictation with "etc.?", EditGuard reverted both marks together with an unrelated rejected edit earlier in the sentence, so the dictation was pasted as "etc" with no mark at all. The period and the question mark the AI added after the abbreviation now stay, unless the question mark is withdrawn as a mood change, in which case both go. Replayed against 2428 AI-cleaned dictations from mid-August to 30 September, this changed one dictation; the share of AI-cleaned dictations from 12 to 30 September ending without a closing mark moved from 3.9% to 3.8% (48 to 47 of 1222). macOS + iOS.
- **Fixed: the closing mark now also survives when AI cleanup dropped or moved the last words of a dictation** — the AI sometimes ended a dictation by replacing a trailing word, such as a closing "I believe", with a period, or by reusing a period from mid-dictation. EditGuard kept your words and dropped the mark with them, so the dictation was pasted with no closing mark. Your words now stay where they were and the closing mark the AI added follows them. Replayed against 2501 AI-cleaned dictations from mid-August to 2 October, this changed 26 dictations; the share of AI-cleaned dictations from 12 September to 2 October ending without a closing mark moved from 3.7% to 2.9% (48 to 38 of 1295). macOS + iOS.
- **Fixed: a repeated word such as "for for" or "the the" that AI cleanup removed could come back** — whenever EditGuard reverted a sentence around an unrelated rejected edit, a stutter the AI had correctly collapsed to one word was put back along with it, even though the surviving copy of the word was never in doubt. Across 2114 AI-cleaned dictations replayed from mid-August to late September, 9 such stutters now stay collapsed. A double that can be correct as spoken, such as German "die die" or English "that that", is still left exactly as dictated. macOS + iOS.
- **Fixed: AI cleanup can no longer move a whole clause of your dictation to another place in the sentence** — EditGuard accepted any word move, so the AI could carry a clause across a comma or a sentence boundary, drop the period in front of it and paste a sentence you never said. Such moves now keep your original order and sentence break, while single-word reorders and in-clause fixes such as a German verb moved to the end are kept. Replayed against 2411 AI-cleaned dictations from mid-August to 30 September, 1 dictation changed (the relocated clause went back to where you said it) and the 13 other dictations with moved words that were checked came out byte-identical. macOS + iOS.
- **Fixed: punctuation before a name that starts with a dot, such as .NET, no longer disappears after AI cleanup** — EditGuard's final pass over doubled punctuation read the name's leading dot as a second full stop and deleted the mark in front of it, so "two things: .NET" was pasted as "two things.NET"; such names now keep the colon or comma in front of them. Replayed against 2414 AI-cleaned dictations from mid-August to 30 September, exactly one output changed, and it is the affected dictation. macOS + iOS.
- **Fixed: AI cleanup could lose all of its corrections in a German dictation containing a number from 1 to 10 followed by a period** — at the end of a sentence or in a date such as "am 3. Oktober", the AI sometimes wrote that number out as a word. The step that keeps numbers in the form you dictated did not recognise such a number, so a later safety check found it missing and discarded the whole cleaned text, including correct grammar fixes such as "ihr ist" to "ihr seid". Replayed against 2399 AI-cleaned dictations from mid-August to the end of September, 1 dictation changed: it now keeps its corrections with the number as dictated. The safety check itself is unchanged. macOS + iOS.
- **Fixed: two words that Whisper runs together with a dot or hyphen are no longer rewritten into a brand name** — the brand matcher's near-match correction treated "in.cloud" as one misspelled token and pasted "iCloud" where two words were dictated. A near-match that has to change letters now keeps a dot or hyphen the brand name does not contain; brand names written with a dot still correct ("cloud.ai" → claude.ai) and pure spelling-format fixes such as "1-password" → 1Password are unchanged. Replay of 2477 logged dictations (13 Aug–30 Sep) changed 2 outputs: the glued "in.cloud" case and one German partial repair that is now left as dictated. macOS + iOS.
- **Fixed: a doubled "to" that AI cleanup removed is no longer put back** — EditGuard treated "to to" (as in "we continue to to build") as a possibly correct double and restored it whenever it reverted the sentence around an unrelated rejected edit. In 3767 logged dictations since late June, 3 of the 4 "to to" were stutters, and the AI never deleted a copy of the one correct double, so a removed "to to" now stays collapsed. Other doubles that can be correct, such as "that that", are unchanged. macOS + iOS.
- **Fixed: a stray key press, or a recording in which Dicticus heard no voice, no longer pastes a lone "You", "And" or "-"** — Whisper sometimes decoded a brief accidental hold, or a silent recording, as one of these words and Dicticus pasted it. When the whole transcript is one of them and the recording is under 1.5 seconds or the voice gate found no speech in it, the recording is now discarded like silence. Across the 1719 macOS dictations logged from mid-August to the end of September this matches exactly the 5 stray recordings (3 under 1.5 seconds, 2 without voice) and no real dictation; punctuated forms such as "You." are left alone. macOS.
- **Fixed: an acronym after a dot, such as the capital extension in a filename like "notes.MD", keeps its capitals through AI cleanup** — EditGuard accepted any casing-only change the AI made, so an extension like that could come out title-cased ("notes.Md"); a casing change that lowers an all-capitals word directly after a period is now rejected and the dictated form kept, while sentence-initial capitals and brand recasing in the middle of a sentence are still accepted. Replayed against 2428 AI-cleaned dictations from mid-August to 30 September, 1 dictation changed, and it is the affected one. macOS + iOS.
- **Fixed: a number range, a hyphenated number pair or a zero-padded number no longer loses digits in Swiss number formatting** — the step that renders "1,80" as "1.80" and "1,000" as "1'000" also turned "2-3 Franken" into "2 Franken", "10-04" into "10" and "006" into "6", in plain and AI-cleanup mode alike, because it re-spelled every token from its numeric value. A token is now rewritten only when the result differs from what you dictated in its separators alone; anything else is pasted as dictated. The same check keeps a leading plus sign ("+41") and stops "0.125" from becoming "125". Replayed against 2504 logged dictations from mid-August to 1 October, exactly the 3 affected dictations changed (they now keep their digits) and the 3 dictations whose thousands or decimal separators were reformatted before come out identical. macOS + iOS.
- **Fixed: quotation marks you dictate are kept when AI cleanup is on, spaced as you dictated them** — the step that removes quotation marks the model wraps around its answer removed every double quotation mark, including ones transcribed from your speech. It now keeps them when the model's output carries exactly the quotation marks of your dictation; marks the model adds on its own are still removed. EditGuard, which checks the model's edits, decided the space before a straight quotation mark from how the same word and mark were spaced elsewhere in the dictation, so it could delete the space before an opening mark or add one before a closing mark; it now spaces opening and closing marks separately. Replayed against 2457 logged AI-cleanup dictations, 11 changed: 10 keep the quotation marks that cleanup had stripped, and 1 had a stray closing mark that is now paired with its opening mark; none came out worse. macOS + iOS.
- **Fixed: a brand name your dictionary spells two ways now comes out the same way every time** — when the dictionary held two spellings of one name that differ only in capitals, spaces or dots (for example "AdGuard Home" and "AdGuardHome", or "Claude.ai" and "claude.ai"), the brand correction could pick a different one each time Dicticus launched. It now prefers the built-in brand list and otherwise picks one spelling in a fixed character order. Replayed against 2477 dictations from 13 August to 30 September 2026, 19 outputs changed, each to the other spelling of the same name. macOS + iOS.
- **Fixed: AI cleanup's German adjective-ending fixes such as "reiner" to "reinen" are no longer thrown out** — EditGuard accepts a changed word only as another form of the same word, and it took the longest shared beginning as the stem. For endings that start with the same letter (-er, -es, -em, -en) that left "r" against "n", which is not an ending, so the fix was rejected and the dictated form pasted. It now steps back one letter when that turns both sides into one of these four endings and at least four letters of stem remain. Short stems such as "gutem" to "guten" are still left as dictated, and a German noun ending in -er next to a verb with the same stem (such as "Messer" and "messen") can now pass as one word, as "fahren" and "fahrt" already did. Replayed against 2625 logged dictations from 13 August to 3 October 2026, 1 changed, the "reiner" that was the occasion for this fix, which now comes out as "reinen". macOS + iOS.
- **Fixed: AI cleanup's correction of a misheard German compound such as "Schreiweise" to "Schreibweise" is no longer undone** — macOS's German spell checker accepts such a word by splitting it into two real words, so EditGuard treated the correction as a swap between real words and reverted it. A long German word the checker accepts only that way may now be corrected to a listed word one letter away when the checker itself suggests that word, while real words such as "Koma" are still never swapped for another real word. Replayed against 2628 logged dictations (144 of them German) from 13 August to 3 October 2026, 1 output changed: the "Schreiweise" that was the occasion for this fix, which now comes out as "Schreibweise". macOS; on iOS this applies only where the system spell checker lists word completions, which the simulator does not.
- **Fixed: AI cleanup's sentence breaks in run-on dictations are no longer thrown out** — when the AI replaced an "and" (German "und") between two clauses with a period, EditGuard counted the missing word as a changed word and reverted every comma and capital in that sentence. It now accepts that edit when the words on both sides stay as dictated and the AI capitalised the next word itself, or the next word is "I". "But", "or", "because", "so" and their German counterparts, an "and" turned into a comma or a semicolon, an "and" swapped for another word, and an "and" before a name or noun that was already capitalised stay rejected. A question mark or period the AI moved a few words later to the end of its clause, and a trailing comma replaced by a closing period, are now kept too, and the move is undone together with its sentence when the capital after it is. Replaying 2625 AI-cleaned dictations from 13 August to 3 October 2026, 47 came out different; each was read by hand and none was worse. macOS + iOS.
- **Fixed: AI cleanup's expansion of English contractions such as "that's" to "that is" is no longer thrown out** — EditGuard read the expanded form as a changed word plus an invented word and reverted it together with every other fix in that sentence. It now accepts the expansion when the AI wrote the full form of the same words in place: "it's", "that's", "what's", "where's" and the other listed hosts to "is", "n't" to "not", and "'re", "'ve", "'ll", "'m" to "are", "have", "will", "am". "'d", "let's", a "'s" that could mean "has" ("it's been", "it's already gone"), a dropped pronoun, verb or "not", and German contractions such as "geht's" stay as dictated. Replaying 2625 AI-cleaned dictations from 13 August to 3 October 2026, 4 came out different; each was read by hand and none was worse. macOS + iOS.
- **Fixed: AI cleanup's commas and capitals in a sentence are no longer thrown away when EditGuard rejects one swapped word in it** — EditGuard reverted the whole sentence around a single word the AI had replaced by another, so commas, capitals and acronym casing the AI had added correctly in the same sentence were lost with the swap. The swapped word still stays as dictated; the commas and capitals that are not next to it now stay. The sentence still reverts completely when it holds a second rejected edit, a changed sentence end or question mark, a swap of a conjunction or negation, a number or a pronoun, a word-for-two-words swap such as "wanna" to "want to", or a function-word, inflection or word-order fix; a capital turned into a lowercase letter is not kept either. Replaying 2625 AI-cleaned dictations from 13 August to 3 October 2026, 18 came out different; each was read by hand and none was worse. Twelve older test expectations that pinned the previous behaviour were updated (listed in commit 33a7796). macOS + iOS.
- **Fixed: a contraction expansion whose added word the AI capitalised mid-sentence, such as "do Not", is no longer accepted** — the new rule for English contractions required the host word to match but not the added word's case, so "don't" to "do Not" shipped a stray capital. The added word must now be lowercase; the replay showed no dictation affected. macOS + iOS.

---

## 1.2.2 — Clean Quit — 2026-09-20

- **Fixed: quitting Dicticus no longer produces a crash report** — with the AI-cleanup model loaded (always, when "Unload AI model after idle" is set to Never), every quit aborted inside the model runtime's Metal teardown because the model was still resident when the process exited; Dicticus now unloads it as part of quitting. macOS.

---

## 1.2.1 — Paste Delivery Fixes — 2026-09-20

- **Fixed: dictation is no longer refused as "Couldn't paste" while some app holds secure keyboard input** — the pre-check that blocked on macOS's secure-input flag was measured (2026-09-20) to refuse pastes that deliver fine — 8 of 8 dictations on one day were refused while a background media app held the flag; the flag is now only recorded in debug builds. macOS.
- **Fixed: your previous clipboard comes back after a dictation again** — the restore was skipped whenever a clipboard manager (e.g. Pure Paste) rewrote the transcript as plain text, which on this setup was every paste; Dicticus now restores when the clipboard still holds the transcript it wrote (ignoring trailing whitespace) and leaves anything else you copied in the meantime alone. macOS.
- **Added: Settings → General → "Copy transcript to clipboard when it can't be pasted"** (on by default). Switched off, an undeliverable paste leaves your clipboard untouched and the notification tells you to open Dicticus and copy the transcript from history. macOS.

---

## 1.2.0 — Delivery Reliability & Cleanup Precision — 2026-09-13

- **Fixed: AI cleanup no longer ships half of a coupled rewrite** — when EditGuard rejects a content edit, the cosmetic edits the LLM made around it in the same sentence (word order, function words, punctuation, casing) now revert with it instead of being kept alone, which could leave German verb-position clauses reading differently from both what you said and what the LLM proposed. macOS + iOS.
- **Fixed: conjunctions and negators are no longer treated as cosmetic** — swaps or insertions of `and`/`or`/`but`/`not`/`nicht`/`kein` and their kin are blocked as meaning changes, and a hyphen inserted between a word and a version number (`Fable 5` → `Fable-5`) is blocked too. macOS + iOS.
- **Fixed: spacing around ellipses and dashes after AI cleanup** (Phase 49.5) — punctuation runs (`...`, `!!`) are handled as one unit and spacing at edit seams is derived from the source text, ending glued words (`possible.points`) and stray spaces before dashes. macOS + iOS.
- **Fixed: Swiss thousands now render with the apostrophe** — an amount dictated as "2,273" is shown as `2'273` (previously `2.273`, a wrong decimal); years and plain integers (`2026`, `10000`) are never grouped; and when you name the punctuation yourself ("1,80 not 1.80") the numbers in that sentence are left exactly as spoken. macOS + iOS.
- **Fixed: "clusters one two five" no longer becomes "clusters 102 five"** — the range fix that already turned "phases 102 four" into "phases 1 to 4" now also covers "clusters" — the one further count noun with a live dictation; a noun outside the list is left as a plain miss, never rewritten. macOS + iOS.
- **Added: four brand spellings in the Brand Names starter pack** — "host point", "1 password", "open router" and "taffoli" now correct to Hostpoint, 1Password, OpenRouter and Tavily after re-importing the pack. macOS + iOS.
- **Changed: a dictionary entry written entirely in capitals (e.g. `HEY`) now matches only when dictated in capitals** — so an all-caps mishearing can be corrected without touching the ordinary word; multi-word capitalised entries such as "USB C" are unaffected. macOS + iOS.
- **Fixed: dictation no longer disappears when you speak into a quiet microphone** — recordings of two seconds or longer always go to the speech recognizer instead of being dropped as "silence" by the pre-check that had been tuned on one microphone; a long deliberately silent hold may now paste a stray phrase you can delete, which beats losing what you said. If a paste cannot be delivered (a password field or a terminal with secure input has focus, or you switched apps after releasing the hotkey), the text is left on your clipboard, the menu-bar icon shows a warning until you open the menu or dictate again, and the menu tells you to press ⌘V; a system notification is sent too, which your Focus / Do Not Disturb settings may mute. macOS.
- **Fixed: a slow app could paste your previous clipboard instead of what you just dictated** — after pasting, Dicticus now keeps the dictation on the clipboard for three-quarters of a second (was a tenth) before putting your previous clipboard back, and puts it back only if nothing else has written to the clipboard in the meantime; seen once in Gemini for macOS on the first dictation after the AI model had been idle. macOS.
- **Fixed: dictating again, or pressing Revert to Raw, within a second of a paste could leave an earlier dictation's text on your clipboard instead of what you had copied before** — Dicticus now waits for the previous paste's clipboard restore to finish before it touches the clipboard again, so what comes back is always your own earlier copy. macOS.
- **Added: checksums for downloads** — every release now ships a `Dicticus.dmg.sha256` next to the DMG (verify with `shasum -c`), and the AI-cleanup model file is verified against its expected SHA-256 after download and at every launch; a corrupted or substituted file is deleted and downloaded again, and if that fails too AI cleanup is disabled for the session with a "Model failed verification" status (relaunch to retry). macOS.
- **Added: the AI-cleanup model unloads after idle** — Settings → AI Cleanup → "Unload AI model after idle" (5/10/30 min or Never, default 10) frees ~2.7 GB of memory when you have not used AI cleanup for that long; the model reloads while you speak on the next AI-cleanup dictation, and cleanup waits for it rather than pasting uncleaned text. macOS.
- **Fixed: push-to-talk no longer launches Apple Music when nothing is playing** — the media auto-pause now only acts when it measures real playback (a ten-times higher level than before; every genuine playback ever logged is far above it), so a near-silent output can no longer trigger a pause/resume pair that macOS answers by opening Music. macOS.

---

## 1.1.0 — Dictation Reliability & Cleanup Fixes — 2026-09-02

- **Fixed: push-to-talk media pause could launch Apple Music unprompted** — on audio sources macOS can't address directly (some browser tabs, bare-bones IPTV/streaming apps), the pause toggle could hit the system's "no active player" fallback and launch Music instead of just pausing what was already playing. Switched to discrete pause/resume commands that have no such fallback. macOS.
- **Fixed: fuzzy brand-matching could corrupt short words and acronyms** — the phonetic brand matcher could rewrite spans crossing word boundaries ("…my Tailscale IP and not…" became "…my Tailscale iPad, not…"), swallow digits ("Opus 5" → "USB-A"), or misfire on short acronyms in context ("as BCAA" → "USB-C"). New vetoes (function-word boundary, digit-sequence parity, short-acronym context gate) close all three while keeping genuine brand fixes. macOS + iOS.
- **Fixed: several AI-cleanup punctuation glitches** — EditGuard no longer fabricates a comma/dash/period sequence that wasn't present in either your speech or the cleaned text (a "mixed-provenance" punctuation bug), and a punctuation mark that gets restored after a rejected edit now always keeps its own correct spacing instead of occasionally gluing onto the next word. macOS + iOS.
- **Fixed: AI cleanup rejected legitimate hyphen joins** — compounds dictated as two words ("code wise", "self evaluation") now come through as "code-wise" / "self-evaluation" instead of being blocked; a sentence-split bookkeeping bug that could strip a correct sentence-start capital is also fixed. macOS + iOS.
- **Fixed: "Thank you." no longer appears out of nowhere** — a short closed list of Whisper's known pause-hallucination phrases is now discarded before it reaches you, instead of being pasted as if you'd said it. macOS.
- **Fixed: wrong "check your models" alert on silent presses** — pressing the hotkey without speaking no longer shows "Transcription failed. Check that models are loaded."; it now stays silent, matching how other no-speech cases are already handled. macOS.
- **Added: a safety net for AI cleanup** — a new independent guard blocks any cleanup result that silently drops a number, URL, email address, or file path that was present in your dictation, falling back to the pre-cleanup text instead. macOS + iOS.
- **Improved: less gets thrown away when AI cleanup partially misbehaves** — previously, if any part of a cleaned multi-sentence response failed the correctness check, cleanup reverted the *entire* response to raw text; now an isolated bad edit reverts on its own, keeping the rest of the cleanup. macOS + iOS.
- **Faster first dictation** (macOS) — the cleanup model is pre-warmed the moment you press to start recording, removing the ~5 s cold-start on the first AI cleanup after launch or idle (~1 s now).
- **Debug logs stop fabricating a confidence signal** — the per-segment no-speech probability (never actually computed by WhisperKit) is no longer logged as a fake 0; compression ratio and temperature are recorded instead (macOS Debug-Recorder builds).
- **Debug logging improvements** (macOS Debug-Recorder builds) — the cleanup log now records the exact final text after capitalization, and a new diagnostic probe records secure-input state at paste time, to speed up future bug investigations.

---

## 1.0.2 — Starter packs + media-pause fix — 2026-08-05

- **Starter packs expanded** — added brand and tech dictation corrections to the bundled starter packs (Dictionary → Starter Packs), macOS + iOS.
- **Fixed: media pause could un-pause the wrong app** (macOS) — when the playing audio came from an app that doesn't register with macOS's now-playing system (e.g. bare-bones IPTV players), the pause-while-dictating toggle could land on a different, paused app and start it. The toggle now verifies that audio actually stopped; if it didn't, it restores the other app and mutes the output for the rest of the dictation instead.

---

## 1.0.1 — Repo rename + cleanup fix — 2026-08-01

- **Project home renamed** to `github.com/maksim-101/dicticus` (was `dicticus-macos` — the repo hosts both the macOS and iOS apps). The Sparkle update feed moved to `maksim-101.github.io/dicticus/appcast.xml`; 1.0.0 installs carry the old feed URL and need this one manual update.
- **Fixed: AI-cleanup sentence glue** — when EditGuard (correctly) rejected an LLM merge of two sentences, the restored sentence break could lose its space ("labeled.So"). The rejected-edit restore path now keeps the original spacing. macOS + iOS.

---

## 1.0.0 — First public release — 2026-07-31

> **Versioning note:** 1.0.0 marks the first public release under a clean version line.
> The sections below it document earlier development milestones whose numbers (v1.x/v2.x
> and `macos-v1.x` tags) were internal counters; those tags and releases have been retired.

The first public Dicticus release, and a major engine generation:

- **New ASR engine** — Whisper large-v3-turbo via WhisperKit on the Apple Neural Engine, replacing Parakeet: better word accuracy and repair behavior in German and English, with clip-relative adaptive voice gating so quiet speech isn't dropped.
- **AI cleanup, rebuilt around fidelity** — cleanup (Qwen3.5-4B via llama.cpp) is strictly opt-in with its own hotkey, and every LLM edit now passes **EditGuard**, a deterministic edit-level guard that blocks the model from rewriting what you actually dictated (content-word deletions/insertions/identity changes, pronoun flips, phantom moves) while letting punctuation, casing, and safe grammar repairs through.
- **Context-aware formatting** — the active app is detected and the cleanup prompt adapts (code context keeps identifiers safe); per-app overrides and a session pin are configurable.
- **Plain dictation got smarter** — deterministic multi-sentence capitalization, spoken punctuation, acronym collapse, number/currency formatting, and the brand-matcher (phonetic recovery of misheard technical terms) all run without any LLM.
- **Custom dictionary platform** — user-owned corrections with CSV/JSON import/export and bundled starter packs.
- **Quality-of-life** — media auto-pause during push-to-talk (Music/Spotify pause, other audio muted only when actually playing), searchable local history (FTS5), menu-bar popover with Home/Dictionary/History tabs.
- **iOS app** — Shortcuts/Action-Button dictation with the same shared pipeline, deferred delivery for background recordings, and on-device models throughout.

Fully local as always: no audio or text ever leaves the device.

---

## v2.4 — Public-Release Readiness + Dictionary as Platform — shipped 2026-06-09 · tag `macos-v1.4.0`

Public-release prep: the dictionary becomes a user-owned platform, deterministic spoken-punctuation lands pre-cleanup, the iOS first-run experience gets an overhaul, and both apps are reorganized into a clean tabbed information architecture.

- **Phase 31 (2026-06-06)** — Dictionary as a platform: the public build ships an empty default dictionary (personal entries gated behind a local-only flag and kept out of the release binary), CSV/JSON import & export with three merge strategies and RFC-4180 validation, bundled offline starter packs with one-tap import, and docs for the CSV-author tech-term recovery workflow. macOS + iOS.
- **Phase 32 (2026-06-07)** — Spoken punctuation: saying "comma", "period", "new line", etc. is converted deterministically before AI cleanup, with an in-app reference table. macOS + iOS.
- **Phase 33 (2026-06-08)** — iOS first-run & onboarding overhaul: fixed the relaunch download-screen flash (including a follow-up where an already-downloaded model still showed a fake "Downloading" screen during warmup), download-screen label truncation at small widths, and a duplicate Action Button entry in Settings; added a 3-page guided onboarding tour that auto-presents after setup and is re-triggerable from Settings. Also removed a misleading dictation Live Activity that implied background recording the app couldn't actually do — leaving the app mid-dictation now finalizes and copies what you said instead. iOS.
- **Phase 34 (2026-06-08)** — AI cleanup R8 over-promotion fix (V19D → V19E): tightened the R8 EXCEPTION so AI cleanup no longer collapses real words next to number-words into identifier stems ("kink three" stays "kink three", "King Four" → "King four" — not K3/K4). The EXCEPTION now requires the preceding stem to be ALL-CAPS (e.g. GPT, E, API) or contain a non-letter character (e.g. iOS, E2), not just any capitalized word. Also added a deterministic content-word-preservation gate that falls back to pre-LLM text when a content word is dropped — a backstop for local word-loss invisible to the whole-text Levenshtein gate. Gap-closure (2026-06-08): the gate now runs on short utterances (≤3 words) instead of only on longer inputs, and legitimate number-word promotions ("M three" → "M3") are preserved by allowlisting spelled-out cardinals and ordinals. macOS + iOS.
- **Phase 35 (2026-06-09)** — UI reorganization (macOS + iOS): the macOS menu-bar popover is split into a fixed-height tabbed layout (Home / Dictionary / History) with a 4-pane ⌘, Settings window (Hotkeys / AI Cleanup / General / About) and all hotkey configuration consolidated into one pane; the popover Dictionary tab gains an inline add-entry form. iPhone gains a matching 3-tab layout (Dictate / Dictionary / History) with frequency-ordered Settings and Dictionary promoted out of Settings; on iPad the NavigationSplitView sidebar gains a Dictionary destination. Custom-dictionary entries you add now sort to the top of the list (above imported and default entries). Signed-build polish: full-width tab tap targets, a visible Quit button + hover tooltips in the popover header, and a Stage Manager fix so the Dictionary / History / Settings windows stay findable when switching apps. macOS + iOS.

---

## v2.3 — Live-Capture Quality Pass — shipped 2026-06-06 · tag `macos-v1.3.0`

Quality pass driven by analysis of real multi-day dictation logs (the DebugRecorder capture). Focus: stop the dictionary from corrupting text, and sharpen the AI cleanup prompt.

- **Phase 27 (2026-05-27)** — Dictionary hallucination guard (stops fuzzy-matching from mangling correct words), DebugRecorder enrichment, and a batch of brand/jargon dictionary additions.
- **Phase 28 (2026-05-27)** — "V19D" AI-cleanup prompt iteration: better clause handling, contraction handling, de-duplication, and number formatting.
- **Phase 29 (2026-05-29)** — Post-ASR fixes: spelled-out acronyms collapse (`N F S K` → `NFSK`), spoken letter names resolve inside acronyms (zed/zee → Z, etc.), and the Zed IDE (misheard as "set") is recovered via a period-anchored dictionary entry. Cross-platform (macOS + iOS).
- **Phase 30 (2026-06-06)** — Push-to-talk now pauses Apple Music / Spotify while you dictate and resumes on release; for other audio (browser/YouTube/podcasts) it mutes output during the hold and unmutes on release. Respects a system you muted yourself. macOS-only. (Note: output devices with hardware-only volume — some external USB DACs — can't be muted by macOS, so the mute fallback is a no-op there; the Music/Spotify pause is unaffected.)
- **Fix** — ASR model download now retries on a transient network drop instead of failing the whole download (the ~2.7 GB Parakeet download from HuggingFace would abort on a single "connection reset"). macOS + iOS.

_Shipped as macOS `1.3.0` (build 5) on 2026-06-06, tag `macos-v1.3.0` — the first installable update since `macos-v1.2.0`, so it delivers the v2.2 + v2.3 work together to anyone updating from 1.2.0._

---

## v2.2 — Adaptive Cleanup & Stability — shipped 2026-05-03 → 2026-05-22

Stability and correctness work on the cleanup pipeline, plus number/ITN handling.

- **Adaptive cleanup & stability (2026-05-03)** — Debounce fix, surgical completion, 6-token repair window.
- **Resolver regression hotfix (2026-05-08)** — Fixed self-correction regex (comma-prefix + word boundaries); locked behavior with cross-platform fixtures.
- **Pipeline quality hardening (2026-05-22)** — Inverse text normalization for spoken decimal markers (`Punkt`/`Komma`/`point`) and fixes for comma-separated digit words.

---

## v2.1 — AI Cleanup & Swiss-Ification Polish — shipped 2026-05-01  ·  tag `macos-v1.2.0`

Originally scoped as "keyboard extension + iCloud sync," but pivoted: the iOS keyboard extension was removed (iOS 26 blocked the URL-opening trick it relied on), and AI cleanup quality became the main work. Shipped as a notarized macOS release with auto-update.

- **AI cleanup overhaul** — Upgraded to Gemma 4 E2B; numbers/currencies/dates formatting; Swiss German orthography (ß→ss, dialect-aware); refined cleanup prompt with order-locking tests.
- **macOS distribution hardened** — Notarized DMG, Sparkle EdDSA-signed auto-update feed, full build→sign→notarize→staple pipeline.
- **Keyboard extension pivot** — Removed from shipping app; architecture preserved in history for possible future revival.
- **Repo hygiene** — Planning artifacts moved out of version control.

_Known limitations carried forward: non-reactive transcribing/cleaning menu-bar icon (cosmetic); occasional sentence-stitching by the LLM._

---

## v2.0 — iOS App (Shortcut Dictation) — shipped 2026-04-22

Dicticus became multi-platform with a native iOS app for iPhone and iPad.

- **Shared core pipeline** — Transcription/cleanup logic unified into a cross-platform `Shared/` module used by both macOS and iOS.
- **On-device iOS dictation** — FluidAudio on iOS with ~2.7 GB model provisioning and background warmup.
- **System integration** — "Start Dictation" Siri Shortcut / Action Button support and a Live Activity for real-time feedback.
- **Universal layout** — Adaptive SwiftUI UI (iPhone + iPad sidebar).
- **Local persistence** — History and dictionary stored via GRDB with full-text search.

---

## v1.1 — Cleanup Intelligence & Distribution — shipped 2026-04-20/21  ·  tags `v1.1.0`, `v1.1.1`

- **Smarter AI cleanup** — Upgraded the LLM to Gemma 4 E2B; redesigned prompt infers meaning from broken/non-native German rather than just fixing grammar.
- **Inverse text normalization** — Spelled-out numbers become digits, English and German ("one hundred twenty three" / "einhundertdreiundzwanzig" → "123").
- **Custom dictionary** — User-configurable find-and-replace for recurring ASR errors, pre-seeded with 35+ common fixes (pipeline: ASR → Dictionary → ITN → AI cleanup).
- **Transcription history** — Searchable full-text history of past dictations (GRDB + FTS5) with one-click copy.
- **Distribution** — Developer ID signed + Apple notarized (no Gatekeeper override); Sparkle auto-updates via EdDSA-signed appcast.
- **v1.1.1 patch (2026-04-21)** — Fixed default dictionary entries not populating on Sparkle updates (only fresh installs).

---

## v1.0 — MVP — shipped 2026-04-18  ·  tags `v1.0`, `v0.1.0`

First working release: a fully local macOS menu-bar dictation app.

- **System-wide push-to-talk** — Hold a hotkey, speak, release; text appears at the cursor in any app.
- **On-device ASR** — FluidAudio + Parakeet TDT v3 (German ~5% WER, English ~6% WER), ~200× realtime on the Apple Neural Engine.
- **Local AI cleanup** — Gemma (via llama.cpp) for grammar/punctuation; no cloud dependency.
- **Modifier-only hotkeys** — Fn+Shift / Fn+Control via a global event monitor.
- **Lightweight** — ~170 MB memory footprint.
- **DMG distribution** with a permissions onboarding flow.

---

_For deeper detail on any release, see the per-milestone records under `.planning/milestones/` and the phase summaries in `.planning/phases/` (local only — not tracked in git). GitHub Releases: https://github.com/maksim-101/dicticus/releases_
