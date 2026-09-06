import SwiftUI

struct TransportSection: View {
    let isPlaying: Bool
    let title: String
    let countdown: Text?
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
            } else if let countdown {
                Text("\(title) · \(countdown) left")
            } else {
                Text(title)
            }
        }
    }
}

extension Session {
    /// The countdown as text. While playing it is drawn from the deadline,
    /// so it ticks without a re-render; paused it is the frozen remainder.
    var countdown: Text? {
        if let deadline {
            return Text(timerInterval: Date.now...max(Date.now, deadline), countsDown: true)
        }
        // Not observed, but every change to it while paused comes with a
        // change to `length` or `isPlaying`, which every caller reads.
        return remaining.map { Text($0.countdown) }
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
