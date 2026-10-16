import CoreGraphics

/// Pure placement math for the live overlay panel (Phase 51, D-10/D-11).
/// Works in AppKit coordinates (bottom-left origin) once `appKitRect(fromAX:)` has run.
enum OverlayPlacement {

    struct ScreenGeometry: Sendable, Equatable {
        var frame: CGRect
        var visibleFrame: CGRect
    }

    enum Source: String, Sendable {
        case caret, element, window, screen
    }

    struct Placement: Sendable, Equatable {
        var origin: CGPoint
        var source: Source
        var flipped: Bool
        var visibleFrame: CGRect
    }

    /// Large-text-area rule: clearance below the window top (title and tab bar), above the window
    /// bottom, and the element-to-window height ratio that makes an element "large".
    nonisolated static let topInset: CGFloat = 44
    nonisolated static let bottomInset: CGFloat = 16
    nonisolated static let largeAreaRatio: CGFloat = 0.5

    /// Single-line field rule: with a caret, an element is one line when it is at most this many
    /// caret heights tall; without a caret, when it is at most `singleLineMaxHeight` points.
    nonisolated static let singleLineCaretMultiple: CGFloat = 3
    nonisolated static let singleLineMaxHeight: CGFloat = 60

    /// A caret whose midpoint lies farther than this outside the focused element (or the window,
    /// when there is no element) is a bogus rect from the app and is not used as an anchor.
    nonisolated static let caretContainmentTolerance: CGFloat = 24

    nonisolated static func isSingleLine(elementHeight: CGFloat, caretHeight: CGFloat?) -> Bool {
        elementHeight <= (caretHeight.map { $0 * singleLineCaretMultiple } ?? singleLineMaxHeight)
    }

    nonisolated static func appKitRect(fromAX ax: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: ax.minX, y: primaryScreenHeight - ax.maxY, width: ax.width, height: ax.height)
    }

    nonisolated static func screen(containing point: CGPoint, in screens: [ScreenGeometry]) -> ScreenGeometry? {
        screens.first { $0.frame.contains(point) }
    }

    /// Vertical position follows the caret line; horizontal position is `centreX`.
    nonisolated static func caretOrigin(
        anchor: CGRect, centreX: CGFloat, panel: CGSize, visible: CGRect, gap: CGFloat = 8
    ) -> (origin: CGPoint, flipped: Bool) {
        var y = anchor.maxY + gap
        var flipped = false
        if y + panel.height > visible.maxY {
            y = anchor.minY - gap - panel.height
            flipped = true
        }
        return (clamp(CGPoint(x: centreX - panel.width / 2, y: y), panel: panel, visible: visible), flipped)
    }

    nonisolated static func bottomCentreOrigin(
        on frame: CGRect, centreX: CGFloat? = nil, panel: CGSize, visible: CGRect, inset: CGFloat = 16
    ) -> CGPoint {
        clamp(CGPoint(x: (centreX ?? frame.midX) - panel.width / 2, y: frame.minY + inset), panel: panel, visible: visible)
    }

    nonisolated static func place(
        candidates: CaretAnchor.Candidates,
        panel: CGSize,
        screens: [ScreenGeometry],
        primaryScreenHeight: CGFloat,
        fallback: ScreenGeometry
    ) -> Placement {
        func converted(_ ax: CGRect?) -> CGRect? {
            guard let ax, [ax.origin.x, ax.origin.y, ax.width, ax.height].allSatisfy(\.isFinite) else { return nil }
            return appKitRect(fromAX: ax, primaryScreenHeight: primaryScreenHeight)
        }

        let window = converted(candidates.window)
        let element = converted(candidates.element)

        /// The panel is centred on the focused window in every app (host session 1). A window or
        /// element whose midpoint lies on another display does not count, so a stale rect cannot
        /// drag the panel away from the screen the user is typing on.
        func centreX(on target: ScreenGeometry) -> CGFloat {
            for rect in [window, element] {
                if let rect, rect.width > 0, rect.height > 0,
                   rect.midX >= target.frame.minX, rect.midX < target.frame.maxX { return rect.midX }
            }
            return target.visibleFrame.midX
        }

        /// A large text area (terminal pane, editor, document, mail compose) is an element taller than
        /// `largeAreaRatio` of its window. The panel goes to the half of the window opposite the caret
        /// line, so a growing input box is never covered (host session 2). The window must sit on the
        /// target display; otherwise the caret or element rule below applies.
        func largeAreaWindow(on target: ScreenGeometry) -> CGRect? {
            guard let window, let element, window.width > 0, window.height > 0,
                  window.midX >= target.frame.minX, window.midX < target.frame.maxX,
                  window.midY >= target.frame.minY, window.midY < target.frame.maxY,
                  element.height > window.height * largeAreaRatio,
                  // Each half must hold the panel, or the band lands on the caret (palette-style windows).
                  window.height / 2 >= panel.height + topInset else { return nil }
            return window
        }

        func topOfWindow(_ window: CGRect, on target: ScreenGeometry) -> CGPoint {
            clamp(CGPoint(x: centreX(on: target) - panel.width / 2, y: window.maxY - topInset - panel.height),
                  panel: panel, visible: target.visibleFrame)
        }

        /// The caret must lie in the focused element, else in the window. A container whose midpoint
        /// is on another display does not count (it is stale, see `centreX`), so it cannot veto a caret.
        func caretIsPlausible(_ caret: CGRect, on target: ScreenGeometry) -> Bool {
            let container = [element, window].compactMap { $0 }.first {
                $0.width > 0 && $0.height > 0 && target.frame.contains(CGPoint(x: $0.midX, y: $0.midY))
            }
            guard let container else { return true }
            return container.insetBy(dx: -caretContainmentTolerance, dy: -caretContainmentTolerance)
                .contains(CGPoint(x: caret.midX, y: caret.midY))
        }

        if let caret = converted(candidates.caret), caret.height > 0,
           let target = screen(containing: CGPoint(x: caret.midX, y: caret.midY), in: screens),
           caretIsPlausible(caret, on: target) {
            if let window = largeAreaWindow(on: target) {
                if caret.midY < window.midY {
                    return Placement(origin: topOfWindow(window, on: target), source: .caret, flipped: false,
                                     visibleFrame: target.visibleFrame)
                }
                let origin = bottomCentreOrigin(
                    on: window, centreX: centreX(on: target), panel: panel, visible: target.visibleFrame,
                    inset: bottomInset)
                return Placement(origin: origin, source: .caret, flipped: true, visibleFrame: target.visibleFrame)
            }
            // A single-line field (search or address bar) is kept clear as a whole (host session 2);
            // a tall text area such as a terminal pane or document keeps the caret line.
            var anchor = caret
            if let element, isSingleLine(elementHeight: element.height, caretHeight: caret.height),
               element.minY <= caret.midY, caret.midY <= element.maxY {
                anchor = CGRect(x: caret.minX, y: element.minY, width: caret.width, height: element.height)
            }
            let (origin, flipped) = caretOrigin(
                anchor: anchor, centreX: centreX(on: target), panel: panel, visible: target.visibleFrame)
            return Placement(origin: origin, source: .caret, flipped: flipped, visibleFrame: target.visibleFrame)
        }
        for (rect, source) in [(element, Source.element), (window, .window)] {
            guard let rect, rect.width > 0, rect.height > 0,
                  let target = screen(containing: CGPoint(x: rect.midX, y: rect.midY), in: screens) else { continue }
            if source == .element, let window = largeAreaWindow(on: target) {
                return Placement(origin: topOfWindow(window, on: target), source: source, flipped: false,
                                 visibleFrame: target.visibleFrame)
            }
            // A single-line field with no reported caret (e.g. a selected URL) is kept clear like one with a caret.
            if source == .element, isSingleLine(elementHeight: rect.height, caretHeight: nil) {
                let (origin, flipped) = caretOrigin(
                    anchor: rect, centreX: centreX(on: target), panel: panel, visible: target.visibleFrame)
                return Placement(origin: origin, source: source, flipped: flipped, visibleFrame: target.visibleFrame)
            }
            let origin = bottomCentreOrigin(
                on: rect, centreX: centreX(on: target), panel: panel, visible: target.visibleFrame)
            return Placement(origin: origin, source: source, flipped: false, visibleFrame: target.visibleFrame)
        }
        let origin = bottomCentreOrigin(on: fallback.visibleFrame, panel: panel, visible: fallback.visibleFrame, inset: 48)
        return Placement(origin: origin, source: .screen, flipped: false, visibleFrame: fallback.visibleFrame)
    }

    /// The lower bound wins when the panel is larger than the visible frame.
    private nonisolated static func clamp(_ p: CGPoint, panel: CGSize, visible: CGRect) -> CGPoint {
        CGPoint(
            x: max(visible.minX, min(p.x, visible.maxX - panel.width)),
            y: max(visible.minY, min(p.y, visible.maxY - panel.height))
        )
    }
}
