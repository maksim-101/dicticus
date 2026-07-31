import WidgetKit
import SwiftUI
import AppIntents

struct DictationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DictationAttributes.self) { context in
            // Lock-screen banner — primary no-reopen stop surface (D-01a).
            // The Stop button fires StopDictationIntent (LiveActivityIntent),
            // which runs backgrounded and posts .stopDictation without opening the app.
            HStack {
                Image(systemName: "mic.fill").foregroundColor(.red)
                Text(context.state.isRecording ? "Recording\u{2026}" : "Processing\u{2026}")
                Spacer()
                Text(timerInterval: context.state.startedAt...Date.distantFuture, countsDown: false)
                    .monospacedDigit()
                Button(intent: StopDictationIntent()) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14, weight: .bold))
                        .padding(8)
                        .background(Circle().fill(Color.red))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "mic.fill").foregroundColor(.red)
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
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(timerInterval: context.state.startedAt...Date.distantFuture, countsDown: false)
                            .monospacedDigit()
                            .font(.caption)
                            .fixedSize()  // timer is short — never let it expand at expense of label
                        Spacer()
                        Text("Tap to open Dicticus")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .layoutPriority(1)  // prefer label over spacer compression
                    }
                    .padding(.horizontal, 4)  // keep content off the DI edges
                }
            } compactLeading: {
                Image(systemName: "mic.fill").foregroundColor(.red)
            } compactTrailing: {
                Text(timerInterval: context.state.startedAt...Date.distantFuture, countsDown: false)
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "mic.fill").foregroundColor(.red)
            }
        }
    }
}
