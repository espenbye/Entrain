import Foundation

/// The snapshot the widget draws from. The app writes it on every state
/// change and reloads the widget; the widget only ever reads. Timed sessions
/// carry the wall-clock deadline so the widget counts down on its own.
struct WidgetState: Codable, Sendable {
    static let group = "group.no.espenbye.entrain"
    static let kind = "no.espenbye.entrain.widget"
    private static let key = "widgetState"

    var mode: Mode
    var sound: String
    var isPlaying: Bool
    /// Seconds left while paused, or on a timed session that has not started.
    var remaining: Int?
    /// When a running timed session ends. Nil when paused or endless.
    var deadline: Date?

    static func load(from defaults: UserDefaults? = UserDefaults(suiteName: group)) -> WidgetState? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetState.self, from: data)
    }

    func save(to defaults: UserDefaults? = UserDefaults(suiteName: group)) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults?.set(data, forKey: Self.key)
    }
}
