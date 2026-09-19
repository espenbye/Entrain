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
    /// Whether the day is driving the session: see `Program`. The widget
    /// needs it for the same reason the player does — while it is on, the
    /// mode on screen is the day's choice and not this listener's, and the
    /// thing to light up is the day rather than the mode it happens to be
    /// playing this hour.
    var program: Bool

    init(mode: Mode, sound: String, isPlaying: Bool, remaining: Int?, deadline: Date?, program: Bool = false) {
        self.mode = mode
        self.sound = sound
        self.isPlaying = isPlaying
        self.remaining = remaining
        self.deadline = deadline
        self.program = program
    }

    /// A snapshot written by a version that had no program in it reads back
    /// as a session nobody was following the day with, which is what it was.
    /// Without this the first launch after an update would decode nothing at
    /// all and the widget would fall back to its placeholder.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decode(Mode.self, forKey: .mode)
        sound = try container.decode(String.self, forKey: .sound)
        isPlaying = try container.decode(Bool.self, forKey: .isPlaying)
        remaining = try container.decodeIfPresent(Int.self, forKey: .remaining)
        deadline = try container.decodeIfPresent(Date.self, forKey: .deadline)
        program = try container.decodeIfPresent(Bool.self, forKey: .program) ?? false
    }

    /// Whether the widget would draw the same thing from `other`. Two
    /// deadlines within a second of each other are the same countdown.
    func matches(_ other: WidgetState?) -> Bool {
        guard let other, mode == other.mode, sound == other.sound,
              isPlaying == other.isPlaying, program == other.program
        else { return false }
        switch (deadline, other.deadline) {
        case let (mine?, theirs?): return abs(mine.timeIntervalSince(theirs)) < 1
        case (nil, nil): return remaining == other.remaining
        default: return false
        }
    }

    /// The snapshot as of `date`. A timed session whose deadline has passed
    /// is over, even if the app was killed before it could say so.
    func at(_ date: Date) -> WidgetState {
        guard isPlaying, let deadline, deadline <= date else { return self }
        return WidgetState(mode: mode, sound: sound, isPlaying: false, remaining: nil, deadline: nil, program: program)
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
