import Foundation
import Testing
@testable import Entrain

/// The sun and the arc it drives, against fixed dates and places.
@MainActor
struct CircadianTests {
    static let oslo = TimeZone(identifier: "Europe/Oslo")!
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = oslo
        return calendar
    }

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    static func minutes(_ date: Date) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return parts.hour! * 60 + parts.minute!
    }

    /// Oslo, 21 June 2026: almanac sunrise 03:53, sunset 22:44.
    @Test func midsummerInOslo() {
        let day = SolarDay.solar(latitude: 59.9, longitude: 10.75, on: Self.date(2026, 6, 21, 12), calendar: Self.calendar)
        #expect(abs(Self.minutes(day.sunrise) - (3 * 60 + 53)) <= 4)
        #expect(abs(Self.minutes(day.sunset) - (22 * 60 + 44)) <= 4)
    }

    /// Oslo, 21 December 2026: almanac sunrise 09:18, sunset 15:12.
    @Test func midwinterInOslo() {
        let day = SolarDay.solar(latitude: 59.9, longitude: 10.75, on: Self.date(2026, 12, 21, 12), calendar: Self.calendar)
        #expect(abs(Self.minutes(day.sunrise) - (9 * 60 + 18)) <= 4)
        #expect(abs(Self.minutes(day.sunset) - (15 * 60 + 12)) <= 4)
    }

    /// Tromsø in January has no sunrise; the day clamps to four hours around noon.
    @Test func polarNightClampsToAShortDay() {
        let day = SolarDay.solar(latitude: 69.65, longitude: 18.95, on: Self.date(2026, 1, 5, 12), calendar: Self.calendar)
        #expect(abs(day.sunset.timeIntervalSince(day.sunrise) - SolarDay.shortestDay) < 1)
        #expect(abs(Self.minutes(day.sunrise) + 120 - (11 * 60 + 40)) <= 10)
    }

    @Test func midnightSunClampsToALongDay() {
        let day = SolarDay.solar(latitude: 69.65, longitude: 18.95, on: Self.date(2026, 6, 21, 12), calendar: Self.calendar)
        #expect(abs(day.sunset.timeIntervalSince(day.sunrise) - SolarDay.longestDay) < 1)
    }

    @Test func clockDayRunsSevenToNineteen() {
        let day = SolarDay.clock(on: Self.date(2026, 3, 1, 15), calendar: Self.calendar)
        #expect(Self.minutes(day.sunrise) == 7 * 60)
        #expect(Self.minutes(day.sunset) == 19 * 60)
    }

    static let clock: @MainActor (Date) -> SolarDay = { SolarDay.clock(on: $0, calendar: calendar) }

    @Test func morningIsBrighterAndDeeperThanNight() {
        let morning = Circadian.adjustment(at: Self.date(2026, 3, 1, 10), day: Self.clock)
        let afternoon = Circadian.adjustment(at: Self.date(2026, 3, 1, 16), day: Self.clock)
        let evening = Circadian.adjustment(at: Self.date(2026, 3, 1, 22), day: Self.clock)
        let night = Circadian.adjustment(at: Self.date(2026, 3, 2, 2), day: Self.clock)
        #expect(morning.brightness > afternoon.brightness)
        #expect(afternoon.brightness > evening.brightness)
        #expect(evening.brightness > night.brightness)
        #expect(morning.depth > night.depth)
        #expect(morning.depth <= 1 && night.depth >= 0.8)
        #expect(morning.brightness <= 0.5 && night.brightness >= -0.7)
    }

    /// No step at sunrise or sunset, and every minute stays within range.
    @Test func arcIsContinuousAcrossTheDay() {
        var previous = Circadian.adjustment(at: Self.date(2026, 3, 1, 0), day: Self.clock)
        for minute in stride(from: 1, through: 24 * 60, by: 1) {
            let next = Circadian.adjustment(at: Self.date(2026, 3, 1, 0).addingTimeInterval(Double(minute) * 60), day: Self.clock)
            #expect(abs(next.brightness - previous.brightness) < 0.02)
            #expect(abs(next.depth - previous.depth) < 0.01)
            #expect((-1...1).contains(next.brightness) && (0.8...1).contains(next.depth))
            previous = next
        }
    }

    /// A winter afternoon in Oslo is already evening for the arc; a June one is not.
    @Test func seasonMovesTheArc() {
        let solar: @MainActor (Date) -> SolarDay = { SolarDay.solar(latitude: 59.9, longitude: 10.75, on: $0, calendar: Self.calendar) }
        let december = Circadian.adjustment(at: Self.date(2026, 12, 21, 16), day: solar)
        let june = Circadian.adjustment(at: Self.date(2026, 6, 21, 16), day: solar)
        #expect(december.brightness < june.brightness)
        #expect(december.depth < june.depth)
    }

    @Test func curveHoldsItsEndsAndPassesThroughPoints() {
        let curve = Curve([(0, 1), (0.5, 3), (1, 2)])
        #expect(curve.value(at: -1) == 1)
        #expect(curve.value(at: 0.5) == 3)
        #expect(curve.value(at: 2) == 2)
        #expect(abs(curve.value(at: 0.25) - 2) < 1e-9)
    }

    @Test func inputRunsOnlyWhilePlaying() async {
        let day = Self.date(2026, 3, 1, 10)
        let circadian = Circadian(day: Self.clock, now: { day })
        var changes = 0
        circadian.onChange = { changes += 1 }
        #expect(circadian.adjustment == .none)
        circadian.start(for: .focus)
        #expect(changes == 1)
        #expect(circadian.adjustment.brightness > 0)
        circadian.stop()
    }
}
