import AppIntents

/// The session as a value Shortcuts can branch on. Built fresh on every
/// query, so it needs no identity of its own.
struct EntrainState: TransientAppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Entrain State")

    @Property(title: "Mode") var mode: Mode
    @Property(title: "Is Playing") var isPlaying: Bool
    @Property(title: "Sound") var sound: String
    @Property(title: "Remaining Seconds") var remaining: Int?
    @Property(title: "Intensity") var intensity: Intensity
    @Property(title: "Binaural Beats") var binaural: Bool

    init() {}

    @MainActor
    init(_ session: Session) {
        mode = session.mode
        isPlaying = session.isPlaying
        sound = session.layers.title
        remaining = session.remaining
        intensity = session.intensity
        binaural = session.binaural
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(mode.title) · \(sound)",
            subtitle: isPlaying ? "Playing" : "Paused"
        )
    }
}

struct GetStateIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Entrain State"
    static let description = IntentDescription("Returns the mode, whether it is playing, the sound, the time left, the intensity and whether binaural beats are on.")
    static var supportedModes: IntentModes { .background }
    #if compiler(>=6.4)
    @available(macOS 27, iOS 27, watchOS 27, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    @MainActor
    func perform() async throws -> some ReturnsValue<EntrainState> & ProvidesDialog {
        let session = Session.shared
        let dialog: IntentDialog = session.isPlaying ? "Entrain is playing \(session.title)." : "Entrain is paused."
        return .result(value: EntrainState(session), dialog: dialog)
    }
}

// MARK: Settings

struct SetTimerIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Set Timer"
    static let description = IntentDescription("Changes the timer. A running session starts its countdown over.")
    static var supportedModes: IntentModes { .background }
    #if compiler(>=6.4)
    @available(macOS 27, iOS 27, watchOS 27, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    @Parameter(title: "Timer") var value: SessionLength

    static var parameterSummary: some ParameterSummary {
        Summary("Set timer to \(\.$value)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        Session.shared.length = value
        return .result()
    }
}

struct SetIntensityIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Set Intensity"
    static let description = IntentDescription("Changes how deep the modulation goes. The sleep modes ignore it.")
    static var supportedModes: IntentModes { .background }
    #if compiler(>=6.4)
    @available(macOS 27, iOS 27, watchOS 27, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    @Parameter(title: "Intensity") var value: Intensity

    static var parameterSummary: some ParameterSummary {
        Summary("Set intensity to \(\.$value)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        Session.shared.intensity = value
        return .result()
    }
}

struct SetVolumeIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Set Volume"
    static let description = IntentDescription("Sets the app's own volume, on top of the system level.")
    static var supportedModes: IntentModes { .background }
    #if compiler(>=6.4)
    @available(macOS 27, iOS 27, watchOS 27, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    @Parameter(title: "Volume", controlStyle: .stepper, inclusiveRange: (0, 100)) var value: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Set volume to \(\.$value) %")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        Session.shared.volume = Double(min(100, max(0, value))) / 100
        return .result()
    }
}

struct SetBinauralIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Set Binaural Beats"
    static let description = IntentDescription("Turns the binaural beat on or off. It plays over headphones only.")
    static var supportedModes: IntentModes { .background }
    #if compiler(>=6.4)
    @available(macOS 27, iOS 27, watchOS 27, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    @Parameter(title: "Binaural Beats") var value: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Turn binaural beats \(\.$value)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        Session.shared.binaural = value
        return .result()
    }
}
