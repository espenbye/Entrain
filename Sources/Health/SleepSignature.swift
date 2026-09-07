import Foundation

/// When this person actually sleeps, from the nights Health holds.
///
/// The app started with the sun: bedtime was three hours after sunset and
/// morning was sunrise. That is a reasonable prior and a poor description
/// of anyone, and it is worst where the sun is least useful — a Norwegian
/// June evening is not bedtime at 22:00 because it is still light. The
/// signature replaces those two edges with the listener's own habitual
/// times, and everything else about the day stays measured against the sun.
struct SleepSignature: Equatable, Sendable {
    /// Habitual times as seconds from local midnight, 0..<86400. Bedtime
    /// past midnight is a small number, so build dates with `time(_:on:)`
    /// rather than adding it to a day.
    var bedtime: TimeInterval
    var wake: TimeInterval
    /// Habitual sleep-onset latency, when Health had time in bed to measure
    /// it against. Nil when no source recorded lights-out.
    var latency: TimeInterval?
    /// How far the bedtimes scatter, as a circular standard deviation in
    /// seconds. A wide scatter means there is no habitual bedtime to speak of.
    var spread: TimeInterval
    /// Nights the signature rests on.
    var nights: Int
}

extension SleepSignature {
    /// Nights considered. Two weeks covers a working rhythm with its
    /// weekends without letting a holiday three weeks ago still count.
    static let window = 14
    /// Fewer than this and one late night moves the whole signature.
    static let leastNights = 5
    /// Past this scatter the bedtimes describe no habit worth acting on, so
    /// the sun keeps the night's edges.
    static let widestSpread: TimeInterval = 2 * 3600

    /// The signature is only used where it says something the sun does not,
    /// and where the ordinary reading of "bedtime" and "morning" holds:
    /// enough nights, close enough together, and an evening-to-morning
    /// shape. A night-shift rhythm falls back to the sun rather than being
    /// mapped onto a night it does not have.
    var isSettled: Bool {
        nights >= Self.leastNights && spread <= Self.widestSpread
            && (bedtime >= 18 * 3600 || bedtime < 6 * 3600)
            && (2 * 3600...12 * 3600).contains(wake)
    }

    /// How long the sleep bed should take to settle, from this person's own
    /// latency. `Arc.swift` sizes the onset on the ten-to-twenty minutes a
    /// healthy adult takes to fall asleep; where Health knows the real
    /// figure it is better than the average, held inside a range so one odd
    /// night cannot collapse or stretch the arc.
    var onset: TimeInterval? { latency.map { min(45 * 60, max(5 * 60, $0)) } }

    /// The signature over the most recent `window` nights, or nil when
    /// there are none. Nights with no data were never in `nights` and do
    /// not count against it.
    static func from(_ nights: [SleepNight], calendar: Calendar = .current) -> SleepSignature? {
        let recent = nights.suffix(window)
        guard !recent.isEmpty else { return nil }
        let bedtimes = recent.map { secondsOfDay(of: $0.bedtime, calendar: calendar) }
        let (bedtime, spread) = circularMean(of: bedtimes)
        let (wake, _) = circularMean(of: recent.map { secondsOfDay(of: $0.wake, calendar: calendar) })
        let latencies = recent.compactMap(\.latency).sorted()
        return SleepSignature(
            bedtime: bedtime,
            wake: wake,
            // The median, not the mean: one night spent awake in bed for two
            // hours should not double the onset for a fortnight.
            latency: latencies.isEmpty ? nil : latencies[latencies.count / 2],
            spread: spread,
            nights: recent.count
        )
    }

    /// The habitual wake that ends the night on the day holding `date`. It
    /// stands in for `SolarDay.sunrise`, so it is that day's morning.
    func morning(on date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date).addingTimeInterval(wake)
    }

    /// The habitual bedtime that opens the night beginning on the day
    /// holding `date`, standing in for `SolarDay.sunset`. A bedtime in the
    /// small hours belongs to the night that day opens, so it lands on the
    /// following calendar day.
    func evening(on date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date).addingTimeInterval(bedtime + (bedtime < 12 * 3600 ? 86400 : 0))
    }

    /// Clock times wrap, so 23:40 and 00:20 average to midnight and not to
    /// noon. Each time is a point on a twenty-four hour circle; the mean is
    /// the direction of their sum, and the spread follows from how far that
    /// sum falls short of unit length.
    static func circularMean(of seconds: [TimeInterval]) -> (mean: TimeInterval, spread: TimeInterval) {
        guard !seconds.isEmpty else { return (0, .infinity) }
        let turn = 2 * Double.pi / 86400
        let x = seconds.reduce(0) { $0 + cos($1 * turn) } / Double(seconds.count)
        let y = seconds.reduce(0) { $0 + sin($1 * turn) } / Double(seconds.count)
        let length = (x * x + y * y).squareRoot()
        guard length > 1e-9 else { return (0, .infinity) }
        let angle = atan2(y, x)
        let mean = (angle / turn).truncatingRemainder(dividingBy: 86400)
        return (mean < 0 ? mean + 86400 : mean, (-2 * log(min(1, length))).squareRoot() / turn)
    }

    static func secondsOfDay(of date: Date, calendar: Calendar) -> TimeInterval {
        date.timeIntervalSince(calendar.startOfDay(for: date))
    }
}
