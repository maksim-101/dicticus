import Foundation

/// Phase 38 Plan 01 (CTXFMT-01, approved scope extension — see 38-01-SUMMARY.md
/// "Deviations"): `context:` was added to the required `cleanup(...)` method so a
/// resolved `DictationContext` actually reaches `CleanupPrompt.build(context:)`
/// inside every conformer's implementation — without this, 38-02's fidelity gate
/// would validate prompt bodies production could never send (R7, the
/// vacuous-gate anti-pattern this project has shipped bugs behind twice).
@MainActor
public protocol CleanupProvider: Sendable {
    var isLoaded: Bool { get }
    func cleanup(text: String, language: String, dictionaryContext: [String: String]?, context: DictationContext) async -> String
}

public extension CleanupProvider {
    /// Back-compat convenience overload (protocol churn kept minimal per
    /// D-01): every call site written before Phase 38 Plan 01 — and any
    /// future caller with no `DictationContext` to thread (e.g. the iOS
    /// background-delivery batch-cleanup path in `DictationViewModel`,
    /// which has no press-time bundle-ID capture) — keeps compiling
    /// unchanged and gets `.default` behavior, byte-identical to
    /// pre-Phase-38 output.
    func cleanup(text: String, language: String, dictionaryContext: [String: String]? = nil) async -> String {
        await cleanup(text: text, language: language, dictionaryContext: dictionaryContext, context: .default)
    }
}
