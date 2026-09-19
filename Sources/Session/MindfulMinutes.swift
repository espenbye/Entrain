import Foundation

/// Where a mindful segment goes once it ends, and where the practice screen
/// reads them back from. The iPhone and the watch use Health; the Mac has no
/// Health, and tests collect the segments.
@MainActor
protocol MindfulLog {
    /// A mindful segment just started. The one moment the user is certainly
    /// present, so it is when Health may ask for permission.
    func prepare()
    func log(_ segment: DateInterval)
    /// Every mindful session Health holds over the last `days` days, in no
    /// particular order. Empty when Health is unavailable, when there is
    /// nothing there and when the read was refused: HealthKit deliberately
    /// never says which, so nothing downstream may treat empty as an error.
    func sessions(days: Int) async -> [DateInterval]
}

#if os(iOS) || os(watchOS)
import HealthKit

/// Meditate and Restore sessions as mindful minutes: what Health expects
/// from an app in the healthcare category, and it puts a session on the same
/// chart as Mindfulness and Breathe. Each stretch of play is one sample.
///
/// The type is asked for in both directions now. The write is unchanged; the
/// read is what the practice screen draws, and it is the same type in the
/// same store, so one authorization covers both.
@MainActor
struct MindfulMinutes: MindfulLog {
    /// A tap that stops within the minute is a false start, not a session.
    static let minimum: TimeInterval = 60

    private static let store = HKHealthStore()
    private static let type = HKCategoryType(.mindfulSession)

    func prepare() {
        Task { await Self.authorize() }
    }

    /// In whatever order Health returns them; `PracticeHistory` puts them
    /// newest first, so there is nothing for a sort descriptor to add here.
    func sessions(days: Int) async -> [DateInterval] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let start = PracticeHistory.start(ofLast: days)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(
                type: Self.type,
                predicate: HKQuery.predicateForSamples(withStart: start, end: nil)
            )],
            sortDescriptors: []
        )
        await Self.authorize()
        guard let samples = try? await descriptor.result(for: Self.store) else { return [] }
        return samples.map { DateInterval(start: $0.startDate, end: $0.endDate) }
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
    ///
    /// `statusForAuthorizationRequest` rather than `authorizationStatus`,
    /// which is the only thing Health will say about a read — whether there
    /// is anything left to ask for, never what the answer was — and so the
    /// only thing that can keep the sheet from appearing twice now that the
    /// type is read as well as written. Somebody who already allowed the
    /// write sees the sheet once more for the read, which is correct: it is
    /// a permission they have not been asked for before.
    private static func authorize() async {
        guard HKHealthStore.isHealthDataAvailable(),
              let status = try? await store.statusForAuthorizationRequest(toShare: [type], read: [type]),
              status == .shouldRequest
        else { return }
        try? await store.requestAuthorization(toShare: [type], read: [type])
    }
}
#endif
