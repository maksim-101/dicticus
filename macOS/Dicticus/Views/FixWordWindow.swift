import SwiftUI

/// Which dictation the "Fix a word" window shows; set before opening it, so the popover
/// and History can open the single window on a chosen dictation.
@MainActor
final class FixWordRequest: ObservableObject {
    static let shared = FixWordRequest()
    @Published var uuid: UUID?

    /// Opens the window on `entry` (nil: the last dictation).
    static func open(_ entry: TranscriptionEntry?, with openWindow: OpenWindowAction) {
        shared.uuid = entry?.uuid
        openWindow(id: "fix-word")
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// "Fix a word" window (slice 52 criterion 11, mockup `pointer-r2` B): recent dictations on
/// the left, the chosen one large on the right with the shared fix-a-word component.
struct FixWordWindow: View {
    @EnvironmentObject private var historyService: HistoryService
    @ObservedObject private var request = FixWordRequest.shared
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var selection: UUID?

    static let recentCount = 20
    private static let spacing: CGFloat = 20

    private var recent: [TranscriptionEntry] { Array(historyService.entries.prefix(Self.recentCount)) }
    private var chosen: TranscriptionEntry? { recent.first { $0.uuid == selection } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                List(recent, id: \.uuid, selection: $selection) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.shortStamp(entry))
                            .font(.system(size: 11, weight: .semibold))
                        Text(entry.text)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.sidebar)
                .frame(width: 210)
                .safeAreaInset(edge: .top, spacing: 0) {
                    Text("RECENT DICTATIONS")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 4)
                }

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let entry = chosen {
                            Text("Selected: \(entry.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(entry.language.uppercased())")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            FixWordView(text: entry.text, fontSize: 17)
                        } else {
                            Text("No dictation yet. Dictate something, then pick the words Dicticus got wrong here.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Self.spacing)
                }
            }

            Divider()

            HStack {
                Text("Esc closes")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Copy") {
                    guard let text = chosen?.text else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .controlSize(.small)
                .disabled(chosen == nil)
            }
            .padding(.horizontal, Self.spacing)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 620, minHeight: 380)
        .onExitCommand { dismissWindow(id: "fix-word") }
        .onAppear {
            applyRequest()
            NotificationCenter.default.post(name: .dicticusAuxWindowOpened, object: nil)
        }
        .onChange(of: request.uuid) { _, _ in applyRequest() }
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
