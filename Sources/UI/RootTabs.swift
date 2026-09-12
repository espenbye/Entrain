import SwiftUI

/// The iPhone and iPad shell: the player, and the day behind it.
///
/// Your Day started as a button over the player, which was the wrong shape
/// for it. A corner button reads as an accessory to what is on screen — a
/// gear, an info panel — and the day is not an accessory to the player, it
/// is the other half of the app: one screen is this session, the other is
/// the twenty-four hours the session sits in. Two tabs say that; a button
/// said the day was a detail of the player.
///
/// Settings sits in the same bar for the same reason: a gear over the
/// player said settings belonged to the player, when most of them are about
/// the day and the system.
///
/// The Mac keeps the buttons. Its window is two columns wide and has no tab
/// bar to put anything in, so the day stays a sheet off `PlayerScreen` and
/// settings the Settings window; this file is iOS and iPadOS only.
struct RootTabs: View {
    @Bindable var session: Session

    var body: some View {
        TabView {
            Tab("Player", systemImage: "waveform") {
                PlayerScreen(session: session)
            }
            Tab("Day", systemImage: "clock") {
                DayScreen(session: session)
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsScreen(session: session)
            }
        }
        // The tab bar takes the mode's tint like everything else, so
        // switching mode moves the whole shell and not just the backdrop.
        .tint(session.mode.tint)
        // Both screens force dark, but the bar between them is outside
        // either, so it is set here rather than left to follow the system
        // and sit light under two dark screens.
        .preferredColorScheme(.dark)
    }
}
