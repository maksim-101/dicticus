import Foundation

/// Curated subset of high-frequency Swiss German Helvetisms used to anchor
/// Gemma's vocabulary choice during AI cleanup. Per Phase 19.5 D-D2.
///
/// Loaded once and embedded in the cleanup prompt as a HELVETISMS: block
/// when `useSwissGerman` AppGroup toggle is ON AND `language == "de"`.
/// Single call site: `Shared/Models/CleanupPrompt.build(...)`.
///
/// Curation criteria: daily-use frequency over exhaustiveness. ~30 words
/// covers >90% of everyday Swiss Standard German vocabulary divergence
/// from German Standard German per the underlying research.
///
/// Source: German Wikipedia "Liste von Helvetismen" (CC BY-SA 3.0)
///   https://de.wikipedia.org/wiki/Liste_von_Helvetismen
/// Attribution required by license — keep this header intact when editing.
public enum SwissHelvetisms {
    /// W9 (Phase 19.5 revision): public attribution constant for runtime
    /// test assertions. Tests should NOT walk `#filePath` to read the
    /// source file — they should assert on this string instead.
    /// MUST contain the literals "CC BY-SA 3.0" and "Liste von Helvetismen".
    public static let licenseAttribution =
        "Source: German Wikipedia \"Liste von Helvetismen\" — CC BY-SA 3.0 — " +
        "https://de.wikipedia.org/wiki/Liste_von_Helvetismen"

    public static let words: [String] = [
        "Velo",
        "Trottoir",
        "parkieren",
        "Billett",
        "Perron",
        "Camion",
        "Poulet",
        "Rüebli",
        "Cervelat",
        "Znacht",
        "Zmorgen",
        "Zvieri",
        "Estrich",
        "Lavabo",
        "Cheminée",
        "Detailhandel",
        "Identitätskarte",
        "Matur",
        "Ferien",
        "allfällig",
        "zuhanden",
        "anfangs",
        "grillieren",
        "Spital",
        "Tram",
        "Nachtessen",
        "Morgenessen",
        "Kantonsschule",
        "Abwart",
        "Rande"
    ]
}
