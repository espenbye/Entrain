import Foundation

/// A stretch of one mode actually played, as this device remembers it.
///
/// Health has no record of a Sleep session. Meditate and Restore land there
/// as mindful minutes, and everything else Entrain plays leaves no trace at
/// all — so a night that had a bed under it and a night that did not look
/// identical from Health's side. This is the missing half: the sound's own
/// timeline, kept locally, so `NightEffect` has something to pair a night
/// against.
struct PlayedSession: Equatable, Codable, Sendable {
    var mode: Mode
    var interval: DateInterval

    init(_ mode: Mode, _ interval: DateInterval) {
        self.mode = mode
        self.interval = interval
    }
}

/// The log itself: what is kept, for how long, and what is not worth
/// keeping.
///
/// Only the modes that end in bed are recorded. A log of everything the
/// user ever played would be a more interesting file and a worse idea:
/// nothing here asks what they listened to at their desk, and a record that
/// exists for one question should hold only what that question needs.
///
/// There is no separate note of when the log began, because the oldest
/// entry is it. A night earlier than the first session on file is a night
/// this device cannot speak for — it may have had a bed under it, before
/// there was anywhere to write that down — and `NightEffect` drops those
/// rather than counting them as quiet. Pruning cannot break that: the log
/// runs three months and the comparison looks at two, so the entry that
/// bounds the window is always still there.
enum SessionLog {
    /// Days kept. Longer than `NightEffect.window` on purpose; see above.
    static let window = 90
    /// A bed switched off inside five minutes was a try, not a night.
    static let shortest: TimeInterval = 5 * 60
    /// A ceiling, so a pathological week of taps cannot grow the file
    /// without bound. Three months of ordinary nights is well under it.
    static let most = 500

    static let key = "sessions.slept"
    static let openKey = "sessions.slept.open"

    /// Whether a stretch of `mode` belongs in the log.
    static func keeps(_ mode: Mode) -> Bool { mode.purpose == .sleep }

    /// `log` with `session` in it, oldest first, pruned to the window.
    /// Sessions shorter than `shortest` are dropped rather than recorded as
    /// a night's sound.
    static func appending(
        _ session: PlayedSession, to log: [PlayedSession],
        now: Date = .now, calendar: Calendar = .current
    ) -> [PlayedSession] {
        guard session.interval.duration >= shortest else { return prune(log, now: now, calendar: calendar) }
        return prune(log + [session], now: now, calendar: calendar)
    }

    private static func prune(
        _ log: [PlayedSession], now: Date, calendar: Calendar
    ) -> [PlayedSession] {
        let oldest = calendar.date(byAdding: .day, value: -window, to: now) ?? now
        return log
            .filter { $0.interval.end >= oldest }
            .sorted { $0.interval.start < $1.interval.start }
            .suffix(most)
            .map { $0 }
    }

    static func load(from defaults: UserDefaults) -> [PlayedSession] {
        defaults.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([PlayedSession].self, from: $0) } ?? []
    }

    /// Notes that a stretch has begun, before anything knows when it will
    /// end.
    ///
    /// A bed is the one thing Entrain plays that routinely outlives the
    /// session watching it: an endless Sleep runs until somebody pauses it
    /// in the morning, and a night that ends in a force quit or a flat
    /// battery would never reach `appending` at all. That is not a lost
    /// entry, it is a wrong one — an unrecorded night with a bed under it
    /// lands in the quiet group and quietly spoils both halves of the
    /// comparison — so the start is written down the moment it happens.
    static func opening(_ mode: Mode, at start: Date, in defaults: UserDefaults) {
        defaults.set(
            try? JSONEncoder().encode(PlayedSession(mode, DateInterval(start: start, duration: shortest))),
            forKey: openKey
        )
    }

    static func closing(in defaults: UserDefaults) {
        defaults.removeObject(forKey: openKey)
    }

    /// The log, with any stretch left open by a launch that never came back
    /// folded into it.
    ///
    /// Such a stretch keeps its start and is given the shortest length that
    /// counts, because nothing can recover when the sound actually stopped.
    /// Only the start is read anyway — a night is grouped by whether a
    /// stretch reached it and the onset is measured from where it began —
    /// so the invented end costs the comparison nothing and is never shown.
    static func recover(in defaults: UserDefaults, now: Date = .now) -> [PlayedSession] {
        let log = load(from: defaults)
        guard let stranded = defaults.data(forKey: openKey)
            .flatMap({ try? JSONDecoder().decode(PlayedSession.self, from: $0) })
        else { return log }
        closing(in: defaults)
        let recovered = appending(stranded, to: log, now: now)
        save(recovered, to: defaults)
        return recovered
    }

    static func save(_ log: [PlayedSession], to defaults: UserDefaults) {
        defaults.set(try? JSONEncoder().encode(log), forKey: key)
    }
}
