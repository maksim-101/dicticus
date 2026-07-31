import Foundation

/// Phase 44 Plan 06 (D-01 core): the token-level differ. Myers/LCS backbone,
/// then a post-pass that reinterprets adjacent delete+insert pairs as
/// substitutions and remaining identical delete/insert pairs as moves, plus
/// the degenerate-alignment fail-closed gate that turns a chatbot reply,
/// translation, or wholesale rewrite into a whole-output discard BEFORE any
/// per-edit classification (`EditGuard.classify`, plan 44-10) runs.
///
/// `CollectionDifference.inferringMoves()` is NOT used — it cannot
/// disambiguate duplicate `Hashable` elements, and short dictation
/// utterances are saturated with duplicate function words ("die", "und",
/// "the", "a"). This file builds its own move pass instead (see
/// `pairMovesFirst` below), matching 44-RESEARCH.md Pattern 2.
public enum EditDiff {

    // MARK: - Public entry point

    /// Diffs `baseline` against `candidate`, producing a typed edit stream.
    ///
    /// Three phases (44-RESEARCH.md Pattern 2 / this plan's `<implementation>`,
    /// REORDERED post-merge — see the "Post-merge gate fix" note below):
    /// 1. LCS backbone over `Token.normalized` → raw keep/delete/insert
    ///    stream (`keep` only when `.text` also matches exactly; otherwise a
    ///    `punctuationOrCasing`-flavored `substitute` at the SAME aligned
    ///    position — this is a Step-1-level substitute, distinct from the
    ///    pairing steps below).
    /// 2. GLOBAL move detection FIRST: every remaining delete/insert of
    ///    IDENTICAL `normalized` text, ANYWHERE in the ops stream (not just
    ///    within one local delete/insert "gap") → bipartite nearest-
    ///    neighbour match → `move`. A tie (two candidates equidistant) is
    ///    left UNRESOLVED (fail closed on ambiguity, per T-44-15) — the pair
    ///    stays a plain delete + insert, which routes it into the strict
    ///    per-edit classification path.
    /// 3. THEN adjacent delete-run + insert-run (of whatever the move pass
    ///    left behind) → plausibility-ranked `substitute` edits (prefers the
    ///    insert sharing the longest common stem/prefix with the deleted
    ///    token over a positionally-first pairing); surplus on the longer
    ///    side stays delete/insert.
    ///
    /// **Post-merge gate fix (44-10, bug 1):** the ORIGINAL plan order ran
    /// step 3 (then "step 2") BEFORE move detection. That let a single
    /// delete+insert pair sharing a local "gap" get eagerly consumed into a
    /// (wrong) substitute before move detection ever got a chance to see
    /// that the SAME token, in IDENTICAL form, existed elsewhere in the
    /// stream (e.g. baseline "Wir ... morgen" / candidate "Morgen ... wir"
    /// — "Wir" and "Morgen" sit in the same local gap and got substituted
    /// against each other, even though "wir" and "morgen" each had an exact
    /// match a few tokens away that move detection would have found). Move
    /// detection is a STRICTER, more specific match (identical normalized
    /// text) than gap-adjacency, so it must run first and claim its pairs
    /// before the looser adjacency-based substitute pass gets a turn.
    public static func diff(
        baseline: [EditGuard.Token],
        candidate: [EditGuard.Token]
    ) -> [EditGuard.Edit] {
        let backbone = lcsBackbone(baseline: baseline, candidate: candidate)
        let withMoves = pairMovesFirst(backbone)
        let withSubstitutes = pairAdjacentSubstitutes(withMoves)
        return toEdits(withSubstitutes)
    }

    // MARK: - Step 1: LCS backbone

    /// Raw alignment op — the LCS backbone's output, before the move and
    /// substitute post-passes run. `.substitute` here only ever means the
    /// Step-1 "matched position, different text" (casing/punctuation) case;
    /// the substitute pairing pass produces its OWN substitutes from paired
    /// delete/insert runs, added directly to the returned `[RawOp]` — both
    /// end up as `EditGuard.EditKind.substitute` in the final stream, the
    /// distinction only matters internally while building the op list.
    /// `.move` is populated by `pairMovesFirst`, which runs BEFORE the
    /// substitute pairing pass (see `diff`'s doc comment / the post-merge
    /// gate fix note) so it can claim identical-normalized-text pairs
    /// before the looser gap-adjacency pass gets a turn at them.
    private enum RawOp {
        case keep(EditGuard.Token, EditGuard.Token)
        case substitute(EditGuard.Token, EditGuard.Token)
        case delete(EditGuard.Token)
        case insert(EditGuard.Token)
        case move(EditGuard.Token, EditGuard.Token)
    }

    /// Standard O(m·n) LCS dynamic program over `.normalized`, short
    /// dictation utterances only (a few hundred tokens at most per
    /// 44-RESEARCH.md — no need for Myers' O(ND) space-saving variant).
    private static func lcsBackbone(
        baseline: [EditGuard.Token],
        candidate: [EditGuard.Token]
    ) -> [RawOp] {
        let m = baseline.count
        let n = candidate.count
        guard m > 0 || n > 0 else { return [] }

        var dp = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)
        if m > 0 && n > 0 {
            var i = m - 1
            while i >= 0 {
                var j = n - 1
                while j >= 0 {
                    if baseline[i].normalized == candidate[j].normalized {
                        dp[i][j] = dp[i + 1][j + 1] + 1
                    } else {
                        dp[i][j] = max(dp[i + 1][j], dp[i][j + 1])
                    }
                    j -= 1
                }
                i -= 1
            }
        }

        var ops: [RawOp] = []
        var i = 0
        var j = 0
        while i < m && j < n {
            if baseline[i].normalized == candidate[j].normalized {
                if baseline[i].text == candidate[j].text {
                    ops.append(.keep(baseline[i], candidate[j]))
                } else {
                    ops.append(.substitute(baseline[i], candidate[j]))
                }
                i += 1
                j += 1
            } else if dp[i + 1][j] >= dp[i][j + 1] {
                ops.append(.delete(baseline[i]))
                i += 1
            } else {
                ops.append(.insert(candidate[j]))
                j += 1
            }
        }
        while i < m {
            ops.append(.delete(baseline[i]))
            i += 1
        }
        while j < n {
            ops.append(.insert(candidate[j]))
            j += 1
        }
        return ops
    }

    // MARK: - Step 2 (runs FIRST, post-merge gate fix): global move pass

    /// Scans the ENTIRE ops stream (not one local delete/insert "gap" at a
    /// time) for delete/insert pairs whose `normalized` text is IDENTICAL,
    /// and greedily matches each delete (in stream order) to its nearest
    /// unclaimed identical insert, minimizing `|fromIndex - toIndex|`. Runs
    /// BEFORE `pairAdjacentSubstitutes` so an exact-text match anywhere in
    /// the sentence — the strongest possible signal that two tokens are the
    /// SAME word repositioned — always wins over a same-gap positional
    /// pairing with a token that merely happens to be adjacent (44-10
    /// post-merge bug 1: baseline "Wir ... morgen" / candidate "Morgen ...
    /// wir" used to pair "Wir" against "Morgen" — both sit in the same
    /// local gap — before this pass ever got a chance to notice "wir" and
    /// "morgen" each had an EXACT match a few tokens away).
    ///
    /// Tie rule (load-bearing, T-44-15): if two candidate inserts are
    /// equidistant from the same delete, the pairing is AMBIGUOUS and is
    /// left UNRESOLVED — no guessing. The delete and every tied insert stay
    /// plain `.delete`/`.insert`, which routes the content-word deletion
    /// into the strict per-edit classification path (a missed repair, not a
    /// guessed-wrong accept).
    ///
    /// **Coordinate-space fix + locality constraint (quick task 260719-8am):**
    /// distance used to be `abs(delete.token.index - insert.token.index)` —
    /// `token.index` is the token's position in its OWN stream (baseline for
    /// a delete, candidate for an insert), so this mixed two DIFFERENT
    /// coordinate spaces. A delete near the start of a long baseline and an
    /// insert near the start of a long candidate could read as "close"
    /// purely by coincidence of where each stream happened to be, even
    /// though they sit in unrelated clauses ~60 tokens apart in the actual
    /// merged text (the root cause of the "that's is" cross-clause phantom:
    /// a delete of "is" from "finding that is there" got paired with an
    /// unrelated insert of "is" near "that's ... just so delicious", far
    /// away in a different sentence). Fixed to `abs(delete.opsIndex -
    /// insert.opsIndex)` — both `Slot.opsIndex` values are positions in the
    /// SAME merged `ops` stream, a single coordinate space.
    ///
    /// That alone doesn't stop a genuinely distant pairing when nothing
    /// closer exists, so a LOCALITY constraint is layered on top: a
    /// delete/insert pair may only become a move if it is "locally unique"
    /// — no OTHER token with the same `normalized` text appears anywhere
    /// strictly between the delete's and the insert's `opsIndex` in the
    /// merged ops stream. A same-clause word-order repair (e.g. "werden"
    /// moving from clause-medial to clause-final a handful of tokens away)
    /// never has another "werden" in its span. A cross-clause phantom does:
    /// the ~60-token span between the stray "is" delete and the stray "is"
    /// insert in the 8am fixture contains several OTHER "is" tokens ("this
    /// is something new", etc.) — exactly the shape that distinguishes a
    /// same-word repositioning from two unrelated occurrences of a common
    /// function word. Disqualified pairs fall back to independent plain
    /// delete + insert, which routes the delete into the strict per-edit
    /// classifier (restored at its baseline anchor) — never a looser accept.
    ///
    /// The locality constraint applies to WORD/content tokens only, never
    /// to punctuation (see "Punctuation IS still a move candidate here"
    /// below for why unbounded punctuation pairing is safe) — commas are
    /// the most repetitive token in any text, so "locally unique" would
    /// almost always disqualify a punctuation pairing, breaking
    /// `applyMoveRunCoupling`'s filler+punctuation coupling
    /// (`fx-mov-filler-de`/`fx-mov-filler-en`: disqualifying the adjacent
    /// comma's move demoted it to an independent delete+insert, which
    /// `classifyDelete`/`classifyInsert`'s punctuation branches accept
    /// unconditionally and `applyMoveRunCoupling` can no longer see —
    /// reproducing the exact doubled-comma corruption those fixtures exist
    /// to block).
    ///
    /// **Punctuation IS still a move candidate here, deliberately** (do not
    /// "fix" the 44-FIDELITY-REPLAY.md SC#3 punctuation-move corruption by
    /// excluding punctuation from candidacy in this pass — that was tried
    /// and reverted). `EditGuard.classifyMove` rejects every punctuation
    /// move unconditionally instead (the actual fix — see its own doc
    /// comment). Excluding punctuation from candidacy HERE breaks
    /// `EditGuard.applyMoveRunCoupling`: `fx-mov-filler-de`/`fx-mov-filler-
    /// en` require a filler's rejected move and its immediately-adjacent
    /// punctuation's move to be recognized as one CONTIGUOUS move-run and
    /// reverted together (D-05: a filler must be deleted, not relocated,
    /// and its neighboring comma must not independently drift to wherever
    /// the filler's move target was) — if punctuation never becomes a
    /// `.move` op at all, that punctuation instead becomes an independently
    /// classified plain delete+insert (unconditionally accepted per
    /// `classifyDelete`/`classifyInsert`'s punctuation branches), which
    /// `applyMoveRunCoupling` cannot see or couple, reproducing exactly the
    /// doubled-comma corruption those two fixtures exist to block.
    private static func pairMovesFirst(_ ops: [RawOp]) -> [RawOp] {
        struct Slot {
            let opsIndex: Int
            let token: EditGuard.Token
        }
        var deletes: [Slot] = []
        var inserts: [Slot] = []
        for (pos, op) in ops.enumerated() {
            switch op {
            case .delete(let t): deletes.append(Slot(opsIndex: pos, token: t))
            case .insert(let t): inserts.append(Slot(opsIndex: pos, token: t))
            case .keep, .substitute, .move: break
            }
        }

        // Locality helper: true when some OTHER occurrence of `normalized`
        // sits strictly between `lo` and `hi` (exclusive) in the merged ops
        // stream — see the doc comment above for why this is the signature
        // that separates a same-clause word-order repair from a cross-clause
        // phantom pairing of an unrelated pair of occurrences.
        func hasRepeatBetween(_ lo: Int, _ hi: Int, normalized: String) -> Bool {
            guard hi > lo + 1 else { return false }
            for pos in (lo + 1)..<hi {
                let opNormalized: String
                switch ops[pos] {
                case .keep(let a, _): opNormalized = a.normalized
                case .substitute(let a, _): opNormalized = a.normalized
                case .delete(let t): opNormalized = t.normalized
                case .insert(let t): opNormalized = t.normalized
                case .move: continue // never present in the input to this pass
                }
                if opNormalized == normalized { return true }
            }
            return false
        }

        var claimedInsertSlots = Set<Int>() // index into `inserts`
        var moveTargetForDeleteOpsIndex: [Int: EditGuard.Token] = [:]
        var consumedInsertOpsIndices = Set<Int>()

        for delete in deletes {
            var candidates: [(insertSlot: Int, distance: Int)] = []
            for (insertSlot, insert) in inserts.enumerated() {
                guard !claimedInsertSlots.contains(insertSlot) else { continue }
                guard insert.token.normalized == delete.token.normalized else { continue }
                // Locality is only enforced for non-punctuation tokens.
                // Punctuation marks are the most repetitive token class in
                // any text (commas especially) — applying "locally unique"
                // to them would disqualify the very pairing
                // `EditGuard.applyMoveRunCoupling` depends on (a filler's
                // rejected move + its immediately-adjacent punctuation's
                // move, recognized as one contiguous run and reverted
                // together — `fx-mov-filler-de`/`fx-mov-filler-en`). This is
                // safe: `EditGuard.classifyMove` already rejects EVERY
                // `kind == .punctuation` move unconditionally (see this
                // function's own doc comment above), so an unbounded
                // punctuation pairing here can never become a wrongly
                // ACCEPTED phantom move — only word/content tokens can.
                if delete.token.kind != .punctuation {
                    let lo = min(delete.opsIndex, insert.opsIndex)
                    let hi = max(delete.opsIndex, insert.opsIndex)
                    guard !hasRepeatBetween(lo, hi, normalized: delete.token.normalized) else { continue }
                }
                candidates.append((insertSlot, abs(delete.opsIndex - insert.opsIndex)))
            }
            guard let minDistance = candidates.map(\.distance).min() else { continue }
            let nearest = candidates.filter { $0.distance == minDistance }
            guard nearest.count == 1 else { continue } // ambiguous tie — leave unresolved
            let chosen = nearest[0].insertSlot
            claimedInsertSlots.insert(chosen)
            moveTargetForDeleteOpsIndex[delete.opsIndex] = inserts[chosen].token
            consumedInsertOpsIndices.insert(inserts[chosen].opsIndex)
        }

        var result: [RawOp] = []
        for (pos, op) in ops.enumerated() {
            switch op {
            case .keep, .substitute, .move:
                result.append(op)
            case .delete(let t):
                if let target = moveTargetForDeleteOpsIndex[pos] {
                    result.append(.move(t, target))
                } else {
                    result.append(op)
                }
            case .insert:
                guard !consumedInsertOpsIndices.contains(pos) else { continue }
                result.append(op)
            }
        }
        return result
    }

    // MARK: - Step 3: substitute post-pass (runs AFTER move detection)

    /// Any maximal run of consecutive delete/insert ops LEFT BEHIND by
    /// `pairMovesFirst` (a "gap" between two keep/substitute/move anchors,
    /// or the string's start/end) is split into its delete tokens and
    /// insert tokens, in their original relative order, then paired by
    /// PLAUSIBILITY — the insert sharing the longest common lowercased
    /// prefix ("stem") with the delete wins, not whichever insert happens
    /// to sit leftmost in the gap (44-10 post-merge bug 1: baseline
    /// "Format" deleted alongside candidate inserts "des" and "Formats" in
    /// the same gap — the OLD leftmost-first pairing produced
    /// `substitute(Format, des)` + a stranded `insert(Formats)`, neither of
    /// which survives classification; "Format"/"Formats" share a 6-char
    /// stem while "Format"/"des" share none, so plausibility-ranked pairing
    /// produces the correct `substitute(Format, Formats)` + `insert(des)`).
    /// When NO candidate pair in a gap shares any stem overlap at all
    /// (score 0 for every combination), the ranking degrades to the
    /// original leftmost-first order — `greedyRankedPairing`'s stable sort
    /// guarantees this, so ordinary unrelated-word substitutions keep their
    /// pre-existing positional behavior. The surplus on the longer side (if
    /// the run is delete-heavy or insert-heavy) is re-emitted as plain
    /// `.delete`/`.insert`.
    private static func pairAdjacentSubstitutes(_ ops: [RawOp]) -> [RawOp] {
        var result: [RawOp] = []
        var idx = 0
        while idx < ops.count {
            switch ops[idx] {
            case .keep, .substitute, .move:
                result.append(ops[idx])
                idx += 1
            case .delete, .insert:
                var deletes: [EditGuard.Token] = []
                var inserts: [EditGuard.Token] = []
                var j = idx
                loop: while j < ops.count {
                    switch ops[j] {
                    case .delete(let t):
                        deletes.append(t)
                        j += 1
                    case .insert(let t):
                        inserts.append(t)
                        j += 1
                    case .keep, .substitute, .move:
                        break loop
                    }
                }
                let pairing = greedyRankedPairing(deletes: deletes, inserts: inserts)
                let pairedDeleteIndices = Set(pairing.map(\.deleteIndex))
                let pairedInsertIndices = Set(pairing.map(\.insertIndex))
                for pair in pairing.sorted(by: { $0.deleteIndex < $1.deleteIndex }) {
                    result.append(.substitute(deletes[pair.deleteIndex], inserts[pair.insertIndex]))
                }
                for k in 0..<deletes.count where !pairedDeleteIndices.contains(k) {
                    result.append(.delete(deletes[k]))
                }
                for k in 0..<inserts.count where !pairedInsertIndices.contains(k) {
                    result.append(.insert(inserts[k]))
                }
                idx = j
            }
        }
        return result
    }

    /// The longest common PREFIX length between two lowercased strings —
    /// the plausibility score `pairAdjacentSubstitutes` ranks candidate
    /// delete/insert pairs by. Deliberately simple (no suffix-table
    /// dependency on `InflectionRules`, which is a classification
    /// component, not a diffing one) — the differ only needs a RELATIVE
    /// ranking signal, not a verdict.
    private static func stemOverlap(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        var i = 0
        while i < aChars.count, i < bChars.count, aChars[i] == bChars[i] {
            i += 1
        }
        return i
    }

    /// Greedily selects `min(deletes.count, inserts.count)` (delete, insert)
    /// pairs, highest `stemOverlap` first, breaking ties by the pair with
    /// the smallest `(deleteIndex, insertIndex)` — which is exactly
    /// leftmost-first when every candidate pair scores 0, preserving the
    /// pre-existing behavior for unrelated-word substitutions.
    private static func greedyRankedPairing(
        deletes: [EditGuard.Token],
        inserts: [EditGuard.Token]
    ) -> [(deleteIndex: Int, insertIndex: Int)] {
        let pairCount = min(deletes.count, inserts.count)
        guard pairCount > 0 else { return [] }

        var candidates: [(deleteIndex: Int, insertIndex: Int, score: Int)] = []
        for d in deletes.indices {
            for i in inserts.indices {
                candidates.append((d, i, stemOverlap(deletes[d].normalized, inserts[i].normalized)))
            }
        }
        candidates.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.deleteIndex != rhs.deleteIndex { return lhs.deleteIndex < rhs.deleteIndex }
            return lhs.insertIndex < rhs.insertIndex
        }

        var claimedDeletes = Set<Int>()
        var claimedInserts = Set<Int>()
        var pairs: [(deleteIndex: Int, insertIndex: Int)] = []
        for candidate in candidates {
            guard pairs.count < pairCount else { break }
            guard !claimedDeletes.contains(candidate.deleteIndex),
                  !claimedInserts.contains(candidate.insertIndex) else { continue }
            claimedDeletes.insert(candidate.deleteIndex)
            claimedInserts.insert(candidate.insertIndex)
            pairs.append((candidate.deleteIndex, candidate.insertIndex))
        }
        return pairs
    }

    // MARK: - RawOp -> EditGuard.Edit

    /// Final conversion, once move detection and substitute pairing have
    /// both run: every `RawOp` maps 1:1 onto an `EditGuard.Edit`, in the
    /// same stream order.
    private static func toEdits(_ ops: [RawOp]) -> [EditGuard.Edit] {
        var result: [EditGuard.Edit] = []
        result.reserveCapacity(ops.count)
        for op in ops {
            switch op {
            case .keep(let a, let b):
                result.append(EditGuard.Edit(kind: .keep, from: a, to: b))
            case .substitute(let a, let b):
                result.append(EditGuard.Edit(kind: .substitute, from: a, to: b))
            case .move(let a, let b):
                result.append(EditGuard.Edit(kind: .move, from: a, to: b))
            case .delete(let t):
                result.append(EditGuard.Edit(kind: .delete, from: t, to: nil))
            case .insert(let t):
                result.append(EditGuard.Edit(kind: .insert, from: nil, to: t))
            }
        }
        return result
    }

    // MARK: - Degenerate-alignment gate

    /// The three computable ratios (44-RESEARCH.md Pattern 3) that detect
    /// "this isn't an edit, it's a rewrite/refusal" before any per-edit
    /// classification runs, plus the baseline token count the short-utterance
    /// floor (`isDegenerate`) needs — carried on the struct (not a separate
    /// parameter) so `EditDiff.isDegenerate(_:)`'s single-argument shape,
    /// already depended on by plan 44-10, stays frozen.
    public struct AlignmentConfidence: Sendable {
        public let lengthRatio: Double
        public let matchRatio: Double
        public let unmatchedFraction: Double
        public let baselineTokenCount: Int

        public init(lengthRatio: Double, matchRatio: Double, unmatchedFraction: Double, baselineTokenCount: Int = 0) {
            self.lengthRatio = lengthRatio
            self.matchRatio = matchRatio
            self.unmatchedFraction = unmatchedFraction
            self.baselineTokenCount = baselineTokenCount
        }
    }

    /// CALIBRATED against the 44-01 corpus snapshot's 90-German +
    /// 30-sampled-English hand-labeled seed set (`corpus-snapshot/analysis/
    /// qwen-era-{de,en}-labeled*.json`) plus every `.accept` fixture in
    /// `EditGuardFixtures.all` — NOT the research's starting values
    /// (0.5/1.5, 0.7, 0.3), which this project's short push-to-talk
    /// utterances make too tight (see the calibration table in
    /// `44-06-SUMMARY.md`). Widened specifically so every hand-labeled
    /// `repair` record AND every accept fixture (including the D-04
    /// multi-move German word-order repairs, which legitimately swing
    /// `matchRatio` down to ~0.6 on short sentences) stays non-degenerate,
    /// while the 2026-07-05 prompt-injection record, a DE→EN translation,
    /// and a wholesale German rewrite all remain clearly degenerate.
    public static let lengthRatioMin = 0.5
    public static let lengthRatioMax = 1.4
    public static let matchRatioMin = 0.35
    public static let unmatchedFractionMax = 1.0

    /// Below this many baseline tokens, a single edit swings every ratio far
    /// enough that they stop being a reliable degeneracy signal (calibrated
    /// from the same fixture/corpus pass: the shortest accept fixtures — 3
    /// and 5 baseline tokens — have `matchRatio` as low as 0.4-0.57 purely
    /// from a single legitimate move/casing edit). Below the floor,
    /// `isDegenerate` returns `false` unconditionally and the per-edit
    /// classifier (44-10) does all the work — it is strict enough on its
    /// own. The 2026-07-05 injection record (7 baseline tokens) sits ABOVE
    /// this floor and is still evaluated normally, which is why the floor is
    /// pinned at 6, not higher.
    public static let shortUtteranceFloorTokens = 6

    /// Computes `AlignmentConfidence` for a `(baseline, candidate, edits)`
    /// triple. `keepCount` is literal `.keep`-kind edits only (exact text
    /// match at an aligned position) — a `punctuationOrCasing` substitute at
    /// the same aligned position does NOT count toward `matchRatio`, by
    /// design: `matchRatio` measures how much of the output survived
    /// byte-for-byte, which is a stricter (and, per calibration, still
    /// safe) signal than "was this position aligned at all."
    public static func confidence(
        baseline: [EditGuard.Token],
        candidate: [EditGuard.Token],
        edits: [EditGuard.Edit]
    ) -> AlignmentConfidence {
        let bn = baseline.count
        let cn = candidate.count
        guard bn > 0 else {
            // Empty baseline: any non-empty candidate is maximally
            // unmatched (pure insertion); an empty candidate is a trivial
            // exact match (both sides empty).
            return AlignmentConfidence(
                lengthRatio: cn > 0 ? Double.greatestFiniteMagnitude : 1,
                matchRatio: cn > 0 ? 0 : 1,
                unmatchedFraction: cn > 0 ? Double.greatestFiniteMagnitude : 0,
                baselineTokenCount: 0
            )
        }
        let keepCount = edits.reduce(into: 0) { if $1.kind == .keep { $0 += 1 } }
        let insertCount = edits.reduce(into: 0) { if $1.kind == .insert { $0 += 1 } }
        let deleteCount = edits.reduce(into: 0) { if $1.kind == .delete { $0 += 1 } }
        return AlignmentConfidence(
            lengthRatio: Double(cn) / Double(bn),
            matchRatio: Double(2 * keepCount) / Double(bn + cn),
            unmatchedFraction: Double(insertCount + deleteCount) / Double(bn),
            baselineTokenCount: bn
        )
    }

    /// Whether `confidence` describes a degenerate (untrustworthy) alignment
    /// — fail closed. Any single breached threshold is sufficient; this is
    /// deliberately an OR, not a weighted score, so a chatbot reply that
    /// happens to be close to baseline length (translation of similar
    /// length) is still caught by `matchRatio`/`unmatchedFraction` alone.
    public static func isDegenerate(_ confidence: AlignmentConfidence) -> Bool {
        guard confidence.baselineTokenCount >= shortUtteranceFloorTokens else { return false }
        return confidence.lengthRatio < lengthRatioMin
            || confidence.lengthRatio > lengthRatioMax
            || confidence.matchRatio < matchRatioMin
            || confidence.unmatchedFraction > unmatchedFractionMax
    }
}
