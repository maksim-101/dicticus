import WidgetKit
import SwiftUI
import AppIntents

struct DictationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DictationAttributes.self) { context in
            // Lock-screen banner — primary no-reopen stop surface (D-01a).
            // The Stop button fires StopDictationIntent (LiveActivityIntent),
            // which runs backgrounded and posts .stopDictation without opening the app.
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.red)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.isRecording ? "Recording" : "Processing")
                        .font(.subheadline.weight(.semibold))
                    // Bounded to DictationAttributes.maxDictationSeconds (not
                    // Date.distantFuture) — see 46-LIVEACTIVITY-REDESIGN.md.
                    Text(timerInterval: context.state.startedAt...context.state.startedAt.addingTimeInterval(DictationAttributes.maxDictationSeconds),
                         countsDown: false, showsHours: false)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(intent: StopDictationIntent()) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14, weight: .bold))
                        .padding(10)
                        .background(Circle().fill(Color.red))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            // Tap-through navigation (user-requested, D-01a-adjacent): tapping the
            // lock-screen banner body opens Dicticus on the Dictate tab. The Stop
            // button above is a LiveActivityIntent and is its own tap target —
            // widgetURL only fires for taps outside interactive elements, so this
            // cannot conflate with or regress the no-reopen Stop path. Handled by
            // DeepLinkRouter, not the pendingDictation mechanism — see its doc
            // comment for why those two must stay separate.
            .widgetURL(URL(string: "dicticus://liveactivity"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.red)
                }
                // Stop button in .trailing (higher-priority region than .bottom) ensures
                // it renders on iOS 26+ where .bottom may be deprioritized on Pro Max.
                // This is the D-01a fix for the "long-press showed no Stop" bug.
                DynamicIslandExpandedRegion(.trailing) {
                    Button(intent: StopDictationIntent()) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 14, weight: .bold))
                            .padding(8)
                            .background(Circle().fill(Color.red))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                }
                // .center sits directly below the camera sensor — HIG's slot for a
                // title/high-level status banner. Filling it lets .bottom hold just
                // the timer, which is why the old label+Spacer .layoutPriority(1)
                // compression fix there is no longer needed (nothing competes with
                // the timer for width in .bottom anymore).
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.isRecording ? "Recording\u{2026}" : "Processing\u{2026}")
                        .font(.footnote.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    // Bounded to DictationAttributes.maxDictationSeconds (not
                    // Date.distantFuture) — see 46-LIVEACTIVITY-REDESIGN.md.
                    // No "Tap to open Dicticus" hint: tapping a Live Activity to
                    // open its app is an existing system-wide convention, and none
                    // of the researched real-world examples spell it out either.
                    Text(timerInterval: context.state.startedAt...context.state.startedAt.addingTimeInterval(DictationAttributes.maxDictationSeconds),
                         countsDown: false, showsHours: false)
                        .font(.title3.weight(.medium))
                        .monospacedDigit()
                        .fixedSize()  // timer is short — never let it expand at expense of the region
                }
            } compactLeading: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.red)
            } compactTrailing: {
                // App identity mark (user-requested 2026-08-11, "like WhatsApp" —
                // the red mic glyph alone says something is recording but not
                // WHICH app). This is a STATIC vector image, not a live-updating
                // element — the lesson from the timer investigation above still
                // holds (only Text(timerInterval:) was ever shown to reserve
                // outsized pill width; a static Image has no such property, and
                // this was measured, not assumed — see
                // 46-LIVEACTIVITY-REDESIGN.md §9). The timer stays out of this
                // region entirely; it lives in the lock-screen banner and the
                // expanded .bottom region only, unchanged.
                Image("LiveActivityAppMark")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 15, height: 15)
            } minimal: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.red)
            }
            // Same tap-through URL as the lock-screen banner (see comment there):
            // tapping the compact pill, minimal presentation, or non-interactive
            // parts of the expanded presentation opens Dicticus on the Dictate
            // tab. The Stop button in .trailing remains its own interactive tap
            // target and is unaffected — StopDictationIntent still runs
            // backgrounded with no app open (D-01a).
            .widgetURL(URL(string: "dicticus://liveactivity"))
        }
    }
}

#Preview("Lock Screen", as: .content, using: DictationAttributes()) {
    DictationLiveActivity()
} contentStates: {
    DictationAttributes.ContentState(isRecording: true, startedAt: .now.addingTimeInterval(-7))
}

#Preview("Dynamic Island Compact", as: .dynamicIsland(.compact), using: DictationAttributes()) {
    DictationLiveActivity()
} contentStates: {
    DictationAttributes.ContentState(isRecording: true, startedAt: .now.addingTimeInterval(-7))
}

#Preview("Dynamic Island Expanded", as: .dynamicIsland(.expanded), using: DictationAttributes()) {
    DictationLiveActivity()
} contentStates: {
    DictationAttributes.ContentState(isRecording: true, startedAt: .now.addingTimeInterval(-7))
}

#Preview("Dynamic Island Minimal", as: .dynamicIsland(.minimal), using: DictationAttributes()) {
    DictationLiveActivity()
} contentStates: {
    DictationAttributes.ContentState(isRecording: true, startedAt: .now.addingTimeInterval(-7))
}
