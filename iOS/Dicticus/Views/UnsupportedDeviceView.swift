import SwiftUI

/// Launch-time screen shown when `DeviceCapabilityGate.isCurrentDeviceSupported`
/// is false (WHISP-05). Replaces the normal app root entirely — no dictation UI,
/// no onboarding, no model download attempt — so an unsupported device never
/// triggers the ~1.1 GB Parakeet TDT v3 model download. Note (D-03, Phase 47.1):
/// the iPhone 15+ floor is kept as a deliberate quality/consistency decision, not
/// a hard technical requirement — Parakeet's footprint no longer strictly needs it.
struct UnsupportedDeviceView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 80))
                .foregroundColor(.orange)

            Text("Device Not Supported")
                .font(.title).bold()

            Text("Dicticus requires iPhone 15 or later to run its on-device speech model.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text("Dicticus transcribes speech entirely on your iPhone using the Parakeet TDT v3 speech model on Apple's Neural Engine. Dicticus requires the A16 chip (iPhone 15 and later) to guarantee reliable, real-time performance — older iPhones are not supported.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
}

#Preview {
    UnsupportedDeviceView()
}
