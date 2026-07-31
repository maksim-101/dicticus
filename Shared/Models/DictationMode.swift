import Foundation

/// Dictation mode — determines which pipeline processes the transcription.
/// Per D-12: Both registered in Phase 3. Per D-13: AI cleanup is a no-op stub.
public enum DictationMode: String, Sendable, CaseIterable {
    case plain
    case aiCleanup  // Wired to LLM pipeline in Phase 4
}
