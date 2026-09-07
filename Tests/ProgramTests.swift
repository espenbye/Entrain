import Foundation
import Testing
@testable import Entrain

/// The day walked on its own: what the program plays, what it refuses to
/// play, and the hertz walk it uses to get from one to the next.
struct ProgramTests {
    static var calendar: Calendar { SuggestionTests.calendar }

    static func plan(_ hour: Int, _ minute: Int = 0, sleep: SleepSignature? = nil) -> Program.Plan {
        Program.at(
            SuggestionTests.date(hour, minute), day: { SolarDay.clock(on: $0, calendar: calendar) },
            sleep: sleep, calendar: calendar
        )
    }

    /// The program is the suggestion read forward, so it plays exactly what
    /// the card would have offered.
    @Test func playsWhatTheDaySuggests() {
        #expect(Self.plan(9).mode == .focus)
        #expect(Self.plan(13).mode == .gamma)
        #expect(Self.plan(16).mode == .relax)
        #expect(Self.plan(20).mode == .windDown)
        #expect(Self.plan(5).mode == .wake)
    }

    /// It stops at Wind Down rather than putting anyone to bed, and says so.
    @Test func holdsWindDownRatherThanGoingToBed() {
        let night = Self.plan(23)
        #expect(night.mode == .windDown)
        #expect(night.next == .wake)

        // And an hour before the boundary it names the bed it will not enter.
        let evening = Self.plan(21)
        #expect(evening.mode == .windDown)
        #expect(evening.next == .sleep)
        #expect(evening.asks)
    }

    /// The next change is the real boundary, not the next sample.
    @Test func findsTheNextBoundary() {
        let morning = Self.plan(9)
        #expect(morning.next == .gamma)
        // 7 to 19 makes midday start at 40 % of the day, which is 11:48.
        #expect(morning.at == SuggestionTests.date(11, 50))

        let midday = Self.plan(13)
        #expect(midday.next == .relax)
        #expect(midday.at == SuggestionTests.date(14, 15))
    }

    /// A settled bedtime moves the program's boundaries with the suggestion's.
    @Test func followsAHabitualBedtime() {
        #expect(Self.plan(20, sleep: SuggestionTests.owl).mode == .relax)
        #expect(Self.plan(23, sleep: SuggestionTests.owl).mode == .windDown)
        #expect(Self.plan(3, sleep: SuggestionTests.owl).mode == .windDown)
        #expect(Self.plan(3, sleep: SuggestionTests.owl).next == .wake)
    }

    /// The transition is a walk in hertz, not a step: it leaves on the rate
    /// the outgoing mode was playing and arrives on the incoming mode's.
    @Test func theRateWalksBetweenModes() {
        let glide = RateGlide(from: 16)
        #expect(glide.rate(to: 10, elapsed: 0) == 16)
        #expect(glide.rate(to: 10, elapsed: RateGlide.seconds / 2) == 13)
        #expect(glide.rate(to: 10, elapsed: RateGlide.seconds) == 10)
        #expect(glide.isOver(elapsed: RateGlide.seconds))
        #expect(!glide.isOver(elapsed: RateGlide.seconds - 1))
    }
}
