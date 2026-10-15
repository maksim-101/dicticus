import SwiftUI
import AppKit

/// What `HotkeyManager` needs from the live transcript overlay (Phase 51).
@MainActor
protocol LiveOverlayPresenting: AnyObject {
    /// Incremented by every real `show()`. Lets a release Task tell whether the panel it
    /// started with is still the current one before it hides.
    var currentSeq: Int { get }
    func show()
    func update(_ text: String)
    func setProcessing()
    func hide(reason: LiveOverlayHideReason)
}

enum LiveOverlayHideReason: String {
    case pasting, taskEnd, earlyReturn, demo
}

@MainActor
final class LiveOverlayModel: ObservableObject {
    enum Phase { case listening, processing }

    @Published var text = ""
    @Published var phase: Phase = .listening
    /// Read at every `show()`: an opaque fill replaces the glass sheen.
    @Published var reduceTransparency = false
    /// Read at every `show()`: no rise and no line slide, fade only.
    @Published var reduceMotion = false
}

/// The system accessibility settings the overlay honours, sampled once per `show()`.
struct OverlayAccessibilityFlags: Equatable {
    var reduceTransparency = false
    var reduceMotion = false

    @MainActor static func system() -> OverlayAccessibilityFlags {
        let workspace = NSWorkspace.shared
        return OverlayAccessibilityFlags(
            reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
            reduceMotion: workspace.accessibilityDisplayShouldReduceMotion)
    }
}

/// `NSHostingView` reports itself as an accessibility element regardless of `setAccessibilityElement`.
private final class SilentHostingView<Content: View>: NSHostingView<Content> {
    override func isAccessibilityElement() -> Bool { false }
}

/// Borderless, non-activating panel (D-12). It never becomes key or main and is only
/// ever ordered front with `orderFrontRegardless()`, so the paste target keeps focus.
final class LiveOverlayPanel: NSPanel {

    /// The visible glass pane. `OverlayPlacement` and the probe work on this rect.
    static let paneSize = CGSize(width: LiveOverlayView.width, height: LiveOverlayView.height)
    /// Transparent room around the pane so its radius-14, offset-7 shadow is never clipped.
    static let shadowMargin: CGFloat = 32
    static let size = CGSize(width: paneSize.width + shadowMargin * 2, height: paneSize.height + shadowMargin * 2)

    static let shadowRadius: CGFloat = 14
    static let shadowOffset = CGSize(width: 0, height: -7)
    static let shadowOpacity: Float = 0.28

    /// Black 8% in dark, 3.2% in light.
    static let glassTint = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return NSColor.black.withAlphaComponent(dark ? 0.08 : 0.08 * 0.4)
    }

    static func windowOrigin(forPaneOrigin origin: CGPoint) -> CGPoint {
        CGPoint(x: origin.x - shadowMargin, y: origin.y - shadowMargin)
    }

    let shadowView: NSView
    let glassView: NSGlassEffectView

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    @MainActor
    init(model: LiveOverlayModel, capturable: Bool = false) {
        let paneRect = CGRect(origin: CGPoint(x: Self.shadowMargin, y: Self.shadowMargin), size: Self.paneSize)

        let shadow = NSView(frame: paneRect)
        shadow.wantsLayer = true
        shadow.layer?.shadowPath = CGPath(
            roundedRect: shadow.bounds, cornerWidth: LiveOverlayView.cornerRadius,
            cornerHeight: LiveOverlayView.cornerRadius, transform: nil)
        shadow.layer?.shadowColor = NSColor.black.cgColor
        shadow.layer?.shadowOpacity = Self.shadowOpacity
        shadow.layer?.shadowRadius = Self.shadowRadius
        shadow.layer?.shadowOffset = Self.shadowOffset

        let host = SilentHostingView(rootView: LiveOverlayView(model: model))
        host.sizingOptions = []

        let glass = NSGlassEffectView(frame: paneRect)
        glass.cornerRadius = LiveOverlayView.cornerRadius
        glass.tintColor = Self.glassTint
        host.frame = glass.bounds
        glass.contentView = host

        let root = NSView(frame: CGRect(origin: .zero, size: Self.size))
        root.addSubview(shadow)
        root.addSubview(glass)
        // The panel is non-activating and never focused; VoiceOver must not announce it.
        for view in [root, shadow, glass, host] { view.setAccessibilityElement(false) }

        shadowView = shadow
        glassView = glass
        super.init(
            contentRect: CGRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        // D-18: dictated text stays out of screen sharing and recording. AppKit keeps `.none`
        // for good once it is set, so the one DEBUG exception must be decided before the first set.
        #if DEBUG
        let allowCapture = capturable || DicticusDefaults.suite.bool(forKey: "debugOverlayCapturable")
        #else
        let allowCapture = false
        #endif
        sharingType = allowCapture ? .readOnly : .none

        contentView = root
    }
}

@MainActor
final class LiveOverlayController: LiveOverlayPresenting {

    private static let entryDuration: TimeInterval = 0.42
    private static let exitDuration: TimeInterval = 0.36
    private static let riseDistance: CGFloat = 8
    private static let easing = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)

    private let targetAlpha: CGFloat
    private let model = LiveOverlayModel()
    private var panel: LiveOverlayPanel?
    private var visible = false
    private var shownAt = ContinuousClock.now
    #if DEBUG_RECORDER
    private var recordedShowSeq = 0
    #endif

    #if DEBUG
    var debugCapturable = false
    var debugAppearance: NSAppearance?
    #endif

    private(set) var currentSeq = 0

    /// Resolves the caret anchor for the frontmost app's pid. Injectable so a test gets a
    /// deterministic placement whichever app is frontmost.
    typealias CandidateProvider = @Sendable (pid_t?) async -> CaretAnchor.Candidates

    static let resolveCandidates: CandidateProvider = { pid in
        guard let pid, pid != ProcessInfo.processInfo.processIdentifier else { return CaretAnchor.Candidates() }
        return await Task.detached { CaretAnchor.resolve(pid: pid) }.value
    }

    private let candidateProvider: CandidateProvider
    private let accessibility: () -> OverlayAccessibilityFlags

    init(
        targetAlpha: CGFloat = 1,
        accessibility: @escaping () -> OverlayAccessibilityFlags = { OverlayAccessibilityFlags.system() },
        candidateProvider: @escaping CandidateProvider = LiveOverlayController.resolveCandidates
    ) {
        self.targetAlpha = targetAlpha
        self.accessibility = accessibility
        self.candidateProvider = candidateProvider
    }

    var isVisible: Bool { visible }

    var modelForTesting: LiveOverlayModel { model }
    var panelForTesting: LiveOverlayPanel? { panel }

    func show() {
        let flags = accessibility()
        model.text = ""
        model.phase = .listening
        model.reduceTransparency = flags.reduceTransparency
        model.reduceMotion = flags.reduceMotion

        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.shadowView.isHidden = flags.reduceTransparency
        #if DEBUG_RECORDER
        // A press during the previous paste's restore window re-shows the same panel; close the
        // superseded show so every recorded show keeps exactly one hide.
        if visible, recordedShowSeq == currentSeq {
            let shownMs = OverlayProbe.milliseconds(ContinuousClock.now - shownAt)
            let superseded = currentSeq
            Task { await OverlayProbe.shared.recordHide(seq: superseded, reason: "superseded", shownMs: shownMs) }
        }
        #endif
        visible = true
        currentSeq += 1
        shownAt = ContinuousClock.now
        let seq = currentSeq

        // AX is read off the main actor; the panel appears once the anchor resolves. A hide
        // (or a newer show) before that means this press never shows a panel.
        let frontmost = NSWorkspace.shared.frontmostApplication
        let pid = frontmost?.processIdentifier
        let bundleID = frontmost?.bundleIdentifier
        let provider = candidateProvider
        Task { [weak self] in
            let candidates = await provider(pid)
            self?.present(seq: seq, candidates: candidates, bundleID: bundleID)
        }
    }

    private func present(seq: Int, candidates: CaretAnchor.Candidates, bundleID: String?) {
        guard visible, currentSeq == seq, let panel else { return }
        let screens = NSScreen.screens.map {
            OverlayPlacement.ScreenGeometry(frame: $0.frame, visibleFrame: $0.visibleFrame)
        }
        guard let primary = screens.first else { return }
        let main = NSScreen.main.map { OverlayPlacement.ScreenGeometry(frame: $0.frame, visibleFrame: $0.visibleFrame) }
        let placement = OverlayPlacement.place(
            candidates: candidates,
            panel: LiveOverlayPanel.paneSize,
            screens: screens,
            primaryScreenHeight: primary.frame.height,
            fallback: main ?? primary
        )
        let target = LiveOverlayPanel.windowOrigin(forPaneOrigin: placement.origin)
        let rise = model.reduceMotion ? 0 : Self.riseDistance
        panel.setFrameOrigin(CGPoint(x: target.x, y: target.y - rise))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        animate(panel, alpha: targetAlpha, origin: target, duration: Self.entryDuration)
        #if DEBUG_RECORDER
        let frame = Self.rect(CGRect(origin: placement.origin, size: LiveOverlayPanel.paneSize))
        let visibleFrame = Self.rect(placement.visibleFrame)
        let source = placement.source.rawValue
        let flipped = placement.flipped
        recordedShowSeq = seq
        Task {
            await OverlayProbe.shared.recordShow(
                seq: seq, anchorSource: source, flipped: flipped, frame: frame, visibleFrame: visibleFrame,
                bundleId: bundleID, candidates: candidates)
        }
        #endif
    }

    func update(_ text: String) {
        guard visible else { return }
        model.text = text
    }

    func setProcessing() {
        guard visible else { return }
        model.phase = .processing
    }

    func hide(reason: LiveOverlayHideReason) {
        guard visible, let panel else { return }
        visible = false
        #if DEBUG_RECORDER
        // A release before the anchor resolved never showed the panel, so it has no show to pair.
        if recordedShowSeq == currentSeq {
            let seq = currentSeq
            let shownMs = OverlayProbe.milliseconds(ContinuousClock.now - shownAt)
            Task { await OverlayProbe.shared.recordHide(seq: seq, reason: reason.rawValue, shownMs: shownMs) }
        }
        #endif
        // The text stays until the next `show()` so the fade-out still has something to show.
        animate(panel, alpha: 0, origin: nil, duration: Self.exitDuration) { [weak self, weak panel] in
            guard let self, let panel, !self.visible else { return }
            panel.orderOut(nil)
        }
    }

    private func makePanel() -> LiveOverlayPanel {
        #if DEBUG
        let panel = LiveOverlayPanel(model: model, capturable: debugCapturable)
        panel.appearance = debugAppearance
        #else
        let panel = LiveOverlayPanel(model: model)
        #endif
        return panel
    }

    /// Never awaited: the paste does not wait for the panel.
    private func animate(
        _ panel: NSPanel, alpha: CGFloat, origin: CGPoint?, duration: TimeInterval,
        completion: (@MainActor () -> Void)? = nil
    ) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = Self.easing
            panel.animator().alphaValue = alpha
            if let origin {
                panel.animator().setFrame(CGRect(origin: origin, size: panel.frame.size), display: true)
            }
        } completionHandler: {
            completion?()
        }
    }

    #if DEBUG_RECORDER
    private static func rect(_ r: CGRect) -> [Double] {
        [r.origin.x, r.origin.y, r.size.width, r.size.height].map { Double($0) }
    }
    #endif
}

#if DEBUG
/// Launch-argument demo for the VM render check: `-DicticusOverlayDemo YES` shows the panel
/// through the same placement path as a real press, with fixed neutral sample text.
/// `-DicticusOverlayDemoAppearance light|dark` pins the appearance for the screenshot only.
extension LiveOverlayController {

    private static var demoController: LiveOverlayController?

    static var isDemoRequested: Bool {
        UserDefaults.standard.bool(forKey: "DicticusOverlayDemo")
    }

    static func runDemoIfRequested() {
        guard isDemoRequested else { return }
        let controller = LiveOverlayController()
        controller.debugCapturable = true
        switch UserDefaults.standard.string(forKey: "DicticusOverlayDemoAppearance") {
        case "light": controller.debugAppearance = NSAppearance(named: .aqua)
        case "dark": controller.debugAppearance = NSAppearance(named: .darkAqua)
        default: break
        }
        demoController = controller

        let sample = [
            "The quarterly report is ready for review and the figures match last month.",
            "Please move the meeting to Thursday afternoon if the room is free.",
            "We still need to confirm the delivery date with the supplier.",
            "After that I will send the updated schedule to everyone on the team.",
            "Let me know if anything in the plan looks unclear or missing."
        ].joined(separator: " ")

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            controller.show()
            controller.update(sample)
            try? await Task.sleep(for: .seconds(4))
            controller.setProcessing()
            try? await Task.sleep(for: .seconds(3))
            controller.hide(reason: .demo)

            // `-DicticusOverlayDemoEdges YES`: the two lifecycle shapes a real press can produce,
            // so the DEBUG_RECORDER log can be checked for show/hide pairing without a hotkey.
            guard UserDefaults.standard.bool(forKey: "DicticusOverlayDemoEdges") else { return }
            try? await Task.sleep(for: .seconds(1))
            controller.show()
            controller.hide(reason: .earlyReturn)
            try? await Task.sleep(for: .seconds(1))
            controller.show()
            controller.update("Edge sample.")
            try? await Task.sleep(for: .seconds(1))
            controller.show()
            try? await Task.sleep(for: .seconds(1))
            controller.hide(reason: .demo)
        }
    }
}
#endif
