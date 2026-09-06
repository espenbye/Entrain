import Foundation

/// entrain:// commands, for Raycast, Alfred, shell scripts and anything else
/// that can open a URL. Same vocabulary as the intents: mode and length raw values.
///
///     entrain://play?mode=focus&length=30
///     entrain://pause
///     entrain://toggle
enum URLCommand: Equatable {
    case play(mode: Mode?, length: SessionLength?)
    case pause
    case toggle

    static let scheme = "entrain"

    init?(_ url: URL) {
        guard url.scheme == Self.scheme else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        switch url.host {
        case "play":
            var length: SessionLength?
            if let raw = value("length") {
                guard let minutes = Int(raw), let parsed = SessionLength(rawValue: minutes) else { return nil }
                length = parsed
            }
            var mode: Mode?
            if let raw = value("mode") {
                guard let parsed = Mode(rawValue: raw) else { return nil }
                mode = parsed
            }
            self = .play(mode: mode, length: length)
        case "pause": self = .pause
        case "toggle": self = .toggle
        default: return nil
        }
    }

    @MainActor
    func run(on session: Session) async {
        switch self {
        case .play(let mode, let length):
            if let mode { session.mode = mode }
            if let length { session.length = length }
            await session.play()
        case .pause: session.pause()
        case .toggle: await session.toggle()
        }
    }
}
