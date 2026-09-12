import Foundation

/// Where `CircadianDay` comes from. The model itself lives beside `Mode`
/// and `WidgetState` because the widget draws it too, and the widget has
/// neither HealthKit nor Core Location; this is the half that needs them,
/// and it stays in the app.
extension CircadianDay {
    /// The calendar day holding `date`, phase by phase.
    static func on(
        _ date: Date, day: (Date) -> SolarDay, sleep: SleepSignature? = nil,
        target: SleepTarget? = nil, vitals: [BodyMetric: BodySignal] = [:], calendar: Calendar = .current
    ) -> CircadianDay {
        let start = calendar.startOfDay(for: date)
        let end = Self.midnight(after: start, calendar: calendar)
        let length = end.timeIntervalSince(start)
        let today = day(start.addingTimeInterval(12 * 3600))
        let edges = SleepEdges.tonight(target: target, measured: sleep)

        var spans: [Span] = []
        var at: TimeInterval = 0
        while at < length {
            let when = start.addingTimeInterval(at)
            let suggestion = Suggestion.at(when, day: day, sleep: sleep, target: target, vitals: vitals, calendar: calendar)
            let next = min(length, at + Program.step)
            if var last = spans.last, last.phase == suggestion.phase, last.mode == suggestion.mode {
                last.interval = DateInterval(start: last.interval.start, end: start.addingTimeInterval(next))
                spans[spans.count - 1] = last
            } else {
                spans.append(Span(
                    phase: suggestion.phase,
                    mode: suggestion.mode,
                    interval: DateInterval(start: when, end: start.addingTimeInterval(next))
                ))
            }
            at = next
        }

        return CircadianDay(
            start: start,
            end: end,
            spans: spans,
            sunrise: today.sunrise,
            sunset: today.sunset,
            // The habitual times as they fall on this calendar day, so a
            // bedtime in the small hours lands at the top of the ring rather
            // than off the end of it.
            bedtime: edges.map { start.addingTimeInterval($0.bedtime) },
            wake: edges.map { start.addingTimeInterval($0.wake) }
        )
    }
}
