import SwiftUI

/// The menu bar menu. Every child is a real menu item, so the look is macOS's own.
struct PlayerMenu: View {
    @Bindable var session: Session
    @Environment(\.openWindow) private var openWindow
    @AppStorage(DockIcon.key) private var showInDock = false

    var body: some View {
        PlayerControls(session: session)
        Divider()
        Button("Open Entrain…") {
            openWindow(id: PlayerWindow.id)
            NSApplication.shared.activate()
        }
        .keyboardShortcut("o")
        Toggle("Show in Dock", isOn: Binding(
            get: { showInDock },
            set: { showInDock = $0; DockIcon.apply($0) }
        ))
        Divider()
        Button("Quit Entrain") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// The same controls in a regular window, for people who want Entrain on screen.
struct PlayerWindow: View {
    static let id = "player"
    @Bindable var session: Session

    var body: some View {
        Form {
            PlayerControls(session: session)
        }
        .formStyle(.grouped)
    }
}

/// Transport, mode and settings. Renders as menu items inside a menu and as
/// grouped rows inside a Form, so the menu and the window share one source.
struct PlayerControls: View {
    @Bindable var session: Session

    var body: some View {
        TransportSection(
            isPlaying: session.isPlaying,
            mode: session.mode,
            soundscape: session.soundscape,
            remaining: session.remaining,
            toggle: session.toggle
        )
        ModeSection(selection: $session.mode)
        SettingsSection(
            soundscape: $session.soundscape,
            intensity: $session.intensity,
            length: $session.length,
            binaural: $session.binaural,
            steady: session.mode.isSteady
        )
    }
}

/// What the menu bar shows: the waveform, plus the countdown while a timed session plays.
struct MenuBarLabel: View {
    let isPlaying: Bool
    let remaining: Int?

    var body: some View {
        Label {
            if isPlaying, let remaining {
                Text(Duration.seconds(remaining), format: .time(pattern: .minuteSecond))
                    .monospacedDigit()
            }
        } icon: {
            Image(systemName: "waveform")
                .symbolEffect(.variableColor.iterative, isActive: isPlaying)
        }
    }
}

struct TransportSection: View {
    let isPlaying: Bool
    let mode: Mode
    let soundscape: Soundscape
    let remaining: Int?
    let toggle: () -> Void

    var body: some View {
        Section {
            Button(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill", action: toggle)
                .keyboardShortcut(.space, modifiers: [])
        } header: {
            StatusLine(isPlaying: isPlaying, mode: mode, soundscape: soundscape, remaining: remaining)
        }
    }
}

struct StatusLine: View {
    let isPlaying: Bool
    let mode: Mode
    let soundscape: Soundscape
    let remaining: Int?

    var body: some View {
        if let remaining {
            Text("\(mode.title) · \(soundscape.title) · \(Duration.seconds(remaining), format: .time(pattern: .minuteSecond)) left")
        } else {
            Text("\(mode.title) · \(soundscape.title)")
        }
    }
}

struct ModeSection: View {
    @Binding var selection: Mode

    var body: some View {
        Section {
            Picker("Mode", selection: $selection) {
                ForEach(Mode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.inline)
        }
    }
}

struct SettingsSection: View {
    @Binding var soundscape: Soundscape
    @Binding var intensity: Intensity
    @Binding var length: SessionLength
    @Binding var binaural: Bool
    /// Sleep is a fixed steady bed; sound and intensity have nothing to set.
    let steady: Bool

    var body: some View {
        Section {
            Picker("Sound", selection: $soundscape) {
                ForEach(Soundscape.allCases) { Text($0.title).tag($0) }
            }
            .disabled(steady)
            Picker("Intensity", selection: $intensity) {
                ForEach(Intensity.allCases) { Text($0.title).tag($0) }
            }
            .disabled(steady)
            Picker("Timer", selection: $length) {
                ForEach(SessionLength.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Binaural Beats", isOn: $binaural)
        }
    }
}
