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
        let weekStart = start(ofLast: week, before: now, calendar: calendar)
        let ordered = sessions.sorted { $0.start > $1.start }
        return PracticeHistory(
            sessions: Array(ordered.prefix(shown)),
            today: ordered.lazy.filter { $0.start >= midnight }.reduce(0) { $0 + $1.duration },
            lastWeek: ordered.lazy.filter { $0.start >= weekStart }.reduce(0) { $0 + $1.duration },
            count: ordered.count
        )
    }

    /// The midnight a window of `days` days begins at, counting today as one
    /// of them: seven days is today and the six before it, not today and
    /// seven.
    ///
    /// It lives here because both ends of the figure have to agree on it.
    /// The week's total measured inclusively while the Health query asked
    /// for `days` days before today's midnight, which is a day more, so the
    /// footer named a window the count did not keep to. One definition, used
    /// by both, is the only way that stays true.
    static func start(ofLast days: Int, before now: Date = .now, calendar: Calendar = .current) -> Date {
        let midnight = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -(days - 1), to: midnight) ?? midnight
    }
}

extension TimeInterval {
    /// A span of practice as "25 min", growing to "1 hr 25 min" past an hour.
    ///
    /// Floored to the whole minute here rather than left to the format
    /// style, which rounds to nearest: ninety seconds of sitting is a minute
    /// and a half, and reporting it as two credits half a minute nobody sat.
    /// A practice log that rounds up is a practice log that flatters, and
    /// the figure is meant to be the one Health holds. Formatting a whole
    /// number of minutes also makes the style's rounding a no-op, so the
    /// hours-and-minutes split past an hour is exact.
    var practiceMinutes: String {
        let minutes = Int(self) / 60
        // The set is named rather than written inline in the call: two array
        // literals either side of a ternary have nothing to infer their
        // element type from, and the compiler reads the pair as `[Any]`.
        let allowed: Set<Duration.UnitsFormatStyle.Unit> = minutes >= 60 ? [.hours, .minutes] : [.minutes]
        return Duration.seconds(minutes * 60).formatted(.units(allowed: allowed, width: .abbreviated))
    }
}
