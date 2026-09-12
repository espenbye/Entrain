#if os(iOS) || os(watchOS)
import Foundation
import HealthKit

/// The signals as HealthKit hands them over. Reads only: nothing here saves
/// anything, and the mindful-minutes write in `MindfulMinutes` is left
/// exactly as it was, with its own authorization.
@MainActor
final class HealthReader: BodySensing {
    /// One store per process, like the write side keeps.
    private static let store = HKHealthStore()

    private static let types: Set<HKObjectType> = [
        HKCategoryType(.sleepAnalysis),
        HKQuantityType(.restingHeartRate),
        HKQuantityType(.heartRateVariabilitySDNN),
        HKQuantityType(.timeInDaylight),
    ]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Asks once. `statusForAuthorizationRequest` is the only thing Health
    /// will say about read access — whether there is anything left to ask
    /// for, never what the answer was — so it is also what keeps the sheet
    /// from appearing twice.
    func authorize() async {
        guard HKHealthStore.isHealthDataAvailable(),
              let status = try? await Self.store.statusForAuthorizationRequest(toShare: [], read: Self.types),
              status == .shouldRequest
        else { return }
        try? await Self.store.requestAuthorization(toShare: [], read: Self.types)
    }

    // MARK: Sleep

    private static let anchorKey = "health.sleep.anchor"
    private static let nightsKey = "health.sleep.nights"

    func nights() async -> [SleepNight] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let start = Calendar.current.date(byAdding: .day, value: -(SleepSignature.window + 1), to: .now) ?? .now
        let predicate = HKSamplePredicate.categorySample(
            type: HKCategoryType(.sleepAnalysis),
            predicate: HKQuery.predicateForSamples(withStart: start, end: nil)
        )
        // The nights already reduced, minus any that have fallen out of the
        // window. They and the anchor stand or fall together: an anchor
        // without them would skip the nights it has already reported.
        let cached = nights(inDefaults: start)
        let anchor = cached.isEmpty ? nil : anchor

        // The anchor answers one question — has Health anything new for this
        // window since the last look — and that is all it is used for. It
        // cannot build the nights incrementally: a night reaches the phone in
        // fragments over the following morning, and a fragment reduced on its
        // own is a wrong night. So a change means re-reading the window, and
        // no change, which is the usual case, means no work at all.
        guard let change = try? await HKAnchoredObjectQueryDescriptor(predicates: [predicate], anchor: anchor)
            .result(for: Self.store)
        else { return cached }

        if anchor == nil {
            // A query with no anchor returns the whole window, so this is
            // already the full read.
            return save(SleepNight.nights(from: change.addedSamples.map(Self.stage)), anchor: change.newAnchor)
        }
        guard !change.addedSamples.isEmpty || !change.deletedObjects.isEmpty else { return cached }
        guard let samples = try? await HKSampleQueryDescriptor(predicates: [predicate], sortDescriptors: [])
            .result(for: Self.store)
        else { return cached }
        return save(SleepNight.nights(from: samples.map(Self.stage)), anchor: change.newAnchor)
    }

    /// A HealthKit sleep sample as the reduction wants it. `.asleepCore`,
    /// `.asleepDeep`, `.asleepREM` and `.asleepUnspecified` are all just
    /// sleep here: which stage a night was in says nothing about when it
    /// began or ended, and mixing sources makes the staging incomparable
    /// anyway.
    private static func stage(_ sample: HKCategorySample) -> SleepStageSample {
        let stage: SleepStageSample.Stage = switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
        case .inBed: .inBed
        case .awake: .awake
        default: .asleep
        }
        return SleepStageSample(
            stage, DateInterval(start: sample.startDate, end: sample.endDate),
            source: sample.sourceRevision.source.bundleIdentifier
        )
    }

    private var anchor: HKQueryAnchor? {
        defaults.data(forKey: Self.anchorKey)
            .flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0) }
    }

    private func nights(inDefaults start: Date) -> [SleepNight] {
        let stored = defaults.data(forKey: Self.nightsKey)
            .flatMap { try? JSONDecoder().decode([SleepNight].self, from: $0) } ?? []
        return stored.filter { $0.interval.end >= start }
    }

    private func save(_ nights: [SleepNight], anchor: HKQueryAnchor) -> [SleepNight] {
        defaults.set(try? JSONEncoder().encode(nights), forKey: Self.nightsKey)
        defaults.set(
            try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true),
            forKey: Self.anchorKey
        )
        return nights
    }

    // MARK: Resting heart rate and variability

    /// One value a day. Resting heart rate is written once a day already;
    /// variability is sampled several times, and the day's average is the
    /// summary Health itself shows. No anchor and no background delivery
    /// here: a day's figure is settled by the time anything asks for it, and
    /// waking the app to learn it early would buy nothing.
    func daily(_ metric: BodyMetric, days: Int) async -> [DailyValue] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let start = calendar.date(byAdding: .day, value: -days, to: today) else { return [] }
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(
                type: HKQuantityType(metric.identifier),
                predicate: HKQuery.predicateForSamples(withStart: start, end: nil)
            ),
            options: metric.statistics,
            anchorDate: today,
            intervalComponents: DateComponents(day: 1)
        )
        guard let collection = try? await descriptor.result(for: Self.store) else { return [] }
        return collection.statistics().compactMap { statistics in
            metric.quantity(in: statistics).map {
                DailyValue(day: statistics.startDate, value: $0.doubleValue(for: metric.unit))
            }
        }
    }
}

extension BodyMetric {
    var identifier: HKQuantityTypeIdentifier {
        switch self {
        case .restingHeartRate: .restingHeartRate
        case .heartRateVariability: .heartRateVariabilitySDNN
        case .timeInDaylight: .timeInDaylight
        }
    }

    /// A heart rate is a rate, so a day's figure is its average; minutes
    /// outdoors are minutes, so a day's figure is their sum. Averaging the
    /// daylight samples would report the length of a typical walk rather
    /// than how long the day was spent outside.
    var statistics: HKStatisticsOptions {
        self == .timeInDaylight ? .cumulativeSum : .discreteAverage
    }

    func quantity(in statistics: HKStatistics) -> HKQuantity? {
        self == .timeInDaylight ? statistics.sumQuantity() : statistics.averageQuantity()
    }

    var unit: HKUnit {
        switch self {
        case .restingHeartRate: .count().unitDivided(by: .minute())
        case .heartRateVariability: .secondUnit(with: .milli)
        case .timeInDaylight: .minute()
        }
    }
}
#endif
