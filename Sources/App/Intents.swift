import AppIntents

/// Shortcuts and Siri. Each intent hops to the main actor: Session lives there.
struct StartSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Session"
    static let description = IntentDescription("Plays a mode, optionally for a set length.")
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Mode") var mode: Mode
    @Parameter(title: "Length") var length: SessionLength?

    static var parameterSummary: some ParameterSummary {
        Summary("Start \(\.$mode)") {
            \.$length
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let session = Session.shared
        session.mode = mode
        if let length { session.length = length }
        session.play()
        guard session.isPlaying else { throw SessionIntentError.audioUnavailable }
        return .result()
    }
}

struct StopSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Session"
    static let description = IntentDescription("Pauses playback. The timer keeps its place.")
    static var supportedModes: IntentModes { .background }

    @MainActor
    func perform() async throws -> some IntentResult {
        Session.shared.pause()
        return .result()
    }
}

struct ToggleSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Play or Pause"
    static let description = IntentDescription("Toggles playback of the current mode.")
    static var supportedModes: IntentModes { .background }

    @MainActor
    func perform() async throws -> some IntentResult {
        let session = Session.shared
        session.toggle()
        if let error = session.error { throw SessionIntentError.failed(error) }
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

// Raw values double as the persisted identity of saved shortcuts: never rename them.

extension Mode: AppEnum {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Mode")
    static let caseDisplayRepresentations: [Mode: DisplayRepresentation] = [
        .focus: "Focus",
        .relax: "Relax",
        .meditate: "Meditate",
        .sleep: "Sleep",
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
