import SwiftUI

/// The practice on the watch: the breath to follow, the circle while it
/// runs, and the minutes Health has.
///
/// The phone and iPad get a tab and the Mac a sheet, for the reason
/// `PracticeScreen` gives: the player answers which mode, and a practice
/// starts from which breath, so the two do not belong in one list. The
/// watch has no tab bar, so it gets the same separation as a screen one row
/// down from the player.
///
/// Much smaller than `PracticeScreen`, and deliberately. There is no bed to
/// pick, because the mode is already what the player is on and switching it
/// from here would mean coming back to a different session; and there is no
/// list of sittings, because a wrist has room for the two figures and not
/// for ten rows under them.
///
/// The row into it is on the rest shelf only, as the pickers it replaces
/// were: over Focus or a sleep bed there is no breath to set, and the watch
/// list is read as settings for the mode that is on.
struct WatchPracticeView: View {
    @Bindable var session: Session
    @State private var history: PracticeHistory = .empty

    var body: some View {
        List {
            if session.breath.isActive {
                Section {
                    BreathingCircle(guide: session.breath, tint: session.mode.tint, size: 96)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }
            Section {
                BreathingPickers(session: session)
            } footer: {
                Text(session.breathing.blurb)
            }
            Section {
                if history.isEmpty {
                    Text("Nothing here yet. A Meditate or Restore session lasting a minute or more is logged to Health as mindful minutes, and shows up here.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    LabeledContent("Today", value: history.today.practiceMinutes)
                    LabeledContent("Last 7 Days", value: history.lastWeek.practiceMinutes)
                }
            } header: {
                Text("Your Practice")
            }
        }
        .navigationTitle("Practice")
        // Same shape as the phone's, and the same reason for the second
        // read: the sitting that just ended is still on its way into Health.
        .task(id: session.isPlaying) {
            history = await session.practice()
            guard !session.isPlaying else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            history = await session.practice()
        }
    }
}
