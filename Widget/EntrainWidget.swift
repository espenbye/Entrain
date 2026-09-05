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
                Divider()
                modes
            }
        }
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(state.mode.title, systemImage: state.mode.symbol)
                .font(.headline)
            Text(state.sound)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            countdown
                .font(.title3.monospacedDigit())
            Button(intent: ToggleSessionIntent()) {
                Label(state.isPlaying ? "Pause" : "Play", systemImage: state.isPlaying ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .tint(.accentColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    /// Two columns: six modes stacked would not fit the medium height.
    private var modes: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
            ForEach(Mode.allCases) { mode in
                Button(intent: StartSessionIntent(mode: mode)) {
                    Label(mode.title, systemImage: mode.symbol)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .tint(mode == state.mode && state.isPlaying ? .accentColor : .secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
