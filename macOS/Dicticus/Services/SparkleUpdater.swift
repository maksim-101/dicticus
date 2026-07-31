import Sparkle
import SwiftUI
import Combine

/// A wrapper around Sparkle's SPUStandardUpdaterController to make it usable in SwiftUI.
@MainActor
final class SparkleUpdater: ObservableObject {
    @Published var canCheckForUpdates = false

    private let updaterController: SPUStandardUpdaterController
    private var cancellables = Set<AnyCancellable>()

    init() {
        // startingUpdater: true starts the background check immediately based on Info.plist
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

        // Observe the updater's ability to check for updates (e.g., disable button if already checking)
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] canCheck in
                self?.canCheckForUpdates = canCheck
            }
            .store(in: &cancellables)
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
