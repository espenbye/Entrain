#if os(iOS)
import ActivityKit
import Foundation

/// Drives the session's Live Activity. The session tells it about every
/// state change; a timed session that is playing has an activity, a paused
/// one keeps it frozen, and anything else ends it. Attributes cannot change
/// once requested, so a new mode or sound ends the activity and, if the
/// session is playing, requests a fresh one.
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

    func update(_ snapshot: (attributes: SessionActivityAttributes, state: SessionActivityAttributes.ContentState)?) {
        guard let snapshot else { return end() }
        let content = ActivityContent(state: snapshot.state, staleDate: snapshot.state.deadline)
        if let activity, activity.attributes == snapshot.attributes {
            guard snapshot.state != state else { return }
            state = snapshot.state
            // `Activity` is not Sendable, but its calls only hop off the
            // actor for their own duration and nothing else touches it.
            nonisolated(unsafe) let activity = activity
            enqueue { await activity.update(content) }
        } else {
            end()
            // Only a playing session opens one; a pause under new attributes
            // has nothing live to show.
            guard snapshot.state.isPlaying else { return }
            activity = try? Activity.request(attributes: snapshot.attributes, content: content)
            state = snapshot.state
        }
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
