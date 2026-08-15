import SwiftUI

/// The four fully-specified warm-up stages a user can see on Home, per
/// `46-UI-SPEC.md`'s Component Inventory. `nil` means "render nothing" — there is
/// deliberately no resting "Ready" state (E1 empty).
enum WarmupBannerStage: Equatable {
    case modelMissing
    case downloading
    case loading
    case failed

    /// Pure stage-selection function, free of SwiftUI and service types so it is
    /// directly unit-testable — the whole point of extracting it is that the icon,
    /// the copy and the progress element can never silently drift apart the way
    /// three separately-derived computed properties can.
    ///
    /// Precedence: a present error with warm-up not running wins over everything else
    /// (regardless of `hasModels`/`isReady`); then warming with the model already on
    /// disk is `.loading`; warming without the model on disk is `.downloading`;
    /// otherwise, if the model is ready, there is nothing to show (`nil`); otherwise,
    /// if there is no model on disk, `.modelMissing`.
    static func resolve(hasModels: Bool, isWarming: Bool, isReady: Bool, error: String?) -> WarmupBannerStage? {
        if error != nil, !isWarming {
            return .failed
        }
        if isWarming {
            return hasModels ? .loading : .downloading
        }
        if isReady {
            return nil
        }
        if !hasModels {
            return .modelMissing
        }
        return nil
    }
}

/// Non-blocking warm-up status card, per `46-UI-SPEC.md`'s "Warm-up status banner"
/// Component Inventory row. Renders beside the mic button, never instead of it —
/// the mic button's own enabled state is driven entirely separately (`DictationView`),
/// so this view carries no ability to gate anything.
struct WarmupStatusBanner: View {
    let stage: WarmupBannerStage
    let downloadProgress: Double
    let warmupStartedAt: Date?
    let error: String?
    /// 260815-ait Fix 5: true when the current `.loading` warm-up is the first one
    /// for this app build/model (see `IOSModelWarmupService.isFirstWarmupForCurrentVersion`)
    /// — selects the honest "First-time setup…" copy over the fast-path copy below.
    /// Defaults to `false` (via the explicit initializer below) so existing call
    /// sites and the locked fast-copy test stay unchanged.
    let isFirstWarmup: Bool
    let onDownloadNow: () -> Void
    let onRetry: () -> Void

    init(
        stage: WarmupBannerStage,
        downloadProgress: Double,
        warmupStartedAt: Date?,
        error: String?,
        isFirstWarmup: Bool = false,
        onDownloadNow: @escaping () -> Void,
        onRetry: @escaping () -> Void
    ) {
        self.stage = stage
        self.downloadProgress = downloadProgress
        self.warmupStartedAt = warmupStartedAt
        self.error = error
        self.isFirstWarmup = isFirstWarmup
        self.onDownloadNow = onDownloadNow
        self.onRetry = onRetry
    }

    /// `warning` is a declared `DESIGN.md` token but iOS ships no color-asset
    /// catalog yet (confirmed absent — see 46-04-SUMMARY.md follow-up note), so this
    /// falls back to the system `.orange` per this task's own instruction rather than
    /// hardcoding the spec's hex value.
    private var warningTint: Color { .orange }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(iconTint)
                .symbolEffect(.pulse, isActive: stage == .loading)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text(headline)
                    .font(.headline)

                Text(bodyText)
                    .font(.body)
                    .foregroundStyle(.secondary)

                progressElement
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(headline)
        .accessibilityValue(bodyText)
    }

    @ViewBuilder
    private var progressElement: some View {
        switch stage {
        case .downloading:
            if downloadProgress > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: downloadProgress, total: 1.0)
                        .progressViewStyle(.linear)
                    Text("\(Int(downloadProgress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Download progress")
                .accessibilityValue("\(Int(downloadProgress * 100)) percent")
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
                    .accessibilityLabel("Starting download")
            }
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .progressViewStyle(.circular)
                if let warmupStartedAt {
                    Text(warmupStartedAt, style: .timer)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Elapsed time")
                }
            }
        case .modelMissing:
            Button("Download Now", action: onDownloadNow)
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
        case .failed:
            Button("Retry", action: onRetry)
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
        }
    }

    /// Internal (not `private`) so `WarmupStatusBannerTests` can assert the exact
    /// copy per stage by constructing a `WarmupStatusBanner` value directly and
    /// reading this property — no rendering required, and the strings cannot drift
    /// from the locked `46-UI-SPEC.md` Copywriting Contract without a test noticing.
    var headline: String {
        switch stage {
        case .downloading:   return "Downloading speech model\u{2026}"
        case .loading:       return "Go ahead — you can start recording"
        case .modelMissing:  return "Speech model not downloaded"
        case .failed:        return "Couldn't load the speech model"
        }
    }

    /// See `headline` — same testability rationale.
    var bodyText: String {
        switch stage {
        case .downloading:
            return "One-time download, about 626 MB. You can start recording anytime — we'll transcribe once it's ready."
        case .loading:
            // 260815-ait Fix 5: the first ANE recompile for a build/model can take
            // ~60-90s, not "a few seconds" — the fast-path copy would look like a
            // hang during that window, so the first warm-up gets honest copy.
            return isFirstWarmup
                ? "First-time setup \u{2014} preparing the speech model. This can take up to a minute."
                : "Dicticus is getting ready in the background, which takes a few seconds. It'll catch up with what you've said as soon as it's done."
        case .modelMissing:
            return "Recordings will wait until you download it."
        case .failed:
            return error ?? "Unknown error."
        }
    }

    /// See `headline` — same testability rationale (SF Symbol name, easy to assert exactly).
    var iconName: String {
        switch stage {
        case .downloading:   return "arrow.down.circle"
        case .loading:       return "gearshape.2"
        case .modelMissing:  return "tray.and.arrow.down"
        case .failed:        return "exclamationmark.triangle.fill"
        }
    }

    private var iconTint: Color {
        switch stage {
        case .downloading:   return .accentColor
        case .loading:       return .secondary
        case .modelMissing:  return warningTint
        case .failed:        return warningTint
        }
    }
}

#Preview("Downloading") {
    WarmupStatusBanner(
        stage: .downloading,
        downloadProgress: 0.42,
        warmupStartedAt: nil,
        error: nil,
        onDownloadNow: {},
        onRetry: {}
    )
}

#Preview("Downloading — no progress yet") {
    WarmupStatusBanner(
        stage: .downloading,
        downloadProgress: 0,
        warmupStartedAt: nil,
        error: nil,
        onDownloadNow: {},
        onRetry: {}
    )
}

#Preview("Loading") {
    WarmupStatusBanner(
        stage: .loading,
        downloadProgress: 0,
        warmupStartedAt: Date(timeIntervalSinceNow: -3),
        error: nil,
        onDownloadNow: {},
        onRetry: {}
    )
}

#Preview("Model missing") {
    WarmupStatusBanner(
        stage: .modelMissing,
        downloadProgress: 0,
        warmupStartedAt: nil,
        error: nil,
        onDownloadNow: {},
        onRetry: {}
    )
}

#Preview("Failed") {
    WarmupStatusBanner(
        stage: .failed,
        downloadProgress: 0,
        warmupStartedAt: nil,
        error: "Model load failed: The network connection was lost.",
        onDownloadNow: {},
        onRetry: {}
    )
}
