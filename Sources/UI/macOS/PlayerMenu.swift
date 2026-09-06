import SwiftUI

/// The menu bar menu. Every child is a real menu item, so the look is macOS's own.
struct PlayerMenu: View {
    @Bindable var session: Session
    @Environment(\.openWindow) private var openWindow
    @AppStorage(DockIcon.key) private var showInDock = false
    @AppStorage(HotKey.key) private var globalShortcut = false
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        PlayerControls(session: session)
        Divider()
        Button("Open Entrain…") {
            openWindow(id: PlayerScreen.windowID)
            NSApplication.shared.activate()
        }
        .keyboardShortcut("o")
        Toggle(HotKey.title, isOn: Binding(
            get: { globalShortcut },
            set: { on in
                globalShortcut = on
                on ? HotKey.enable { Task { await session.toggle() } } : HotKey.disable()
            }
        ))
        Toggle("Control Center & Media Keys", isOn: $session.nowPlaying)
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
                    Text(verbatim: "\(mode.title) \(remaining.countdown)")
                        .monospacedDigit()
                } else {
                    Text(mode.title)
                }
            }
        }
    }
}

/// Transport, mode and settings as menu items, for the menu bar menu.
struct PlayerControls: View {
    @Bindable var session: Session

    var body: some View {
        TransportSection(
            isPlaying: session.isPlaying,
            title: session.title,
            remaining: session.remaining,
            error: session.error,
            toggle: session.toggle
        )
        ModeSection(selection: $session.mode)
        SettingsSection(
            layers: session.layers,
            setLayer: session.setLayer,
            intensity: $session.intensity,
            length: $session.length,
            binaural: $session.binaural,
            sleep: session.mode.isSleep
        )
        VolumeSection(volume: $session.volume)
    }
}

struct SettingsSection: View {
    let layers: Set<Soundscape>
    let setLayer: (Soundscape, Bool) -> Void
    @Binding var intensity: Intensity
    @Binding var length: SessionLength
    @Binding var binaural: Bool
    /// Sleep modes play a fixed bed; sound and intensity have nothing to set.
    let sleep: Bool

    var body: some View {
        Section {
            Menu("Sound") { LayerToggles(layers: layers, setLayer: setLayer) }.disabled(sleep)
            Picker("Intensity", selection: $intensity) {
                ForEach(Intensity.allCases) { Text($0.title).tag($0) }
            }
            .disabled(sleep)
            Picker("Timer", selection: $length) {
                ForEach(SessionLength.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Binaural Beats", isOn: $binaural)
        }
    }
}

/// Menus cannot host a slider, so volume is a submenu of steps.
struct VolumeSection: View {
    @Binding var volume: Double

    private static let steps: [Double] = [0.25, 0.5, 0.75, 1]

    var body: some View {
        Section {
            Picker("Volume", selection: Binding(
                get: { Self.steps.min { abs($0 - volume) < abs($1 - volume) } ?? 1 },
                set: { volume = $0 }
            )) {
                ForEach(Self.steps, id: \.self) { step in
                    Text(step, format: .percent).tag(step)
                }
            }
        }
    }
}
