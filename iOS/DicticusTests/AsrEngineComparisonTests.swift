import XCTest
@testable import Dicticus

/// Phase 47 plan 01 (tracer) — Track B: as-shipped column harness.
///
/// This is a measurement tool, not a regression test — the sibling of
/// macOS's `AsrReplayHarnessTests`, but for the D-03 two-layer comparison's
/// second column. It never loads an ASR model and never links FluidAudio or
/// WhisperKit: it reads RAW transcripts already produced off-device by
/// Track A's SwiftPM drivers (`whisperkit-driver`, `parakeet-driver`, run via
/// `run_phase47_bakeoff.py`), feeds each one through the exact iOS-default
/// plain-mode pipeline (`TextProcessingService.process(mode: .plain)`), and
/// records the as-shipped output — dictionary + ITN, no LLM, each engine's
/// own dictionary reality.
///
/// Opt-in only. Without `DICTICUS_ASR_RAW_DIR` set it skips immediately, so a
/// normal `xcodebuild test` run never touches this harness.
///
///     DICTICUS_ASR_RAW_DIR="$HOME/code/dicticus/.planning/spikes/011-asr-decode-time-vocab/wer" \
///     DICTICUS_ASR_OUT=/tmp/asr-engine-comparison.jsonl \
///     xcodebuild test -only-testing:DicticusTests/AsrEngineComparisonTests
///
/// The input directory is read strictly read-only (every `*.jsonl` file in
/// it is scanned for `{id, lang, engine, raw}` rows — the exact shape
/// `run_phase47_bakeoff.py` writes); output goes to `DICTICUS_ASR_OUT`
/// (defaults to a temp file), never back into the input directory.
@MainActor
final class AsrEngineComparisonTests: XCTestCase {

    private struct RawRow {
        let id: String
        let lang: String
        let engine: String
        let raw: String
    }

    func testAsShippedColumnFromRawTranscripts() async throws {
        // Per the AsrReplayHarnessTests precedent (macOS/DicticusTests/AsrReplayHarnessTests.swift
        // lines 25-29): an env var set to "" is present-but-empty, not absent — that class of
        // mistake once fed `language: ""` into a decoder/pipeline and silently emptied every
        // result. The no-op control row below exists specifically to catch that here too.
        let env = ProcessInfo.processInfo.environment
        guard let rawDirPath = env["DICTICUS_ASR_RAW_DIR"], !rawDirPath.isEmpty else {
            throw XCTSkip("Set DICTICUS_ASR_RAW_DIR to a directory of Track-A RAW-transcript JSONL rows to run this harness.")
        }

        let rawDirURL = URL(fileURLWithPath: rawDirPath)
        let jsonlFiles = try FileManager.default
            .contentsOfDirectory(at: rawDirURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var rows: [RawRow] = []
        for file in jsonlFiles {
            guard let contents = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for line in contents.split(separator: "\n") {
                guard let data = line.data(using: .utf8),
                      let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let id = obj["id"] as? String,
                      let lang = obj["lang"] as? String,
                      let engine = obj["engine"] as? String,
                      let raw = obj["raw"] as? String
                else { continue }
                rows.append(RawRow(id: id, lang: lang, engine: engine, raw: raw))
            }
        }

        // Take every Nth row rather than the first N, so a truncated diagnostic run
        // still spans the whole set instead of only the earliest rows (mirrors the
        // AsrReplayHarnessTests stride-sampling rationale).
        if let limit = env["DICTICUS_ASR_LIMIT"].flatMap(Int.init), limit > 0, rows.count > limit {
            let stride = Double(rows.count) / Double(limit)
            rows = (0..<limit).map { rows[min(rows.count - 1, Int(Double($0) * stride))] }
        }

        XCTAssertFalse(rows.isEmpty, "No RAW-transcript rows found under \(rawDirPath) (looked for *.jsonl with id/lang/engine/raw fields)")

        let outPath = env["DICTICUS_ASR_OUT"]
            ?? NSTemporaryDirectory().appending("asr-engine-comparison.jsonl")
        FileManager.default.createFile(atPath: outPath, contents: nil)
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: outPath))
        defer { try? handle.close() }

        // Isolated history so process()'s Step-4 save() never writes to the real
        // App Group database (same rationale as TextProcessingServiceTests).
        let historyContainer = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("AsrEngineComparisonTests-\(UUID().uuidString)", isDirectory: true)
        let testHistory = HistoryService.makeForTesting(containerURLProvider: { historyContainer })

        // No-op control row: proves the pipeline is actually running with a real,
        // non-empty language and produces non-empty output — a batch that measured
        // nothing (e.g. because DICTICUS_ASR_RAW_DIR pointed at an empty-language
        // dataset) would still look like a finding without this guard.
        let controlService = TextProcessingService(cleanupService: nil, historyService: testHistory)
        let controlInput = "control probe two hundred"
        let controlOutput = await controlService.process(text: controlInput, language: "en", mode: .plain)
        XCTAssertFalse(controlOutput.isEmpty, "No-op control row produced empty output — pipeline is not running correctly")
        Self.write(["id": "control", "engine": "control", "lang": "en", "raw": controlInput, "as_shipped": controlOutput], to: handle)

        for row in rows {
            let service = TextProcessingService(cleanupService: nil, historyService: testHistory)
            let asShipped = await service.process(text: row.raw, language: row.lang, mode: .plain)
            XCTAssertFalse(asShipped.isEmpty, "As-shipped output empty for id=\(row.id) engine=\(row.engine) — non-empty RAW input must not collapse to empty output")
            Self.write([
                "id": row.id,
                "engine": row.engine,
                "lang": row.lang,
                "raw": row.raw,
                "as_shipped": asShipped,
            ], to: handle)
        }

        print("AsrEngineComparisonTests wrote \(rows.count + 1) rows (incl. control) to \(outPath)")
    }

    // MARK: - Helpers

    private static func write(_ row: [String: Any], to handle: FileHandle) {
        guard let data = try? JSONSerialization.data(withJSONObject: row) else { return }
        handle.write(data)
        handle.write(Data("\n".utf8))
    }
}
