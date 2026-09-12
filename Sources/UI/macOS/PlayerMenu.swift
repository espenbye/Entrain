import SwiftUI

/// The menu bar menu. Every child is a real menu item, so the look is macOS's own.
struct PlayerMenu: View {
    @Bindable var session: Session
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        PlayerControls(session: session)
        Divider()
        Button("Open Entrain…") {
            openWindow(id: PlayerScreen.windowID)
            NSApplication.shared.activate()
        }
        .keyboardShortcut("o")
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Divider()
        Button("Quit Entrain") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// What the menu bar shows: the waveform, plus the mode and countdown while playing.
/// Laid out by hand: a `Label` in a status item renders icon-only. The symbol
/// does not animate: a status item redrawing all day is a battery cost for
/// an app meant to sit in the background.
struct MenuBarLabel: View {
    let isPlaying: Bool
    let mode: Mode
    let deadline: Date?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "waveform")
            if isPlaying {
                if let deadline {
                    Text("\(mode.title) \(Text(timerInterval: Date.now...max(Date.now, deadline), countsDown: true))")
                        .monospacedDigit()
                } else {
                    Text(mode.title)
                }
            }
        }
    }
}

/// Transport, mode and timer as menu items, for the menu bar menu. The
/// rest is a click away in the window or Settings.
struct PlayerControls: View {
    @Bindable var session: Session

    var body: some View {
        TransportSection(
            isPlaying: session.isPlaying,
            title: session.title,
            countdown: session.countdown,
            error: session.error,
            toggle: session.toggle
        )
        ModeSection(session: session)
        Section {
            Picker("Timer", selection: $session.length) {
                ForEach(SessionLength.allCases) { Text($0.title).tag($0) }
            }
            if session.mode == .meditate {
                BreathingPickers(session: session)
            }
        }
    }
}
