import Foundation
import Testing
@testable import Entrain

/// The practice reduction: which modes breathe, which ones Health has a
/// place for, and what the screen makes of the samples it gets back.
struct PracticeTests {
    /// A calendar that does not depend on where the test runs.
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    static let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 19, hour: 14))!
    static var midnight: Date { calendar.startOfDay(for: now) }

    /// A sitting `days` days back, starting at `hour`, lasting `minutes`.
    static func sitting(days: Int = 0, hour: Double, minutes: Double) -> DateInterval {
        let day = calendar.date(byAdding: .day, value: -days, to: midnight)!
        return DateInterval(start: day.addingTimeInterval(hour * 3600), duration: minutes * 60)
    }

    /// The rest shelf breathes and nothing else does; Health takes Meditate
    /// and Restore and not Relax, which is unwinding rather than practice.
    @Test func theRestShelfBreathesAndTwoOfItAreMindful() {
        #expect(Mode.allCases.filter(\.guidesBreath) == [.relax, .meditate, .restore])
        #expect(Mode.allCases.filter(\.isMindful) == [.meditate, .restore])
        #expect(Mode.allCases.allSatisfy { !$0.guidesBreath || $0.purpose == .rest })
        // Everything Health logs is something a breath may be paced over,
        // so the practice screen's two halves can never disagree.
        #expect(Mode.allCases.allSatisfy { !$0.isMindful || $0.guidesBreath })
        #expect(!Mode.focus.guidesBreath)
        #expect(!Mode.sleep.guidesBreath)
        #expect(!Mode.relax.isMindful)
    }

    @Test func historyCountsTodayAndTheLastSevenDays() {
        // Newest first, which is the order the reduction should arrive at
        // whatever order it is given them in.
        let sittings = [
            Self.sitting(hour: 13, minutes: 20),
            Self.sitting(hour: 8, minutes: 10),
            Self.sitting(days: 3, hour: 9, minutes: 15),
            Self.sitting(days: 6, hour: 9, minutes: 30),
            // A day outside the week but inside the window.
            Self.sitting(days: 7, hour: 9, minutes: 45),
            Self.sitting(days: 20, hour: 9, minutes: 5),
        ]
        let history = PracticeHistory.from(sittings, now: Self.now, calendar: Self.calendar)

        #expect(history.today == 30 * 60)
        #expect(history.lastWeek == 75 * 60)
        #expect(history.count == 6)
        #expect(!history.isEmpty)
        // Newest first, whatever order Health handed them over in.
        #expect(history.sessions.map(\.start) == sittings.map(\.start))
        let shuffled = PracticeHistory.from(Array(sittings.reversed()), now: Self.now, calendar: Self.calendar)
        #expect(shuffled == history)
    }

    /// A sitting that runs past midnight is still that evening's, and is
    /// counted whole against the day it began on rather than split in two.
    @Test func aSittingCountsAgainstTheDayItBeganOn() {
        let overnight = Self.sitting(days: 1, hour: 23, minutes: 120)
        #expect(overnight.end > Self.midnight)
        let history = PracticeHistory.from([overnight], now: Self.now, calendar: Self.calendar)
        #expect(history.today == 0)
        #expect(history.lastWeek == 120 * 60)
        #expect(history.count == 1)
    }

    /// The window can hold more sittings than the screen draws; the figures
    /// still count all of them.
    @Test func theListIsCappedAndTheTotalsAreNot() {
        let many = (0..<15).map { Self.sitting(days: $0, hour: 9, minutes: 10) }
        let history = PracticeHistory.from(many, now: Self.now, calendar: Self.calendar)
        #expect(history.sessions.count == PracticeHistory.shown)
        #expect(history.count == 15)
        #expect(history.sessions.first?.start == many.first?.start)
        #expect(history.lastWeek == 70 * 60)
        #expect(history.today == 10 * 60)
    }

    @Test func nothingReducesToEmpty() {
        let history = PracticeHistory.from([], now: Self.now, calendar: Self.calendar)
        #expect(history == .empty)
        #expect(history.isEmpty)
        #expect(PracticeHistory.empty.today == 0)
    }

    /// Minutes are truncated, not rounded: a sitting is credited with the
    /// minutes it actually ran, which is what Health does with its own.
    @Test func spansReadAsMinutesAndGrowPastAnHour() {
        #expect(TimeInterval(59).practiceMinutes == TimeInterval(0).practiceMinutes)
        #expect(TimeInterval(119).practiceMinutes == TimeInterval(60).practiceMinutes)
        #expect(TimeInterval(3540).practiceMinutes != TimeInterval(3600).practiceMinutes)
        #expect(!TimeInterval(1500).practiceMinutes.isEmpty)
    }
}

/// `Session.practice` against a log the test holds.
@MainActor
struct SessionPracticeTests {
    let defaults: UserDefaults
    let widgetDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let audio = SessionTests.FakeAudio()

    init() {
        let suite = "entrain.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.createDirectory(at: widgetDirectory, withIntermediateDirectories: true)
    }

    /// Fixed so the reduction lands on the same day wherever and whenever
    /// the test runs.
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    func makeSession(mindful: (any MindfulLog)?) -> Session {
        Session(
            defaults: defaults, widgetDirectory: widgetDirectory, mindful: mindful,
            clock: { Self.now }
        ) { [audio] _ in audio }
    }

    @Test func practiceReducesWhatTheLogHandsBack() async {
        let mindful = SessionTests.FakeMindful()
        let session = makeSession(mindful: mindful)

        #expect(await session.practice().isEmpty)
        #expect(mindful.asked == PracticeHistory.window)

        let midnight = Calendar.current.startOfDay(for: Self.now)
        mindful.stored = [
            DateInterval(start: midnight.addingTimeInterval(3600), duration: 600),
            DateInterval(start: midnight.addingTimeInterval(-2 * 86400), duration: 900),
        ]
        let history = await session.practice()
        #expect(history.count == 2)
        #expect(history.today == 600)
        #expect(history.lastWeek == 1500)
    }

    /// No log at all, which is the Mac: the screen gets an empty history
    /// rather than a reason to hide itself.
    @Test func aSessionWithNoLogHasNoPractice() async {
        #expect(await makeSession(mindful: nil).practice() == .empty)
    }

    /// Restore joins Meditate on the mindful chart; the other rest mode
    /// does not, and neither does anything off the shelf.
    @Test func restoreSegmentsReachTheMindfulLog() async {
        let mindful = SessionTests.FakeMindful()
        let session = makeSession(mindful: mindful)
        session.mode = .restore
        await session.play()
        #expect(mindful.prepared == 1)
        session.pause()
        #expect(mindful.segments.count == 1)

        await session.play()
        #expect(mindful.prepared == 2)
        // Relax breathes but is not a practice, so the segment closes here
        // and no new one opens.
        session.mode = .relax
        #expect(mindful.segments.count == 2)
        #expect(mindful.prepared == 2)
        session.pause()
        #expect(mindful.segments.count == 2)
    }
}
