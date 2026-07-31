# Allowlist Attribution

The files `allowlist-en.txt` and `allowlist-de.txt` are derived from the hermitdave/FrequencyWords corpus (https://github.com/hermitdave/FrequencyWords), an OpenSubtitles-derived per-language frequency list.

Source: https://github.com/hermitdave/FrequencyWords (commit `master`, files `content/2018/en/en_50k.txt` and `content/2018/de/de_50k.txt`).

License: Creative Commons Attribution-ShareAlike 4.0 International (CC-BY-SA 4.0). Full license: https://creativecommons.org/licenses/by-sa/4.0/

Methodology: top 1000 lemmas per language, lowercased, filtered to entries matching `^[a-zäöüß]+$` with length ≥ 2. For English, the K1 morphological variants `remind`, `apply`, `applies`, `applied`, `applying` are appended to ensure coverage of the live-capture hallucination cases (per Phase 27 RESEARCH §6.4). Additionally, `germinate` is appended in Phase 27-03 to protect the real English word from the new `germinize → Gemini` carried-backlog entry (distance 2, ratio 0.222 ≤ 0.25 cap — would otherwise fuzzy-fire and corrupt `germinate`). This is the canonical Guard A defense the 27-01 allowlist was designed for.

## Brand-matcher lexicon (`lexicon-en.txt`, `lexicon-de.txt`)

The files `lexicon-en.txt` and `lexicon-de.txt` are the comprehensive common-word guard for the Phase 36.5 brand-name matcher (BMATCH-02). They are SEPARATE from the small `allowlist-{en,de}.txt` above (which powers the tuned `DictionaryService` fuzzy pass and is left unperturbed). The matcher only fires on tokens ABSENT from these lexicons; a curated stoplist provably failed (spike-009 `could → Claude ×56`), so a comprehensive list is required.

Source: hermitdave/FrequencyWords (https://github.com/hermitdave/FrequencyWords, commit `master`), files `content/2018/en/en_full.txt` and `content/2018/de/de_full.txt` — OpenSubtitles 2018 per-language surface-form frequency lists (inflected forms included naturally).

License: Creative Commons Attribution-ShareAlike 4.0 International (CC-BY-SA 4.0). Full license: https://creativecommons.org/licenses/by-sa/4.0/ — share-alike applies to these data files / derivative word lists, NOT to the app source code.

Methodology (reproducible via `scripts/build-brand-lexicon.sh`): take the top `EN_CAP=300000` / `DE_CAP=250000` frequency-sorted lines, strip the trailing count field (keep the word only), lowercase, NFC-normalize, filter (EN: `^[a-z'-]+$` — letters plus apostrophe/hyphen; DE: `^[a-zäöüß]+$` — letters plus umlauts ä/ö/ü plus eszett ß, NEVER ASCII-stripped), drop length-1 tokens, de-duplicate, byte-sort (`LC_ALL=C`). EN fallback documented in the script header: SCOWL (Kevin Atkinson, MIT-like permissive) if `en_full` shows EN false-positives in the 36.5-05 scale test.
