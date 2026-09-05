import AppIntents
import SwiftUI
import WidgetKit

@main
struct EntrainWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetState.kind, provider: Provider()) { entry in
            WidgetView(state: entry.state)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Entrain")
        .description("Play, pause and switch modes.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let state: WidgetState
}

/// One entry, never expiring: the app reloads the timeline whenever the
/// session changes, and the countdown is drawn from the deadline.
struct Provider: TimelineProvider {
    private static let placeholder = WidgetState(mode: .focus, sound: "Rain", isPlaying: false, remaining: nil, deadline: nil)

    func placeholder(in context: Context) -> Entry {
        Entry(date: .now, state: Self.placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now, state: WidgetState.load() ?? Self.placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry(date: .now, state: WidgetState.load() ?? Self.placeholder)], policy: .never))
    }
}

struct WidgetView: View {
    let state: WidgetState
    @Environment(\.widgetFamily) private var family

    var body: some View {
        HStack(spacing: 12) {
            status
            if family == .systemMedium {
                modes
            }
        }
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(state.mode.title, systemImage: state.mode.symbol)
                .font(.headline)
                .lineLimit(1)
            Text(state.sound)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            countdown
                .font(.title3.monospacedDigit())
                .lineLimit(1)
            Button(intent: ToggleSessionIntent()) {
                Label(state.isPlaying ? "Pause" : "Play", systemImage: state.isPlaying ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.accentColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var countdown: some View {
        if state.isPlaying, let deadline = state.deadline {
            Text(timerInterval: Date.now...deadline, countsDown: true)
        } else if let remaining = state.remaining {
            Text(remaining.countdown)
        } else {
            Text(state.isPlaying ? "Playing" : "Paused")
                .foregroundStyle(.secondary)
        }
    }

    /// Icon-only, three across: the names would not fit, and the current
    /// mode is spelled out on the left.
    private var modes: some View {
        let modes = Mode.allCases
        return Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(Array(stride(from: 0, to: modes.count, by: 3)), id: \.self) { start in
                GridRow {
                    ForEach(modes[start..<min(start + 3, modes.count)]) { mode in
                        ModeButton(mode: mode, active: mode == state.mode)
                    }
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct ModeButton: View {
    let mode: Mode
    let active: Bool

    var body: some View {
        Button(intent: StartSessionIntent(mode: mode)) {
            Image(systemName: mode.symbol)
                .font(.title3)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.bordered)
        .tint(active ? .accentColor : nil)
        .accessibilityLabel(mode.title)
    }
}
