import SwiftUI

@main
struct EntrainApp: App {
    private let session = Session.shared

    var body: some Scene {
        WindowGroup {
            PlayerScreen(session: session)
        }
    }
}
