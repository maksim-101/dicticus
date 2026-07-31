import Foundation

/// App-level transcription result from the ASR pipeline.
///
/// Engine-agnostic value type that holds the final output of a transcription session.
/// Conforms to Sendable so it can safely cross actor boundaries (e.g., from transcription
/// task back to the main actor for UI updates).
struct DicticusTranscriptionResult: Sendable {
    /// Transcribed text output, trimmed of leading/trailing whitespace.
    let text: String
    /// Detected language code, restricted to "de" or "en" (D-13 in 02.1-CONTEXT.md).
    /// Parakeet TDT v3 does not output language codes; detection uses NLLanguageRecognizer post-hoc.
    let language: String
    /// Confidence score from 0.0 to 1.0, derived from ASR engine confidence score.
    /// Higher values indicate higher confidence that speech was present.
    let confidence: Float
}
