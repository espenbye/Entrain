import Foundation

/// The mode that fits the time of day: a tap starts it with the timer
/// already set. Morning is for work, midday for the sharpest attention,
/// afternoon for a breather; the hours before bed ease toward it, the night
/// is for sleep, and the last two hours before morning are for waking.
///
/// The day is measured against the sun, like the circadian arc. The night's
/// two edges are not: when Health knows this person's habitual bedtime and
/// wake, those replace sunset and sunrise, because the sun is the worst
/// guide exactly where it matters most. Three hours after a Norwegian
/// midsummer sunset is half past one in the morning, and three hours after
/// a December one is dinner. Without a settled signature — a fresh install,
/// a Mac, or a refusal, which look the same — the sun stands in, which is
/// where this started.
struct Suggestion: Equatable, Sendable {
    var mode: Mode
    var reason: LocalizedStringResource

    static func == (a: Self, b: Self) -> Bool { a.mode == b.mode }

    /// How long before bed Wind Down is the suggestion. Unchanged from the
    /// sunset heuristic it replaces; only what it hangs off has moved.
    static let windDownLead: TimeInterval = 3 * 3600
    /// How long before waking Wake is the suggestion.
    static let wakeLead: TimeInterval = 2 * 3600

    static func at(
        _ date: Date, day: (Date) -> SolarDay, sleep: SleepSignature? = nil, calendar: Calendar = .current
    ) -> Suggestion {
        let signature = sleep?.isSettled == true ? sleep : nil
        let today = day(date)
        let morning = signature?.morning(on: date, calendar: calendar) ?? today.sunrise
        let evening = signature.map { $0.evening(on: date, calendar: calendar) - windDownLead } ?? today.sunset

        if date < morning {
            let yesterday = date.addingTimeInterval(-86400)
            let opened = signature.map { $0.evening(on: yesterday, calendar: calendar) - windDownLead }
                ?? day(yesterday).sunset
            return night(date, evening: opened, morning: morning, habitual: signature != nil)
        }
        if date < evening {
            // The daylight hours keep the sun: a bright morning is a fact
            // about the light, not about when this person went to bed. The
            // progress clamps, so an evening that starts after sunset simply
            // stays at the far end of the afternoon until Wind Down takes over.
            let span = today.sunset.timeIntervalSince(today.sunrise)
            let p = span > 0 ? min(1, max(0, date.timeIntervalSince(today.sunrise) / span)) : 1
            if p < 0.4 { return Suggestion(mode: .focus, reason: "Suggested for a bright morning") }
            if p < 0.6 { return Suggestion(mode: .gamma, reason: "Suggested for midday") }
            return Suggestion(mode: .relax, reason: "Suggested for the afternoon")
        }
        let tomorrow = date.addingTimeInterval(86400)
        let closes = signature?.morning(on: tomorrow, calendar: calendar) ?? day(tomorrow).sunrise
        return night(date, evening: evening, morning: closes, habitual: signature != nil)
    }

    private static func night(_ date: Date, evening: Date, morning: Date, habitual: Bool) -> Suggestion {
        if date.timeIntervalSince(evening) < windDownLead {
            return Suggestion(
                mode: .windDown,
                reason: habitual ? "Suggested before your usual bedtime" : "Suggested for the evening"
            )
        }
        if morning.timeIntervalSince(date) <= wakeLead {
            return Suggestion(
                mode: .wake,
                reason: habitual ? "Suggested before you usually wake" : "Suggested before sunrise"
            )
        }
        return Suggestion(mode: .sleep, reason: "Suggested for the night")
    }
}
