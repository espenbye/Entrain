import AppIntents

/// A Focus filter: the Focus (Work, Sleep, ...) it is attached to starts a
/// mode when it turns on, and can pause the session when it turns off. The
/// system runs it in the app process on every Focus change; when no Focus
/// is on it arrives with every parameter at its default.
struct EntrainFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Focus Filter"
    static let description = IntentDescription("Starts a mode when the Focus turns on.")
    static var supportedModes: IntentModes { .background }
    #if compiler(>=6.4)
    @available(macOS 27, iOS 27, watchOS 27, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    @Parameter(title: "Mode") var mode: Mode?
    @Parameter(title: "Length") var length: SessionLength?
    @Parameter(title: "Stop when this Focus turns off", default: false) var stopWhenOff: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: mode.map { "Start \($0.title)" } ?? "Nothing",
            subtitle: stopWhenOff ? "Stops when the Focus turns off" : nil
        )
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let session = Session.shared
        await session.applyFocusFilter(mode: mode, length: length, stopWhenOff: stopWhenOff)
        if mode != nil, !session.isPlaying { throw SessionIntentError.audioUnavailable }
        return .result()
    }
}
