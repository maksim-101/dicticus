import AppKit
import ApplicationServices
import CoreGraphics

/// Read-only Accessibility lookup of where the user is typing (Phase 51, D-09).
///
/// Every call here blocks on IPC with another process, so callers run it off the main actor.
/// Values come from arbitrary third-party apps: each one is type-checked before use.
enum CaretAnchor {

    nonisolated static let messagingTimeoutSeconds: Float = 0.25

    /// Rects in Accessibility coordinates (top-left origin of the primary display).
    struct Candidates: Sendable, Equatable {
        var caret: CGRect?
        var element: CGRect?
        var window: CGRect?
        #if DEBUG_RECORDER
        var trace: Trace?
        #endif
    }

    /// Where `Candidates.caret` came from.
    enum CaretSource: String, Sendable {
        case range
        case prevChar = "prev_char"
        case none
    }

    /// The caret rect chosen from the range bounds and, for an empty range after text, the
    /// previous character's trailing edge. `previousBounds` is only evaluated when needed.
    nonisolated static func chooseCaret(
        range: CFRange, rangeBounds: CGRect?, previousBounds: () -> CGRect?
    ) -> (rect: CGRect?, source: CaretSource) {
        if let rangeBounds, usableCaret(rangeBounds) { return (rangeBounds, .range) }

        // End-of-text carets often report no bounds: use the previous character's trailing edge.
        if range.length == 0, range.location > 0, let prev = previousBounds(), usableCaret(prev) {
            return (CGRect(x: prev.maxX, y: prev.minY, width: 0, height: prev.height), .prevChar)
        }
        return (nil, .none)
    }

    #if DEBUG_RECORDER
    /// Raw Accessibility evidence behind one caret (Phase 51 plan 08). Rects, indices and a
    /// role identifier only: no attribute that returns document text is ever read.
    struct Trace: Sendable, Equatable {
        var caretSource: String?
        var rangeRect: CGRect?
        var previousCharacterRect: CGRect?
        var selectionLocation: Int?
        var selectionLength: Int?
        var lineStart: Int?
        var elementRole: String?
    }
    #endif

    nonisolated static func focusedElement(
        pid: pid_t, timeout: Float = messagingTimeoutSeconds
    ) -> (element: AXUIElement?, app: AXUIElement) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        guard let v = attribute(app, kAXFocusedUIElementAttribute), CFGetTypeID(v) == AXUIElementGetTypeID() else {
            return (nil, app)
        }
        let el = v as! AXUIElement
        AXUIElementSetMessagingTimeout(el, timeout)
        return (el, app)
    }

    nonisolated static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &v) == .success ? v : nil
    }

    nonisolated static func resolve(pid: pid_t) -> Candidates {
        let (element, app) = focusedElement(pid: pid)
        var result = Candidates()
        if let element {
            #if DEBUG_RECORDER
            var trace = Trace()
            result.caret = caretRect(element, trace: &trace)
            if let role = attribute(element, kAXRoleAttribute), CFGetTypeID(role) == CFStringGetTypeID() {
                trace.elementRole = role as? String
            }
            result.trace = trace
            #else
            result.caret = caretRect(element)
            #endif
            result.element = frame(of: element)
        }
        if let w = attribute(app, kAXFocusedWindowAttribute), CFGetTypeID(w) == AXUIElementGetTypeID() {
            let window = w as! AXUIElement
            AXUIElementSetMessagingTimeout(window, messagingTimeoutSeconds)
            result.window = frame(of: window)
        }
        if result.window == nil {
            result.window = onScreenWindowBounds(pid: pid)
        }
        return result
    }

    // MARK: - Caret

    private nonisolated static func selectedRange(of element: AXUIElement) -> CFRange? {
        guard let v = attribute(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(v) == AXValueGetTypeID(),
              AXValueGetType(v as! AXValue) == .cfRange else { return nil }
        var range = CFRange()
        return AXValueGetValue(v as! AXValue, .cfRange, &range) ? range : nil
    }

    #if !DEBUG_RECORDER
    private nonisolated static func caretRect(_ element: AXUIElement) -> CGRect? {
        guard let range = selectedRange(of: element) else { return nil }
        return chooseCaret(
            range: range,
            rangeBounds: bounds(of: range, in: element),
            previousBounds: { bounds(of: CFRange(location: range.location - 1, length: 1), in: element) }
        ).rect
    }
    #else
    /// Same decision as the release path, but every read happens eagerly and is kept in `trace`.
    private nonisolated static func caretRect(_ element: AXUIElement, trace: inout Trace) -> CGRect? {
        guard let range = selectedRange(of: element) else {
            trace.caretSource = CaretSource.none.rawValue
            return nil
        }
        trace.selectionLocation = range.location
        trace.selectionLength = range.length
        let rangeBounds = bounds(of: range, in: element)
        let previous = range.location > 0
            ? bounds(of: CFRange(location: range.location - 1, length: 1), in: element) : nil
        trace.rangeRect = rangeBounds
        trace.previousCharacterRect = previous
        trace.lineStart = lineStart(containing: range.location, in: element)
        let chosen = chooseCaret(range: range, rangeBounds: rangeBounds, previousBounds: { previous })
        trace.caretSource = chosen.source.rawValue
        return chosen.rect
    }

    private nonisolated static func lineStart(containing index: Int, in element: AXUIElement) -> Int? {
        var line: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXLineForIndexParameterizedAttribute as CFString, NSNumber(value: index), &line
        ) == .success, let line, CFGetTypeID(line) == CFNumberGetTypeID(), let lineNo = (line as? NSNumber)?.intValue
        else { return nil }
        var out: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXRangeForLineParameterizedAttribute as CFString, NSNumber(value: lineNo), &out
        ) == .success, let out, CFGetTypeID(out) == AXValueGetTypeID(),
              AXValueGetType(out as! AXValue) == .cfRange else { return nil }
        var range = CFRange()
        return AXValueGetValue(out as! AXValue, .cfRange, &range) ? range.location : nil
    }
    #endif

    private nonisolated static func bounds(of range: CFRange, in element: AXUIElement) -> CGRect? {
        var r = range
        guard let param = AXValueCreate(.cfRange, &r) else { return nil }
        var out: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, param, &out
        ) == .success, let out, CFGetTypeID(out) == AXValueGetTypeID(),
              AXValueGetType(out as! AXValue) == .cgRect else { return nil }
        var rect = CGRect.zero
        return AXValueGetValue(out as! AXValue, .cgRect, &rect) ? rect : nil
    }

    nonisolated static func usableCaret(_ r: CGRect) -> Bool {
        r.origin.x.isFinite && r.origin.y.isFinite && r.width.isFinite && r.height.isFinite && r.height > 0
    }

    // MARK: - Frames

    private nonisolated static func frame(of element: AXUIElement) -> CGRect? {
        guard let p = attribute(element, kAXPositionAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), AXValueGetType(p as! AXValue) == .cgPoint,
              let s = attribute(element, kAXSizeAttribute),
              CFGetTypeID(s) == AXValueGetTypeID(), AXValueGetType(s as! AXValue) == .cgSize else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &origin),
              AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        let rect = CGRect(origin: origin, size: size)
        let finite = [rect.origin.x, rect.origin.y, rect.width, rect.height].allSatisfy(\.isFinite)
        return finite && rect.width > 0 && rect.height > 0 ? rect : nil
    }

    private nonisolated static func onScreenWindowBounds(pid: pid_t) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dict as CFDictionary),
                  rect.width > 0, rect.height > 0 else { continue }
            return rect
        }
        return nil
    }
}
