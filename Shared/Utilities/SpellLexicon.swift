import Foundation
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Quick task 260723-sx1: the "is this token a known word" seam criterion A
/// (`EditGuard`'s non-word-repair exemption) needs to answer "is `old` a
/// known word / is `new` a known word".
///
/// Planner decision (stated in the plan's objective, restated here as the
/// binding rationale for future readers of this type): platform spell
/// checkers (`NSSpellChecker` on macOS, `UITextChecker` on iOS) behind this
/// protocol, augmented with `DefaultLexicon`/`PersonalLexicon` replacement
/// VALUES (those are, by construction, known-good words — the corrected
/// side of every dictionary entry) plus the per-utterance `dictProtected`
/// set (handled by the caller, not this type).
///
/// Trade-off, stated plainly: the DANGEROUS failure direction of criterion A
/// is a REAL dictated word misread by this lexicon as a non-word (that
/// wrongly opens it to "repair"). A shippable embedded frequency list is
/// exactly wrong for German — compounds and inflected forms
/// (`Organisationseinheit`, `Fusszeile`, `aufgefahren`) are common,
/// productive, and impossible to enumerate, but they are exactly what the
/// PLATFORM's spell checker covers natively (it ships the OS's own German/
/// English dictionaries) at zero added binary size. The price: a
/// serialized, memoized lookup hop (bounded — only substitute pairs that
/// already survived steps 1-6 of `classifySubstitute` ever reach this
/// query) and this protocol seam so tests and the harness stay
/// deterministic. Paid once, small.
public protocol SpellLexicon: Sendable {
    func isKnownWord(_ text: String, language: String) -> Bool
}

/// The production implementation: `NSSpellChecker` (macOS) / `UITextChecker`
/// (iOS), augmented with the static replacement-value vocabulary from
/// `DefaultLexicon` + (Debug/Debug-Recorder builds only) `PersonalLexicon`.
///
/// Serialization: `isKnownWord` is called exclusively from `EditGuard`'s
/// `@MainActor`-isolated classification functions (its only call site in
/// this codebase — the harness's `Harness` entry point and every XCTest
/// invocation of `EditGuard.apply` are themselves `@MainActor`), so every
/// platform query already lands on the main thread/actor by construction —
/// exactly what `NSSpellChecker` requires (Apple's documented main-thread-
/// only contract) — with NO additional queue hop needed at the call site.
/// The internal `NSLock`-protected memoization cache is defense-in-depth
/// for any future caller that is NOT already `@MainActor`: a lock-protected
/// dictionary is trivially safe to call from any thread, and a synchronous
/// hop here can never deadlock because `CleanupService`'s LLM inference
/// (the expensive work upstream of `EditGuard.apply`) runs off-main, and
/// main is never blocked waiting on cleanup — so there is no thread that
/// could be holding this lock while ALSO waiting on the caller.
public final class PlatformSpellLexicon: SpellLexicon, @unchecked Sendable {
    public static let shared = PlatformSpellLexicon()

    private let lock = NSLock()
    private var cache: [String: Bool] = [:]
    private let augmentation: Set<String>

    /// Standard idioms/loanwords the platform spell checkers false-negative
    /// on but that are real, known words — never eligible for criterion A's
    /// non-word-repair exemption. Case-insensitive, like every other
    /// augmentation entry.
    ///
    /// - "puncto": 260723-sx1's flagged case #3 (cleanup-2026-07-10.jsonl:26)
    ///   — "in puncto Schulungsmaterial" ("regarding X", a standard
    ///   Latin-derived German idiom) was NOT flagged by the platform
    ///   checker's dictionary, so EditGuard's criterion A misread it as a
    ///   non-word and "repaired" it to "Punkt" — a wrongful edit. That
    ///   fixture was left AS-IS pending this decision at the time.
    static let idiomKnownWords: Set<String> = ["puncto"]

    init(extraAugmentation: Set<String> = []) {
        var aug = Set<String>()
        for value in DefaultLexicon.entries.values {
            for word in value.split(whereSeparator: { $0.isWhitespace }) {
                aug.insert(word.lowercased())
            }
        }
        #if PERSONAL_LEXICON
        for value in PersonalLexicon.entries.values {
            for word in value.split(whereSeparator: { $0.isWhitespace }) {
                aug.insert(word.lowercased())
            }
        }
        #endif
        for word in Self.idiomKnownWords { aug.insert(word) }
        for word in extraAugmentation { aug.insert(word.lowercased()) }
        self.augmentation = aug
    }

    public func isKnownWord(_ text: String, language: String) -> Bool {
        let lower = text.lowercased()
        let key = "\(language):\(lower)"

        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let result: Bool
        if augmentation.contains(lower) || hasAugmentedConstituent(lower) {
            result = true
        } else {
            result = Self.platformKnown(text, language: language)
        }

        lock.lock()
        cache[key] = result
        lock.unlock()
        return result
    }

    /// Follow-up (260723-sx1, R6 compound-constituent closure): a
    /// hyphenated compound counts as known when ANY hyphen-separated
    /// constituent (case-insensitive) is itself an augmented term — e.g.
    /// `"MüraX-Verhalten"` contains the augmented brand `"MüraX"`, so the
    /// whole compound is known and criterion A's non-word-repair exemption
    /// can never fire on it (a dictionary/PersonalLexicon term must never
    /// be "repairable", per the plan's own R6 requirement, and a compound
    /// BUILT FROM one is the same case — the constituent IS the protected
    /// term, just with a suffix glued on by German compounding). Deliberately
    /// scoped to the AUGMENTATION check only, never consulted by
    /// `platformKnown` — the platform spell checker's own compound handling
    /// (if any) is untouched.
    private func hasAugmentedConstituent(_ lower: String) -> Bool {
        guard lower.contains("-") else { return false }
        return lower.split(separator: "-").contains { augmentation.contains(String($0)) }
    }

    private static func platformKnown(_ text: String, language: String) -> Bool {
        #if canImport(AppKit)
        let checker = NSSpellChecker.shared
        let checkerLanguage = language.hasPrefix("de") ? "de" : "en"
        let range = checker.checkSpelling(of: text, startingAt: 0, language: checkerLanguage, wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
        return range.length == 0
        #elseif canImport(UIKit)
        let checker = UITextChecker()
        let checkerLanguage = language.hasPrefix("de") ? "de" : "en"
        let range = checker.rangeOfMisspelledWord(in: text, range: NSRange(location: 0, length: (text as NSString).length), startingAt: 0, wrap: false, language: checkerLanguage)
        return range.location == NSNotFound
        #else
        return true
        #endif
    }
}
