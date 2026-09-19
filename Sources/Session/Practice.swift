import Foundation

/// The mindful sessions Health holds, reduced for the practice screen.
///
/// Deliberately not a streak and deliberately not a goal. `DayScreen` makes
/// the same argument about nights: a count of days kept turns a practice
/// into something you can fail at, and somebody who misses a Tuesday should
/// come back on Wednesday to a record of what they have done rather than to
/// a broken run. So this counts minutes and lists sittings, and says nothing
/// at all about whether there were enough of them.
///
/// It reports everything Health has, not only what Entrain wrote. Writing
/// mindful minutes is how a session lands on the same chart as Mindfulness
/// and Breathe, and reading only Entrain's own back would be a different
/// and smaller claim than the one the write makes. The screen says as much
/// under the figures rather than leaving a surprising number unexplained.
struct PracticeHistory: Equatable, Sendable {
    /// How many days back the screen asks Health for.
    static let window = 30
    /// What "this week" spans, in days, counting today.
    static let week = 7
    /// The longest list the screen draws.
    static let shown = 10

    /// The sittings themselves, newest first, at most `shown` of them.
    var sessions: [DateInterval]
    /// Seconds practised since midnight.
    var today: TimeInterval
    /// Seconds practised over the last `week` days, today included.
    var lastWeek: TimeInterval
    /// Sittings in the whole window, which may be more than `sessions` holds.
    var count: Int

    static let empty = PracticeHistory(sessions: [], today: 0, lastWeek: 0, count: 0)

    /// Nothing to draw. True on the Mac, which has no Health, on a fresh
    /// install, and when the read was refused — Health never says which,
    /// so all three have to look the same here.
    var isEmpty: Bool { count == 0 }

    /// Reduces what Health handed over. A sitting counts against the day it
    /// began on: one that runs past midnight is still that evening's, and
    /// splitting it across two days would make both of them wrong.
    static func from(
        _ sessions: [DateInterval], now: Date = .now, calendar: Calendar = .current
    ) -> PracticeHistory {
        let midnight = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -(week - 1), to: midnight) ?? midnight
        let ordered = sessions.sorted { $0.start > $1.start }
        return PracticeHistory(
            sessions: Array(ordered.prefix(shown)),
            today: ordered.lazy.filter { $0.start >= midnight }.reduce(0) { $0 + $1.duration },
            lastWeek: ordered.lazy.filter { $0.start >= weekStart }.reduce(0) { $0 + $1.duration },
            count: ordered.count
        )
    }
}

extension TimeInterval {
    /// A span of practice as "25 min", growing to "1 h 25 min" past an hour.
    /// Rounded down to the minute, like Health's own mindful figure: a
    /// session is credited with the minutes it actually ran.
    var practiceMinutes: String {
        // Spelled out rather than written inline in the call: two array
        // literals either side of a ternary have nothing to infer their
        // element type from, and the compiler reads the pair as `[Any]`.
        let allowed: Set<Duration.UnitsFormatStyle.Unit> = self >= 3600 ? [.hours, .minutes] : [.minutes]
        return Duration.seconds(Int(self)).formatted(.units(allowed: allowed, width: .abbreviated))
    }
}
