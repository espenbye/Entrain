import Foundation
import Testing
@testable import Entrain

struct PhaseNotificationTests {
    static let phases = DayPhases(
        spans: [
            .init(phase: .night, mode: .sleep, start: 0),
            .init(phase: .wake, mode: .wake, start: 5 * 3600),
            .init(phase: .morning, mode: .focus, start: 7 * 3600),
            .init(phase: .windDown, mode: .windDown, start: 20 * 3600 + 600),
            .init(phase: .night, mode: .sleep, start: 23 * 3600 + 600),
        ],
        sunrise: 6 * 3600, sunset: 20 * 3600, bedtime: nil, wake: nil
    )

    @Test func schedulesOnlyEnabledPhasesAtTheirStart() {
        let requests = PhaseNotifications.requests(for: Self.phases, enabled: [.wake, .windDown])
        #expect(requests.map(\.phase) == [.wake, .windDown])
        let starts: [TimeInterval] = [5 * 3600, 20 * 3600 + 600]
        #expect(requests.map(\.start) == starts)
        #expect(Set(requests.map(\.id)).count == 2)
    }

    @Test func midnightContinuesTheNightRatherThanStartingIt() {
        let requests = PhaseNotifications.requests(for: Self.phases, enabled: [.night])
        let starts: [TimeInterval] = [23 * 3600 + 600]
        #expect(requests.map(\.start) == starts)
    }

    @Test func nothingWhenNothingIsOn() {
        #expect(PhaseNotifications.requests(for: Self.phases, enabled: []).isEmpty)
    }
}
