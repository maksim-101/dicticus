import Foundation
import Combine
import os.log

/// Foreground URLSession downloader for the Qwen2.5-3B-Instruct GGUF.
///
/// - Per **D-10**: the inline Settings download UI (Wave 3) consumes this class's
///   `@Published` `state` / `progress` / `bytesPerSec` to render progress and
///   pause/resume controls. Delegate-based download gives us mid-flight progress
///   callbacks that the macOS `URLSession.shared.download(from:)` path can't
///   provide.
/// - Per **D-11**: destination is
///   `Application Support/Dicticus/Models/qwen2.5-3b-instruct-q4_k_m.gguf` (mirrors the
///   macOS `ModelDownloadService` path).
/// - Per **D-14 / Q6**: the downloaded file is marked
///   `URLResourceValues.isExcludedFromBackup = true` immediately after move, so a
///   ~1.93 GB GGUF does not bloat the user's iCloud Backup.
/// - Pause/resume uses `cancel(byProducingResumeData:)` +
///   `downloadTask(withResumeData:)`; resume data is kept in-memory only.
/// - The `init(sessionConfiguration:)` seam lets tests inject a
///   `URLSessionConfiguration` whose `protocolClasses = [MockURLProtocol.self]`.
@MainActor
public final class IOSModelDownloadService: NSObject, ObservableObject, URLSessionDownloadDelegate {

    // MARK: - Public types

    public enum DownloadState: Equatable {
        case idle
        case downloading
        case paused
        case completed
        case failed(String)
    }

    // MARK: - Constants (mirror macOS ModelDownloadService per D-11)

    /// HuggingFace CDN URL for the ungated Qwen3.5-4B Q4_K_M GGUF (unsloth, verified ungated
    /// HTTP 200 + sha256-identical to the Phase 44 benchmarked/fidelity-gated file, 2026-07-15).
    /// `nonisolated` so non-main delegate callbacks can read it without hopping actors.
    public nonisolated static let modelURL = URL(string: "https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q4_K_M.gguf")!

    /// Local cache file name (mirrors the macOS constant, matches the URL artifact name).
    /// Contains "qwen3" so the Qwen3 reasoning-preclose + EOG paths fire.
    public nonisolated static let modelFileName = "qwen3.5-4b-q4_k_m.gguf"

    /// Phase 44 Plan 14: the GGUF the app actually loads. Defaults to the shipped
    /// `modelFileName`; a `-llmModelFileOverride <name>.gguf` launch argument points
    /// it at a side-loaded GGUF instead, so the Qwen2.5-vs-Qwen3.5 memory A/B runs
    /// against one build. Shipped behaviour is unchanged when the argument is absent.
    public nonisolated static var activeModelFileName: String {
        UserDefaults.standard.string(forKey: "llmModelFileOverride") ?? modelFileName
    }

    /// User-facing model name — single source of truth for Settings labels so a future
    /// model swap cannot leave a stale label behind (mirrors the macOS constant).
    public nonisolated static let modelDisplayName = "Qwen3.5-4B-Instruct (Q4_K_M)"

    /// Filenames of retired GGUFs, removed best-effort so upgrading users reclaim disk:
    /// Gemma 4 E2B (~3.1 GB) and Qwen2.5-3B (~1.93 GB, superseded by Qwen3.5 in Phase 44).
    public nonisolated static let legacyModelFileNames = [
        "gemma-4-E2B-it-Q4_K_M.gguf",
        "qwen2.5-3b-instruct-q4_k_m.gguf",
    ]

    /// Computed path to the cached model file in Application Support.
    /// Path: `~/Library/Application Support/Dicticus/Models/qwen2.5-3b-instruct-q4_k_m.gguf`
    /// `nonisolated` so the `didFinishDownloadingTo` delegate (running on the
    /// URLSession delegate queue) can resolve the destination synchronously.
    public nonisolated static func modelPath() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("Dicticus")
            .appendingPathComponent("Models")
            .appendingPathComponent(activeModelFileName)
    }

    /// Whether the GGUF is already present on disk (for onboarding / warmup gating).
    /// Also triggers best-effort orphan cleanup of the retired Gemma file on a cache hit.
    public nonisolated static func isModelCached() -> Bool {
        let cached = FileManager.default.fileExists(atPath: modelPath().path)
        if cached {
            removeOrphanedModelsIfPresent()
        }
        return cached
    }

    /// Best-effort removal of retired GGUFs (Gemma, Qwen2.5) once the current model is present.
    /// Non-fatal — errors are ignored since this is a disk-reclaim convenience, not a
    /// correctness requirement. `nonisolated` so both the delegate queue and MainActor
    /// call sites can invoke it directly.
    public nonisolated static func removeOrphanedModelsIfPresent() {
        let modelsDir = modelPath().deletingLastPathComponent()
        for name in legacyModelFileNames {
            try? FileManager.default.removeItem(at: modelsDir.appendingPathComponent(name))
        }
    }

    // MARK: - Published state

    @Published public private(set) var state: DownloadState = .idle
    @Published public private(set) var progress: Double = 0
    @Published public private(set) var bytesPerSec: Double = 0

    // MARK: - Internals

    private let log = Logger(subsystem: "com.dicticus", category: "download")
    private var session: URLSession!
    private var task: URLSessionDownloadTask?
    private var resumeData: Data?
    private var lastBytes: Int64 = 0
    private var lastSampleAt: Date = .distantPast
    private var completionContinuation: CheckedContinuation<Void, Error>?

    // MARK: - Init (test seam)

    /// - Parameter sessionConfiguration: Inject a configuration with
    ///   `protocolClasses = [MockURLProtocol.self]` in tests. Defaults to
    ///   `URLSessionConfiguration.default`, which waits for connectivity on
    ///   Wi-Fi drops.
    public init(sessionConfiguration: URLSessionConfiguration = .default) {
        super.init()
        sessionConfiguration.waitsForConnectivity = true
        // Delegate queue must be non-main — Apple docs warn that main-queue
        // delegate callbacks can deadlock with synchronous reads on the main
        // thread. We hop to @MainActor via `Task { @MainActor in ... }` for
        // every `@Published` mutation.
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "com.dicticus.IOSModelDownloadService"
        self.session = URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: queue)
    }

    // MARK: - Public API

    /// Start a fresh download, or resume from the last paused checkpoint if
    /// `pause()` was called on a previous run.
    public func start() {
        // Ensure parent directory exists before the task finishes.
        let parent = Self.modelPath().deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        if let resumeData {
            task = session.downloadTask(withResumeData: resumeData)
            self.resumeData = nil
        } else {
            task = session.downloadTask(with: Self.modelURL)
        }
        state = .downloading
        progress = 0
        lastBytes = 0
        lastSampleAt = Date()
        task?.resume()
    }

    /// Pause an in-flight download. Produces resume data held in memory;
    /// the next call to `start()` (or `resume()`) continues from the Range
    /// checkpoint.
    public func pause() {
        guard let task else { return }
        task.cancel(byProducingResumeData: { [weak self] data in
            Task { @MainActor in
                guard let self else { return }
                self.resumeData = data
                self.state = .paused
            }
        })
        self.task = nil
    }

    /// Equivalent to `start()` — kept as a distinct verb for call-site clarity.
    public func resume() { start() }

    /// Test helper: start and await completion or failure.
    /// Throws the underlying `URLSession` / file-system error on failure.
    public func startAndWaitForCompletion() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.completionContinuation = cont
            self.start()
        }
    }

    /// Test helper: await whatever in-flight download settles. Polls state at
    /// 50 ms intervals. Safe to call when `state` is already terminal.
    public func waitForCompletion() async {
        while state == .downloading || state == .paused {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    // MARK: - URLSessionDownloadDelegate

    public nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        // Snapshot values off the delegate queue, hop to MainActor for @Published.
        let written = totalBytesWritten
        let expected = totalBytesExpectedToWrite
        Task { @MainActor in
            guard expected > 0 else { return }
            self.progress = Double(written) / Double(expected)
            let now = Date()
            let elapsed = now.timeIntervalSince(self.lastSampleAt)
            if elapsed > 0.5 {
                let delta = Double(written - self.lastBytes)
                self.bytesPerSec = delta / elapsed
                self.lastBytes = written
                self.lastSampleAt = now
            }
        }
    }

    public nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Called on delegate queue. Move the file synchronously while `location`
        // is still valid (iOS deletes the temp file as soon as this method returns),
        // then hop to MainActor for the state publish.
        let dest = Self.modelPath()
        let parent = dest.deletingLastPathComponent()
        var moveError: Error?
        do {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            // Overwrite any stale file (e.g. failed previous run).
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: location, to: dest)

            // Q6 / D-14: exclude from iCloud backup. ~1.93 GB cacheable blob should
            // never bloat user backups; Apple App Review flags this.
            var urlRef = dest
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try urlRef.setResourceValues(values)

            // CLEANRD-01: reclaim disk from the retired Gemma model now that Qwen is present.
            Self.removeOrphanedModelsIfPresent()
        } catch {
            moveError = error
        }

        Task { @MainActor in
            if let moveError {
                self.state = .failed("Failed to save model: \(moveError.localizedDescription)")
                self.completionContinuation?.resume(throwing: moveError)
            } else {
                self.progress = 1.0
                self.state = .completed
                self.completionContinuation?.resume()
            }
            self.completionContinuation = nil
            self.task = nil
        }
    }

    public nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        let nsError = error as NSError
        // User-initiated pause — `cancel(byProducingResumeData:)` raises
        // NSURLErrorCancelled which is not a failure.
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return
        }
        Task { @MainActor in
            self.state = .failed(error.localizedDescription)
            self.completionContinuation?.resume(throwing: error)
            self.completionContinuation = nil
        }
    }
}
