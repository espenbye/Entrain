import Foundation
import Testing
@testable import Entrain

/// The suggested mode over a clock day, 7 to 19.
struct SuggestionTests {
    static func at(_ hour: Int) -> Mode {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Oslo")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: hour))!
        return Suggestion.at(date) { SolarDay.clock(on: $0, calendar: calendar) }.mode
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
}
