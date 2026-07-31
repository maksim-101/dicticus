import AppKit
import SwiftUI

/// Captures the hosting NSWindow on appearance and applies a configuration closure.
///
/// Used to set NSWindow.collectionBehavior and register willCloseNotification observers —
/// AppKit properties that have no SwiftUI equivalent.
///
/// The close notification strategy (NSWindow.willCloseNotification rather than onDisappear)
/// is intentional: willCloseNotification fires only on genuine window dismissal, not on
/// minimize. This prevents the activation-policy counter from decrementing when the user
/// minimizes an auxiliary window to the Dock.
struct WindowAccessor: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // Defer to the next run loop so the window hierarchy is fully assembled
        // before we walk up to the NSWindow.
        DispatchQueue.main.async {
            if let window = view.window {
                configure(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Notification names for auxiliary-window lifetime tracking

extension Notification.Name {
    /// Posted by each auxiliary window (Dictionary, History, Settings) on onAppear.
    /// DicticusApp listens and increments the open-window counter, switching to
    /// .regular activation policy when the count goes from 0 to 1.
    static let dicticusAuxWindowOpened = Notification.Name("com.dicticus.auxWindowOpened")

    /// Posted by NSWindow.willCloseNotification observer installed in WindowAccessor.
    /// DicticusApp listens and decrements the open-window counter, restoring .accessory
    /// activation policy when the count returns to 0.
    static let dicticusAuxWindowClosed = Notification.Name("com.dicticus.auxWindowClosed")
}
