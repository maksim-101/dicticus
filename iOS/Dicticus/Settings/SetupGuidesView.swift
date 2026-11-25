import SwiftUI

struct SetupGuidesView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("1. Open the Shortcuts app.")
                    Text("2. Create a new Shortcut.")
                    Text("3. Search for the 'Start Dictation' action from Dicticus.")
                    Text("4. Assign this Shortcut to your Action Button or Back Tap.")
                }
                .padding(.vertical, 8)
            } header: {
                Label("Siri Shortcut Setup", systemImage: "bolt.fill")
            } footer: {
                Text("This allows you to trigger Dicticus from anywhere without opening the app.")
            }
            
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("1. Go to Settings > Action Button.")
                    Text("2. Swipe to 'Shortcut'.")
                    Text("3. Select the 'Start Dictation' shortcut you created.")
                }
                .padding(.vertical, 8)
            } header: {
                Label("Action Button (iPhone 15 Pro+)", systemImage: "iphone.gen3")
            }
            
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("1. Go to Settings > Accessibility > Touch.")
                    Text("2. Scroll to 'Back Tap'.")
                    Text("3. Choose Double or Triple Tap.")
                    Text("4. Select your 'Start Dictation' shortcut.")
                }
                .padding(.vertical, 8)
            } header: {
                Label("Back Tap (All iPhones)", systemImage: "hand.tap.fill")
            }
        }
        .navigationTitle("Setup Guides")
    }
}

#Preview {
    NavigationStack {
        SetupGuidesView()
    }
}
