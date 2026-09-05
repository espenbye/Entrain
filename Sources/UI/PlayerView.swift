import SwiftUI

/// The same controls in a regular window, for people who want Entrain on
/// screen. On iPhone and iPad this is the app.
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
            sleep: session.mode.isSleep,
            inMenu: inMenu
        )
        VolumeSection(volume: $session.volume, inMenu: inMenu)
    }
}

struct TransportSection: View {
    let isPlaying: Bool
    let title: String
    let remaining: Int?
    let error: String?
    let toggle: () async -> Void

    var body: some View {
        Section {
            Button(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill") {
                Task { await toggle() }
            }
            .spaceBarToggles()
        } header: {
            if let error {
                Text(verbatim: "\(title) · \(error)")
            } else if let remaining {
                Text("\(title) · \(remaining.countdown) left")
            } else {
                Text(title)
            }
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
    let layers: Set<Soundscape>
    let setLayer: (Soundscape, Bool) -> Void
    @Binding var intensity: Intensity
    @Binding var length: SessionLength
    @Binding var binaural: Bool
    /// Sleep modes play a fixed bed; sound and intensity have nothing to set.
    let sleep: Bool
    let inMenu: Bool

    var body: some View {
        Section {
            #if os(macOS)
            if inMenu {
                Menu("Sound") { LayerToggles(layers: layers, setLayer: setLayer) }.disabled(sleep)
            }
            #endif
            if !inMenu {
                LabeledContent("Sound") { HStack { LayerToggles(layers: layers, setLayer: setLayer) } }
                    .toggleStyle(.button)
                    .disabled(sleep)
            }
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

/// One check item per soundscape; any combination plays together.
struct LayerToggles: View {
    let layers: Set<Soundscape>
    let setLayer: (Soundscape, Bool) -> Void

    var body: some View {
        ForEach(Soundscape.allCases) { soundscape in
            Toggle(soundscape.title, isOn: Binding(
                get: { layers.contains(soundscape) },
                set: { setLayer(soundscape, $0) }
            ))
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

private extension View {
    /// Space plays and pauses wherever there is a keyboard.
    func spaceBarToggles() -> some View {
        #if os(watchOS)
        self
        #else
        keyboardShortcut(.space, modifiers: [])
        #endif
    }
}
