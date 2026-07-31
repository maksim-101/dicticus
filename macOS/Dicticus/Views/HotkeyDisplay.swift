// HotkeyDisplay.swift
// Pure formatter for the Home status hotkey subline and its VoiceOver-label sibling (D-07).
//
// All inputs are injected as plain strings so this module is testable without instantiating
// a View, reading KeyboardShortcuts.getShortcut, or touching ModifierHotkeyListener.
// The "reflects live bindings" requirement (D-07) is intentionally NOT surfaced as visible
// UI copy — the caller (HomePane) is responsible for reactive re-rendering on rebind.
//
// No SwiftUI import needed: this is a pure Swift value-type with no framework dependencies.

import Foundation

enum HotkeyDisplay {

    // MARK: - StatusState

    /// Driving state for the VoiceOver status-label string.
    enum StatusState {
        case ready
        case recording
        case needsPermission
    }

    // MARK: - Public API

    /// Returns the hotkey subline string shown below the status headline on the Home tab.
    ///
    /// - Parameters:
    ///   - plainStandard: Display string for the plain-dictation shortcut (e.g. "⌃⇧S"), or nil if unset.
    ///   - cleanupStandard: Display string for the AI-cleanup shortcut (e.g. "⌃⇧D"), or nil if unset.
    /// - Returns: UI-SPEC–exact copy for the D-07 hotkey subline.
    static func hotkeySubline(plainStandard: String?, cleanupStandard: String?) -> String {
        switch (plainStandard, cleanupStandard) {
        case let (plain?, cleanup?):
            return "Press \(plain) to dictate · \(cleanup) with AI cleanup"
        case let (plain?, nil):
            return "Press \(plain) to dictate"
        case let (nil, cleanup?):
            return "Press \(cleanup) with AI cleanup"
        case (nil, nil):
            return "Set a hotkey in Settings →"
        }
    }

    /// Returns the VoiceOver accessibility label for the Home status HStack container.
    ///
    /// - Parameters:
    ///   - state: The current pipeline / permission state.
    ///   - plainStandard: Display-glyph string for plain dictation (e.g. "⌃⇧S"), or nil if unset.
    ///   - cleanupStandard: Display-glyph string for AI cleanup (e.g. "⌃⇧D"), or nil if unset.
    /// - Returns: UI-SPEC–exact VoiceOver label string (Accessibility Contract D-16/D-17).
    static func voiceOverStatusLabel(
        state: StatusState,
        plainStandard: String?,
        cleanupStandard: String?
    ) -> String {
        switch state {
        case .recording:
            return "Status: Recording."
        case .needsPermission:
            return "Status: Needs Permission. Tap to open System Settings."
        case .ready:
            var label = "Status: Ready."
            let parts = [
                plainStandard.map { "Plain dictation \(spelledOut($0))" },
                cleanupStandard.map { "AI cleanup \(spelledOut($0))" }
            ].compactMap { $0 }
            if !parts.isEmpty {
                label += " \(parts.joined(separator: ", "))."
            }
            return label
        }
    }

    // MARK: - Internal helpers

    /// Converts a glyph shortcut string (e.g. "⌃⇧S") to a spoken hyphenated form
    /// (e.g. "Control-Shift-S") matching the UI-SPEC Accessibility Contract example
    /// "Plain dictation Control-Shift-S, AI cleanup Control-Shift-D."
    ///
    /// Supported modifier glyphs: ⌃ (Control), ⇧ (Shift), ⌘ (Command), ⌥ (Option).
    /// The trailing key character is uppercased for spoken clarity.
    static func spelledOut(_ glyph: String) -> String {
        var modifiers: [String] = []
        var remaining = glyph

        let glyphMap: [(Character, String)] = [
            ("⌃", "Control"),
            ("⇧", "Shift"),
            ("⌘", "Command"),
            ("⌥", "Option")
        ]

        for (glyph, name) in glyphMap {
            if remaining.contains(glyph) {
                modifiers.append(name)
                remaining = remaining.replacingOccurrences(of: String(glyph), with: "")
            }
        }

        let key = remaining.uppercased()
        let parts = modifiers + (key.isEmpty ? [] : [key])
        return parts.joined(separator: "-")
    }
}
