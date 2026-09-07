import Foundation

/// The mode that fits the time of day, measured against the sun like the
/// circadian arc: a tap starts it with the timer already set. Morning is
/// for work, midday for the sharpest attention, afternoon for a breather;
/// the first hours after sunset ease toward bed, the night is for sleep,
/// and the last two hours before sunrise are for waking.
struct Suggestion: Equatable, Sendable {
    var mode: Mode
    var reason: LocalizedStringResource

    static func == (a: Self, b: Self) -> Bool { a.mode == b.mode }

    static func at(_ date: Date, day: (Date) -> SolarDay) -> Suggestion {
        let today = day(date)
        if date < today.sunrise {
            return night(date, sunset: day(date.addingTimeInterval(-86400)).sunset, sunrise: today.sunrise)
        }
        if date < today.sunset {
            let p = date.timeIntervalSince(today.sunrise) / today.sunset.timeIntervalSince(today.sunrise)
            if p < 0.4 { return Suggestion(mode: .focus, reason: "Suggested for a bright morning") }
            if p < 0.6 { return Suggestion(mode: .gamma, reason: "Suggested for midday") }
            return Suggestion(mode: .relax, reason: "Suggested for the afternoon")
        }
        return night(date, sunset: today.sunset, sunrise: day(date.addingTimeInterval(86400)).sunrise)
    }

    private static func night(_ date: Date, sunset: Date, sunrise: Date) -> Suggestion {
        if date.timeIntervalSince(sunset) < 3 * 3600 { return Suggestion(mode: .windDown, reason: "Suggested for the evening") }
        if sunrise.timeIntervalSince(date) <= 2 * 3600 { return Suggestion(mode: .wake, reason: "Suggested before sunrise") }
        return Suggestion(mode: .sleep, reason: "Suggested for the night")
    }
}
