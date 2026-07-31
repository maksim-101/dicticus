import Foundation

/// Curated subset of high-frequency Swiss German dialect FORMS that Gemma 4 E2B
/// has been observed to inject into AI-cleanup output when the speaker dictated
/// clean Standard High German. Per Phase 20.08 D-06..D-09.
///
/// Loaded once and consumed via `Set<String>` membership lookup by exactly one
/// call site: `Shared/Services/CleanupService.swift::gateLLMDialect`.
///
/// Distinct from `SwissHelvetisms.words` — that list is for substantive
/// helvetisms (Velo, Trottoir, parkieren) used as a prompt orthography anchor.
/// This list is for dialect FORMS (uf, hie, het, wahrschiinli) used for
/// post-LLM demotion when the model unsolicited-Swiss-ifies clean High German.
///
/// Curation: tokens drawn from the 2026-04-27 UAT failure transcript (D-11)
/// plus high-frequency Swiss German particles, auxiliaries, and orthographic
/// shifts. Homographs with Standard High German (e.g. "de", "sind") are
/// EXCLUDED to avoid false-positive demotions on legitimate German output.
///
/// Source: German Wikipedia "Schweizerdeutsch" (CC BY-SA 4.0)
///   https://de.wikipedia.org/wiki/Schweizerdeutsch
/// Attribution required by license — keep this header intact when editing.
public enum SwissDialectForms {

    /// Public attribution constant for runtime test assertions.
    /// MUST contain the literals "CC BY-SA 4.0" and "Schweizerdeutsch".
    public static let licenseAttribution =
        "Source: German Wikipedia \"Schweizerdeutsch\" — CC BY-SA 4.0 — " +
        "https://de.wikipedia.org/wiki/Schweizerdeutsch"

    /// Lowercased canonical forms. Single call site: CleanupService.gateLLMDialect.
    /// Target size: 30..50 entries.
    public static let tokens: [String] = [
        // 2026-04-27 UAT failure (verbatim Swiss output the gate must reject)
        "uf",            // High German "auf"
        "siite",         // "Seite" — vowel shift ei→ii
        "wahrschiinli",  // "wahrscheinlich" — ei→ii + -li
        "alli",          // "alle"
        "mini",          // "meine"
        "wuer",          // "wäre" (Bernese/Alemannic subjunctive)
        "het",           // "hat"
        "hie",           // "hier"
        "usfiltere",     // "ausfiltern"

        // High-frequency Swiss particles / auxiliaries
        "isch",          // "ist"
        "gsi",           // "gewesen"
        "gseh",          // "gesehen"
        "gha",           // "gehabt"
        "nid",           // "nicht"
        "nüt",           // "nichts"
        "öppis",         // "etwas"
        "öpper",         // "jemand"
        "dini",          // "deine"
        "sini",          // "seine"
        "üses",          // "unser"
        "iri",           // "ihre"
        "chönd",         // "können" (2pl)
        "händ",          // "haben" (1/3pl)
        "wänd",          // "wollen"
        "müend",         // "müssen"

        // Swiss vowel-shift / consonant markers
        "iikaufe",       // "einkaufen"
        "usgfloge",      // "ausgeflogen"
        "choschtet",     // "kostet"
        "chauft",        // "kauft"
        "gässe",         // "gegessen"
        "gschribe",      // "geschrieben"
        "gloffe",        // "gelaufen"
        "natürli",       // "natürlich"
        "speter",        // "später"
        "chliis",        // "klein"
        "chliins",       // "kleines"
        "beidne",        // "beiden"
        "biide",         // "beide"
        "büechli"        // "Büchlein"
    ]
}
