import SwiftUI

struct WhatsNewView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            Text("What's New in v2.0")
                .font(.largeTitle).bold()
                .multilineTextAlignment(.center)
            
            VStack(alignment: .leading, spacing: 24) {
                FeatureRow(
                    icon: "iphone.gen3",
                    color: .blue,
                    title: "iOS Dictation",
                    description: "Dicticus is now available on your iPhone. Powerful local ASR in your pocket."
                )
                
                FeatureRow(
                    icon: "bolt.fill",
                    color: .orange,
                    title: "Siri Shortcuts",
                    description: "Trigger dictation with your voice or assign it to the Action Button and Back Tap."
                )
                
                FeatureRow(
                    icon: "clock.fill",
                    color: .green,
                    title: "History & Search",
                    description: "All your transcriptions are saved locally. Search through them instantly with FTS5."
                )
                
                FeatureRow(
                    icon: "book.fill",
                    color: .purple,
                    title: "Custom Dictionary",
                    description: "Your custom replacements now sync across your devices via the shared pipeline."
                )
            }
            .padding(.horizontal)
            
            Spacer()
            
            Button("Continue") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 40)
        }
        .padding()
    }
}

struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(color)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    WhatsNewView()
}
