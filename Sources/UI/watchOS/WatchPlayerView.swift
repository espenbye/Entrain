import SwiftUI

/// The watch app: transport up top, then the same settings as the other
/// platforms, one row each so they read at wrist size. Volume is the Digital
/// Crown in the system Now Playing app, so it has no row here.
struct WatchPlayerView: View {
    @Bindable var session: Session

    var body: some View {
        NavigationStack {
            List {
                TransportSection(
                    isPlaying: session.isPlaying,
                    title: session.title,
                    countdown: session.countdown,
                    error: session.error,
                    toggle: session.toggle
                )
                ModeSection(selection: $session.mode)
                Section {
                    if !session.mode.isSleep {
                        NavigationLink("Sound") {
                            List { LayerToggles(layers: session.layers, setLayer: session.setLayer) }
                            .navigationTitle("Sound")
                        }
                        Picker("Intensity", selection: $session.intensity) {
                            ForEach(Intensity.allCases) { Text($0.title).tag($0) }
                        }
                    }
                    Picker("Timer", selection: $session.length) {
                        ForEach(SessionLength.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Binaural Beats", isOn: $session.binaural)
                }
            }
            .navigationTitle("Entrain")
        }
    }
}
