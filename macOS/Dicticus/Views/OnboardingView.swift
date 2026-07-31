import SwiftUI

/// Sequential first-launch permission onboarding flow.
///
/// Guides the user through three permissions one at a time (D-01):
/// Microphone → Accessibility
///
/// The user can skip any step with "I'll do this later" (D-02 — non-blocking).
/// After all steps, onboarding is marked complete and the panel dismisses.
struct OnboardingView: View {
    @EnvironmentObject var permissionManager: PermissionManager
    @Binding var isPresented: Bool

    @State private var currentStep = 0

    private struct PermissionStep {
        let icon: String
        let title: String
        let body: String
    }

    // Step definitions match the Copywriting Contract in UI-SPEC.md exactly
    private let steps: [PermissionStep] = [
        PermissionStep(
            icon: "mic",
            title: "Microphone",
            body: "Microphone access is required to hear your voice. Your audio never leaves this device."
        ),
        PermissionStep(
            icon: "accessibility",
            title: "Accessibility",
            body: "Accessibility access lets Dicticus type at your cursor in any app."
        )
    ]

    var body: some View {
        VStack(spacing: 24) {
            Text("Dicticus needs a few permissions to work")
                .font(.headline)
                .multilineTextAlignment(.center)

            if currentStep < steps.count {
                let step = steps[currentStep]

                VStack(spacing: 16) {
                    // Permission icon — 40pt per UI-SPEC Onboarding Flow
                    Image(systemName: step.icon)
                        .font(.system(size: 40))
                        .foregroundColor(.accentColor)

                    Text(step.title)
                        .font(.headline)

                    Text(step.body)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Grant Access") {
                        grantCurrentPermission()
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)

                    // Non-blocking skip link per D-02
                    Button("I'll do this later") {
                        advanceStep()
                    }
                    .controlSize(.small)
                    .foregroundColor(.secondary)
                    .buttonStyle(.plain)
                }
            }
        }
        // Panel width: 360pt and xl (32pt) padding per UI-SPEC spacing exceptions
        .padding(32)
        .frame(width: 360)
    }

    private func grantCurrentPermission() {
        switch currentStep {
        case 0:
            Task {
                await permissionManager.requestMicrophone()
                advanceStep()
            }
        case 1:
            // Accessibility prompt is async — user goes to System Settings.
            // Advance immediately; polling detects the grant within 2 seconds.
            permissionManager.requestAccessibility()
            advanceStep()
        default:
            break
        }
    }

    private func advanceStep() {
        if currentStep < steps.count - 1 {
            currentStep += 1
        } else {
            // All steps shown — mark complete and dismiss panel
            permissionManager.markOnboardingComplete()
            isPresented = false
        }
    }
}
