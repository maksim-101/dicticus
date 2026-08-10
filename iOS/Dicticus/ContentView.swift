import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: DictationViewModel
    @EnvironmentObject var warmupService: IOSModelWarmupService
    @EnvironmentObject var historyService: HistoryService
    @EnvironmentObject var dictionaryService: DictionaryService
    @EnvironmentObject var pendingStore: PendingRecordingStore

    @Environment(\.horizontalSizeClass) var sizeClass
    @State private var selectedTab = 0
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        if sizeClass == .regular {
            // iPad / Mac layout
            NavigationSplitView(columnVisibility: $columnVisibility) {
                List {
                    Button { selectedTab = 0 } label: {
                        Label("Dictate", systemImage: "mic")
                            .foregroundColor(selectedTab == 0 ? .accentColor : .primary)
                    }
                    Button { selectedTab = 1 } label: {
                        Label("Dictionary", systemImage: "book")
                            .foregroundColor(selectedTab == 1 ? .accentColor : .primary)
                    }
                    Button { selectedTab = 2 } label: {
                        Label("History", systemImage: "clock")
                            .foregroundColor(selectedTab == 2 ? .accentColor : .primary)
                    }
                    .badge(pendingStore.pendingCount)
                }
                .navigationTitle("Dicticus")
            } detail: {
                if selectedTab == 0 {
                    DictationView(onOpenPendingQueue: { selectedTab = 2 })
                        .environmentObject(viewModel)
                        .environmentObject(warmupService)
                        .environmentObject(pendingStore)
                } else if selectedTab == 1 {
                    NavigationStack {
                        DictionaryManagementView()
                            .environmentObject(dictionaryService)
                    }
                } else {
                    HistoryView()
                        .environmentObject(historyService)
                        .environmentObject(pendingStore)
                        .environmentObject(viewModel)
                }
            }
            .task {
                viewModel.setupNotificationObserver()
            }
            .onAppear {
                if warmupService.hasModels && !warmupService.isWarming && !warmupService.isReady {
                    warmupService.warmup()
                }
            }
        } else {
            // iPhone layout
            TabView(selection: $selectedTab) {
                DictationView(onOpenPendingQueue: { selectedTab = 2 })
                    .environmentObject(viewModel)
                    .environmentObject(warmupService)
                    .environmentObject(pendingStore)
                    .tabItem {
                        Label("Dictate", systemImage: "mic")
                    }
                    .tag(0)

                NavigationStack {
                    DictionaryManagementView()
                        .environmentObject(dictionaryService)
                }
                .tabItem {
                    Label("Dictionary", systemImage: "book")
                }
                .tag(1)

                HistoryView()
                    .environmentObject(historyService)
                    .environmentObject(pendingStore)
                    .environmentObject(viewModel)
                    .tabItem {
                        Label("History", systemImage: "clock")
                    }
                    .tag(2)
                    .badge(pendingStore.pendingCount)
            }
            .task {
                viewModel.setupNotificationObserver()
            }
            .onAppear {
                if warmupService.hasModels && !warmupService.isWarming && !warmupService.isReady {
                    warmupService.warmup()
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(DictationViewModel())
        .environmentObject(IOSModelWarmupService())
        .environmentObject(HistoryService.shared)
        .environmentObject(DictionaryService.shared)
        .environmentObject(PendingRecordingStore.shared)
}
