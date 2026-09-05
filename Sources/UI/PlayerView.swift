import SwiftUI

/// The menu bar menu. Every child is a real menu item, so the look is macOS's own.
struct PlayerMenu: View {
    @Bindable var session: Session
    @Environment(\.openWindow) private var openWindow
    @AppStorage(DockIcon.key) private var showInDock = false
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        PlayerControls(session: session, inMenu: true)
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
        Toggle("Launch at Login", isOn: Binding(
            get: { launchAtLogin },
            set: { LaunchAtLogin.set($0); launchAtLogin = LaunchAtLogin.isEnabled }
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
            PlayerControls(session: session, inMenu: false)
        }
        .formStyle(.grouped)
    }
}

/// Transport, mode and settings. Renders as menu items inside a menu and as
/// grouped rows inside a Form, so the menu and the window share one source.
struct PlayerControls: View {
    @Bindable var session: Session
    /// Menus cannot host a slider, so volume becomes a submenu of steps there.
    let inMenu: Bool

    var body: some View {
        TransportSection(
            isPlaying: session.isPlaying,
            mode: session.mode,
            soundscape: session.soundscape,
            remaining: session.remaining,
            error: session.error,
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
        VolumeSection(volume: $session.volume, inMenu: inMenu)
    }
}

/// What the menu bar shows: the waveform, plus the mode and countdown while playing.
/// Laid out by hand: a `Label` in a status item renders icon-only. The symbol
/// does not animate: a status item redrawing all day is a battery cost for
/// an app meant to sit in the background.
struct MenuBarLabel: View {
    let isPlaying: Bool
    let mode: Mode
    let remaining: Int?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "waveform")
            if isPlaying {
                if let remaining {
                    Text("\(mode.title) \(Duration.seconds(remaining), format: .time(pattern: .minuteSecond))")
                        .monospacedDigit()
                } else {
                    Text(mode.title)
                }
            }
        }
    }
}

struct TransportSection: View {
    let isPlaying: Bool
    let mode: Mode
    let soundscape: Soundscape
    let remaining: Int?
    let error: String?
    let toggle: () -> Void

    var body: some View {
        Section {
            Button(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill", action: toggle)
                .keyboardShortcut(.space, modifiers: [])
        } header: {
            StatusLine(isPlaying: isPlaying, mode: mode, soundscape: soundscape, remaining: remaining, error: error)
        }
    }
}

struct StatusLine: View {
    let isPlaying: Bool
    let mode: Mode
    let soundscape: Soundscape
    let remaining: Int?
    let error: String?

    var body: some View {
        if let error {
            Text("\(mode.title) · \(soundscape.title) · \(error)")
        } else if let remaining {
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

struct VolumeSection: View {
    @Binding var volume: Double
    let inMenu: Bool

    private static let steps: [Double] = [0.25, 0.5, 0.75, 1]

    var body: some View {
        Section {
            if inMenu {
                Picker("Volume", selection: Binding(
                    get: { Self.steps.min { abs($0 - volume) < abs($1 - volume) } ?? 1 },
                    set: { volume = $0 }
                )) {
                    ForEach(Self.steps, id: \.self) { step in
                        Text(step, format: .percent).tag(step)
                    }
                }
            } else {
                Slider(value: $volume, in: 0...1) {
                    Text("Volume")
                } minimumValueLabel: {
                    Image(systemName: "speaker.fill")
                } maximumValueLabel: {
                    Image(systemName: "speaker.wave.3.fill")
                }
            }
        }
    }
}
