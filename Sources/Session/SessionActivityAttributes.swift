import Foundation

/// A running timed session on the Lock Screen and in the Dynamic Island.
/// Shared with the widget, which draws the Live Activity from it. The mode
/// and sound are fixed for the activity's life: switching either starts a
/// new one. Endless sessions have nothing to count down, so they get none.
struct SessionActivityAttributes: Codable, Hashable, Sendable {
    var mode: Mode
    /// The soundscape, "Rain + Pad".
    var sound: String

    struct ContentState: Codable, Hashable, Sendable {
        /// When the session ends. While paused, where it would end had it
        /// kept playing from `pausedAt`, so the frozen countdown reads right.
        var deadline: Date
        /// Set while paused. The view freezes its timer at this instant.
        var pausedAt: Date?

        var isPlaying: Bool { pausedAt == nil }
    }

    /// What the activity should show for a session state, or nil for a
    /// session with no timer. `now` is the instant a pause is frozen at.
    static func snapshot(
        mode: Mode, sound: String, isPlaying: Bool, remaining: Int?, deadline: Date?, now: Date = .now
    ) -> (attributes: SessionActivityAttributes, state: ContentState)? {
        guard let remaining else { return nil }
        let attributes = SessionActivityAttributes(mode: mode, sound: sound)
        if isPlaying, let deadline {
            return (attributes, ContentState(deadline: deadline, pausedAt: nil))
        }
        return (attributes, ContentState(deadline: now.addingTimeInterval(Double(remaining)), pausedAt: now))
    }
}

#if os(iOS)
import ActivityKit

extension SessionActivityAttributes: ActivityAttributes {}
#endif
