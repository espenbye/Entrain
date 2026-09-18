import Foundation

/// The mode that fits the time of day: a tap starts it with the timer
/// already set. Morning is for work and midday for the sharpest attention;
/// the afternoon dips and then recovers, so the dip is worked in rounds and
/// the recovery is a breather; the hours before bed ease toward it, the
/// night is for sleep, and the last two hours before morning are for waking.
///
/// The day is measured against the sun, like the circadian arc. The night's
/// two edges are not: a target replaces them where one is set, this person's
/// habitual bedtime and wake where Health knows them, and the sun only when
/// neither does — because the sun is the worst guide exactly where it
/// matters most. Three hours after a Norwegian
/// midsummer sunset is half past one in the morning, and three hours after
/// a December one is dinner. Without a settled signature — a fresh install,
/// a Mac, or a refusal, which look the same — the sun stands in, which is
/// where this started.
///
/// The body gets a say over the daylight hours and nowhere else. On a day
/// well outside this person's own range, Focus and Gamma become Relax and
/// Sprint becomes Restore — the same argument twice, that a taxed body is
/// not going to be argued into a long stretch of work. After a short night
/// the dip is a Nap instead, because sleep debt is the one thing only sleep
/// repays, and the dip is the one window in the day where paying it does
/// not come out of tonight. Nothing after the afternoon moves: an unusual
/// day is no reason to change what a night should sound like, and the
/// suggestion is a suggestion either way.
struct Suggestion: Equatable, Sendable {
    var mode: Mode
    /// What the body clock is doing at this hour, which is not the same
    /// question as what to play through it: a strained morning is still a
    /// morning, it is simply suggested as Relax. `CircadianDay` reads the
    /// day off this rather than keeping a table of its own.
    var phase: CircadianPhase
    var reason: LocalizedStringResource

    static func == (a: Self, b: Self) -> Bool { a.mode == b.mode }

    /// How long before bed Wind Down is the suggestion. Unchanged from the
    /// sunset heuristic it replaces; only what it hangs off has moved.
    static let windDownLead: TimeInterval = 3 * 3600
    /// How long before waking Wake is the suggestion.
    static let wakeLead: TimeInterval = 2 * 3600
    /// Where the afternoon dip opens and closes, as a fraction of the
    /// daylight between sunrise and sunset. The dip is the stretch the
    /// afternoon's own description has always named — alertness sags a few
    /// hours after midday and comes back toward the evening — and until now
    /// the whole afternoon was played as though it were only the recovery.
    /// Measured against the sun like the rest of the daylight hours, and
    /// not at wake plus seven hours: a second anchor inside the day would
    /// be a second schedule, and the sun already carries the other two
    /// boundaries this one sits between.
    static let dipOpens = 0.6
    static let dipCloses = 0.75
    /// How much of the dip a nap is suggested for. Half an hour is the
    /// figure Nap's own description gives — long enough to be worth taking
    /// and short enough to stay out of deep sleep — and the rest of the dip
    /// goes back to what the afternoon would otherwise have been, so a nap
    /// is never suggested for two hours.
    static let napLength: TimeInterval = 30 * 60
    /// How far outside this person's own range a day has to sit before the
    /// body gets a say. One and a half standard deviations is the
    /// conventional band for "unusual for this person", and below it the
    /// day-to-day noise in both metrics is larger than anything they mean.
    static let strain = 1.5

    /// Whether today is unusual enough to be worth a lighter mode. Low
    /// variability and a high resting heart rate are the same argument from
    /// two directions: both track what a poor night, an illness or a hard
    /// day before costs the autonomic system (Task Force of the ESC and
    /// NASPE 1996; Buchheit 2014). Either on its own is enough, and neither
    /// is a diagnosis — it is one day against sixty of this person's own.
    static func isStrained(_ vitals: [BodyMetric: BodySignal]) -> Bool {
        if let variability = vitals[.heartRateVariability], variability.deviation <= -strain { return true }
        if let resting = vitals[.restingHeartRate], resting.deviation >= strain { return true }
        return false
    }

    static func at(
        _ date: Date, day: (Date) -> SolarDay, sleep: SleepSignature? = nil,
        target: SleepTarget? = nil, vitals: [BodyMetric: BodySignal] = [:], calendar: Calendar = .current
    ) -> Suggestion {
        let edges = SleepEdges.tonight(target: target, measured: sleep)
        let today = day(date)
        let morning = edges?.morning(on: date, calendar: calendar) ?? today.sunrise
        let evening = edges.map { $0.evening(on: date, calendar: calendar) - windDownLead } ?? today.sunset

        if date < morning {
            let yesterday = date.addingTimeInterval(-86400)
            let opened = edges.map { $0.evening(on: yesterday, calendar: calendar) - windDownLead }
                ?? day(yesterday).sunset
            return night(date, evening: opened, morning: morning, source: edges?.source)
        }
        if date < evening {
            // The daylight hours keep the sun: a bright morning is a fact
            // about the light, not about when this person went to bed. The
            // progress clamps, so an evening that starts after sunset simply
            // stays at the far end of the afternoon until Wind Down takes over.
            let span = today.sunset.timeIntervalSince(today.sunrise)
            let p = span > 0 ? min(1, max(0, date.timeIntervalSince(today.sunrise) / span)) : 1
            let phase: CircadianPhase = p < 0.4 ? .morning : p < dipOpens ? .sharpest
                : p < dipCloses ? .dip : .afternoon
            if p < dipOpens {
                if isStrained(vitals) {
                    return Suggestion(mode: .relax, phase: phase, reason: "Suggested for a day below your usual")
                }
                if p < 0.4 { return Suggestion(mode: .focus, phase: phase, reason: "Suggested for a bright morning") }
                return Suggestion(mode: .gamma, phase: phase, reason: "Suggested for midday")
            }
            if p < dipCloses {
                // The nap holds the top of the dip only, the way Wake holds
                // the end of the night rather than the whole of it. Last
                // night is read whether or not the signature is settled: how
                // long you slept is a fact on its own, and unlike the night's
                // edges it needs no habit to be read against.
                let opened = today.sunrise.addingTimeInterval(dipOpens * span)
                if sleep?.wasShort(before: date) == true,
                   date < opened.addingTimeInterval(napLength) {
                    return Suggestion(mode: .nap, phase: phase, reason: "Suggested after a short night")
                }
                if isStrained(vitals) {
                    return Suggestion(mode: .restore, phase: phase, reason: "Suggested for a day below your usual")
                }
                return Suggestion(mode: .sprint, phase: phase, reason: "Suggested for the afternoon dip")
            }
            return Suggestion(mode: .relax, phase: phase, reason: "Suggested for the afternoon")
        }
        let tomorrow = date.addingTimeInterval(86400)
        let closes = edges?.morning(on: tomorrow, calendar: calendar) ?? day(tomorrow).sunrise
        return night(date, evening: evening, morning: closes, source: edges?.source)
    }

    private static func night(_ date: Date, evening: Date, morning: Date, source: SleepEdges.Source?) -> Suggestion {
        if date.timeIntervalSince(evening) < windDownLead {
            let reason: LocalizedStringResource = switch source {
            case .target: "Suggested before your target bedtime"
            case .habit: "Suggested before your usual bedtime"
            case nil: "Suggested for the evening"
            }
            return Suggestion(mode: .windDown, phase: .windDown, reason: reason)
        }
        if morning.timeIntervalSince(date) <= wakeLead {
            let reason: LocalizedStringResource = switch source {
            case .target: "Suggested before your target wake"
            case .habit: "Suggested before you usually wake"
            case nil: "Suggested before sunrise"
            }
            return Suggestion(mode: .wake, phase: .wake, reason: reason)
        }
        return Suggestion(mode: .sleep, phase: .night, reason: "Suggested for the night")
    }
}
