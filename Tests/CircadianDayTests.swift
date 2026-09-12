import Foundation
import Testing
@testable import Entrain

/// The day as a ring. Nothing here should be able to disagree with
/// `SuggestionTests`: `CircadianDay` samples the same function, so these
/// check that the sampling loses nothing and that the phases and the modes
/// stay separable.
struct CircadianDayTests {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Oslo")!
        return calendar
    }

    static func date(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: hour, minute: minute))!
    }

    static func day(sleep: SleepSignature? = nil, vitals: [BodyMetric: BodySignal] = [:]) -> CircadianDay {
        CircadianDay.on(
            date(12), day: { SolarDay.clock(on: $0, calendar: calendar) },
            sleep: sleep, vitals: vitals, calendar: calendar
        )
    }

    @Test func coversTheWholeDayWithoutGaps() {
        let day = Self.day()
        #expect(day.start == Self.calendar.startOfDay(for: Self.date(12)))
        #expect(day.spans.first?.interval.start == day.start)
        #expect(day.spans.last?.interval.end == day.end)
        for (a, b) in zip(day.spans, day.spans.dropFirst()) {
            #expect(a.interval.end == b.interval.start)
        }
    }

    /// The ring must say what the suggestion card says at the same minute,
    /// or the app has two opinions about the hour.
    @Test func agreesWithTheSuggestion() {
        let day = Self.day()
        for hour in 0..<24 {
            let when = Self.date(hour, 30)
            let suggestion = Suggestion.at(
                when, day: { SolarDay.clock(on: $0, calendar: Self.calendar) }, calendar: Self.calendar
            )
            #expect(day.span(at: when)?.mode == suggestion.mode)
            #expect(day.span(at: when)?.phase == suggestion.phase)
        }
    }

    @Test func namesTheClockDayInOrder() {
        let day = Self.day()
        #expect(day.span(at: Self.date(3))?.phase == .night)
        #expect(day.span(at: Self.date(6))?.phase == .wake)
        #expect(day.span(at: Self.date(9))?.phase == .morning)
        #expect(day.span(at: Self.date(13))?.phase == .sharpest)
        #expect(day.span(at: Self.date(16))?.phase == .afternoon)
        #expect(day.span(at: Self.date(20))?.phase == .windDown)
        #expect(day.span(at: Self.date(23))?.phase == .night)
    }

    /// A strained day changes what is played, not what the clock is doing.
    /// Collapsing the two would report a body with no morning at all.
    @Test func strainMovesTheModeAndNotThePhase() {
        let strained: [BodyMetric: BodySignal] = [
            .heartRateVariability: BodySignal(
                metric: .heartRateVariability, today: 30, baseline: 50, deviation: -2, days: 60
            )
        ]
        let day = Self.day(vitals: strained)
        #expect(day.span(at: Self.date(9))?.phase == .morning)
        #expect(day.span(at: Self.date(9))?.mode == .relax)
        #expect(Self.day().span(at: Self.date(9))?.mode == .focus)
    }

    /// A settled signature moves the night's edges on the ring too, and the
    /// two habitual ticks replace the sun's.
    static let owl = SleepSignature(bedtime: 1 * 3600, wake: 9 * 3600, latency: 15 * 60, spread: 900, nights: 10)

    @Test func aLateSleeperGetsALateRing() {
        let day = Self.day(sleep: Self.owl)
        #expect(day.isAnchored)
        #expect(day.bedtime == Self.date(1))
        #expect(day.wake == Self.date(9))
        #expect(day.span(at: Self.date(23))?.phase == .windDown)
        #expect(day.span(at: Self.date(8))?.phase == .wake)
        #expect(Self.day().isAnchored == false)
    }

    // MARK: The widget's snapshot

    /// The widget stores times of day, not dates, so that a snapshot taken
    /// on one day still draws correctly on the next. Laying it back over the
    /// same day must give the same day back.
    @Test func phasesRoundTripThroughTheSnapshot() throws {
        let day = Self.day(sleep: Self.owl)
        let back = day.phases.day(on: Self.date(12), calendar: Self.calendar)
        #expect(back.start == day.start)
        #expect(back.spans == day.spans)
        #expect(back.sunrise == day.sunrise)
        #expect(back.sunset == day.sunset)
        #expect(back.bedtime == day.bedtime)
        #expect(back.wake == day.wake)
    }

    /// And on another day it is the same shape, moved: this is the whole
    /// reason the snapshot holds seconds rather than dates.
    @Test func aSnapshotLaidOverAnotherDayKeepsItsShape() {
        let day = Self.day()
        let tomorrow = Self.calendar.date(byAdding: .day, value: 1, to: Self.date(12))!
        let moved = day.phases.day(on: tomorrow, calendar: Self.calendar)
        #expect(moved.start == Self.calendar.startOfDay(for: tomorrow))
        #expect(moved.spans.map(\.phase) == day.spans.map(\.phase))
        #expect(moved.spans.map(\.mode) == day.spans.map(\.mode))
        for (a, b) in zip(moved.spans, day.spans) {
            #expect(a.interval.start.timeIntervalSince(moved.start) == b.interval.start.timeIntervalSince(day.start))
        }
        #expect(moved.spans.last?.interval.end == moved.end)
    }

    @Test func theSnapshotSurvivesEncoding() throws {
        let phases = Self.day(sleep: Self.owl).phases
        let data = try JSONEncoder().encode(phases)
        #expect(try JSONDecoder().decode(DayPhases.self, from: data) == phases)
    }

    @Test func progressRunsMidnightToMidnight() {
        let day = Self.day()
        #expect(day.progress(of: day.start) == 0)
        #expect(abs(day.progress(of: Self.date(12)) - 0.5) < 1e-9)
        #expect(day.progress(of: day.end) == 1)
    }
}
