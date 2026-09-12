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
/// The Mac keeps the button. Its window is two columns wide and has no tab
/// bar to put anything in, so the day stays a sheet off `PlayerScreen`
/// there; this file is iOS and iPadOS only.
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
