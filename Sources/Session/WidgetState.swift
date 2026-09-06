import Foundation
#if os(macOS)
import Security
#endif

/// The snapshot the widget draws from. The app writes it on every state
/// change and reloads the widget; the widget only ever reads. Timed sessions
/// carry the wall-clock deadline so the widget counts down on its own.
///
/// On the Mac a development or Developer ID build keeps it in a folder both
/// sandboxes open through a path exception: group containers need a
/// certificate-backed identity to sign and to pass the privacy check. App
/// Review rejects that exception, so a Mac App Store build is signed with the
/// App Group entitlements in `AppStore/` instead and uses the group
/// container, which is what iOS and watchOS always do.
struct WidgetState: Codable, Sendable {
    static let kind = "no.espenbye.entrain.widget"
    static let group = "group.no.espenbye.entrain"

    static var directory: URL? {
        #if os(macOS)
        if hasGroupEntitlement {
            return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        }
        // `~/Library/Application Support/Entrain` in the real home, which the
        // sandbox otherwise hides behind the container.
        guard let home = getpwuid(getuid())?.pointee.pw_dir else { return nil }
        return URL(filePath: String(cString: home)).appending(path: "Library/Application Support/Entrain")
        #else
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        #endif
    }

    #if os(macOS)
    /// Whether this process was signed into the App Group. The app and the
    /// widget are signed alike, so both land on the same folder.
    private static var hasGroupEntitlement: Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let groups = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil) as? [String]
        else { return false }
        return groups.contains(group)
    }
    #endif

    var mode: Mode
    var sound: String
    var isPlaying: Bool
    /// Seconds left while paused, or on a timed session that has not started.
    var remaining: Int?
    /// When a running timed session ends. Nil when paused or endless.
    var deadline: Date?

    /// Whether the widget would draw the same thing from `other`. Two
    /// deadlines within a second of each other are the same countdown.
    func matches(_ other: WidgetState?) -> Bool {
        guard let other, mode == other.mode, sound == other.sound, isPlaying == other.isPlaying else { return false }
        switch (deadline, other.deadline) {
        case let (mine?, theirs?): return abs(mine.timeIntervalSince(theirs)) < 1
        case (nil, nil): return remaining == other.remaining
        default: return false
        }
    }

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
