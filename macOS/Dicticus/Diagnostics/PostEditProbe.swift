#if DEBUG_RECORDER
// PostEditProbe — quick 261003-jvq. After a delivered paste, reads the target text field's
// Accessibility attributes (never sets one) and logs whether the user edits the pasted span.
// Output: ~/Library/Application Support/Dicticus/DebugRecordings/postedit-YYYY-MM-DD.jsonl (UTC),
// 14-day retention. Pure logic lives in PostEditDiff; this file is the I/O half.

import Foundation
@preconcurrency import ApplicationServices

public actor PostEditProbe {

    public static let shared = PostEditProbe()

    private let directoryURL: URL
    private let retentionDays: Int = 14
    private var hasPurgedThisLaunch = false

    private init() {
        let fm = FileManager.default
        let appSupport = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support")

        self.directoryURL = appSupport
            .appendingPathComponent("Dicticus", isDirectory: true)
            .appendingPathComponent("DebugRecordings", isDirectory: true)
    }

    // MARK: - Arm

    private struct Base {
        let pasteTs: String
        let dictationTs: String?
        let dictationEmission: Int?
        let bundleID: String?
        let mode: String
        let pastedWords: Int
        let secureInputEnabled: Bool
    }

    func arm(pasted: String, mode: String, pid: pid_t?, bundleID: String?,
             secureInputEnabled: Bool, pasteDate: Date) async {
        ensureDirectory()
        purgeIfNeeded()

        var dictationTs: String?
        var dictationEmission: Int?
        // 261003-jvq: read-only use of the recorder's last record, solely to link this paste to its dictation.
        if let rec = await DebugRecorder.shared.lastRecordForTests, rec.steps.finalStage?.text == pasted {
            dictationTs = rec.ts
            dictationEmission = rec.emission_counter
        }
        let pastedTokens = PostEditDiff.tokenize(pasted)
        let base = Base(
            pasteTs: DebugRecorder.iso8601Timestamp(pasteDate), dictationTs: dictationTs,
            dictationEmission: dictationEmission, bundleID: bundleID, mode: mode,
            pastedWords: pastedTokens.count, secureInputEnabled: secureInputEnabled)

        if PostEditDiff.exclusion(bundleID: bundleID, role: nil, subrole: nil) == .excludedApp {
            write(base, outcome: .excludedApp)
            return
        }

        let t0 = Date()
        func elapsed() -> Double { Date().timeIntervalSince(t0) * 1000 }

        guard let pid, let focused = Self.focusedElement(pid: pid).element else {
            write(base, outcome: .noFocusedElement, axMs: elapsed())
            return
        }
        let role = Self.stringAttr(focused, kAXRoleAttribute)
        let subrole = Self.stringAttr(focused, kAXSubroleAttribute)
        if PostEditDiff.exclusion(bundleID: nil, role: role, subrole: subrole) == .secure {
            write(base, outcome: .secure, role: role, subrole: subrole, axMs: elapsed())
            return
        }
        if pastedTokens.count < PostEditDiff.minPastedTokens {
            write(base, outcome: .spanNotFound, reason: "too_short", role: role, subrole: subrole, axMs: elapsed())
            return
        }
        let numChars = Self.intAttr(focused, kAXNumberOfCharactersAttribute)
        if let numChars, numChars > PostEditDiff.fieldCapUTF16 {
            write(base, outcome: .spanNotFound, reason: "too_large", role: role, subrole: subrole,
                  fieldUTF16: numChars, axMs: elapsed())
            return
        }
        guard let value = Self.stringAttr(focused, kAXValueAttribute), !value.isEmpty else {
            write(base, outcome: .noTextValue, role: role, subrole: subrole, axMs: elapsed())
            return
        }
        let fieldUTF16 = value.utf16.count
        if fieldUTF16 > PostEditDiff.fieldCapUTF16 {
            write(base, outcome: .spanNotFound, reason: "too_large", role: role, subrole: subrole,
                  fieldUTF16: fieldUTF16, axMs: elapsed())
            return
        }
        let caret = Self.caretLocation(focused)
        let result = PostEditDiff.locateAtPaste(
            pasted: pasted, field: value, fieldTokens: PostEditDiff.tokenize(value), caretUTF16: caret)
        let axMs = elapsed()
        switch result {
        case .failure(let failure):
            write(base, outcome: .spanNotFound, reason: failure.rawValue, role: role, subrole: subrole,
                  fieldUTF16: fieldUTF16, axMs: axMs)
        case .success(let located):
            write(base, outcome: .unchanged, located: true, matchKind: located.matchKind, end: "paste",
                  role: role, subrole: subrole, fieldUTF16: fieldUTF16, axMs: axMs)
        }
    }

    // MARK: - Accessibility reads (read-only; no attribute is ever set)

    private static func focusedElement(pid: pid_t) -> (element: AXUIElement?, app: AXUIElement) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, PostEditDiff.axMessagingTimeoutSeconds)
        guard let v = copy(app, kAXFocusedUIElementAttribute), CFGetTypeID(v) == AXUIElementGetTypeID() else {
            return (nil, app)
        }
        let el = v as! AXUIElement
        AXUIElementSetMessagingTimeout(el, PostEditDiff.axMessagingTimeoutSeconds)
        return (el, app)
    }

    private static func copy(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
    }

    private static func stringAttr(_ e: AXUIElement, _ name: String) -> String? {
        copy(e, name) as? String
    }

    private static func intAttr(_ e: AXUIElement, _ name: String) -> Int? {
        (copy(e, name) as? NSNumber)?.intValue
    }

    private static func caretLocation(_ e: AXUIElement) -> Int? {
        guard let v = copy(e, kAXSelectedTextRangeAttribute), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var r = CFRange()
        return AXValueGetValue(v as! AXValue, .cfRange, &r) ? r.location : nil
    }

    // MARK: - Record writing

    private func write(_ base: Base, outcome: PostEditDiff.Outcome, reason: String? = nil,
                       located: Bool = false, matchKind: PostEditDiff.MatchKind? = nil, end: String? = nil,
                       role: String? = nil, subrole: String? = nil, fieldUTF16: Int? = nil, axMs: Double = 0) {
        let record = PostEditDiff.Record(
            ts: DebugRecorder.iso8601Timestamp(), paste_ts: base.pasteTs,
            dictation_ts: base.dictationTs, dictation_emission: base.dictationEmission,
            bundle_id: base.bundleID, mode: base.mode, pasted_words: base.pastedWords,
            outcome: outcome, reason: reason, located_at_paste: located, match_kind: matchKind, end: end,
            polls: 0, located_polls: 0, observed_ms: nil, last_located_ms: nil, ax_ms_max: axMs,
            role: role, subrole: subrole, field_utf16: fieldUTF16,
            secure_input_enabled: base.secureInputEnabled, changes: nil, changes_truncated: nil,
            word_edits: 0, observable_edit: false)
        guard let data = PostEditDiff.encodeLine(record) else { return }
        appendData(data)
    }

    // MARK: - Plumbing (mirrors PasteProbe)

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func currentJsonlURL() -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return directoryURL.appendingPathComponent("postedit-\(f.string(from: Date())).jsonl")
    }

    private func appendData(_ data: Data) {
        let url = currentJsonlURL()
        if FileManager.default.fileExists(atPath: url.path) {
            if let h = try? FileHandle(forWritingTo: url) {
                defer { try? h.close() }
                try? h.seekToEnd()
                try? h.write(contentsOf: data)
            }
        } else {
            try? data.write(to: url)
        }
    }

    private func purgeIfNeeded() {
        guard !hasPurgedThisLaunch else { return }
        hasPurgedThisLaunch = true
        let cutoff = Date().addingTimeInterval(-Double(retentionDays * 86_400))
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: directoryURL, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        for entry in entries where entry.lastPathComponent.hasPrefix("postedit-") {
            if let mod = try? entry.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               mod < cutoff {
                try? fm.removeItem(at: entry)
            }
        }
    }
}

#endif
