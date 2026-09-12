import Foundation
import Testing
@testable import Entrain

/// The reductions Health feeds the adaptive layer, against synthetic
/// samples. Everything here is a pure function: no store, no permission,
/// and the same result on a Mac that has no HealthKit at all.
struct HealthTests {
    static let oslo = TimeZone(identifier: "Europe/Oslo")!
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = oslo
        return calendar
    }

    static func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute))!
    }

    static func asleep(_ from: Date, _ to: Date, source: String = "watch") -> SleepStageSample {
        SleepStageSample(.asleep, DateInterval(start: from, end: to), source: source)
    }

    static func minutes(_ seconds: TimeInterval) -> Int { Int((seconds / 60).rounded()) }

    /// Seconds from midnight as "23:10", for readable failures.
    static func clock(_ seconds: TimeInterval) -> Int { minutes(seconds) }

    // MARK: One interval per night

    /// The stages a watch writes are contiguous pieces of one night; the
    /// night is their span, and the asleep time is their sum.
    @Test func stagesReduceToOneNight() {
        let nights = SleepNight.nights(
            from: [
                Self.asleep(Self.date(10, 23), Self.date(11, 1)),
                Self.asleep(Self.date(11, 1), Self.date(11, 3)),
                Self.asleep(Self.date(11, 3), Self.date(11, 6, 30)),
            ],
            calendar: Self.calendar
        )
        #expect(nights.count == 1)
        #expect(nights[0].bedtime == Self.date(10, 23))
        #expect(nights[0].wake == Self.date(11, 6, 30))
        #expect(Self.minutes(nights[0].asleep) == 7 * 60 + 30)
    }

    /// A wakening in the middle bounds nothing and counts as nothing: the
    /// night still runs to the last stage, and the asleep time skips it.
    @Test func wakeningsDoNotCountAsSleep() {
        let nights = SleepNight.nights(
            from: [
                Self.asleep(Self.date(10, 23), Self.date(11, 2)),
                SleepStageSample(.awake, DateInterval(start: Self.date(11, 2), end: Self.date(11, 2, 40)), source: "watch"),
                Self.asleep(Self.date(11, 2, 40), Self.date(11, 7)),
            ],
            calendar: Self.calendar
        )
        #expect(nights.count == 1)
        #expect(nights[0].wake == Self.date(11, 7))
        #expect(Self.minutes(nights[0].asleep) == 7 * 60 + 20)
    }

    /// Two sources describing the same night are not added together. The
    /// one that recorded most of it wins outright, so eight hours of watch
    /// and a third-party app's overlapping seven do not become fifteen.
    @Test func onlyTheSourceThatRecordedMostOfTheNightCounts() {
        let nights = SleepNight.nights(
            from: [
                Self.asleep(Self.date(10, 23), Self.date(11, 7), source: "watch"),
                Self.asleep(Self.date(10, 23, 30), Self.date(11, 6), source: "other"),
                Self.asleep(Self.date(11, 6), Self.date(11, 6, 30), source: "other"),
            ],
            calendar: Self.calendar
        )
        #expect(nights.count == 1)
        #expect(Self.minutes(nights[0].asleep) == 8 * 60)
        #expect(nights[0].interval == DateInterval(start: Self.date(10, 23), end: Self.date(11, 7)))
    }

    /// Overlapping stages from one source are merged, not summed.
    @Test func overlapWithinASourceIsMergedOnce() {
        let nights = SleepNight.nights(
            from: [
                Self.asleep(Self.date(10, 23), Self.date(11, 4)),
                Self.asleep(Self.date(11, 2), Self.date(11, 7)),
            ],
            calendar: Self.calendar
        )
        #expect(Self.minutes(nights[0].asleep) == 8 * 60)
    }

    /// An afternoon nap is a separate episode and too short to be a night,
    /// so it never drags the bedtime earlier.
    @Test func napsAreNotNights() {
        let nights = SleepNight.nights(
            from: [
                Self.asleep(Self.date(10, 14), Self.date(10, 15)),
                Self.asleep(Self.date(10, 23), Self.date(11, 7)),
            ],
            calendar: Self.calendar
        )
        #expect(nights.count == 1)
        #expect(nights[0].bedtime == Self.date(10, 23))
    }

    /// Time in bed is not time asleep: it supplies the latency and bounds
    /// nothing.
    @Test func timeInBedGivesTheLatencyOnly() {
        let nights = SleepNight.nights(
            from: [
                SleepStageSample(.inBed, DateInterval(start: Self.date(10, 22, 45), end: Self.date(11, 7)), source: "phone"),
                Self.asleep(Self.date(10, 23, 5), Self.date(11, 7)),
            ],
            calendar: Self.calendar
        )
        #expect(nights[0].bedtime == Self.date(10, 23, 5))
        #expect(nights[0].latency.map(Self.minutes) == 20)
    }

    /// A night nothing was recorded for is absent, not a night of no sleep.
    @Test func nightsWithoutDataAreDroppedRatherThanCountedAsZero() {
        let nights = SleepNight.nights(
            from: [
                Self.asleep(Self.date(10, 23), Self.date(11, 7)),
                // Nothing at all for the 11th.
                Self.asleep(Self.date(12, 23), Self.date(13, 7)),
            ],
            calendar: Self.calendar
        )
        #expect(nights.count == 2)
        let signature = SleepSignature.from(nights, calendar: Self.calendar)
        #expect(Self.clock(signature!.bedtime) == 23 * 60)
    }

    /// A short fragment is a watch that came off, not a night.
    @Test func fragmentsAreNotNights() {
        let nights = SleepNight.nights(
            from: [Self.asleep(Self.date(10, 23), Self.date(11, 1))],
            calendar: Self.calendar
        )
        #expect(nights.isEmpty)
    }

    // MARK: The signature

    static func fortnight(
        bedtime: (hour: Int, minute: Int), wake: (hour: Int, minute: Int),
        count: Int = 10, from first: Int = 1
    ) -> [SleepNight] {
        (first..<(first + count)).map { day in
            let start = calendar.date(from: DateComponents(
                year: 2026, month: 3, day: day, hour: bedtime.hour, minute: bedtime.minute
            ))!
            let end = calendar.date(from: DateComponents(
                year: 2026, month: 3, day: bedtime.hour >= 12 ? day + 1 : day, hour: wake.hour, minute: wake.minute
            ))!
            return SleepNight(
                night: SleepNight.key(for: start, calendar: calendar),
                interval: DateInterval(start: start, end: end),
                asleep: end.timeIntervalSince(start),
                latency: 15 * 60
            )
        }
    }

    @Test func signatureFollowsTheNights() {
        let signature = SleepSignature.from(
            Self.fortnight(bedtime: (23, 10), wake: (6, 50)), calendar: Self.calendar
        )!
        #expect(Self.clock(signature.bedtime) == 23 * 60 + 10)
        #expect(Self.clock(signature.wake) == 6 * 60 + 50)
        #expect(signature.onset.map(Self.minutes) == 15)
        #expect(signature.isSettled)
    }

    /// Clock times wrap. Half past eleven and half past midnight average to
    /// midnight; an arithmetic mean would put bedtime at noon.
    @Test func bedtimesAverageAroundMidnightAndNotThroughNoon() {
        let (mean, spread) = SleepSignature.circularMean(of: [23.5 * 3600, 0.5 * 3600])
        #expect(Self.clock(mean) == 0 || Self.clock(mean) == 24 * 60)
        #expect(spread > 0)
    }

    /// Bedtimes all over the clock describe no habit, so the sun keeps the
    /// night's edges.
    @Test func aScatteredSleeperIsNotSettled() {
        var nights = Self.fortnight(bedtime: (23, 0), wake: (7, 0))
        for index in nights.indices where index.isMultiple(of: 2) {
            nights[index].interval = DateInterval(
                start: nights[index].interval.start.addingTimeInterval(-4 * 3600),
                end: nights[index].interval.end
            )
        }
        let signature = SleepSignature.from(nights, calendar: Self.calendar)!
        #expect(signature.spread > SleepSignature.widestSpread)
        #expect(!signature.isSettled)
    }

    @Test func tooFewNightsAreNotSettled() {
        let nights = Array(Self.fortnight(bedtime: (23, 0), wake: (7, 0)).prefix(3))
        #expect(SleepSignature.from(nights, calendar: Self.calendar)!.isSettled == false)
    }

    // MARK: Social jetlag

    /// March 2026 opens on a Sunday, so days 6 and 7 are the Friday and
    /// Saturday nights — the two a fortnight of ten nights from the first
    /// contains, which is exactly the minimum the difference needs.
    static func withLateWeekend(_ shift: TimeInterval) -> [SleepNight] {
        fortnight(bedtime: (23, 0), wake: (7, 0)).map { night in
            guard SleepSignature.isFree(night, calendar: calendar) else { return night }
            var late = night
            late.interval = DateInterval(
                start: night.interval.start.addingTimeInterval(shift),
                end: night.interval.end.addingTimeInterval(shift)
            )
            return late
        }
    }

    @Test func freeNightsShiftTheMiddleOfSleep() {
        let signature = SleepSignature.from(Self.withLateWeekend(2 * 3600), calendar: Self.calendar)!
        // Two of ten nights moved two hours, so the difference between the
        // two means is the full two hours, not a tenth of it.
        #expect(Self.minutes(signature.drift!) == 120)
    }

    /// The same schedule every night is no drift at all, and the sign says
    /// which way it went rather than only how far.
    @Test func aSteadySleeperHasNoDrift() {
        let signature = SleepSignature.from(Self.withLateWeekend(0), calendar: Self.calendar)!
        #expect(Self.minutes(signature.drift!) == 0)
        let early = SleepSignature.from(Self.withLateWeekend(-3600), calendar: Self.calendar)!
        #expect(Self.minutes(early.drift!) == -60)
    }

    /// Mid-sleep, not bedtime: a late night that still ends at the same
    /// alarm has moved the middle half as far as its bedtime.
    @Test func driftIsMeasuredAtTheMiddleAndNotTheBedtime() {
        let nights = Self.fortnight(bedtime: (23, 0), wake: (7, 0)).map { night -> SleepNight in
            guard SleepSignature.isFree(night, calendar: Self.calendar) else { return night }
            var late = night
            late.interval = DateInterval(
                start: night.interval.start.addingTimeInterval(2 * 3600), end: night.interval.end
            )
            return late
        }
        #expect(Self.minutes(SleepSignature.from(nights, calendar: Self.calendar)!.drift!) == 60)
    }

    /// One night of each kind is two nights, not a rhythm, so there is
    /// nothing to report.
    @Test func tooFewOfEitherKindReportNoDrift() {
        let nights = Array(Self.fortnight(bedtime: (23, 0), wake: (7, 0)).prefix(6))
        #expect(SleepSignature.from(nights, calendar: Self.calendar)!.drift == nil)
    }

    /// A rhythm that is not an evening-to-morning night is left to the sun
    /// rather than mapped onto one it does not have.
    @Test func aDaytimeSleeperIsNotSettled() {
        let signature = SleepSignature.from(
            Self.fortnight(bedtime: (9, 0), wake: (17, 0)), calendar: Self.calendar
        )!
        #expect(!signature.isSettled)
    }

    /// Only the most recent nights count, so a fortnight-old holiday does
    /// not still move bedtime.
    @Test func onlyTheWindowCounts() {
        let window = SleepSignature.window
        let old = Self.fortnight(bedtime: (2, 0), wake: (10, 0), count: window, from: 1)
        let recent = Self.fortnight(bedtime: (23, 0), wake: (7, 0), count: window, from: window + 1)
        let signature = SleepSignature.from(old + recent, calendar: Self.calendar)!
        #expect(signature.nights == window)
        #expect(Self.clock(signature.bedtime) == 23 * 60)
    }

    /// The onset the sleep arc uses is held inside a plausible range, so one
    /// two-hour night awake in bed cannot stretch it.
    @Test func onsetIsClamped() {
        var nights = Self.fortnight(bedtime: (23, 0), wake: (7, 0))
        for index in nights.indices { nights[index].latency = 2 * 3600 }
        #expect(SleepSignature.from(nights, calendar: Self.calendar)!.onset == 45 * 60)
        for index in nights.indices { nights[index].latency = 30 }
        #expect(SleepSignature.from(nights, calendar: Self.calendar)!.onset == 5 * 60)
    }

    /// A night spent awake in bed for hours should not double the onset for
    /// a fortnight, so the latency is the median.
    @Test func oneRestlessNightDoesNotMoveTheOnset() {
        var nights = Self.fortnight(bedtime: (23, 0), wake: (7, 0))
        nights[0].latency = 3 * 3600
        #expect(SleepSignature.from(nights, calendar: Self.calendar)!.onset.map(Self.minutes) == 15)
    }

    // MARK: Baselines

    @Test func aDayBelowBaselineReadsBelow() {
        let history = Array(repeating: 55.0, count: 30).enumerated().map { $0.offset.isMultiple(of: 2) ? 53.0 : 57.0 }
        let signal = BodySignal.from(history: history, today: 49, metric: .restingHeartRate)!
        #expect(abs(signal.baseline - 55) < 0.01)
        #expect(signal.deviation < -1.5)
        #expect(signal.days == 30)
    }

    /// Variability is baselined on the log, so the same proportional drop
    /// reads the same whether the baseline is 30 ms or 90 ms. On the raw
    /// scale it would not.
    @Test func variabilityIsBaselinedOnTheLog() {
        func deviation(around centre: Double) -> Double {
            let history = (0..<30).map { centre * ($0.isMultiple(of: 2) ? 0.9 : 1.1) }
            return BodySignal.from(history: history, today: centre * 0.75, metric: .heartRateVariability)!.deviation
        }
        #expect(abs(deviation(around: 30) - deviation(around: 90)) < 1e-6)
        #expect(deviation(around: 60) < 0)
    }

    /// Deviations are clamped: a missed strap is an artefact, not a
    /// gradation, and nothing downstream should see a twelve.
    @Test func deviationsAreClamped() {
        let history = (0..<30).map { 55.0 + Double($0.isMultiple(of: 2) ? -1 : 1) }
        #expect(BodySignal.from(history: history, today: 200, metric: .restingHeartRate)!.deviation == BodySignal.limit)
    }

    /// Too little history says nothing at all rather than saying something
    /// noisy, which is also the state a fresh install is in.
    @Test func tooLittleHistoryPublishesNothing() {
        #expect(BodySignal.from(history: Array(repeating: 55.0, count: 5), today: 50, metric: .restingHeartRate) == nil)
        #expect(BodySignal.from(history: [], today: 50, metric: .restingHeartRate) == nil)
    }

    /// A baseline that never moves has no scale to measure against.
    @Test func aFlatBaselinePublishesNothing() {
        #expect(BodySignal.from(history: Array(repeating: 55.0, count: 30), today: 50, metric: .restingHeartRate) == nil)
    }

    // MARK: Following the breath

    /// Beats every five seconds, which is what a workout session delivers.
    static func beats(over seconds: Double, _ bpm: (Double) -> Double) -> [Beat] {
        stride(from: 0, to: seconds, by: 5).map { Beat(elapsed: $0, bpm: bpm($0)) }
    }

    /// A heart that rises through the inhale and falls through the exhale
    /// correlates with the cue; the same heart against the same pattern
    /// half a breath out of step does not.
    @Test func aHeartOnThePaceCorrelatesWithTheCue() {
        let pattern = BreathingPattern.coherent
        let followed = Self.beats(over: 300) { 60 + 4 * (Coherence.depth(of: pattern, at: $0) ?? 0) }
        #expect(Coherence.correlation(of: followed, following: pattern)! > 0.9)

        let inverted = Self.beats(over: 300) { 60 - 4 * (Coherence.depth(of: pattern, at: $0) ?? 0) }
        #expect(Coherence.correlation(of: inverted, following: pattern)! < -0.9)
    }

    /// A heart doing its own thing shows no relation to the pacing.
    @Test func aHeartOffThePaceDoesNot() {
        let drifting = Self.beats(over: 300) { 60 + 3 * sin($0 / 47) }
        #expect(abs(Coherence.correlation(of: drifting, following: .coherent)!) < 0.5)
    }

    /// Too few beats, or a heart that never moves, says nothing.
    @Test func thereIsNoCorrelationWithoutEnoughToGoOn() {
        #expect(Coherence.correlation(of: Self.beats(over: 30) { _ in 60 }, following: .coherent) == nil)
        #expect(Coherence.correlation(of: Self.beats(over: 300) { _ in 60 }, following: .coherent) == nil)
        #expect(Coherence.correlation(of: Self.beats(over: 300) { _ in 60 }, following: .none) == nil)
    }

    /// The breath curve is the one the circle draws: full after the inhale,
    /// held through a hold, empty after the exhale.
    @Test func theBreathCurveHoldsWhereThePhaseBeforeLeftIt() {
        #expect(Coherence.depth(of: .box, at: 0) == 0)
        #expect(Coherence.depth(of: .box, at: 4) == 1)
        #expect(Coherence.depth(of: .box, at: 6) == 1)
        #expect(Coherence.depth(of: .box, at: 12) == 0)
        #expect(Coherence.depth(of: .box, at: 14) == 0)
    }
}
