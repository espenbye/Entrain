import SwiftUI

@main
struct EntrainApp: App {
    private let session = Session.shared

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                Form {
                    PlayerControls(session: session, inMenu: false)
                    Section {
                        Toggle("Lock Screen & Control Center", isOn: Bindable(session).nowPlaying)
                    } footer: {
                        Text("Off lets Entrain play under music and leaves the playback controls with it.")
                    }
                }
                .navigationTitle("Entrain")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}
