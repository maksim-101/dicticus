import SwiftUI

/// Launch-time screen shown when `DeviceCapabilityGate.isCurrentDeviceSupported`
/// is false (WHISP-05). Replaces the normal app root entirely — no dictation UI,
/// no onboarding, no model download attempt — so an unsupported device never
/// triggers the ~626 MB WhisperKit large-v3-turbo download it cannot run reliably.
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

            Text("Dicticus transcribes speech entirely on your iPhone using the Whisper large-v3-turbo model. That model needs the memory and Neural Engine of the A16 chip (iPhone 15 and later) to run reliably — older iPhones cannot run it without crashing or running out of memory.")
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
