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
    /// How far the middle of sleep moves between working nights and free
    /// ones, the measure chronobiology calls social jetlag (Wittmann et al.
    /// 2006): a body kept on one schedule five nights and another two is
    /// doing a small time-zone change every weekend. Signed, so a later
    /// free-night middle — the usual direction — is positive. Nil unless
    /// there are enough of both kinds of night to compare.
    var drift: TimeInterval? = nil
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
    /// Nights of each kind before the two are worth differencing. One free
    /// night against one working night is two nights, not a rhythm.
    static let leastOfEachKind = 2
    /// The nights most people are not woken by an obligation. It is an
    /// assumption, and a weekend worker is the case it gets wrong, so the
    /// figure is shown and never acted on.
    static func isFree(_ night: SleepNight, calendar: Calendar) -> Bool {
        [6, 7].contains(calendar.component(.weekday, from: night.night))
    }

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
            drift: drift(of: Array(recent), calendar: calendar),
            nights: recent.count
        )
    }

    /// The middle of sleep on free nights against working ones. Mid-sleep,
    /// not bedtime: a late night that still ends at an alarm has moved half
    /// as far as its bedtime suggests, and mid-sleep is what the literature
    /// differences. Both means are circular, so a middle at 03:40 and one at
    /// 04:20 are forty minutes apart and not twenty-three hours.
    static func drift(of nights: [SleepNight], calendar: Calendar = .current) -> TimeInterval? {
        func middle(_ night: SleepNight) -> TimeInterval {
            secondsOfDay(of: night.interval.start.addingTimeInterval(night.interval.duration / 2), calendar: calendar)
        }
        let free = nights.filter { isFree($0, calendar: calendar) }.map(middle)
        let working = nights.filter { !isFree($0, calendar: calendar) }.map(middle)
        guard free.count >= leastOfEachKind, working.count >= leastOfEachKind else { return nil }
        let difference = circularMean(of: free).mean - circularMean(of: working).mean
        // The difference is itself a point on the clock face, so it wraps:
        // anything past twelve hours apart is nearer the other way round.
        if difference > 43200 { return difference - 86400 }
        if difference < -43200 { return difference + 86400 }
        return difference
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
