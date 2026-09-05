import SwiftUI

@main
struct EntrainApp: App {
    @State private var session = Session()

    var body: some Scene {
        MenuBarExtra {
            PlayerMenu(session: session)
        } label: {
            MenuBarLabel(isPlaying: session.isPlaying, remaining: session.remaining)
        }
        .menuBarExtraStyle(.menu)
    }
}
