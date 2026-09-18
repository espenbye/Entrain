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

    static func at(_ hour: Int, _ minute: Int = 0, sleep: SleepSignature? = nil) -> Mode {
        Suggestion.at(
            date(hour, minute), day: { SolarDay.clock(on: $0, calendar: calendar) },
            sleep: sleep, calendar: calendar
        ).mode
    }

    @Test func followsTheDay() {
        #expect(Self.at(5) == .wake)
        #expect(Self.at(3) == .sleep)
        #expect(Self.at(9) == .focus)
        #expect(Self.at(13) == .gamma)
        // 7 to 19 puts the dip at 14:12 and the recovery after it at 16:00.
        #expect(Self.at(15) == .sprint)
        #expect(Self.at(16) == .relax)
        #expect(Self.at(20) == .windDown)
        #expect(Self.at(23) == .sleep)
    }

    /// The afternoon was one long Relax and is now two stretches: the dip,
    /// which is worked in rounds, and the recovery, which is the breather.
    @Test func theAfternoonDipIsWorkedInRounds() {
        #expect(Self.at(14, 10) == .gamma)
        #expect(Self.at(14, 15) == .sprint)
        #expect(Self.at(15, 55) == .sprint)
        #expect(Self.at(16, 5) == .relax)
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

    // MARK: The body's one say

    static func vitals(_ metric: BodyMetric, _ deviation: Double) -> [BodyMetric: BodySignal] {
        [metric: BodySignal(metric: metric, today: 0, baseline: 0, deviation: deviation, days: 30)]
    }

    static func at(_ hour: Int, vitals: [BodyMetric: BodySignal]) -> Mode {
        Suggestion.at(
            date(hour), day: { SolarDay.clock(on: $0, calendar: calendar) },
            vitals: vitals, calendar: calendar
        ).mode
    }

    /// A day well below this person's own variability, or well above their
    /// own resting heart rate, argues the work modes down to Relax.
    @Test func aStrainedDayTradesTheWorkModesForRelax() {
        #expect(Self.at(9, vitals: Self.vitals(.heartRateVariability, -2)) == .relax)
        #expect(Self.at(13, vitals: Self.vitals(.heartRateVariability, -2)) == .relax)
        #expect(Self.at(9, vitals: Self.vitals(.restingHeartRate, 2)) == .relax)
    }

    /// In the dip the lighter mode is Restore rather than Relax: the dip is
    /// already the low point of the day, and a taxed body there wants the
    /// rest a breather only gestures at.
    @Test func aStrainedDayRestsThroughTheDipInsteadOfSprinting() {
        #expect(Self.at(15, vitals: Self.vitals(.heartRateVariability, -2)) == .restore)
        #expect(Self.at(15, vitals: Self.vitals(.restingHeartRate, 2)) == .restore)
        #expect(Self.at(15, vitals: Self.vitals(.heartRateVariability, -1)) == .sprint)
    }

    /// It gets no say after the afternoon, and none at all inside the
    /// ordinary range.
    @Test func theBodyOnlyEverArguesWithTheDaylightHours() {
        let strained = Self.vitals(.heartRateVariability, -2)
        #expect(Self.at(16, vitals: strained) == .relax)
        #expect(Self.at(20, vitals: strained) == .windDown)
        #expect(Self.at(23, vitals: strained) == .sleep)
        #expect(Self.at(5, vitals: strained) == .wake)

        // Inside the range, and the wrong way round, change nothing.
        #expect(Self.at(9, vitals: Self.vitals(.heartRateVariability, -1)) == .focus)
        #expect(Self.at(9, vitals: Self.vitals(.heartRateVariability, 2)) == .focus)
        #expect(Self.at(9, vitals: Self.vitals(.restingHeartRate, -2)) == .focus)
        #expect(Self.at(13, vitals: [:]) == .gamma)
    }

    // MARK: A short night

    /// A settled sleeper who got up at six after `asleep` hours of sleep.
    static func shortSleeper(asleep: TimeInterval = 5 * 3600) -> SleepSignature {
        var signature = SleepSignature(
            bedtime: 23 * 3600, wake: 7 * 3600, latency: 15 * 60, spread: 900, nights: 10
        )
        signature.last = SleepNight(
            night: date(0).addingTimeInterval(-86400),
            interval: DateInterval(start: date(6).addingTimeInterval(-asleep), end: date(6)),
            asleep: asleep
        )
        return signature
    }

    /// A short night turns the top of the dip into a nap, and only the top
    /// of it: half an hour, then the afternoon carries on as it would have.
    @Test func aShortNightBuysHalfAnHourOfNapAtTheTopOfTheDip() {
        let short = Self.shortSleeper()
        #expect(Self.at(14, 15, sleep: short) == .nap)
        #expect(Self.at(14, 40, sleep: short) == .nap)
        #expect(Self.at(14, 45, sleep: short) == .sprint)
        // And nowhere else in the day: a nap is the dip's answer alone.
        #expect(Self.at(9, sleep: short) == .focus)
        #expect(Self.at(13, sleep: short) == .gamma)
        #expect(Self.at(17, sleep: short) == .relax)
        #expect(Self.at(22, sleep: short) == .windDown)
    }

    /// An ordinary night buys nothing, and neither does a night so old that
    /// Health simply has not written the one since.
    @Test func aFullNightAndAStaleNightBothLeaveTheDipAlone() {
        #expect(Self.at(14, 15, sleep: Self.shortSleeper(asleep: 8 * 3600)) == .sprint)

        var stale = Self.shortSleeper()
        stale.last = SleepNight(
            night: Self.date(0).addingTimeInterval(-3 * 86400),
            interval: DateInterval(
                start: Self.date(1).addingTimeInterval(-2 * 86400),
                end: Self.date(6).addingTimeInterval(-2 * 86400)
            ),
            asleep: 5 * 3600
        )
        #expect(Self.at(14, 15, sleep: stale) == .sprint)
    }

    /// Sleep debt is repaid by sleep, so the nap wins over the rest a
    /// strained day would otherwise get.
    @Test func theNapOutranksRestore() {
        #expect(
            Suggestion.at(
                Self.date(14, 15), day: { SolarDay.clock(on: $0, calendar: Self.calendar) },
                sleep: Self.shortSleeper(), vitals: Self.vitals(.heartRateVariability, -2),
                calendar: Self.calendar
            ).mode == .nap
        )
    }

    /// Every minute of the day lands on exactly one mode, with a signature
    /// and without: no hour falls through the night's edges into nothing.
    @Test func everyMinuteHasASuggestion() {
        for signature in [nil, Self.owl, Self.shortSleeper()] as [SleepSignature?] {
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
