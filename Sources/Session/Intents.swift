import AppIntents

/// An intent that may start a session from the background. On iOS that
/// start also opens the session's Live Activity, which `Activity.request`
/// only allows from a `LiveActivityIntent`; the other platforms have none.
#if os(iOS)
protocol StartsSession: LiveActivityIntent {}
#else
protocol StartsSession: AppIntent {}
#endif

/// Shortcuts, Siri and the widget. Each intent hops to the main actor:
/// Session lives there. The widget compiles these too, to build its buttons,
/// but every run is pinned to the app process where the session is, so the
/// widget copies never perform. `AudioPlaybackIntent` lets iOS launch the app
/// in the background from a widget or Control Center and start audio there.
struct StartSessionIntent: AppIntent, AudioPlaybackIntent, StartsSession {
    static let title: LocalizedStringResource = "Start Session"
    static let description = IntentDescription("Plays a mode, optionally for a set length.")
    static var supportedModes: IntentModes { .background }
    #if compiler(>=6.4)
    @available(macOS 27, iOS 27, watchOS 27, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    @Parameter(title: "Mode") var mode: Mode
    @Parameter(title: "Length") var length: SessionLength?

    init() {}

    init(mode: Mode) {
        self.mode = mode
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Start \(\.$mode)") {
            \.$length
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET
        let session = Session.shared
        session.mode = mode
        if let length { session.length = length }
        await session.play()
        guard session.isPlaying else { throw SessionIntentError.audioUnavailable }
        #endif
        return .result()
    }
}

struct StopSessionIntent: AppIntent, AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Stop Session"
    static let description = IntentDescription("Pauses playback. The timer keeps its place.")
    static var supportedModes: IntentModes { .background }
    #if compiler(>=6.4)
    @available(macOS 27, iOS 27, watchOS 27, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET
        Session.shared.pause()
        #endif
        return .result()
    }
}

struct ToggleSessionIntent: AppIntent, AudioPlaybackIntent, StartsSession {
    static let title: LocalizedStringResource = "Play or Pause"
    static let description = IntentDescription("Toggles playback of the current mode.")
    static var supportedModes: IntentModes { .background }
    #if compiler(>=6.4)
    @available(macOS 27, iOS 27, watchOS 27, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET
        let session = Session.shared
        await session.toggle()
        if let error = session.error { throw SessionIntentError.failed(error) }
        #endif
        return .result()
    }
}

/// Follow the Day from outside the app: a widget button, a Control Center
/// toggle or a spoken shortcut. It starts playing as well as switching the
/// program on, because `Program` only ever runs while something is playing
/// — a day nobody can hear is not being followed — and because every other
/// way into the day from outside the app starts a session too.
struct FollowDayIntent: AppIntent, AudioPlaybackIntent, StartsSession {
    static let title: LocalizedStringResource = "Follow the Day"
    static let description = IntentDescription("Plays what the hour asks for, and keeps moving with it.")
    static var supportedModes: IntentModes { .background }
    #if compiler(>=6.4)
    @available(macOS 27, iOS 27, watchOS 27, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET
        let session = Session.shared
        await session.start(.day)
        guard session.isPlaying else { throw SessionIntentError.audioUnavailable }
        #endif
        return .result()
    }
}

/// Behind the Follow the Day control: on follows the day, off pauses, which
/// is the bargain the mode toggles already make. Off does not switch the
/// program off — a paused program runs no clock of its own, and turning it
/// off here would mean the next play came back on a mode nobody chose.
struct SetFollowingDayIntent: SetValueIntent, AudioPlaybackIntent, StartsSession {
    static let title: LocalizedStringResource = "Set Following the Day"
    static let description = IntentDescription("Follows the day, or pauses it.")
    static var supportedModes: IntentModes { .background }
    #if compiler(>=6.4)
    @available(macOS 27, iOS 27, watchOS 27, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    @Parameter(title: "Following") var value: Bool

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET
        let session = Session.shared
        if value {
            await session.start(.day)
            guard session.isPlaying else { throw SessionIntentError.audioUnavailable }
        } else {
            session.pause()
        }
        #endif
        return .result()
    }
}

/// Behind the plain Entrain control: whatever is set, playing or paused.
/// `ToggleSessionIntent` cannot sit in Control Center, which wants a value
/// it can light up rather than a button that flips one it cannot see.
struct SetSessionPlayingIntent: SetValueIntent, AudioPlaybackIntent, StartsSession {
    static let title: LocalizedStringResource = "Set Playing"
    static let description = IntentDescription("Plays or pauses the current mode.")
    static var supportedModes: IntentModes { .background }
    #if compiler(>=6.4)
    @available(macOS 27, iOS 27, watchOS 27, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    @Parameter(title: "Playing") var value: Bool

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET
        let session = Session.shared
        if value {
            await session.play()
            guard session.isPlaying else { throw SessionIntentError.audioUnavailable }
        } else {
            session.pause()
        }
        #endif
        return .result()
    }
}

/// Behind each Control Center toggle: on starts the mode, off pauses.
struct SetModePlayingIntent: SetValueIntent, AudioPlaybackIntent, StartsSession {
    static let title: LocalizedStringResource = "Set Mode Playing"
    static var supportedModes: IntentModes { .background }
    #if compiler(>=6.4)
    @available(macOS 27, iOS 27, watchOS 27, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    @Parameter(title: "Mode") var mode: Mode
    @Parameter(title: "Playing") var value: Bool

    init() {}

    init(mode: Mode) {
        self.mode = mode
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET
        let session = Session.shared
        if value {
            session.mode = mode
            await session.play()
            guard session.isPlaying else { throw SessionIntentError.audioUnavailable }
        } else {
            session.pause()
        }
        #endif
        return .result()
    }
}

enum SessionIntentError: Error, CustomLocalizedStringResourceConvertible {
    case audioUnavailable
    case failed(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .audioUnavailable: "Entrain could not start audio."
        case .failed(let reason): "Entrain could not play: \(reason)"
        }
    }
}

#if !WIDGET
struct EntrainShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartSessionIntent(),
            phrases: [
                "Start \(\.$mode) in \(.applicationName)",
                "Start a \(\.$mode) session in \(.applicationName)",
            ],
            shortTitle: "Start Session",
            systemImageName: "waveform"
        )
        AppShortcut(
            intent: FollowDayIntent(),
            phrases: [
                "Follow the day in \(.applicationName)",
                "Follow my day in \(.applicationName)",
            ],
            shortTitle: "Follow the Day",
            // A literal, not `ModeChoice.symbol`: this argument is a
            // compile-time constant, and a `static let` is not one.
            systemImageName: "sun.horizon"
        )
        AppShortcut(
            intent: StopSessionIntent(),
            phrases: ["Stop \(.applicationName)"],
            shortTitle: "Stop",
            systemImageName: "pause.fill"
        )
        AppShortcut(
            intent: ToggleSessionIntent(),
            phrases: ["Toggle \(.applicationName)"],
            shortTitle: "Play or Pause",
            systemImageName: "playpause.fill"
        )
        AppShortcut(
            intent: GetStateIntent(),
            phrases: ["What is \(.applicationName) playing"],
            shortTitle: "What's Playing",
            systemImageName: "info.circle"
        )
    }
}
#endif

// Raw values double as the persisted identity of saved shortcuts: never rename them.

extension Mode: AppEnum {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Mode")
    static let caseDisplayRepresentations: [Mode: DisplayRepresentation] = [
        .focus: "Focus",
        .gamma: "Recall",
        .sprint: "Sprint",
        .relax: "Relax",
        .meditate: "Meditate",
        .restore: "Restore",
        .sleep: "Sleep",
        .deepSleep: "Deep Sleep",
        .nap: "Nap",
        .windDown: "Wind Down",
        .wake: "Wake",
    ]
}

extension Intensity: AppEnum {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Intensity")
    static let caseDisplayRepresentations: [Intensity: DisplayRepresentation] = [
        .low: "Low",
        .medium: "Medium",
        .high: "High",
        .strong: "Strong",
    ]
}

extension SessionLength: AppEnum {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Length")
    static let caseDisplayRepresentations: [SessionLength: DisplayRepresentation] = [
        .endless: "Endless",
        .fifteen: "15 minutes",
        .thirty: "30 minutes",
        .sixty: "60 minutes",
        .ninety: "90 minutes",
        .twoHours: "2 hours",
        .fourHours: "4 hours",
        .eightHours: "8 hours",
    ]
}
