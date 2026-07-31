import SwiftUI

struct OnboardingTourView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage = 0

    var body: some View {
        NavigationStack {
            VStack {
                TabView(selection: $currentPage) {
                    howToDictatePage.tag(0)
                    historyPage.tag(1)
                    dictionaryPage.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                HStack {
                    if currentPage > 0 {
                        Button("Back") {
                            withAnimation(.easeInOut(duration: 0.4)) { currentPage -= 1 }
                        }
                        .buttonStyle(.borderless)
                    }

                    Spacer()

                    if currentPage < 2 {
                        Button("Next") {
                            withAnimation(.easeInOut(duration: 0.4)) { currentPage += 1 }
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("Done") {
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
            }
        }
    }

    // MARK: - Pages

    private var howToDictatePage: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.fill")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)

            Text("How to Dictate")
                .font(.title).bold()

            Text("Tap **Dictate** on the home screen and speak. Your transcript is automatically copied to the clipboard — just leave the app and paste it anywhere.\n\nNo setup required. The Action Button and Siri Shortcut are optional convenience accelerators, not prerequisites.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            NavigationLink(destination: SetupGuidesView()) {
                Label("Set Up Action Button & Shortcuts", systemImage: "arrow.right.circle")
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        }
        .padding(.vertical)
    }

    private var historyPage: some View {
        VStack(spacing: 20) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)

            Text("History & Search")
                .font(.title).bold()

            Text("Every transcript is saved locally on this device — nothing goes to the cloud. Find past dictations anytime in the **History** tab, and search by keyword.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.vertical)
    }

    private var dictionaryPage: some View {
        VStack(spacing: 20) {
            Image(systemName: "book")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)

            Text("Custom Dictionary")
                .font(.title).bold()

            Text("Fix recurring mishearings with find-and-replace entries. Import CSV files or bundled starter packs to get started quickly.\n\nFind it under **Settings → Custom Dictionary**.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.vertical)
    }
}

#Preview {
    OnboardingTourView()
}
