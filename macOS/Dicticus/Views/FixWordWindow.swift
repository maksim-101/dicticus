import SwiftUI

/// Which dictation the "Fix a word" window shows; set before opening it, so the popover
/// and History can open the single window on a chosen dictation.
@MainActor
final class FixWordRequest: ObservableObject {
    static let shared = FixWordRequest()
    @Published var uuid: UUID?
    /// Changes on every `open`, so a repeated request for the same dictation still reaches the window.
    @Published var token = UUID()

    /// Opens the window on `entry` (nil: the last dictation).
    static func open(_ entry: TranscriptionEntry?, with openWindow: OpenWindowAction) {
        shared.uuid = entry?.uuid
        shared.token = UUID()
        openWindow(id: "fix-word")
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// "Fix a word" window: recent dictations on
/// the left, the chosen one large on the right with the shared fix-a-word component.
struct FixWordWindow: View {
    @EnvironmentObject private var historyService: HistoryService
    @ObservedObject private var request = FixWordRequest.shared
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var selection: UUID?
    @FocusState private var listFocused: Bool

    private static let recentCount = 20
    private static let spacing: CGFloat = 20

    /// The 20 most recent dictations, plus a requested older one so it can be shown and selected.
    private var recent: [TranscriptionEntry] {
        var list = Array(historyService.entries.prefix(Self.recentCount))
        if let uuid = request.uuid, !list.contains(where: { $0.uuid == uuid }),
           let requested = historyService.entries.first(where: { $0.uuid == uuid }) {
            list.append(requested)
        }
        return list
    }
    private var chosen: TranscriptionEntry? { recent.first { $0.uuid == selection } }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Recent Dictations") {
                    ForEach(recent, id: \.uuid) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Self.shortStamp(entry))
                                .font(.system(size: 11, weight: .semibold))
                            Text(entry.text)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 2)
                        .tag(entry.uuid)
                    }
                }
            }
            .focused($listFocused)
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let entry = chosen {
                        FixWordView(text: entry.text, fontSize: 17, onDone: { listFocused = true })
                    } else {
                        Text("No dictation yet. Dictate something, then pick the words Dicticus got wrong here.")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Self.spacing)
            }
            // Date and Copy live in the window toolbar (DESIGN.md).
            .navigationSubtitle(chosen.map { "\($0.createdAt.formatted(date: .abbreviated, time: .shortened)) · \($0.language.uppercased())" } ?? "")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Copy", systemImage: "doc.on.doc") {
                        guard let text = chosen?.text else { return }
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                    .help("Copy this dictation")
                    .disabled(chosen == nil)
                }
            }
        }
        .frame(minWidth: 620, minHeight: 380)
        .onExitCommand { dismissWindow(id: "fix-word") }
        .onAppear {
            applyRequest()
            // Focus in the list lets Escape reach onExitCommand; the spelling field's own
            // Escape cancels the field first (seen not closing in a test VM without it).
            listFocused = true
            NotificationCenter.default.post(name: .dicticusAuxWindowOpened, object: nil)
        }
        .onChange(of: request.token) { _, _ in applyRequest() }
        .background(
            WindowAccessor { window in
                window.collectionBehavior = [.managed, .moveToActiveSpace]
                NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: .main
                ) { _ in
                    NotificationCenter.default.post(name: .dicticusAuxWindowClosed, object: nil)
                }
            }
        )
    }

    /// The requested dictation, else the last one.
    private func applyRequest() {
        if let uuid = request.uuid, recent.contains(where: { $0.uuid == uuid }) {
            selection = uuid
        } else {
            selection = recent.first?.uuid
        }
    }

    private static func shortStamp(_ entry: TranscriptionEntry) -> String {
        let time = entry.createdAt.formatted(date: .omitted, time: .shortened)
        let day = Calendar.current.isDateInToday(entry.createdAt) ? time
            : Calendar.current.isDateInYesterday(entry.createdAt) ? "Yesterday \(time)"
            : entry.createdAt.formatted(date: .abbreviated, time: .shortened)
        return "\(day) · \(entry.language.uppercased())"
    }
}
