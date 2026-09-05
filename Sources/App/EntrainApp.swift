import SwiftUI

@main
struct EntrainApp: App {
    @State private var session = Session()

    var body: some Scene {
        MenuBarExtra {
            PlayerView(session: session)
        } label: {
            Image(systemName: "waveform")
                .symbolEffect(.variableColor.iterative, isActive: session.isPlaying)
        }
        .menuBarExtraStyle(.window)
    }
}
