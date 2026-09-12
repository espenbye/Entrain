import Foundation

/// What the body clock is doing at an hour, named. There are exactly six
/// because `Suggestion` has exactly six branches: this is the same opinion
/// under another name, not a second schedule beside it. Inventing a
/// seventh boundary here — a post-lunch dip at wake plus seven hours, a
/// temperature minimum two hours before it — would put a table in this file
/// that says almost what `Suggestion` says, and the two would drift the
/// first time either was touched.
///
/// A phase describes the clock; the mode describes what to play through it.
/// They are not the same thing, which is why both are carried: on a day
/// well below this person's own baseline the morning is still the morning,
/// it is simply played as Relax, and a day view that collapsed the two
/// would report the body had no morning at all.
enum CircadianPhase: String, Codable, CaseIterable, Sendable {
    case morning, sharpest, afternoon, windDown, night, wake

    var title: LocalizedStringResource {
        switch self {
        case .morning: "Morning"
        case .sharpest: "Midday"
        case .afternoon: "Afternoon"
        case .windDown: "Wind-Down Window"
        case .night: "Night"
        case .wake: "Before Waking"
        }
    }

    /// What the body is doing through the phase. These describe the ordinary
    /// human circadian day, which is all Entrain knows: it measures when you
    /// sleep and where the sun is, and it cannot measure your phase.
    var detail: LocalizedStringResource {
        switch self {
        case .morning:
            "Alertness climbs over the first hours after waking, and light this early pulls the clock earlier. The carrier is at its brightest here."
        case .sharpest:
            "The middle of the day is where attention holds longest and reaction times are shortest."
        case .afternoon:
            "Alertness dips in the afternoon, most noticeably around seven hours after waking, and recovers into the evening."
        case .windDown:
            "Melatonin starts rising a couple of hours before your usual bedtime. Bright light and sharp sound push it later, so Entrain goes warm and shallow."
        case .night:
            "Core temperature falls through the night and bottoms out a couple of hours before you wake, which is when sleep is deepest and waking is worst."
        case .wake:
            "Temperature and cortisol climb toward your usual wake time. A gentle rise meets that rather than cutting across it."
        }
    }
}

/// One day's phases end to end, as the app already decides them.
///
/// Nothing is computed here that `Suggestion` does not already compute.
/// The day is sampled forward at the same resolution `Program` walks it,
/// and equal neighbours are collected into spans, so the ring a reader sees
/// and the mode the program plays cannot disagree — there is one opinion
/// and two ways of reading it.
struct CircadianDay: Equatable, Sendable {
    /// A stretch of the day the clock and the app agree about.
    struct Span: Identifiable, Equatable, Sendable {
        var phase: CircadianPhase
        /// What Entrain would play through it, which is not always the
        /// phase's ordinary mode: see `Suggestion.isStrained`.
        var mode: Mode
        var interval: DateInterval

        var id: Date { interval.start }
    }

    /// Local midnight, and the day that runs from it.
    var start: Date
    /// The next local midnight. Stored rather than start plus a day,
    /// because two days a year it is not: the clocks put twenty-three hours
    /// in one of them and twenty-five in the other, and a ring that drew a
    /// flat twenty-four would leave its marker an hour out and the widget
    /// would reload an hour late or twice.
    var end: Date
    var spans: [Span]
    /// The sun on this day, for the two marks on the ring.
    var sunrise: Date
    var sunset: Date
    /// This person's own habitual times, when Health has a settled
    /// signature. Nil on a Mac, a fresh install and a refusal alike, which
    /// is when the ring falls back to showing only the sun.
    var bedtime: Date?
    var wake: Date?

    /// An ordinary day, for a snapshot with nothing better to go on.
    static let span: TimeInterval = 24 * 3600

    /// How long this day actually is.
    var length: TimeInterval { end.timeIntervalSince(start) }

    /// The local midnight after `date`, which is not always a day later.
    /// Noon the following day is inside the next day whatever the clocks do.
    static func midnight(after date: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: calendar.startOfDay(for: date).addingTimeInterval(36 * 3600))
    }

    /// Whether the night's edges came from Health rather than the sun.
    var isAnchored: Bool { bedtime != nil }

    /// The span holding `date`, or nil when it falls outside the day.
    func span(at date: Date) -> Span? {
        spans.first { $0.interval.contains(date) } ?? (date == end ? spans.last : nil)
    }

    /// How far through the day `date` sits, 0...1, for placing it on the ring.
    func progress(of date: Date) -> Double {
        min(1, max(0, date.timeIntervalSince(start) / length))
    }
}

/// The day as the widget stores it: times of day rather than dates.
///
/// The widget has neither HealthKit nor Core Location, so it cannot work
/// the day out for itself — the app writes this and the widget reads it,
/// exactly as `WidgetState` already works for the session.
///
/// Times of day rather than absolute dates, because a widget outlives the
/// launch that fed it. An extension asked to draw on a morning the app has
/// not run yet would otherwise have yesterday's dates and put the marker
/// off the end of the ring. What the day is made of moves slowly — sunrise
/// by a minute or two, a habitual bedtime hardly at all — so a snapshot a
/// few days stale is still right to within minutes, while one holding
/// yesterday's dates is simply wrong. The app republishes on every
/// foreground and on every change Health reports, so the snapshot is only
/// ever as old as the last time this person opened Entrain.
struct DayPhases: Codable, Equatable, Sendable {
    static let kind = "no.espenbye.entrain.day"

    struct Span: Codable, Equatable, Sendable {
        var phase: CircadianPhase
        var mode: Mode
        /// Seconds from local midnight.
        var start: TimeInterval
    }

    var spans: [Span]
    var sunrise: TimeInterval
    var sunset: TimeInterval
    var bedtime: TimeInterval?
    var wake: TimeInterval?

    static func load(from directory: URL? = WidgetState.directory) -> DayPhases? {
        guard let directory, let data = try? Data(contentsOf: directory.appending(path: "day.json")) else { return nil }
        return try? JSONDecoder().decode(DayPhases.self, from: data)
    }

    func save(to directory: URL? = WidgetState.directory) {
        guard let directory, let data = try? JSONEncoder().encode(self) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appending(path: "day.json"), options: .atomic)
    }

    /// These phases laid over the calendar day holding `date`. Adding
    /// seconds to midnight is what `SleepSignature` already does with its
    /// habitual times, and it drifts by an hour on the two days a year the
    /// clocks change, which is smaller than the thing being drawn.
    func day(on date: Date, calendar: Calendar = .current) -> CircadianDay {
        let start = calendar.startOfDay(for: date)
        let end = CircadianDay.midnight(after: start, calendar: calendar)
        func at(_ seconds: TimeInterval) -> Date { min(end, start.addingTimeInterval(seconds)) }
        return CircadianDay(
            start: start,
            end: end,
            spans: spans.indices.map { index in
                CircadianDay.Span(
                    phase: spans[index].phase,
                    mode: spans[index].mode,
                    interval: DateInterval(
                        start: at(spans[index].start),
                        end: index + 1 < spans.count ? at(spans[index + 1].start) : end
                    )
                )
            },
            sunrise: at(sunrise),
            sunset: at(sunset),
            bedtime: bedtime.map(at),
            wake: wake.map(at)
        )
    }
}

extension CircadianDay {
    /// This day reduced to times of day, for the widget to keep.
    var phases: DayPhases {
        func seconds(_ date: Date) -> TimeInterval { date.timeIntervalSince(start) }
        return DayPhases(
            spans: spans.map { DayPhases.Span(phase: $0.phase, mode: $0.mode, start: seconds($0.interval.start)) },
            sunrise: seconds(sunrise),
            sunset: seconds(sunset),
            bedtime: bedtime.map(seconds),
            wake: wake.map(seconds)
        )
    }
}
