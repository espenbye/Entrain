import Foundation

/// A running timed session on the Lock Screen and in the Dynamic Island.
/// Shared with the widget, which draws the Live Activity from it. One
/// activity lasts a whole timed session; everything it shows is state, so
/// a new mode or sound updates it in place. Endless sessions have nothing
/// to count down, so they get none.
struct SessionActivityAttributes: Codable, Hashable, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        var mode: Mode
        /// The soundscape, "Rain + Pad".
        var sound: String
        /// When the session ends. While paused, where it would end had it
        /// kept playing from `pausedAt`, so the frozen countdown reads right.
        var deadline: Date
        /// Set while paused. The view freezes its timer at this instant.
        var pausedAt: Date?

        var isPlaying: Bool { pausedAt == nil }

        /// What the activity should show for a session state, or nil for a
        /// session with no timer. `now` is the instant a pause is frozen at.
        static func snapshot(
            mode: Mode, sound: String, isPlaying: Bool, remaining: Int?, deadline: Date?, now: Date = .now
        ) -> ContentState? {
            guard let remaining else { return nil }
            if isPlaying, let deadline {
                return ContentState(mode: mode, sound: sound, deadline: deadline, pausedAt: nil)
            }
            return ContentState(mode: mode, sound: sound, deadline: now.addingTimeInterval(Double(remaining)), pausedAt: now)
        }
    }
}

#if os(iOS)
import ActivityKit

extension SessionActivityAttributes: ActivityAttributes {}
#endif
