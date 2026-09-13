import Foundation
import Testing
@testable import Entrain

struct WakeVolleyTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Oslo")!
        return calendar
    }()

    static func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        // September 2026: the 14th is a Monday.
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    static let seven = date(14, 7)
    static let weekdays: Set<Locale.Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]

    @Test func nextWithNoDaysIsTheNextOccurrenceOfTheTime() {
        #expect(WakeVolley.next(Self.seven, days: [], after: Self.date(14, 6, 30), calendar: Self.calendar) == Self.date(14, 7))
        #expect(WakeVolley.next(Self.seven, days: [], after: Self.date(14, 7, 30), calendar: Self.calendar) == Self.date(15, 7))
    }

    @Test func nextSkipsToAPickedDay() {
        // Friday evening: the next weekday ring is Monday.
        let friday = Self.date(18, 20)
        #expect(WakeVolley.next(Self.seven, days: Self.weekdays, after: friday, calendar: Self.calendar) == Self.date(21, 7))
        #expect(WakeVolley.next(Self.seven, days: [.sunday], after: Self.date(14, 8), calendar: Self.calendar) == Self.date(20, 7))
    }

    @Test func lastIsTheMostRecentRingIncludingNow() {
        #expect(WakeVolley.last(Self.seven, days: Self.weekdays, before: Self.date(14, 7), calendar: Self.calendar) == Self.date(14, 7))
        #expect(WakeVolley.last(Self.seven, days: Self.weekdays, before: Self.date(14, 6, 59), calendar: Self.calendar) == Self.date(11, 7))
        #expect(WakeVolley.last(Self.seven, days: [], before: Self.date(14, 6, 59), calendar: Self.calendar) == Self.date(13, 7))
    }

    @Test func followersAreTwoMinutesApartForTwentyMinutes() {
        let followers = WakeVolley.followers(after: Self.seven)
        #expect(followers.count == WakeVolley.count - 1)
        #expect(followers.first == Self.date(14, 7, 2))
        #expect(followers.last == Self.date(14, 7, 18))
        #expect(WakeVolley.window == 1200)
    }

    @Test func liveOnlyInsideTheWindowAfterAFirstRing() {
        #expect(WakeVolley.liveStart(Self.seven, days: Self.weekdays, at: Self.date(14, 6, 59), calendar: Self.calendar) == nil)
        #expect(WakeVolley.liveStart(Self.seven, days: Self.weekdays, at: Self.date(14, 7), calendar: Self.calendar) == Self.date(14, 7))
        #expect(WakeVolley.liveStart(Self.seven, days: Self.weekdays, at: Self.date(14, 7, 19), calendar: Self.calendar) == Self.date(14, 7))
        #expect(WakeVolley.liveStart(Self.seven, days: Self.weekdays, at: Self.date(14, 7, 20), calendar: Self.calendar) == nil)
        // Saturday is not a picked day, so Friday's ring is long over.
        #expect(WakeVolley.liveStart(Self.seven, days: Self.weekdays, at: Self.date(19, 7, 5), calendar: Self.calendar) == nil)
    }

    @Test func weekdayNumbersMatchTheCalendar() {
        #expect(Locale.Weekday.sunday.number == 1)
        #expect(Locale.Weekday.saturday.number == 7)
    }
}
