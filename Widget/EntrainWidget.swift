import AppIntents
import SwiftUI
import WidgetKit

@main
struct EntrainWidgets: WidgetBundle {
    var body: some Widget {
        EntrainWidget()
        DayWidget()
        #if canImport(AlarmKit)
        WakeActivity()
        SessionActivity()
        #endif
        #if !os(watchOS)
        SessionControl()
        FollowDayControl()
        FocusControl()
        GammaControl()
        SprintControl()
        RelaxControl()
        MeditateControl()
        RestoreControl()
        SleepControl()
        DeepSleepControl()
        NapControl()
        WindDownControl()
        WakeControl()
        #endif
    }
}

struct EntrainWidget: Widget {
    /// Desktop and Home Screen sizes where they exist, plus the Lock Screen
    /// and Smart Stack accessories on iPhone and watch.
    private static let families: [WidgetFamily] = {
        #if os(macOS)
        [.systemSmall, .systemMedium, .systemLarge]
        #elseif os(iOS)
        [.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline]
        #else
        [.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline]
        #endif
    }()

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetState.kind, provider: Provider()) { entry in
            WidgetView(state: entry.state)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Entrain")
        .description("Play, pause and switch modes.")
        .supportedFamilies(Self.families)
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let state: WidgetState
}

/// The app reloads the timeline whenever the session changes and the
/// countdown is drawn from the deadline, so one entry does. A timed session
/// adds a stopped entry at its deadline, in case the app is gone by then.
struct Provider: TimelineProvider {
    private static let placeholder = WidgetState(mode: .focus, sound: "Rain", isPlaying: false, remaining: nil, deadline: nil)

    func placeholder(in context: Context) -> Entry {
        Entry(date: .now, state: Self.placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now, state: (WidgetState.load() ?? Self.placeholder).at(.now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let state = WidgetState.load() ?? Self.placeholder
        var entries = [Entry(date: .now, state: state.at(.now))]
        if state.isPlaying, let deadline = state.deadline, deadline > .now {
            entries.append(Entry(date: deadline, state: state.at(deadline)))
        }
        completion(Timeline(entries: entries, policy: .never))
    }
}

struct WidgetView: View {
    let state: WidgetState
    @Environment(\.widgetFamily) private var family

    /// What the widget lights up, which is the day whenever the day is in
    /// charge: the same reading `Session.choice` makes, so the grid here and
    /// the list in the player never disagree about what is selected.
    private var choice: ModeChoice { state.program ? .day : .mode(state.mode) }

    /// The sound, or what the day is doing. While the program owns the mode
    /// the second is the more useful of the two: the name above it changes
    /// on its own at every boundary, and this is the line that says why.
    private var subtitle: String {
        state.program ? String(localized: "Following your day") : state.sound
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label {
                Text(verbatim: state.mode.title + " ") + countdownText
            } icon: {
                Image(systemName: choice.symbol)
            }
        case .accessoryRectangular:
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(state.mode.title, systemImage: choice.symbol)
                        .font(.headline)
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                    countdown
                        .font(.body.monospacedDigit())
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                #if os(watchOS)
                toggle
                    .font(.title2)
                #endif
            }
        #if os(watchOS)
        // The Smart Stack runs widget buttons; the Lock Screen on iOS does not,
        // so only the watch gets one. The circular is nothing but the button;
        // the corner keeps its curved label and opens the app.
        case .accessoryCircular:
            toggle
                .font(.title2)
        case .accessoryCorner:
            Image(systemName: state.isPlaying ? choice.symbol : "pause.fill")
                .font(.title2)
                .widgetLabel { countdownText }
        #endif
        #if !os(watchOS)
        // The one size where the names fit. Icons alone are a guessing game
        // at eleven modes, and the large widget has the room to end it.
        case .systemLarge:
            VStack(spacing: 10) {
                header
                Divider()
                choices(named: true)
                Spacer(minLength: 0)
            }
        #endif
        default:
            HStack(spacing: 12) {
                status
                #if !os(watchOS)
                if family == .systemMedium {
                    choices(named: false)
                }
                #endif
            }
        }
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(state.mode.title, systemImage: choice.symbol)
                .font(.headline)
                .lineLimit(1)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            countdown
                .font(.title3.monospacedDigit())
                .lineLimit(1)
            #if !os(watchOS)
            Button(intent: ToggleSessionIntent()) {
                Label(state.isPlaying ? "Pause" : "Play", systemImage: state.isPlaying ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.accentColor)
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    #if !os(watchOS)
    /// The large widget's top line. What is playing reads across rather than
    /// down here, because the grid below it wants the height.
    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: choice.symbol)
                .font(.title2)
                .foregroundStyle(state.mode.tint)
                .frame(width: 36, height: 36)
                .background(state.mode.tint.opacity(0.25), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.mode.title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            countdown
                .font(.title3.monospacedDigit())
                .lineLimit(1)
            Button(intent: ToggleSessionIntent()) {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .tint(.accentColor)
            .accessibilityLabel(state.isPlaying ? "Pause" : "Play")
        }
    }
    #endif

    #if os(watchOS)
    private var toggle: some View {
        Button(intent: ToggleSessionIntent()) {
            Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .accessibilityLabel(state.isPlaying ? "Pause" : "Play")
    }
    #endif

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

    /// The countdown as one Text, for the places that concatenate.
    private var countdownText: Text {
        if state.isPlaying, let deadline = state.deadline {
            Text(timerInterval: Date.now...deadline, countsDown: true)
        } else if let remaining = state.remaining {
            Text(remaining.countdown)
        } else {
            Text(state.isPlaying ? "Playing" : "Paused")
        }
    }

    #if !os(watchOS)
    /// Every mode, and the day after them: the same twelve the player's list
    /// offers, three across. Icon-only at medium, where the names would not
    /// fit and the current choice is spelled out on the left; named at
    /// large, where they do fit and a grid of symbols alone is a quiz.
    private func choices(named: Bool) -> some View {
        let all = ModeChoice.all
        return Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(Array(stride(from: 0, to: all.count, by: 3)), id: \.self) { start in
                GridRow {
                    ForEach(all[start..<min(start + 3, all.count)], id: \.self) { item in
                        ChoiceButton(choice: item, active: item == choice, named: named)
                    }
                }
            }
        }
        .fixedSize(horizontal: !named, vertical: false)
    }
    #endif
}

#if !os(watchOS)
/// One cell of the widget's grid: a mode to start, or the day to follow.
/// Both are one tap into a playing session, which is the whole point of a
/// button on a widget — the alternative is opening the app to press the
/// same thing.
struct ChoiceButton: View {
    let choice: ModeChoice
    let active: Bool
    var named = false

    var body: some View {
        button
            .buttonStyle(.bordered)
            .tint(active ? .accentColor : nil)
            .accessibilityLabel(choice.title)
    }

    @ViewBuilder
    private var button: some View {
        switch choice {
        case .day:
            Button(intent: FollowDayIntent()) { label }
        case .mode(let mode):
            Button(intent: StartSessionIntent(mode: mode)) { label }
        }
    }

    @ViewBuilder
    private var label: some View {
        if named {
            Label(choice.title, systemImage: choice.symbol)
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Image(systemName: choice.symbol)
                .font(.title3)
                .frame(width: 32, height: 32)
        }
    }
}

/// The session as the controls read it, out of the same snapshot the widget
/// draws. Control Center is reloaded from `Session.broadcast`, so a control
/// is never further behind than the file is.
struct SessionControlValue {
    var mode: Mode = .focus
    var isPlaying = false
    var program = false

    static var current: SessionControlValue {
        guard let state = WidgetState.load()?.at(.now) else { return SessionControlValue() }
        return SessionControlValue(mode: state.mode, isPlaying: state.isPlaying, program: state.program)
    }
}

struct SessionControlProvider: ControlValueProvider {
    var previewValue: SessionControlValue { SessionControlValue() }

    func currentValue() async throws -> SessionControlValue { .current }
}

/// Play or pause whatever Entrain is set to, without having to know which
/// of the twelve toggles below that is. The one control somebody who only
/// ever plays one mode actually wants.
struct SessionControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "no.espenbye.entrain.control.session", provider: SessionControlProvider()) { value in
            ControlWidgetToggle(value.mode.title, isOn: value.isPlaying, action: SetSessionPlayingIntent()) { isOn in
                Label(isOn ? "Playing" : "Paused", systemImage: isOn ? value.mode.symbol : "pause.fill")
            }
        }
        .displayName("Play or Pause")
        .description("Plays or pauses whatever Entrain is set to.")
    }
}

/// Follow the Day from Control Center or the Action button. On means the
/// day is playing and moving on its own; the mode toggles below stay dark
/// while it is, because the mode they would be lit for is the day's pick.
struct FollowDayControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "no.espenbye.entrain.control.day", provider: SessionControlProvider()) { value in
            ControlWidgetToggle(
                String(localized: "Follow the Day"),
                isOn: value.isPlaying && value.program,
                action: SetFollowingDayIntent()
            ) { isOn in
                Label(isOn ? "Following" : "Paused", systemImage: ModeChoice.symbol)
            }
        }
        .displayName("Follow the Day")
        .description("Plays what the hour asks for, and keeps moving with it.")
    }
}

/// One Control Center toggle per mode. On means that mode is playing;
/// switching it off pauses the session. WidgetKit needs a distinct type per
/// control, so each mode gets a one-line wrapper around the shared body.
struct ModeControlValue {
    let mode: Mode
    let isOn: Bool
}

struct ModeControlProvider: ControlValueProvider {
    let mode: Mode

    var previewValue: ModeControlValue { ModeControlValue(mode: mode, isOn: false) }

    func currentValue() async throws -> ModeControlValue {
        let state = WidgetState.load()?.at(.now)
        // Dark while the day is in charge, even on the mode the day happens
        // to be playing: this toggle did not choose it, and lighting it up
        // would offer to switch off something it never switched on.
        let isOn = state?.isPlaying == true && state?.program == false && state?.mode == mode
        return ModeControlValue(mode: mode, isOn: isOn)
    }
}

extension Mode {
    var controlKind: String { "no.espenbye.entrain.control.\(rawValue)" }
}

@MainActor
func modeControl(_ mode: Mode) -> some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: mode.controlKind, provider: ModeControlProvider(mode: mode)) { value in
        ControlWidgetToggle(mode.title, isOn: value.isOn, action: SetModePlayingIntent(mode: mode)) { isOn in
            Label(isOn ? "Playing" : "Paused", systemImage: mode.symbol)
        }
    }
    .displayName(mode.name)
    .description("Plays or pauses \(mode.title).")
}

struct FocusControl: ControlWidget { var body: some ControlWidgetConfiguration { modeControl(.focus) } }
struct GammaControl: ControlWidget { var body: some ControlWidgetConfiguration { modeControl(.gamma) } }
struct SprintControl: ControlWidget { var body: some ControlWidgetConfiguration { modeControl(.sprint) } }
struct RelaxControl: ControlWidget { var body: some ControlWidgetConfiguration { modeControl(.relax) } }
struct MeditateControl: ControlWidget { var body: some ControlWidgetConfiguration { modeControl(.meditate) } }
struct RestoreControl: ControlWidget { var body: some ControlWidgetConfiguration { modeControl(.restore) } }
struct SleepControl: ControlWidget { var body: some ControlWidgetConfiguration { modeControl(.sleep) } }
struct DeepSleepControl: ControlWidget { var body: some ControlWidgetConfiguration { modeControl(.deepSleep) } }
struct NapControl: ControlWidget { var body: some ControlWidgetConfiguration { modeControl(.nap) } }
struct WindDownControl: ControlWidget { var body: some ControlWidgetConfiguration { modeControl(.windDown) } }
struct WakeControl: ControlWidget { var body: some ControlWidgetConfiguration { modeControl(.wake) } }
#endif
