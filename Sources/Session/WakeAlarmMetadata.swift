#if canImport(AlarmKit)
import AlarmKit
import AppIntents
import Foundation

/// The alarm carries nothing: it only ever means "start Wake". Shared with
/// the widget, which draws the alarm's Live Activity from these attributes.
struct WakeAlarmMetadata: AlarmMetadata {}

/// The Cancel button on the Live Activity. Runs in the app; the alarm's
/// fixed id is all it needs, and the alarm updates stream flips the switch.
struct CancelWakeAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Cancel Wake Alarm"
    static var supportedModes: IntentModes { .background }

    func perform() async throws -> some IntentResult {
        try? AlarmManager.shared.cancel(id: WakeAlarmMetadata.alarmID)
        return .result()
    }
}

extension WakeAlarmMetadata {
    /// Fixed, so a relaunch finds the alarm it scheduled.
    static let alarmID = UUID(uuidString: "6F3A1D8E-2B4C-4E9A-9C1F-7D5E8A2B3C4D")!
}
#endif
