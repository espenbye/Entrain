#if os(iOS)
import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// A timed session on the Lock Screen and in the Dynamic Island: the mode,
/// its sound, how long is left and a play/pause button. The countdown runs
/// from the deadline, so the app never updates it per second; a pause
/// freezes it and says so.
struct SessionActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(Color(red: 0.07, green: 0.06, blue: 0.20))
                .activitySystemActionForegroundColor(context.state.mode.tint)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.mode.title, systemImage: context.state.mode.symbol)
                        .font(.headline)
                        .foregroundStyle(context.state.mode.tint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(state: context.state)
                        .font(.title2.weight(.medium).monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 12) {
                        Status(sound: context.state.sound, state: context.state)
                        Spacer()
                        ToggleButton(mode: context.state.mode, state: context.state)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.mode.symbol)
                    .foregroundStyle(context.state.mode.tint)
            } compactTrailing: {
                Countdown(state: context.state)
                    .monospacedDigit()
                    .frame(maxWidth: 64)
            } minimal: {
                Image(systemName: context.state.isPlaying ? context.state.mode.symbol : "pause.fill")
                    .foregroundStyle(context.state.mode.tint)
            }
            .keylineTint(context.state.mode.tint)
        }
    }
}

private struct LockScreenView: View {
    let state: SessionActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: state.mode.symbol)
                .font(.title2)
                .foregroundStyle(state.mode.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.mode.title)
                    .font(.headline)
                Status(sound: state.sound, state: state)
            }
            .lineLimit(1)
            Spacer()
            Countdown(state: state)
                .font(.system(size: 34, weight: .light, design: .rounded).monospacedDigit())
            ToggleButton(mode: state.mode, state: state)
        }
        .padding(16)
    }
}

/// Time left. Runs while playing; a pause freezes it at the pause instant.
private struct Countdown: View {
    let state: SessionActivityAttributes.ContentState

    var body: some View {
        let start = min(state.pausedAt ?? .now, state.deadline)
        Text(timerInterval: start...state.deadline, pauseTime: state.pausedAt, countsDown: true)
    }
}

/// The sound while playing, "Paused" otherwise.
private struct Status: View {
    let sound: String
    let state: SessionActivityAttributes.ContentState

    var body: some View {
        Group {
            if state.isPlaying {
                Text(sound)
            } else {
                Text("Paused")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
}

private struct ToggleButton: View {
    let mode: Mode
    let state: SessionActivityAttributes.ContentState

    var body: some View {
        Button(intent: ToggleSessionIntent()) {
            Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                .font(.title3)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .tint(mode.tint)
        .accessibilityLabel(state.isPlaying ? "Pause" : "Play")
    }
}
#endif
