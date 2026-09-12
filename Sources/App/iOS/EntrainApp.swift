import SwiftUI

@main
struct EntrainApp: App {
    private let session = Session.shared
    @Environment(\.scenePhase) private var phase

    init() {
        MainActor.assumeIsolated {
            HealthSignals.shared.onChange = { DayPublisher.shared.publish() }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabs(session: session)
                .onOpenURL { url in Task { await URLCommand(url)?.run(on: session) } }
                // Coming forward is the one moment the app reliably gets to
                // notice that the day rolled over while it was away.
                .onChange(of: phase, initial: true) { _, new in
                    if new == .active { DayPublisher.shared.publish() }
                }
        }
    }
}
