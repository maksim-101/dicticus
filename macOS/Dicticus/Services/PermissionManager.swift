import SwiftUI
import AVFoundation
@preconcurrency import ApplicationServices

/// Status of a single macOS permission.
enum PermissionStatus: Equatable {
    case granted
    case pending   // not yet requested or in-progress (shows "Required")
    case denied

    /// SF Symbol name representing this status.
    var iconName: String {
        switch self {
        case .granted: return "checkmark.circle.fill"
        case .pending: return "clock"
        case .denied:  return "xmark.circle.fill"
        }
    }

    /// Semantic color for the status badge.
    var color: Color {
        switch self {
        case .granted: return .green
        case .pending: return .secondary
        case .denied:  return .red
        }
    }

    /// Short label shown next to the status badge.
    var label: String {
        switch self {
        case .granted: return "Granted"
        case .pending: return "Required"
        case .denied:  return "Denied"
        }
    }
}

// Capture the AX prompt key at module load time to avoid Swift 6 shared-mutable-state
// warning when accessing the C global `kAXTrustedCheckOptionPrompt` from an actor context.
// String is Sendable so no nonisolated(unsafe) annotation is needed.
private let axTrustedPromptKey: String =
    kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String

/// ObservableObject that checks and requests the required macOS permissions:
/// Microphone and Accessibility.
///
/// Polling every 2 seconds detects grants made in System Settings while the app is running.
/// Timer uses `[weak self]` to prevent retain cycles (T-02-03 mitigation).
@MainActor
class PermissionManager: ObservableObject {
    @Published var microphoneStatus: PermissionStatus = .pending
    @Published var accessibilityStatus: PermissionStatus = .pending
    @Published var hasCompletedOnboarding = false

    /// Paths of all com.dicticus.app bundles found on disk at launch time.
    /// Only populated by the once-per-launch checkMultipleInstalls() call;
    /// NOT refreshed by the 2s polling timer (D-07: mdfind every 2s would be wasteful).
    @Published var multipleDicticusCopies: [URL] = []

    private static let onboardingKey = "hasCompletedOnboarding"

    private var pollTimer: Timer?

    /// True when the required permissions are .granted.
    ///
    /// Only Microphone and Accessibility are required. The global modifier-key
    /// listener (`NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged)`)
    /// runs on Accessibility, and the `^⇧S`/`^⇧D` shortcuts use Carbon
    /// `RegisterEventHotKey` (no permission). Input Monitoring is NOT needed:
    /// `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` only ever reported it
    /// "granted" because Accessibility is a superset, so requiring it added a
    /// phantom requirement that could never be independently detected.
    var allGranted: Bool {
        microphoneStatus == .granted &&
        accessibilityStatus == .granted
    }

    /// Check current permission states without triggering OS prompts.
    func checkAll() {
        // Microphone: AVCaptureDevice is the standard check on macOS
        let audioStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        switch audioStatus {
        case .authorized:           microphoneStatus = .granted
        case .denied, .restricted:  microphoneStatus = .denied
        case .notDetermined:        microphoneStatus = .pending
        @unknown default:           microphoneStatus = .pending
        }

        // Accessibility: AXIsProcessTrusted() reflects current TCC state.
        // Always show .pending when not granted — the "Grant Access" button handles
        // both first-time prompts and re-requests via AXIsProcessTrustedWithOptions.
        let axTrusted = AXIsProcessTrusted()
        accessibilityStatus = axTrusted ? .granted : .pending
    }

    /// Trigger the OS microphone permission prompt. Updates status after user responds.
    func requestMicrophone() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        microphoneStatus = granted ? .granted : .denied
    }

    /// Trigger the OS Accessibility permission prompt.
    /// The result is not immediate — the user must go to System Settings.
    /// Polling via startPolling() will detect the change.
    func requestAccessibility() {
        // Use the module-level cached key (avoids Swift 6 concurrency error on C global)
        let options: NSDictionary = [axTrustedPromptKey: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
        // Do not update status here — polling picks it up within 2 seconds
    }

    /// Start polling all permissions every 2 seconds.
    /// Call this once from the UI entry point (MenuBarView.onAppear).
    func startPolling() {
        guard pollTimer == nil else { return }  // WR-01: prevent duplicate timers on repeated popover opens
        checkAll()
        // [weak self] prevents retain cycle (T-02-03 mitigation)
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkAll()
            }
        }
    }

    /// Stop polling. Call when the app is terminating or entering background.
    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Mark onboarding as complete and persist to UserDefaults.
    func markOnboardingComplete() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: Self.onboardingKey)
    }

    /// Load onboarding completion state from UserDefaults.
    func loadOnboardingState() {
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Self.onboardingKey)
    }

    /// Run `mdfind kMDItemCFBundleIdentifier == 'com.dicticus.app'` once and publish the result.
    /// Designed to be invoked from MenuBarView.onAppear, NOT from the 2s polling timer (D-07).
    /// Excludes nothing — the view layer decides which copies are "stale" vs "canonical".
    func checkMultipleInstalls() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        task.arguments = ["kMDItemCFBundleIdentifier == 'com.dicticus.app'"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                multipleDicticusCopies = []
                return
            }
            let paths = output
                .split(separator: "\n")
                .map(String.init)
                .filter { !$0.isEmpty }
                .filter { $0.hasSuffix("/Dicticus.app") }
                .map { URL(fileURLWithPath: $0) }
            multipleDicticusCopies = paths
        } catch {
            multipleDicticusCopies = []
        }
    }
}
