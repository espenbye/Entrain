import Foundation

/// The snapshot the widget draws from. The app writes it on every state
/// change and reloads the widget; the widget only ever reads. Timed sessions
/// carry the wall-clock deadline so the widget counts down on its own.
///
/// On the Mac it lives in a folder both sandboxes open through a path
/// exception rather than in an App Group: group containers need a
/// certificate-backed identity to sign and to pass the privacy check, which a
/// development build lacks. iOS and watchOS have no such exception, so they
/// use the group container; device builds there need a team anyway.
struct WidgetState: Codable, Sendable {
    static let kind = "no.espenbye.entrain.widget"

    static var directory: URL? {
        #if os(macOS)
        // `~/Library/Application Support/Entrain` in the real home, which the
        // sandbox otherwise hides behind the container.
        guard let home = getpwuid(getuid())?.pointee.pw_dir else { return nil }
        return URL(filePath: String(cString: home)).appending(path: "Library/Application Support/Entrain")
        #else
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.no.espenbye.entrain")
        #endif
    }

    var mode: Mode
    var sound: String
    var isPlaying: Bool
    /// Seconds left while paused, or on a timed session that has not started.
    var remaining: Int?
    /// When a running timed session ends. Nil when paused or endless.
    var deadline: Date?

    static func load(from directory: URL? = directory) -> WidgetState? {
        guard let directory, let data = try? Data(contentsOf: directory.appending(path: "widget.json")) else { return nil }
        return try? JSONDecoder().decode(WidgetState.self, from: data)
    }

    func save(to directory: URL? = directory) {
        guard let directory, let data = try? JSONEncoder().encode(self) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appending(path: "widget.json"), options: .atomic)
    }
}
