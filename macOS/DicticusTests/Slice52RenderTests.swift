import XCTest
import SwiftUI
import AppKit
@testable import Dicticus

/// Slice 52, task 4 (the owner's choice 2026-11-14: render headless on this Mac): draws the
/// Manage Dictionary window, a History row, and the fix-a-word component in its states
/// (Amendment 1) into PNGs, off-screen (the window is never ordered front).
/// Runs only when TEST_RUNNER_RENDER_DIR names an output folder. Invented words only.
@MainActor
final class Slice52RenderTests: XCTestCase {

    private var outDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        guard let dir = ProcessInfo.processInfo.environment["RENDER_DIR"], !dir.isEmpty else {
            throw XCTSkip("RENDER_DIR not set")
        }
        try XCTSkipUnless(DicticusTestBootstrap.didBootstrap, "refusing to touch DictionaryService.shared without the test bootstrap")
        outDir = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let service = DictionaryService.shared
        service.removeAll()
        let csv = """
        kwib ly,Quibbly
        quibli,Quibbly
        Kwiblee,Quibbly
        cloud,Zornex
        zorn ex,Zornex
        flor dex,FlorDex
        floor decks,FlorDex
        flawdex,FlorDex
        flor-dex,FlorDex
        florr dex,FlorDex
        vantel,Vantelli
        mirra cove,Miracove

        """
        _ = service.importData(Data(csv.utf8), format: "csv", strategy: .incomingWins)
    }

    override func tearDown() {
        if outDir != nil { DictionaryService.shared.removeAll() }
        super.tearDown()
    }

    private func render<V: View>(_ view: V, size: CGSize, name: String) throws {
        let hosting = NSHostingView(rootView: view.environmentObject(DictionaryService.shared))
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
        // A window made in code frees itself on close by default; ARC then frees it again
        // (crashed the test host on 2026-11-14 with a dialog on the owner's screen).
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        hosting.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: outDir.appendingPathComponent(name))
        window.close()
    }

    func testRenderDictionaryWindow() throws {
        try render(DictionaryView(), size: CGSize(width: 720, height: 900), name: "render-dictionary-window.png")
    }

    func testRenderHistoryRowAndFixWord() throws {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let text = "Can you check whether mirror cove imports the timeline from the FlorDex export correctly?"
        let entry = TranscriptionEntry(
            text: text,
            rawText: "can you check whether mirror cove imports the timeline from the flor dex export correctly?",
            language: "en", mode: "aiCleanup", confidence: 0.9)
        let row = HistoryRow(entry: entry, formatter: formatter, searchTerm: "", expanded: true)
        try render(row.padding(16).frame(width: 640, alignment: .topLeading), size: CGSize(width: 640, height: 260), name: "render-history-row.png")

        func card(_ view: FixWordView, _ name: String, height: CGFloat) throws {
            try render(view.padding(20).frame(width: 420, alignment: .topLeading), size: CGSize(width: 420, height: height), name: name)
        }
        try card(FixWordView(text: text, fontSize: 17), "render-fixword-1-start.png", height: 160)
        try card(FixWordView(text: text, fontSize: 17, pick: WordRange(anchor: 4, index: 5), correct: "Miracove"), "render-fixword-2-marked.png", height: 240)
        try card(FixWordView(text: "the cloud sync is slow", fontSize: 17, pick: WordRange(anchor: 1, index: 1), correct: "FlorDex"), "render-fixword-warnings.png", height: 300)
        try card(FixWordView(text: text, fontSize: 17, confirmation: "Added: “mirror cove” → “Miracove”. Applies from your next dictation."), "render-fixword-3-added.png", height: 180)
    }
}
