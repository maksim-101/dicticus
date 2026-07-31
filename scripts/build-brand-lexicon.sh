#!/bin/zsh
# build-brand-lexicon.sh — generate the comprehensive EN+DE common-word lexicon
# guard for the Phase 36.5 brand-name matcher (BMATCH-02).
#
# WHY: a curated stoplist provably fails — the spike-009 scale test corrupted
# ordinary prose (could -> Claude x56) until a *comprehensive* word list was
# unioned in. These lexicon files are the load-bearing guard: the matcher only
# fires on tokens ABSENT from them. They are SEPARATE from the small
# allowlist-{en,de}.txt (~1k lemmas) that powers the tuned DictionaryService
# fuzzy pass, so that pass is left unperturbed (RESEARCH 36.5 §2 isolation
# decision).
#
# SOURCE: hermitdave/FrequencyWords (OpenSubtitles 2018 surface forms,
# CC-BY-SA 4.0) — the project's already-attributed lexicon source, single
# consistent license story. Surface forms carry inflections naturally.
#   EN: content/2018/en/en_full.txt
#   DE: content/2018/de/de_full.txt
#
# FALLBACK (EN only): if en_full coverage shows EN false-positives in the
# 36.5-05 scale test, swap the EN source to SCOWL (Kevin Atkinson,
# MIT-like permissive, https://wordlist.aspell.net/) which carries explicit
# inflection variants. Generate a plain wordlist from the SCOWL web tool /
# SourceForge release and run it through the same lowercase/NFC/filter/sort
# pipeline below. SCOWL is bundleable in a closed-source app.
#
# TRANSFORM (per language): strip the trailing count field (keep word only),
# lowercase, NFC-normalize, filter (EN: a-z plus apostrophe/hyphen; DE: letters
# plus umlauts ä/ö/ü plus eszett ß — NEVER ASCII-strip), drop length-1 tokens,
# de-duplicate, byte-sort. The DE filter PRESERVES umlauts and ß (RESEARCH
# Pitfall §4.1/§4.3) — the #1 port correctness bug if lost.
#
# Idempotent: caches raw downloads under $TMPDIR; re-runs deterministically
# (LC_ALL=C byte sort).
#
# Network: the GitHub raw fetch needs network access. If a sandbox blocks it,
# re-run with the sandbox disabled.

set -euo pipefail
export LC_ALL=C

SCRIPT_DIR=${0:A:h}
REPO_ROOT=${SCRIPT_DIR:h}
RES_DIR="$REPO_ROOT/Shared/Resources"
CACHE_DIR="${TMPDIR:-/tmp}/dicticus-lexicon-build"
mkdir -p "$CACHE_DIR"

EN_URL="https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/en/en_full.txt"
DE_URL="https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/de/de_full.txt"

# Cap the frequency-sorted raw lists before filtering: the long tail is noise
# (typos, foreign tokens). Caps are chosen to land EN well above 150k and DE
# above 50k surface forms while keeping bundle size reasonable (ships on iOS).
EN_CAP=300000
DE_CAP=250000

EN_RAW="$CACHE_DIR/en_full.txt"
DE_RAW="$CACHE_DIR/de_full.txt"

fetch() {
  local url=$1 out=$2
  if [[ -s "$out" ]]; then
    echo "cache hit: $out"
  else
    echo "fetching: $url"
    curl -fsSL "$url" -o "$out"
  fi
}

fetch "$EN_URL" "$EN_RAW"
fetch "$DE_URL" "$DE_RAW"

# EN: keep word field, lowercase, NFC, filter [a-z' -] (\x27 apostrophe, \x2d
# hyphen — kept out of shell quoting), drop length-1, byte-sort/uniq.
head -n "$EN_CAP" "$EN_RAW" \
  | perl -CSD -Mutf8 -MUnicode::Normalize -ne 'my @f=split; next unless @f; my $w=NFC(lc $f[0]); next unless length($w)>=2; print "$w\n" if $w=~/^[a-z\x27\x2d]+$/;' \
  | sort -u > "$RES_DIR/lexicon-en.txt"

# DE: same pipeline, filter preserves umlauts + eszett.
head -n "$DE_CAP" "$DE_RAW" \
  | perl -CSD -Mutf8 -MUnicode::Normalize -ne 'my @f=split; next unless @f; my $w=NFC(lc $f[0]); next unless length($w)>=2; print "$w\n" if $w=~/^[a-zäöüß]+$/;' \
  | sort -u > "$RES_DIR/lexicon-de.txt"

EN_COUNT=$(grep -vc '^$' "$RES_DIR/lexicon-en.txt")
DE_COUNT=$(grep -vc '^$' "$RES_DIR/lexicon-de.txt")
echo "lexicon-en.txt: $EN_COUNT words"
echo "lexicon-de.txt: $DE_COUNT words"
echo "done."
