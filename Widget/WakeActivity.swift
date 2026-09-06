#if canImport(AlarmKit)
import ActivityKit
import AlarmKit
import AppIntents
import SwiftUI
import WidgetKit

/// The Wake alarm on the Lock Screen and in the Dynamic Island: how long
/// until it rings, the time it rings at, a bar that fills as it approaches,
/// and a way to cancel. Once it rings the system takes over with its own
/// Dismiss and Start Wake buttons.
struct WakeActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<WakeAlarmMetadata>.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(Color(red: 0.07, green: 0.06, blue: 0.20))
                .activitySystemActionForegroundColor(Mode.wake.tint)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(Mode.wake.title, systemImage: Mode.wake.symbol)
                        .font(.headline)
                        .foregroundStyle(Mode.wake.tint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(state: context.state)
                        .font(.title2.weight(.medium).monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 12) {
                        Progress(state: context.state)
                        CancelButton()
                    }
                }
            } compactLeading: {
                Image(systemName: Mode.wake.symbol)
                    .foregroundStyle(Mode.wake.tint)
            } compactTrailing: {
                Countdown(state: context.state)
                    .monospacedDigit()
                    .frame(maxWidth: 64)
            } minimal: {
                Image(systemName: Mode.wake.symbol)
                    .foregroundStyle(Mode.wake.tint)
            }
            .keylineTint(Mode.wake.tint)
        }
    }
}

private struct LockScreenView: View {
    let state: AlarmPresentationState

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: Mode.wake.symbol)
                    .font(.title2)
                    .foregroundStyle(Mode.wake.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Mode.wake.title)
                        .font(.headline)
                    if let fireDate = state.fireDate {
                        Text("Rings at \(fireDate, style: .time)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Countdown(state: state)
                    .font(.system(size: 34, weight: .light, design: .rounded).monospacedDigit())
            }
            HStack(spacing: 12) {
                Progress(state: state)
                CancelButton()
            }
        }
        .padding(16)
    }
}

/// Time left, live while counting down.
private struct Countdown: View {
    let state: AlarmPresentationState

    var body: some View {
        switch state.mode {
        case .countdown(let countdown):
            Text(timerInterval: Date.now...countdown.fireDate, countsDown: true)
        case .paused(let paused):
            Text(Int(paused.totalCountdownDuration - paused.previouslyElapsedDuration).countdown)
        default:
            Text("Now")
        }
    }
}

/// Fills from when the alarm was set to when it rings.
private struct Progress: View {
    let state: AlarmPresentationState

    var body: some View {
        if case .countdown(let countdown) = state.mode {
            ProgressView(timerInterval: countdown.startDate...countdown.fireDate, countsDown: false, label: {}, currentValueLabel: {})
                .tint(Mode.wake.tint)
        }
    }
}

private struct CancelButton: View {
    var body: some View {
        Button(intent: CancelWakeAlarmIntent()) {
            Label("Cancel", systemImage: "xmark")
                .font(.footnote.weight(.semibold))
                .labelStyle(.titleOnly)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .tint(.white.opacity(0.8))
    }
}

private extension AlarmPresentationState {
    var fireDate: Date? {
        if case .countdown(let countdown) = mode { return countdown.fireDate }
        return nil
    }
}
#endif
