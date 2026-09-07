import Foundation
import Testing
@testable import Entrain

/// The suggested mode over a clock day, 7 to 19.
struct SuggestionTests {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Oslo")!
        return calendar
    }

    static func date(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: hour, minute: minute))!
    }

    static func at(_ hour: Int, sleep: SleepSignature? = nil) -> Mode {
        Suggestion.at(
            date(hour), day: { SolarDay.clock(on: $0, calendar: calendar) }, sleep: sleep, calendar: calendar
        ).mode
    }

    @Test func followsTheDay() {
        #expect(Self.at(5) == .wake)
        #expect(Self.at(3) == .sleep)
        #expect(Self.at(9) == .focus)
        #expect(Self.at(13) == .gamma)
        #expect(Self.at(16) == .relax)
        #expect(Self.at(20) == .windDown)
        #expect(Self.at(23) == .sleep)
    }

    /// A settled signature moves the night's two edges and leaves the
    /// daylight hours to the sun.
    static let owl = SleepSignature(bedtime: 1 * 3600, wake: 9 * 3600, latency: 15 * 60, spread: 900, nights: 10)

    @Test func aLateSleeperGetsALateEvening() {
        #expect(Self.owl.isSettled)
        // Bedtime is one in the morning, so Wind Down opens at ten at night,
        // not three hours after a seven-to-nineteen sunset.
        #expect(Self.at(20, sleep: Self.owl) == .relax)
        #expect(Self.at(23, sleep: Self.owl) == .windDown)
        #expect(Self.at(3, sleep: Self.owl) == .sleep)
        // Waking at nine, so the two hours before that are for waking and
        // the morning proper starts after it.
        #expect(Self.at(8, sleep: Self.owl) == .wake)
        #expect(Self.at(5, sleep: Self.owl) == .sleep)
        #expect(Self.at(10, sleep: Self.owl) == .focus)
    }

    /// An unsettled signature changes nothing: the sun is where this
    /// started, and it is also what a Mac, a refusal and a fresh install
    /// all get.
    @Test func anUnsettledSignatureFallsBackToTheSun() {
        let scattered = SleepSignature(bedtime: 1 * 3600, wake: 9 * 3600, latency: nil, spread: 5 * 3600, nights: 10)
        #expect(!scattered.isSettled)
        #expect(Self.at(20, sleep: scattered) == .windDown)
        #expect(Self.at(5, sleep: scattered) == .wake)
    }

    /// Every minute of the day lands on exactly one mode, with a signature
    /// and without: no hour falls through the night's edges into nothing.
    @Test func everyMinuteHasASuggestion() {
        for signature in [nil, Self.owl] as [SleepSignature?] {
            for minute in stride(from: 0, to: 24 * 60, by: 5) {
                let mode = Suggestion.at(
                    Self.date(0).addingTimeInterval(Double(minute) * 60),
                    day: { SolarDay.clock(on: $0, calendar: Self.calendar) },
                    sleep: signature, calendar: Self.calendar
                ).mode
                #expect(Mode.allCases.contains(mode))
            }
        }
    }
}
