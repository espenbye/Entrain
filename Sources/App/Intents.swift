import AppIntents

/// Shortcuts, Siri and the widget. Each intent hops to the main actor:
/// Session lives there. The widget compiles these too, to build its buttons,
/// but every run is pinned to the app process where the session is, so the
/// widget copies never perform.
struct StartSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Session"
    static let description = IntentDescription("Plays a mode, optionally for a set length.")
    static var supportedModes: IntentModes { .background }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

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
        session.play()
        guard session.isPlaying else { throw SessionIntentError.audioUnavailable }
        #endif
        return .result()
    }
}

struct StopSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Session"
    static let description = IntentDescription("Pauses playback. The timer keeps its place.")
    static var supportedModes: IntentModes { .background }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET
        Session.shared.pause()
        #endif
        return .result()
    }
}

struct ToggleSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Play or Pause"
    static let description = IntentDescription("Toggles playback of the current mode.")
    static var supportedModes: IntentModes { .background }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET
        let session = Session.shared
        session.toggle()
        if let error = session.error { throw SessionIntentError.failed(error) }
        #endif
        return .result()
    }
}

/// Behind each Control Center toggle: on starts the mode, off pauses.
struct SetModePlayingIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Set Mode Playing"
    static var supportedModes: IntentModes { .background }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

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
            session.play()
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
    }
}
#endif

// Raw values double as the persisted identity of saved shortcuts: never rename them.

extension Mode: AppEnum {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Mode")
    static let caseDisplayRepresentations: [Mode: DisplayRepresentation] = [
        .focus: "Focus",
        .gamma: "Gamma",
        .relax: "Relax",
        .meditate: "Meditate",
        .sleep: "Sleep",
        .deepSleep: "Deep Sleep",
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
