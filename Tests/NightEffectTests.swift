import Foundation
import Testing
@testable import Entrain

/// The night comparison, against synthetic nights and a synthetic log.
/// Pure arithmetic on intervals, like the rest of the Health reductions: no
/// store, no permission, and the same answer on a Mac with no HealthKit.
struct NightEffectTests {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Oslo")!
        return calendar
    }

    /// Well clear of the spring clock change, so a day is always 24 hours.
    static let base = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!

    static func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(byAdding: DateComponents(day: day, hour: hour, minute: minute), to: base)!
    }

    /// A night beginning at 23:00 on `day`, lasting `hours` from falling
    /// asleep to waking with `asleep` of it actually asleep.
    static func night(_ day: Int, at hour: Int = 23, minute: Int = 0, hours: Double = 8, asleep: Double = 7) -> SleepNight {
        let start = Self.at(day, hour, minute)
        return SleepNight(
            night: SleepNight.key(for: start, calendar: calendar),
            interval: DateInterval(start: start, duration: hours * 3600),
            asleep: asleep * 3600,
            latency: nil
        )
    }

    static func session(_ mode: Mode, _ day: Int, _ hour: Int, _ minute: Int = 0, hours: Double = 8) -> PlayedSession {
        PlayedSession(mode, DateInterval(start: Self.at(day, hour, minute), duration: hours * 3600))
    }

    static func minutes(_ seconds: TimeInterval?) -> Int? { seconds.map { Int(($0 / 60).rounded()) } }

    // MARK: Splitting the nights

    /// Seven nights with a bed under them against seven without, and each
    /// measure is the median of its own group.
    @Test func splitsNightsByWhetherASoundReachedThem() {
        let nights = (0..<7).map { Self.night($0, asleep: 7.5) } + (7..<14).map { Self.night($0, asleep: 7) }
        let sessions = (0..<7).map { Self.session(.sleep, $0, 22, 30) }
        let effect = NightEffect.from(nights: nights, sessions: sessions, calendar: Self.calendar)

        #expect(effect.nights == 14)
        let asleep = effect.comparisons.first { $0.measure == .asleep }
        #expect(asleep?.soundNights == 7)
        #expect(asleep?.quietNights == 7)
        #expect(Self.minutes(asleep?.withSound) == 7 * 60 + 30)
        #expect(Self.minutes(asleep?.without) == 7 * 60)
        // Awake is the span minus the sleep in it, so the quieter nights,
        // which slept half an hour less of the same eight, read half an
        // hour higher.
        let awake = effect.comparisons.first { $0.measure == .awake }
        #expect(Self.minutes(awake?.withSound) == 30)
        #expect(Self.minutes(awake?.without) == 60)
    }

    /// Wind Down is sound put on for the night that follows it, so the
    /// night it runs into is a night with sound even though the bed itself
    /// never played.
    @Test func windDownCountsForTheNightItRunsInto() {
        let nights = (0..<14).map { Self.night($0) }
        let sessions = (0..<7).map { Self.session(.windDown, $0, 21, hours: 1) }
        let effect = NightEffect.from(nights: nights, sessions: sessions, calendar: Self.calendar)
        #expect(effect.comparisons.first?.soundNights == 7)
        #expect(effect.comparisons.first?.quietNights == 7)
    }

    /// A Relax at nine in the evening is not a night's sound, and the night
    /// after it is a quiet one. Nothing is in the log but the modes that
    /// run into a night, so this is really the guard in `startSleepLog`, but a
    /// log written by an older build could still hold one.
    @Test func daytimeModesDoNotMakeANightASoundNight() {
        let nights = (0..<14).map { Self.night($0) }
        let sessions = [Self.session(.sleep, 0, 22, 30)] + (1..<14).map { Self.session(.relax, $0, 21, hours: 1) }
        let effect = NightEffect.from(nights: nights, sessions: sessions, calendar: Self.calendar)
        // One sound night is under the floor, so there is nothing to
        // compare; what matters is that the thirteen Relax nights did not
        // become sound nights.
        #expect(effect.comparisons.isEmpty)
        #expect(effect.nights == 14)
    }

    /// A night earlier than the oldest session on file is a night this
    /// device cannot speak for. It is dropped rather than counted as quiet,
    /// which would otherwise fill the quiet group with every night from
    /// before the app was installed.
    @Test func nightsBeforeTheLogAreNotCountedAsQuiet() {
        let nights = (0..<14).map { Self.night($0) }
        let sessions = (5..<12).map { Self.session(.sleep, $0, 22, 30) }
        let effect = NightEffect.from(nights: nights, sessions: sessions, calendar: Self.calendar)
        #expect(effect.nights == 9)
        #expect(effect.comparisons.isEmpty)
    }

    /// Nothing in the log means nothing can be said, which is the state
    /// every install is in on its first evening.
    @Test func anEmptyLogSaysNothing() {
        let effect = NightEffect.from(nights: (0..<14).map { Self.night($0) }, sessions: [], calendar: Self.calendar)
        #expect(effect == .empty)
        #expect(effect.isEmpty)
    }

    /// Too few of either kind and no comparison is published at all: six
    /// nights against eight is not a comparison, it is two anecdotes.
    @Test func tooFewNightsOfEitherKindPublishNothing() {
        let nights = (0..<14).map { Self.night($0) }
        let sessions = (0..<6).map { Self.session(.sleep, $0, 22, 30) }
        let effect = NightEffect.from(nights: nights, sessions: sessions, calendar: Self.calendar)
        #expect(effect.comparisons.isEmpty)
        #expect(effect.nights == 14)
    }

    // MARK: The onset

    /// The figure Health cannot produce: from the bed starting to the first
    /// sleep recorded.
    @Test func onsetRunsFromTheBedToTheFirstSleep() {
        let nights = (0..<7).map { Self.night($0, at: 23, minute: 20) }
        let sessions = (0..<7).map { Self.session(.sleep, $0, 23) }
        let effect = NightEffect.from(nights: nights, sessions: sessions, calendar: Self.calendar)
        #expect(Self.minutes(effect.onset) == 20)
        #expect(effect.onsetNights == 7)
    }

    /// Wind Down running straight into the bed is one unbroken sound, and
    /// for grouping nights it is. The onset still starts at the bed: an
    /// hour of easing toward sleep is not an hour of failing to fall
    /// asleep, and counting it would report every evening as ninety
    /// minutes of latency.
    @Test func onsetIgnoresTheWindDownBeforeTheBed() {
        let nights = (0..<7).map { Self.night($0, at: 23, minute: 20) }
        let sessions = (0..<7).flatMap {
            [Self.session(.windDown, $0, 22, hours: 1), Self.session(.deepSleep, $0, 23)]
        }
        let effect = NightEffect.from(nights: nights, sessions: sessions, calendar: Self.calendar)
        #expect(Self.minutes(effect.onset) == 20)
    }

    /// A bed put on early, switched off, and put on again at bedtime is two
    /// stretches, and sleep came after the second one.
    @Test func onsetTakesTheLastBedBeforeSleep() {
        let nights = (0..<7).map { Self.night($0, at: 23, minute: 20) }
        let sessions = (0..<7).flatMap {
            [Self.session(.sleep, $0, 20, hours: 1), Self.session(.sleep, $0, 23)]
        }
        let effect = NightEffect.from(nights: nights, sessions: sessions, calendar: Self.calendar)
        #expect(Self.minutes(effect.onset) == 20)
    }

    /// A bed started hours before sleep is not this night's onset. Past the
    /// lead there is no measurement to make, so the night has no onset and
    /// the median is taken over the rest.
    @Test func onsetIgnoresABedStartedTooLongBefore() {
        let nights = (0..<8).map { Self.night($0, at: 23) }
        var sessions = (0..<7).map { Self.session(.sleep, $0, 22, 45) }
        // Long enough to reach the eighth night, which is therefore a night
        // with sound, and started far enough before it to have no onset.
        sessions.append(Self.session(.sleep, 7, 19, 30, hours: 4))
        let effect = NightEffect.from(nights: nights, sessions: sessions, calendar: Self.calendar)
        #expect(Self.minutes(effect.onset) == 15)
        #expect(effect.onsetNights == 7)
    }

    /// Below the floor there is no median worth taking.
    @Test func tooFewOnsetsPublishNothing() {
        let nights = (0..<6).map { Self.night($0, at: 23, minute: 20) }
        let sessions = (0..<6).map { Self.session(.sleep, $0, 23) }
        let effect = NightEffect.from(nights: nights, sessions: sessions, calendar: Self.calendar)
        #expect(effect.onset == nil)
        #expect(effect.onsetNights == 6)
    }

    // MARK: Resting heart rate

    /// A night takes the resting heart rate of the day it ended in: the
    /// figure is the morning's reading of the night before it.
    @Test func restingHeartRateComesFromTheMorningAfter() {
        let nights = (0..<14).map { Self.night($0) }
        let sessions = (0..<7).map { Self.session(.sleep, $0, 22, 30) }
        // The night beginning on day n ends on the morning of day n + 1.
        let daily = (1...14).map { DailyValue(day: Self.at($0, 0), value: $0 <= 7 ? 54 : 56) }
        let effect = NightEffect.from(
            nights: nights, sessions: sessions, restingHeartRate: daily, calendar: Self.calendar
        )
        let rate = effect.comparisons.first { $0.measure == .restingHeartRate }
        #expect(rate?.withSound == 54)
        #expect(rate?.without == 56)
        #expect(rate?.soundNights == 7)
    }

    /// Days Health had no figure for are absent, not zero, and a measure
    /// left with too few of them drops out while the others stay.
    @Test func aThinRestingHeartRateSeriesDropsOutAlone() {
        let nights = (0..<14).map { Self.night($0) }
        let sessions = (0..<7).map { Self.session(.sleep, $0, 22, 30) }
        let daily = (1...4).map { DailyValue(day: Self.at($0, 0), value: 54) }
        let effect = NightEffect.from(
            nights: nights, sessions: sessions, restingHeartRate: daily, calendar: Self.calendar
        )
        #expect(effect.comparisons.map(\.measure) == [.asleep, .awake])
    }

    // MARK: The pieces

    /// A mode change ends one session and opens the next in the same
    /// second, and to the listener that is one unbroken sound.
    @Test func stretchesJoinAcrossAModeChange() {
        let stretches = NightEffect.stretches(of: [
            Self.session(.windDown, 0, 21, hours: 1),
            Self.session(.sleep, 0, 22, hours: 2),
            Self.session(.sleep, 1, 22, hours: 2),
        ])
        #expect(stretches.count == 2)
        #expect(stretches[0] == DateInterval(start: Self.at(0, 21), end: Self.at(1, 0)))
    }

    /// Time awake is the span minus the sleep inside it.
    @Test func awakeIsTheSpanMinusTheSleep() {
        #expect(Self.minutes(Self.night(0, hours: 8, asleep: 7).awake) == 60)
    }

    /// An even count takes the middle two, so seven nights and eight
    /// nights are both a median rather than one of them being a mean.
    @Test func medianOfAnEvenCountIsTheMiddleTwo() {
        #expect(NightEffect.median([1, 2, 3, 4]) == 2.5)
        #expect(NightEffect.median([3, 1, 2]) == 2)
        #expect(NightEffect.median([]) == nil)
    }
}

/// The log the comparison reads, which is the only record anything has that
/// a bed ever played.
struct SessionLogTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func session(_ mode: Mode, daysAgo: Double, hours: Double = 8) -> PlayedSession {
        PlayedSession(mode, DateInterval(start: now.addingTimeInterval(-daysAgo * 86400), duration: hours * 3600))
    }

    /// Wind Down and the two beds, and nothing else. Nothing here asks what
    /// was playing at the desk, and a nap is not a night.
    @Test func onlyTheModesThatRunIntoANightAreKept() {
        #expect(Mode.allCases.filter(\.runsIntoTheNight) == [.sleep, .deepSleep, .windDown])
    }

    /// A bed switched off inside five minutes was a try, not a night.
    @Test func dropsAStretchTooShortToBeANight() {
        let log = SessionLog.appending(
            Self.session(.sleep, daysAgo: 0, hours: 1.0 / 60), to: [], now: Self.now
        )
        #expect(log.isEmpty)
    }

    /// Past the window an entry goes, and the entries are kept oldest first
    /// so the first of them is the day the log can speak from.
    @Test func prunesPastTheWindowAndKeepsTheRestInOrder() {
        let old = Self.session(.sleep, daysAgo: 120)
        let recent = Self.session(.sleep, daysAgo: 3)
        let newest = Self.session(.deepSleep, daysAgo: 1)
        let log = SessionLog.appending(newest, to: [old, recent], now: Self.now)
        #expect(log == [recent, newest])
    }

    /// The log outlives its window by a month on purpose: the comparison
    /// looks back two, and the entry that bounds it has to still be there.
    @Test func theLogOutlivesTheComparisonWindow() {
        #expect(SessionLog.window > NightEffect.window)
    }
}
