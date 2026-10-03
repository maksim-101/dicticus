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

    private struct Pending {
        let app: AXUIElement
        let element: AXUIElement
        var session: PostEditDiff.Session
        let partial: PostEditDiff.Record
        let pasteInstant: Date
        let generation: Int
        var axMsMax: Double
        var lastLocatedMs: Int?
        var pollTask: Task<Void, Never>?
    }

    private var pending: Pending?
    private var generationCounter = 0

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
        if pending != nil { await finalizePending(end: .nextDictation, readFirst: true) }

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

        guard let pid else {
            write(base, outcome: .noFocusedElement, axMs: elapsed())
            return
        }
        let (focusedOrNil, app) = Self.focusedElement(pid: pid)
        guard let focused = focusedOrNil else {
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
        let fieldTokens = PostEditDiff.tokenize(value)
        let result = PostEditDiff.locateAtPaste(
            pasted: pasted, field: value, fieldTokens: fieldTokens, caretUTF16: caret)
        let axMs = elapsed()
        switch result {
        case .failure(let failure):
            write(base, outcome: .spanNotFound, reason: failure.rawValue, role: role, subrole: subrole,
                  fieldUTF16: fieldUTF16, axMs: axMs)
        case .success(let located):
            if pending != nil { finish(end: .nextDictation) }
            generationCounter += 1
            let generation = generationCounter
            var p = Pending(
                app: app, element: focused, session: PostEditDiff.Session(
                    pasted: pastedTokens.map(\.text),
                    anchor: PostEditDiff.Anchor(range: located.range, fieldTokens: fieldTokens)),
                partial: makeRecord(base, outcome: .unchanged, located: true, matchKind: located.matchKind,
                                    end: "paste", role: role, subrole: subrole, fieldUTF16: fieldUTF16, axMs: axMs),
                pasteInstant: pasteDate, generation: generation, axMsMax: axMs, lastLocatedMs: nil, pollTask: nil)
            p.pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(PostEditDiff.pollIntervalMs))
                    if Task.isCancelled { return }
                    guard let self, await self.poll(generation: generation) else { return }
                }
            }
            pending = p
        }
    }

    // MARK: - Observation

    /// Finalizes the pending observation, if any. `readFirst` takes one last read of the field;
    /// Revert to Raw passes false so no Accessibility call precedes its paste.
    func finalizePending(end: PostEditDiff.EndReason, readFirst: Bool) async {
        guard let p = pending else { return }
        if readFirst { ingestRead(generation: p.generation) }
        finish(end: end)
    }

    /// One poll; returns whether the loop should continue.
    private func poll(generation: Int) -> Bool {
        guard let p = pending, p.generation == generation else { return false }
        if let end = ingestRead(generation: generation) {
            finish(end: end)
            return false
        }
        if Date().timeIntervalSince(p.pasteInstant) >= Double(PostEditDiff.observationLimitSeconds) {
            finish(end: .timeout)
            return false
        }
        return true
    }

    @discardableResult
    private func ingestRead(generation: Int) -> PostEditDiff.EndReason? {
        guard var p = pending, p.generation == generation else { return nil }
        let t0 = Date()
        let read = Self.readField(app: p.app, element: p.element)
        let axMs = Date().timeIntervalSince(t0) * 1000
        let elapsedMs = Int(t0.timeIntervalSince(p.pasteInstant) * 1000)
        let before = p.session.locatedPolls
        let end = p.session.ingest(read, elapsedMs: elapsedMs)
        if p.session.locatedPolls > before { p.lastLocatedMs = elapsedMs }
        p.axMsMax = max(p.axMsMax, axMs)
        pending = p
        return end
    }

    private func finish(end: PostEditDiff.EndReason) {
        guard let p = pending else { return }
        pending = nil
        p.pollTask?.cancel()
        let record = p.partial.finalized(
            result: p.session.result(), end: end, polls: p.session.polls, locatedPolls: p.session.locatedPolls,
            observedMs: Int(Date().timeIntervalSince(p.pasteInstant) * 1000), lastLocatedMs: p.lastLocatedMs,
            axMsMax: p.axMsMax, ts: DebugRecorder.iso8601Timestamp())
        if let data = PostEditDiff.encodeLine(record) { appendData(data) }
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

    /// Reads the stored element. Only the stored app element and its stored focused element are queried;
    /// the element returned by the focus check is compared, never queried.
    private static func readField(app: AXUIElement, element: AXUIElement) -> PostEditDiff.FieldRead {
        var v: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &v)
        if err == .invalidUIElement { return .gone }
        var tokens: [PostEditDiff.Token] = []
        if err == .success, let s = v as? String, s.utf16.count <= PostEditDiff.fieldCapUTF16 {
            tokens = PostEditDiff.tokenize(s)
        }
        let caret = caretLocation(element)
        let frontmost = (copy(app, kAXFrontmostAttribute) as? Bool) ?? false
        var stillFocused = false
        if frontmost, let f = copy(app, kAXFocusedUIElementAttribute) {
            stillFocused = CFEqual(f, element)
        }
        return .read(tokens: tokens, caretUTF16: caret, stillFocused: stillFocused)
    }

    // MARK: - Record writing

    private func makeRecord(_ base: Base, outcome: PostEditDiff.Outcome, reason: String? = nil,
                            located: Bool = false, matchKind: PostEditDiff.MatchKind? = nil, end: String? = nil,
                            role: String? = nil, subrole: String? = nil, fieldUTF16: Int? = nil,
                            axMs: Double = 0) -> PostEditDiff.Record {
        PostEditDiff.Record(
            ts: DebugRecorder.iso8601Timestamp(), paste_ts: base.pasteTs,
            dictation_ts: base.dictationTs, dictation_emission: base.dictationEmission,
            bundle_id: base.bundleID, mode: base.mode, pasted_words: base.pastedWords,
            outcome: outcome, reason: reason, located_at_paste: located, match_kind: matchKind, end: end,
            polls: 0, located_polls: 0, observed_ms: nil, last_located_ms: nil, ax_ms_max: axMs,
            role: role, subrole: subrole, field_utf16: fieldUTF16,
            secure_input_enabled: base.secureInputEnabled, changes: nil, changes_truncated: nil,
            word_edits: 0, observable_edit: false)
    }

    private func write(_ base: Base, outcome: PostEditDiff.Outcome, reason: String? = nil,
                       role: String? = nil, subrole: String? = nil, fieldUTF16: Int? = nil, axMs: Double = 0) {
        let record = makeRecord(base, outcome: outcome, reason: reason, role: role, subrole: subrole,
                                fieldUTF16: fieldUTF16, axMs: axMs)
        if let data = PostEditDiff.encodeLine(record) { appendData(data) }
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
