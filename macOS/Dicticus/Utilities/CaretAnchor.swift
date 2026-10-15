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
    }

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
            result.caret = caretRect(element)
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

    private nonisolated static func caretRect(_ element: AXUIElement) -> CGRect? {
        guard let v = attribute(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(v) == AXValueGetTypeID(),
              AXValueGetType(v as! AXValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(v as! AXValue, .cfRange, &range) else { return nil }

        if let rect = bounds(of: range, in: element), usableCaret(rect) { return rect }

        // End-of-text carets often report no bounds: use the previous character's trailing edge.
        if range.length == 0, range.location > 0,
           let prev = bounds(of: CFRange(location: range.location - 1, length: 1), in: element),
           usableCaret(prev) {
            return CGRect(x: prev.maxX, y: prev.minY, width: 0, height: prev.height)
        }
        return nil
    }

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

    private nonisolated static func usableCaret(_ r: CGRect) -> Bool {
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
