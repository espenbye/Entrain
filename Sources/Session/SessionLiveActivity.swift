#if os(iOS)
import ActivityKit
import Foundation

/// Drives the session's Live Activity. The session tells it about every
/// state change; a timed session that is playing has an activity, a paused
/// one keeps it frozen, and anything else ends it.
@MainActor
final class SessionLiveActivity {
    private var activity: Activity<SessionActivityAttributes>?
    private var state: SessionActivityAttributes.ContentState?
    /// ActivityKit calls are async; chaining them keeps an update from
    /// landing after the end that should follow it.
    private var work: Task<Void, Never>?

    init() {
        // Left over from a launch that was killed mid-session: nothing owns them.
        for activity in Activity<SessionActivityAttributes>.activities {
            end(activity)
        }
    }

    func update(_ state: SessionActivityAttributes.ContentState?) {
        guard let state else { return end() }
        let content = ActivityContent(state: state, staleDate: state.deadline)
        if let activity {
            guard state != self.state else { return }
            // `Activity` is not Sendable, but its calls only hop off the
            // actor for their own duration and nothing else touches it.
            nonisolated(unsafe) let activity = activity
            enqueue { await activity.update(content) }
        } else {
            // Only a playing session opens one; a pause has nothing live to show.
            guard state.isPlaying else { return }
            activity = try? Activity.request(attributes: SessionActivityAttributes(), content: content)
        }
        self.state = state
    }

    /// The timer ran out or the session left the activity behind.
    func end() {
        guard let activity else { return }
        self.activity = nil
        state = nil
        end(activity)
    }

    private func end(_ activity: Activity<SessionActivityAttributes>) {
        nonisolated(unsafe) let activity = activity
        enqueue { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = work
        work = Task { @MainActor in
            await previous?.value
            await operation()
        }
    }
}
#endif
