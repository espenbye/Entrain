import Foundation

/// Where a Meditate segment goes once it ends. The iPhone and the watch log
/// it to Health; the Mac has no Health, and tests collect the segments.
@MainActor
protocol MindfulLog {
    /// A Meditate segment just started. The one moment the user is certainly
    /// present, so it is when Health may ask for permission.
    func prepare()
    func log(_ segment: DateInterval)
}

#if os(iOS) || os(watchOS)
import HealthKit

/// Meditate sessions as mindful minutes: what Health expects from an app in
/// the healthcare category, and it puts a session on the same chart as
/// Mindfulness and Breathe. Each stretch of play is one sample.
@MainActor
struct MindfulMinutes: MindfulLog {
    /// A tap that stops within the minute is a false start, not a session.
    static let minimum: TimeInterval = 60

    private static let store = HKHealthStore()
    private static let type = HKCategoryType(.mindfulSession)

    func prepare() {
        Task { await Self.authorize() }
    }

    /// A save the user declined fails silently: Health hides its own status,
    /// and the session itself succeeded.
    func log(_ segment: DateInterval) {
        guard segment.duration >= Self.minimum else { return }
        let sample = HKCategorySample(
            type: Self.type, value: HKCategoryValue.notApplicable.rawValue,
            start: segment.start, end: segment.end
        )
        Task {
            await Self.authorize()
            try? await Self.store.save(sample)
        }
    }

    /// Asks once; Health keeps the answer, and never asks twice.
    private static func authorize() async {
        guard HKHealthStore.isHealthDataAvailable(),
              store.authorizationStatus(for: type) == .notDetermined
        else { return }
        try? await store.requestAuthorization(toShare: [type], read: [])
    }
}
#endif
