import Foundation

/// What this person's own nights did, with a sleep sound playing and
/// without one.
///
/// The question behind it is whether the sound is working, and the first
/// thing to say is what this cannot answer. It is one person, choosing for
/// themselves which nights get a bed; the nights anyone reaches for one are
/// exactly the nights they expect to sleep badly, so the two groups were
/// never a fair draw and the selection runs against the sound. There is no
/// control, nothing is blinded, and a body that slept badly on Monday
/// sleeps better on Tuesday whatever was playing. So nothing here is a
/// test, nothing here is significant, and none of it is offered as evidence
/// that the sound caused anything. It is a description of two sets of
/// nights, with the number of nights in each printed beside it so the
/// reader can see how thin it is.
///
/// What it does measure is chosen to survive the instrument. A wrist tells
/// sleep from waking well and one stage from another poorly, so this counts
/// hours asleep and time awake inside the night and never touches deep
/// sleep or REM, which are the figures a watch is worst at and the ones a
/// soundscape would most like to claim. Resting heart rate is here because
/// it is measured a different way and carries none of that error.
///
/// One measurement is Entrain's alone: how long after the sound started
/// sleep actually began. Health cannot work it out, because Health does not
/// know when the sound started — only the app does, and only for its own
/// sessions. It is also the figure the Sleep arc is built around, which
/// sizes its onset on the ten to twenty minutes a healthy adult takes. It
/// has nothing to compare against, since a quiet night has no sound to
/// measure from, so it is reported on its own and never as a difference.
struct NightEffect: Equatable, Sendable {
    /// What is compared. Deliberately three things a wrist can hold, and
    /// deliberately not a stage breakdown; see the type's note.
    enum Measure: String, Equatable, Sendable, CaseIterable {
        /// Hours actually asleep.
        case asleep
        /// Time inside the night not recorded as sleep.
        case awake
        /// The resting heart rate of the day the night ended in.
        case restingHeartRate
    }

    /// One measure's two medians. The median, not the mean: a fortnight of
    /// ordinary nights and one flight should not average into a figure
    /// describing neither.
    struct Comparison: Equatable, Sendable {
        var measure: Measure
        /// Median over the nights a sound was playing, in the measure's own
        /// unit: seconds, or beats per minute.
        var withSound: Double
        /// Median over the nights there was none.
        var without: Double
        var soundNights: Int
        var quietNights: Int
    }

    /// One per measure that had enough nights on both sides. Empty is the
    /// ordinary state for weeks after installing.
    var comparisons: [Comparison]
    /// Median seconds from the sound starting to the first sleep Health
    /// recorded. Nil until there are enough nights to take a median of.
    var onset: TimeInterval?
    /// Nights behind `onset`.
    var onsetNights: Int
    /// Nights this device can speak for at all, which is the window minus
    /// everything older than the log.
    var nights: Int

    static let empty = NightEffect(comparisons: [], onset: nil, onsetNights: 0, nights: 0)

    /// Nothing to draw. True on the Mac, which has no Health, on a fresh
    /// install, and when the Health read was refused — Health never says
    /// which, so all three have to look the same here.
    var isEmpty: Bool { comparisons.isEmpty && onset == nil }
}

extension NightEffect {
    /// Nights considered. Two months, which is what makes a split into two
    /// groups worth printing at all; it is also the window `BodySignal`
    /// baselines over, so the sleep read and the vitals read cover the same
    /// stretch of life.
    static let window = 60
    /// Nights of each kind before a comparison is shown. Seven is not a
    /// sample size, it is a floor under the obviously meaningless, and the
    /// counts are printed beside the figures for exactly that reason.
    static let leastNights = 7
    /// How long before sleep a sound still belongs to that night. Wind Down
    /// is meant to run into bed, so an evening session counts for the night
    /// that follows it; three hours is the same bound `SleepNight` puts on
    /// a lights-out sample belonging to the sleep after it.
    static let lead: TimeInterval = 3 * 3600
    /// Stretches of sound this far apart are one stretch. A mode change
    /// from Wind Down to Sleep ends one session and opens the next in the
    /// same second, and to the listener that is one unbroken sound.
    static let joins: TimeInterval = 60

    /// The comparison over `nights`, split by whether `sessions` put a
    /// sound into each of them.
    ///
    /// `restingHeartRate` is the daily series behind `BodySignal`, and a
    /// night takes the value of the day it ended in: a resting heart rate
    /// is the morning's reading of the night before.
    static func from(
        nights: [SleepNight],
        sessions: [PlayedSession],
        restingHeartRate: [DailyValue] = [],
        calendar: Calendar = .current
    ) -> NightEffect {
        // A night before the oldest session on file is a night this device
        // cannot speak for, not a quiet one. See `SessionLog`.
        guard let began = sessions.map(\.interval.start).min() else { return .empty }
        let sound = stretches(of: sessions.filter { $0.mode.runsIntoTheNight })
        // The onset is measured from the sleep bed alone, not from the
        // whole evening. Wind Down is an hour of easing toward bed with a
        // job of its own, and folding it in would report that hour as an
        // hour of failing to fall asleep.
        let beds = stretches(of: sessions.filter(\.mode.isSleep))
        let recent = nights.suffix(window).filter { $0.bedtime >= began }
        guard !recent.isEmpty else { return .empty }

        var withSound: [SleepNight] = []
        var quiet: [SleepNight] = []
        for night in recent {
            let span = DateInterval(start: night.bedtime.addingTimeInterval(-lead), end: night.wake)
            if sound.contains(where: { $0.intersects(span) }) {
                withSound.append(night)
            } else {
                quiet.append(night)
            }
        }

        let onsets = withSound.compactMap { onset(of: $0, in: beds) }
        return NightEffect(
            comparisons: comparisons(
                withSound: withSound, quiet: quiet,
                restingHeartRate: byDay(restingHeartRate, calendar: calendar), calendar: calendar
            ),
            onset: onsets.count >= leastNights ? median(onsets) : nil,
            onsetNights: onsets.count,
            nights: recent.count
        )
    }

    /// How long after the bed started this night's sleep began, or nil when
    /// no bed opened inside the hours before it.
    ///
    /// The latest qualifying stretch, not the earliest: a bed put on at
    /// eight, switched off, and put on again at half eleven is two
    /// stretches, and the one sleep came after is the second.
    static func onset(of night: SleepNight, in beds: [DateInterval]) -> TimeInterval? {
        beds
            .filter { $0.start <= night.bedtime && night.bedtime.timeIntervalSince($0.start) <= lead }
            .map { night.bedtime.timeIntervalSince($0.start) }
            .min()
    }

    /// The sessions as unbroken stretches of sound, oldest first.
    static func stretches(of sessions: [PlayedSession]) -> [DateInterval] {
        var merged: [DateInterval] = []
        for session in sessions.map(\.interval).sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, session.start.timeIntervalSince(last.end) <= joins {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, session.end))
            } else {
                merged.append(session)
            }
        }
        return merged
    }

    private static func comparisons(
        withSound: [SleepNight], quiet: [SleepNight],
        restingHeartRate: [Date: Double], calendar: Calendar
    ) -> [Comparison] {
        Measure.allCases.compactMap { measure -> Comparison? in
            let sound = values(of: measure, over: withSound, rate: restingHeartRate, calendar: calendar)
            let without = values(of: measure, over: quiet, rate: restingHeartRate, calendar: calendar)
            guard sound.count >= leastNights, without.count >= leastNights,
                  let a = median(sound), let b = median(without)
            else { return nil }
            return Comparison(
                measure: measure, withSound: a, without: b,
                soundNights: sound.count, quietNights: without.count
            )
        }
    }

    private static func values(
        of measure: Measure, over nights: [SleepNight],
        rate: [Date: Double], calendar: Calendar
    ) -> [Double] {
        nights.compactMap { night -> Double? in
            switch measure {
            case .asleep:
                return night.asleep
            case .awake:
                return night.awake
            case .restingHeartRate:
                // The night beginning on one day ends on the morning of the
                // next, and that morning's reading is the one it earned.
                return calendar.date(byAdding: .day, value: 1, to: night.night).flatMap { rate[$0] }
            }
        }
    }

    /// The series keyed by the midnight opening the day it belongs to, so a
    /// night can look up the morning it ended in.
    private static func byDay(_ values: [DailyValue], calendar: Calendar) -> [Date: Double] {
        Dictionary(values.map { (calendar.startOfDay(for: $0.day), $0.value) }, uniquingKeysWith: { _, last in last })
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
