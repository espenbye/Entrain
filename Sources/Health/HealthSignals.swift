import Foundation
import Observation

/// One day's value for a body measure.
struct DailyValue: Equatable, Sendable {
    var day: Date
    var value: Double
}

/// Where the body signals come from: Health on iPhone and Apple Watch,
/// nothing on the Mac, a script in tests. The same shape as `MindfulLog`
/// on the write side, and for the same reason — the Mac has no HealthKit
/// and must keep compiling and behaving exactly as it does now.
///
/// Every method fails silently. Health read authorization is deliberately
/// unobservable: an app cannot tell "you said no" from "there is nothing
/// there", both come back as an empty result, so nothing here may treat
/// emptiness as an error worth showing.
@MainActor
protocol BodySensing {
    /// Ask for the read types. Called at the one moment the user
    /// understands why, and never blocks anything.
    func authorize() async
    /// Every night Health knows about inside the signature's window, oldest
    /// first. Nights with no data are absent, not zero.
    func nights() async -> [SleepNight]
    /// Daily values for `metric` over the last `days` days, oldest first,
    /// one entry per day that has one.
    func daily(_ metric: BodyMetric, days: Int) async -> [DailyValue]
}

/// What Health has to say about this body, for the adaptive layer to
/// consult. Nothing here decides anything: it reads, reduces and holds, and
/// `Suggestion` and `Session` make of it what they will. Without a source —
/// on the Mac, on a fresh install, or when the user said no — every signal
/// stays nil and every consumer falls back to the sun and the clock.
@MainActor
@Observable
final class HealthSignals {
    static let shared = HealthSignals(source: source)

    /// When this person habitually sleeps. Nil until there are enough nights.
    private(set) var sleep: SleepSignature?
    /// Today against this person's own baseline, per metric.
    private(set) var vitals: [BodyMetric: BodySignal] = [:]

    private let source: (any BodySensing)?
    private var work: Task<Void, Never>?

    init(source: (any BodySensing)?) {
        self.source = source
        refresh()
    }

    private static var source: (any BodySensing)? {
        #if os(iOS) || os(watchOS)
        HealthReader()
        #else
        nil
        #endif
    }

    /// A mode that ends in bed just started: the one moment reading last
    /// night is obviously the point, so it is when Health may ask. Asking
    /// costs a sheet the user can dismiss, and a refusal is indistinguishable
    /// from an empty Health store, which is a state everything here already
    /// handles.
    func prepare() {
        guard let source else { return }
        work?.cancel()
        work = Task { [weak self] in
            await source.authorize()
            await self?.read()
        }
    }

    /// Re-reads what Health holds. Cheap, and never on a timer: the signals
    /// move once a night, so they are read at launch and when a session that
    /// cares about them begins, and nothing polls.
    func refresh() {
        guard source != nil, work == nil else { return }
        work = Task { [weak self] in await self?.read() }
    }

    private func read() async {
        guard let source else { return }
        sleep = SleepSignature.from(await source.nights())
        for metric in BodyMetric.allCases {
            // The most recent day Health has a value for stands in for
            // today: a resting heart rate is not written until the device
            // has had the day to measure one, so before then yesterday is
            // the freshest thing there is to compare.
            let daily = await source.daily(metric, days: BodySignal.window + 1)
            guard let latest = daily.last else { continue }
            vitals[metric] = BodySignal.from(
                history: daily.dropLast().map(\.value), today: latest.value, metric: metric
            )
        }
        work = nil
    }
}
