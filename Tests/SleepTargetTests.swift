import Foundation
import Testing
@testable import Entrain

/// The one prescriptive thing in the app. These check the two claims it
/// makes: that a night moves no faster than `SleepEdges.step`, and that
/// following it is what advances the walk — there is no stored progress to
/// get out of step with reality.
struct SleepTargetTests {
    static let owl = SleepSignature(bedtime: 1 * 3600, wake: 9 * 3600, latency: 15 * 60, spread: 900, nights: 10)
    static let target = SleepTarget(wake: 7 * 3600, hours: 8 * 3600, isOn: true)

    @Test func bedtimeFollowsFromWakeAndLength() {
        #expect(Self.target.bedtime == 23 * 3600)
        #expect(SleepTarget(wake: 6 * 3600, hours: 8 * 3600, isOn: true).bedtime == 22 * 3600)
        // Past midnight, so it wraps rather than going negative.
        #expect(SleepTarget(wake: 9 * 3600, hours: 7 * 3600, isOn: true).bedtime == 2 * 3600)
    }

    @Test func theOfferedLengthsStayInsideTheAdultRange() {
        #expect(SleepTarget.lengths.first == 6.0 * 3600)
        #expect(SleepTarget.lengths.last == 10.0 * 3600)
    }

    @Test func offTheTargetIsNotConsulted() throws {
        var off = Self.target
        off.isOn = false
        let edges = try #require(SleepEdges.tonight(target: off, measured: Self.owl))
        #expect(edges.source == .habit)
        #expect(edges.bedtime == Self.owl.bedtime)
        #expect(edges.hasArrived)
    }

    @Test func withNothingMeasuredTheTargetAppliesAtOnce() throws {
        let edges = try #require(SleepEdges.tonight(target: Self.target, measured: nil))
        #expect(edges.source == .target)
        #expect(edges.bedtime == Self.target.bedtime)
        #expect(edges.wake == Self.target.wake)
        #expect(edges.hasArrived)
    }

    /// Scattered nights are no habit to ease out of, and are exactly who a
    /// target is for.
    @Test func aScatteredSleeperGetsTheTargetStraightAway() throws {
        let scattered = SleepSignature(bedtime: 1 * 3600, wake: 9 * 3600, latency: nil, spread: 5 * 3600, nights: 10)
        let edges = try #require(SleepEdges.tonight(target: Self.target, measured: scattered))
        #expect(edges.bedtime == Self.target.bedtime)
    }

    @Test func neitherTargetNorHabitLeavesTheSunToIt() {
        #expect(SleepEdges.tonight(target: nil, measured: nil) == nil)
        let scattered = SleepSignature(bedtime: 1 * 3600, wake: 9 * 3600, latency: nil, spread: 5 * 3600, nights: 10)
        #expect(SleepEdges.tonight(target: nil, measured: scattered) == nil)
    }

    /// One o'clock is two hours from the target. Tonight asks for twenty
    /// minutes of it and nothing more.
    @Test func aNightMovesOneStepAtATime() throws {
        let edges = try #require(SleepEdges.tonight(target: Self.target, measured: Self.owl))
        #expect(edges.bedtime == 1 * 3600 - SleepEdges.step)
        #expect(edges.wake == 9 * 3600 - SleepEdges.step)
        #expect(edges.source == .target)
        #expect(!edges.hasArrived)
    }

    /// Keeping the step is what moves the average, which is what moves the
    /// next step. No counter, no drift between a stored plan and real nights.
    @Test func keepingTheStepAdvancesTheWalk() throws {
        var habit = Self.owl
        for _ in 0..<3 {
            let edges = try #require(SleepEdges.tonight(target: Self.target, measured: habit))
            habit.bedtime = edges.bedtime
            habit.wake = edges.wake
        }
        #expect(habit.bedtime == 1 * 3600 - 3 * SleepEdges.step)
        // Not following it leaves the average where it was, and the next
        // night asks for the same twenty minutes again rather than forty.
        let stalled = try #require(SleepEdges.tonight(target: Self.target, measured: Self.owl))
        #expect(stalled.bedtime == 1 * 3600 - SleepEdges.step)
    }

    /// The last step is a short one, and arriving is stated rather than
    /// overshot.
    @Test func theWalkStopsOnTheTarget() throws {
        let close = SleepSignature(bedtime: 23 * 3600 + 10 * 60, wake: 7 * 3600 + 10 * 60, latency: nil, spread: 900, nights: 10)
        let edges = try #require(SleepEdges.tonight(target: Self.target, measured: close))
        #expect(edges.bedtime == Self.target.bedtime)
        #expect(edges.wake == Self.target.wake)
        #expect(edges.hasArrived)
    }

    /// An early bird asked for a later night walks the other way.
    @Test func theStepIsSignedAndTakesTheShortWayRound() throws {
        let lark = SleepSignature(bedtime: 21 * 3600, wake: 5 * 3600, latency: nil, spread: 900, nights: 10)
        let edges = try #require(SleepEdges.tonight(target: Self.target, measured: lark))
        #expect(edges.bedtime == 21 * 3600 + SleepEdges.step)
        #expect(edges.wake == 5 * 3600 + SleepEdges.step)
    }

    /// Half past eleven is twenty minutes before ten to twelve, not
    /// twenty-three hours and forty minutes after it.
    @Test func theOffsetCrossesMidnightTheShortWay() {
        #expect(SleepEdges.offset(from: 23.5 * 3600, to: 23 * 3600 + 50 * 60) == 20 * 60)
        #expect(SleepEdges.offset(from: 0.5 * 3600, to: 23.5 * 3600) == -3600)
        #expect(SleepEdges.offset(from: 23.5 * 3600, to: 0.5 * 3600) == 3600)
    }

    /// A bedtime in the small hours belongs to the night the day opens, so
    /// it falls on the next date — the same convention `SolarDay.sunset`
    /// stands in for.
    @Test func theEveningEdgeLandsOnTheRightDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Oslo"))
        let noon = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12)))
        let late = SleepEdges(bedtime: 1 * 3600, wake: 9 * 3600, source: .habit, hasArrived: true)
        #expect(late.evening(on: noon, calendar: calendar) > noon)
        #expect(calendar.component(.day, from: late.evening(on: noon, calendar: calendar)) == 11)
        #expect(calendar.component(.day, from: late.morning(on: noon, calendar: calendar)) == 10)
    }
}
