import SwiftUI

@main
struct EntrainApp: App {
    private let session = Session.shared

    var body: some Scene {
        WindowGroup {
            PlayerScreen(session: session)
                .onOpenURL { url in Task { await URLCommand(url)?.run(on: session) } }
        }
    }
}
