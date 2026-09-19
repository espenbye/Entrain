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
/// Only `Mode.runsIntoTheNight` is recorded, which is Wind Down and the two
/// sleep beds. A log of everything the user ever played would be a more
/// interesting file and a worse idea: nothing here asks what they listened
/// to at their desk, and a record that exists for one question should hold
/// only what that question needs. Nap and Wake are left out for the same
/// reason — they are daytime sleep and a rise out of it, and no night is
/// grouped by either.
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
    /// How often an open stretch writes down how far it has got. Nothing
    /// reads the end to finer than the hours `NightEffect.lead` works in,
    /// so five minutes is already far more resolution than it needs, and
    /// one small write per five minutes of a bed that is rendering audio
    /// continuously costs nothing worth naming.
    static let mark: TimeInterval = 5 * 60

    static let key = "sessions.slept"
    static let openKey = "sessions.slept.open"

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

    /// Inside the window, oldest first, and no longer than `most`. The
    /// order is what lets the first entry stand in for the day the log
    /// begins; see the type's note.
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

    /// What is on disk, or nothing at all: a log that fails to decode is an
    /// empty log, not an error, because there is nothing a listener could
    /// do about it and the comparison simply has less to say.
    static func load(from defaults: UserDefaults) -> [PlayedSession] {
        defaults.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([PlayedSession].self, from: $0) } ?? []
    }

    /// Notes a stretch that is playing now, and how far it has got.
    ///
    /// A bed is the one thing Entrain plays that routinely outlives the
    /// session watching it: an endless Sleep runs until somebody pauses it
    /// in the morning, and a night that ends in a force quit or a flat
    /// battery would never reach `appending` at all. That is not a lost
    /// entry, it is a wrong one — an unrecorded night with a bed under it
    /// lands in the quiet group and quietly spoils both halves of the
    /// comparison — so the stretch is written down the moment it opens.
    ///
    /// `reached` is re-sent every `mark` while it plays, because the start
    /// alone is not enough. A night is grouped by whether a stretch was
    /// still going inside the hours before sleep, so a bed opened at eight
    /// and left playing all night has to be recoverable as the whole night
    /// and not as the five minutes it was opened with, which would fall
    /// short of the window and file the night as quiet.
    static func opening(_ mode: Mode, from start: Date, through reached: Date, in defaults: UserDefaults) {
        // Never shorter than the length that counts: a stretch a second old
        // is still a stretch, and `appending` would otherwise drop the one
        // thing recovery exists to keep.
        let end = max(reached, start.addingTimeInterval(shortest))
        defaults.set(
            try? JSONEncoder().encode(PlayedSession(mode, DateInterval(start: start, end: end))),
            forKey: openKey
        )
    }

    /// Forgets the open stretch, once it has been written down properly.
    static func closing(in defaults: UserDefaults) {
        defaults.removeObject(forKey: openKey)
    }

    /// The log, with any stretch left open by a launch that never came back
    /// folded into it.
    ///
    /// Such a stretch is taken exactly as `opening` last left it: its real
    /// start, and the last moment it was known to still be playing. That
    /// end is an under-estimate by up to `mark`, which is why the grouping
    /// window is measured in hours and the figure is never shown.
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

    /// Writes the log back. A failure to encode leaves nil, which reads
    /// back as an empty log on the next launch and loses the comparison
    /// rather than anything a listener would miss.
    static func save(_ log: [PlayedSession], to defaults: UserDefaults) {
        defaults.set(try? JSONEncoder().encode(log), forKey: key)
    }
}
