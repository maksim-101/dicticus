import Foundation

/// Phase 36.5 — hybrid fuzzy/phonetic brand-name matcher (Step 1b of the cleanup
/// pipeline). Recovers DISTINCTIVE misheard brand/tech tokens the exact-match
/// `DictionaryService` misses (Sonat→Sonnet, Towry→Tauri, Versal→Vercel,
/// Dicticos→Dicticus), generalizing to unseen spelling variants WITHOUT
/// corrupting ordinary prose.
///
/// HYBRID contract (CONTEXT, locked): the matcher fires ONLY on distinctive
/// tokens — those NOT present in the comprehensive lexicon (after depunctuation +
/// light inflection backoff) AND ≥ `minDistinctiveChars` normalized characters —
/// OR near-exact compounds (jw ≥ `nearExactJW`, dl ≤ `nearExactDL`). It must
/// NEVER rewrite a lexicon word; common-word brand homophones (gravity, cloud,
/// set, opus, gemini, swift, code …) stay with `DictionaryService`'s anchored
/// multi-word exact entries. Acceptable failure mode = MISS, never corrupt.
///
/// Per-language phonetics: English tokens are encoded with `DoubleMetaphone`,
/// German tokens with `ColognePhonetic`; both the token and the canonical are
/// encoded with the SAME encoder per call (a mixed-encoder comparison is
/// meaningless). Orthographic distance uses `BrandStringMetrics`
/// (Damerau-Levenshtein OSA + Jaro-Winkler).
///
/// Ported from the validated spike-009 `matcher.py` (`is_common`, `match_token`,
/// `match_text` window-admission). The Python `norm()` `[^a-z0-9]` strip is
/// deliberately NOT replicated — it destroys ä/ö/ü (RESEARCH §4.1, the #1 port
/// bug); `normalize` keeps umlauts/ß and NFC-normalizes symmetrically with the
/// lexicon.
@MainActor
final class BrandMatcher {

    // MARK: - Tuning constants
    //
    // These thresholds mirror the spike's jellyfish-validated values. The Swift
    // phonetic encoders (Double Metaphone / Kölner) collide a DIFFERENT set of
    // tokens than jellyfish's single Metaphone, so these are RE-TUNED against the
    // real debug-log corpus in 36.5-05's scale test — treat them as provisional.
    static let jwThreshold: Double = 0.86          // orthographic accept floor
    static let maxEditDistance: Int = 2            // orthographic accept cap (OSA dl)
    static let strongOrthoThreshold: Double = 0.93 // ortho-only accept without phonetic agreement
    static let phoneticJWFloor: Double = 0.75      // phonetic-accept needs this jw OR bounded dl
    static let nearExactJW: Double = 0.95          // near-exact compound admission
    static let nearExactDL: Int = 1                // near-exact compound admission
    static let minDistinctiveChars: Int = 4        // a token shorter than this never fires

    // MARK: - State (immutable after init)

    private let baseCanonicals: [String]
    private let combinedLexicon: Set<String>

    /// Runtime union source for the canonical list: the user's LOCAL
    /// `DictionaryService` replacement targets. Injected as a closure so this
    /// file stays decoupled from `DictionaryService` (it compiles standalone via
    /// `swiftc` for the hermetic check). Personal brand terms therefore come from
    /// local user data, never the repo seed (CONTEXT / SC5). `TextProcessingService`
    /// wires this for the `shared` instance; tests/harness leave it nil for
    /// hermetic behaviour.
    var liveDictionaryCanonicalProvider: (() -> [String])?

    // MARK: - Init

    /// Designated initializer. Fully explicit canonical list + lexicon sets so
    /// tests and the 36.5-05 harness run hermetically (no live UserDefaults).
    init(canonicals: [String], enLexicon: Set<String>, deLexicon: Set<String>) {
        self.baseCanonicals = BrandMatcher.dedupeNFC(canonicals)
        self.combinedLexicon = enLexicon.union(deLexicon)
        self.liveDictionaryCanonicalProvider = nil
    }

    /// Shared singleton — comprehensive bundled lexicon + bundled canonical seed.
    /// The live-dictionary union is layered on per call via
    /// `liveDictionaryCanonicalProvider`, wired by `TextProcessingService`.
    static let shared: BrandMatcher = {
        let (en, de) = BrandMatcher.loadBundleLexicons()
        let canon = BrandMatcher.loadBundleCanonicals()
        return BrandMatcher(canonicals: canon, enLexicon: en, deLexicon: de)
    }()

    /// Hermetic factory: explicit canonical list, comprehensive lexicon loaded
    /// from the app bundle. Used by `BrandMatcherTests` so the designed-corpus
    /// precision gate runs against the real comprehensive guard while the
    /// canonical list is fixed (independent of the live dictionary).
    static func bundledLexiconMatcher(canonicals: [String]) -> BrandMatcher {
        let (en, de) = loadBundleLexicons()
        return BrandMatcher(canonicals: canonicals, enLexicon: en, deLexicon: de)
    }

    // MARK: - Public API

    /// One rewrite the matcher made: the matched surface window, the canonical it
    /// was mapped to, and the orthographic scores. Used by the 36.5-05 Brand009
    /// scale harness to gate every rewrite over the real corpus.
    struct Rewrite {
        let surface: String
        let canon: String
        let jw: Double
        let dl: Int
    }

    /// Rewrite distinctive misheard brand tokens in `text` to their canonical
    /// surface form. On no match, returns the input unchanged. Idempotent: a
    /// rewritten canonical is either itself in the lexicon (guarded) or maps to
    /// itself (no-op) on a second pass.
    func apply(to text: String, language: String) -> String {
        applyReportingRewrites(to: text, language: language).output
    }

    /// Same single-pass rewrite as `apply`, additionally reporting every rewrite
    /// it made (surface window → canonical, with scores). The scale harness
    /// (36.5-05) needs the per-rewrite surfaces to assert the subset-of-expected
    /// gate; `apply` simply discards the rewrite list.
    func applyReportingRewrites(to text: String, language: String)
        -> (output: String, rewrites: [Rewrite]) {
        var rewrites: [Rewrite] = []
        if text.isEmpty { return (text, rewrites) }
        let canonicals = resolvedCanonicals()
        if canonicals.isEmpty { return (text, rewrites) }

        let (words, seps) = splitPreservingWhitespace(text)
        if words.isEmpty { return (text, rewrites) }

        // Precompute the canonical phonetic encodings ONCE per call (RESEARCH
        // §4.7: cache encodings; the input is tiny so this is trivial).
        let canonEncoded = canonicals.map { (canon: $0, meta: encode($0, language: language)) }

        var out = ""
        var i = 0
        while i < words.count {
            out += seps[i]
            var matched = false
            // Prefer the longer (2-token) window so "Swift bar" → SwiftBar wins
            // over a spurious single-token match.
            for w in [2, 1] where i + w <= words.count {
                let windowWords = Array(words[i ..< i + w])
                // Sonnet-5 digit-drop guard (260725-debug): no canonical brand
                // contains digits, so a bare-numeric token (e.g. "5" in "Sonnet
                // 5") can never legitimately be part of a real brand-name
                // correction. Without this guard, `normalize` strips the space
                // between window words while KEEPING digit characters, so
                // "Sonnet 5" normalizes to "sonnet5" — scoring jw≈0.97/dl=1
                // against canonical "Sonnet" and clearing the near-exact /
                // strong-ortho accept gates below, which silently ate the
                // trailing digit ("Sonnet 5" -> "Sonnet", "opus 5" -> "Opus",
                // "Gemma 4" -> "Gemma"). Reject any window containing a bare
                // numeric token outright — MISS is the acceptable failure mode
                // here (HYBRID contract), never corrupt.
                guard !windowWords.contains(where: isBareNumeric) else { continue }
                let window = windowWords.joined(separator: " ")
                let distinctive = windowWords.contains {
                    !isCommon($0) && normalize($0).count >= BrandMatcher.minDistinctiveChars
                }
                let guardCommon = (w == 1)
                guard let m = matchToken(window,
                                         language: language,
                                         canonEncoded: canonEncoded,
                                         guardCommon: guardCommon) else { continue }
                // Window admission (precision lever): rewrite only if the window
                // holds a distinctive token, OR it is a near-exact compound the
                // user clearly meant as a brand. All-common fuzzy windows are
                // rejected — left to DictionaryService anchored entries.
                //
                // The near-exact path is scored on NORMALIZED strings, and
                // `normalize` strips symbols — so a canonical like "C++"/"C#"
                // normalizes to a bare single letter. A short input token (e.g.
                // "C") then scores jw=1.0/dl=0 against that stub and bypasses the
                // distinctiveness gate entirely (260724-iw4: "A to C" → "A to
                // C++"). Require the near-exact window itself to also clear
                // `minDistinctiveChars` so short/symbol-stripped canonicals can't
                // re-arm this path; real near-exact admissions (e.g. "Swift bar"
                // → SwiftBar, normalized length 8) are unaffected.
                let nearExact = m.jw >= BrandMatcher.nearExactJW
                    && m.dl <= BrandMatcher.nearExactDL
                    && normalize(window).count >= BrandMatcher.minDistinctiveChars
                guard distinctive || nearExact else { continue }

                let lead = leadingNonCore(windowWords.first!)
                let trail = trailingNonCore(windowWords.last!)
                out += lead + m.canon + trail
                rewrites.append(Rewrite(surface: window, canon: m.canon, jw: m.jw, dl: m.dl))
                i += w
                matched = true
                break
            }
            if !matched {
                out += words[i]
                i += 1
            }
        }
        out += seps[words.count]
        return (out, rewrites)
    }

    /// Diagnostic accessor exposing the matcher's OWN common-word guard
    /// (`isCommon`: depunct + inflection backoff over the comprehensive lexicon).
    /// The Brand009 scale harness classifies every rewrite surface with this — the
    /// SAME guard used at runtime, not raw-set membership — so the `could→Claude`
    /// residual class (`called`, `code.`, `cost,`, `side.`) is provably caught.
    func classifyCommon(_ w: String) -> Bool { isCommon(w) }

    // MARK: - Matching internals (ported from matcher.py)

    /// Try to match a single surface token (1–2 words) to a canonical brand.
    /// Returns the best `(canon, jw, dl)` or nil. Mirrors `match_token`.
    private func matchToken(_ token: String,
                            language: String,
                            canonEncoded: [(canon: String, meta: String)],
                            guardCommon: Bool) -> (canon: String, jw: Double, dl: Int)? {
        let tnorm = normalize(token)
        if tnorm.isEmpty { return nil }

        // Common-word guard: a single-token window that IS a common word is never
        // fuzzy-rewritten (multi-word brands handled as windows).
        let parts = token.lowercased().split(separator: " ")
        if guardCommon, parts.count == 1, isCommon(String(parts[0])) {
            return nil
        }

        let tmeta = encode(token, language: language)
        var best: (canon: String, score: Double, jw: Double, dl: Int)? = nil
        for entry in canonEncoded {
            let na = tnorm
            let nb = normalize(entry.canon)
            if na.isEmpty || nb.isEmpty { continue }
            let jw = BrandStringMetrics.jaroWinkler(na, nb)
            let dl = BrandStringMetrics.damerauLevenshtein(na, nb)
            let phon = !tmeta.isEmpty && tmeta == entry.meta
            let orthoOk = jw >= BrandMatcher.jwThreshold && dl <= BrandMatcher.maxEditDistance
            let phonOk = phon && (jw >= BrandMatcher.phoneticJWFloor
                                  || dl <= max(3, tnorm.count / 2))
            // require_phonetic = true (spike default): accept on a strong
            // orthographic match WITH phonetic agreement (or a very-strong ortho
            // match alone), OR on a phonetic match with bounded distance.
            let accept = (orthoOk && (phon || jw >= BrandMatcher.strongOrthoThreshold)) || phonOk
            if accept {
                let score = jw + (phon ? 0.15 : 0.0)
                if best == nil || score > best!.score {
                    best = (entry.canon, score, jw, dl)
                }
            }
        }
        guard let b = best else { return nil }
        return (b.canon, b.jw, b.dl)
    }

    // MARK: - Lexicon guard (ported from is_common)

    /// True when `w` is a common word — present in the comprehensive lexicon after
    /// depunctuation + NFC, or after backing off a light inflection suffix. The
    /// comprehensive lexicon (not a curated stoplist) is the decisive precision
    /// lever (CONTEXT: `could→Claude ×56` without it).
    private func isCommon(_ w: String) -> Bool {
        let d = depunct(w)
        if d.isEmpty { return false }
        let n = d.precomposedStringWithCanonicalMapping
        if combinedLexicon.contains(n) { return true }
        // Inflection backoff: surface-form lists miss some inflections. Strip a
        // common suffix and re-check the stem (s/ed/ing/es/er/ly/'s + the
        // double-consonant 'called'→'call' case).
        for suf in ["'s", "ing", "ly", "es", "ed", "er", "s"] {
            if n.count > suf.count, n.hasSuffix(suf) {
                let stem = String(n.dropLast(suf.count))
                if combinedLexicon.contains(stem) { return true }
            }
        }
        return false
    }

    // MARK: - Normalization

    /// NFC-preserving normalization: lowercase, NFC-normalize, keep [a-z0-9] plus
    /// German umlauts/ß. Deliberately NOT the spike's `[^a-z0-9]` strip, which
    /// deletes ä/ö/ü (RESEARCH §4.1).
    private func normalize(_ s: String) -> String {
        let lowered = s.lowercased().precomposedStringWithCanonicalMapping
        return String(lowered.filter { ch in
            ("a"..."z").contains(ch) || ("0"..."9").contains(ch) || "äöüß".contains(ch)
        })
    }

    /// Lowercase + strip surrounding punctuation (NOT interior). Mirrors `depunct`.
    private func depunct(_ w: String) -> String {
        let punct = CharacterSet(charactersIn: ".,!?;:'\"()[]")
        return w.lowercased().trimmingCharacters(in: punct)
    }

    /// True when `w` is a bare digit run after stripping surrounding punctuation
    /// (e.g. "5", "24", "12."). Used by the window-admission guard (260725-debug)
    /// to keep standalone numerals out of fuzzy brand-match windows.
    private func isBareNumeric(_ w: String) -> Bool {
        let d = depunct(w)
        return !d.isEmpty && d.allSatisfy { $0.isNumber }
    }

    /// Phonetic key for `s` under the encoder chosen by `language`: Kölner
    /// Phonetik for German, Double Metaphone otherwise. Both encoders strip
    /// non-letters internally, so a multi-word window encodes as its letters.
    private func encode(_ s: String, language: String) -> String {
        if language.lowercased().hasPrefix("de") {
            return ColognePhonetic.encode(s)
        }
        return DoubleMetaphone.encode(s)
    }

    // MARK: - Canonical resolution

    /// Base bundled canonicals unioned with the live user-dictionary replacement
    /// targets (when a provider is wired). Deduped + NFC. Personal brands stay
    /// local — only the bundled seed ships in the repo.
    private func resolvedCanonicals() -> [String] {
        guard let provider = liveDictionaryCanonicalProvider else { return baseCanonicals }
        return BrandMatcher.dedupeNFC(baseCanonicals + provider())
    }

    private static func dedupeNFC(_ list: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in list {
            let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                .precomposedStringWithCanonicalMapping
            if v.isEmpty { continue }
            let key = v.lowercased()
            if seen.insert(key).inserted { out.append(v) }
        }
        return out
    }

    // MARK: - Whitespace-preserving tokenization

    /// Split into word tokens plus the whitespace separators between them, such
    /// that `text == seps[0] + words[0] + seps[1] + … + words[n-1] + seps[n]`
    /// (`seps.count == words.count + 1`). Lets the rewrite preserve original
    /// spacing around untouched and rewritten windows.
    private func splitPreservingWhitespace(_ text: String) -> (words: [String], seps: [String]) {
        var words: [String] = []
        var seps: [String] = []
        var sep = ""
        var word = ""
        for ch in text {
            if ch.isWhitespace {
                if word.isEmpty {
                    sep.append(ch)
                } else {
                    words.append(word)
                    seps.append(sep)
                    word = ""
                    sep = String(ch)
                }
            } else {
                word.append(ch)
            }
        }
        if !word.isEmpty {
            words.append(word)
            seps.append(sep)
            sep = ""
        }
        seps.append(sep)
        return (words, seps)
    }

    private func leadingNonCore(_ s: String) -> String {
        String(s.prefix { !($0.isLetter || $0.isNumber) })
    }

    private func trailingNonCore(_ s: String) -> String {
        String(s.reversed().prefix { !($0.isLetter || $0.isNumber) }.reversed())
    }

    // MARK: - Bundle resource loading (mirrors DictionaryService.loadCommonWords)

    /// Load `lexicon-en.txt` + `lexicon-de.txt` into NFC-lowercased `Set<String>`
    /// pairs. Defensive empty-on-failure so the matcher never crashes init — the
    /// distinctiveness/≥4-char gate still provides defense if a list is missing.
    nonisolated static func loadBundleLexicons() -> (en: Set<String>, de: Set<String>) {
        return (loadLexiconResource("lexicon-en"), loadLexiconResource("lexicon-de"))
    }

    nonisolated private static func loadLexiconResource(_ name: String) -> Set<String> {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt") else {
            print("[BrandMatcher] lexicon load failed: \(name).txt not found in bundle")
            return []
        }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            print("[BrandMatcher] lexicon unreadable: \(name).txt")
            return []
        }
        var words = Set<String>()
        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            // hermitdave frequency lists are `word count`; keep only the surface
            // form (first field). SCOWL-style one-word-per-line is unaffected.
            let field = line.split(separator: " ", maxSplits: 1).first.map(String.init) ?? String(line)
            let trimmed = field.trimmingCharacters(in: .whitespaces)
                .lowercased()
                .precomposedStringWithCanonicalMapping
            if !trimmed.isEmpty { words.insert(trimmed) }
        }
        return words
    }

    nonisolated static func loadBundleCanonicals() -> [String] {
        guard let url = Bundle.main.url(forResource: "canonical-brands", withExtension: "txt"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            print("[BrandMatcher] canonical-brands.txt not found/unreadable in bundle")
            return []
        }
        return content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
