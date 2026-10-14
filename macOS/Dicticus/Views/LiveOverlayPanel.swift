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
}

/// Borderless, non-activating panel (D-12). It never becomes key or main and is only
/// ever ordered front with `orderFrontRegardless()`, so the paste target keeps focus.
final class LiveOverlayPanel: NSPanel {

    static let size = CGSize(width: LiveOverlayView.width, height: LiveOverlayView.height)

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    @MainActor
    init(model: LiveOverlayModel, capturable: Bool = false) {
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
        hasShadow = true
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

        let host = NSHostingView(rootView: LiveOverlayView(model: model))
        host.sizingOptions = []
        host.frame = CGRect(origin: .zero, size: Self.size)
        contentView = host
    }
}

@MainActor
final class LiveOverlayController: LiveOverlayPresenting {

    private static let fadeDuration: TimeInterval = 0.18  // DESIGN motion `fast`
    private static let bottomInset: CGFloat = 48

    private let targetAlpha: CGFloat
    private let model = LiveOverlayModel()
    private var panel: LiveOverlayPanel?
    private var visible = false
    private var shownAt = ContinuousClock.now

    #if DEBUG
    var debugCapturable = false
    var debugAppearance: NSAppearance?
    #endif

    private(set) var currentSeq = 0

    init(targetAlpha: CGFloat = 1) {
        self.targetAlpha = targetAlpha
    }

    var isVisible: Bool { visible }

    var modelForTesting: LiveOverlayModel { model }
    var panelForTesting: LiveOverlayPanel? { panel }

    func show() {
        model.text = ""
        model.phase = .listening

        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setFrameOrigin(Self.placement(for: panel.frame.size))
        panel.alphaValue = 0
        visible = true
        currentSeq += 1
        shownAt = ContinuousClock.now
        panel.orderFrontRegardless()
        fade(panel, to: targetAlpha)
        #if DEBUG_RECORDER
        let seq = currentSeq
        let frame = Self.rect(panel.frame)
        let visibleFrame = Self.rect(NSScreen.main?.visibleFrame ?? .zero)
        Task { await OverlayProbe.shared.recordShow(seq: seq, anchorSource: "fallback", frame: frame, visibleFrame: visibleFrame) }
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
        model.text = ""
        #if DEBUG_RECORDER
        let seq = currentSeq
        let shownMs = OverlayProbe.milliseconds(ContinuousClock.now - shownAt)
        Task { await OverlayProbe.shared.recordHide(seq: seq, reason: reason.rawValue, shownMs: shownMs) }
        #endif
        fade(panel, to: 0) { [weak self, weak panel] in
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

    /// Fades without ever being awaited: the paste does not wait for the panel.
    private func fade(_ panel: NSPanel, to alpha: CGFloat, completion: (@MainActor () -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            panel.animator().alphaValue = alpha
        } completionHandler: {
            completion?()
        }
    }

    #if DEBUG_RECORDER
    private static func rect(_ r: CGRect) -> [Double] {
        [r.origin.x, r.origin.y, r.size.width, r.size.height].map { Double($0) }
    }
    #endif

    /// Bottom-centre of the main screen's visible frame; plan 05 swaps in the caret anchor here.
    private static func placement(for size: CGSize) -> CGPoint {
        guard let visibleFrame = NSScreen.main?.visibleFrame else { return .zero }
        return CGPoint(
            x: (visibleFrame.midX - size.width / 2).rounded(),
            y: visibleFrame.minY + bottomInset
        )
    }
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
        }
    }
}
#endif
