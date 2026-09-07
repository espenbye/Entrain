#if os(watchOS)
import Foundation
import HealthKit
import Observation

/// The heart while a session plays, on the wrist.
///
/// The watch samples the heart every few minutes while it is idle, which
/// says nothing about a ten-minute meditation. A workout session is what
/// puts the sensor into continuous mode, so that is what runs here: a
/// mind and body session, the activity type Apple's own Mindfulness uses,
/// collecting heart rate and nothing else. No workout is ever saved — the
/// builder is discarded when the session ends — and nothing here touches
/// the audio.
@MainActor
@Observable
final class LiveHeartRate {
    static let shared = LiveHeartRate(defaults: .standard)

    /// Whether the heart may steer the sound. Off, and not a setting: what
    /// the sound should do about a heart that has drifted off the pace is a
    /// product question with no answer yet, and wiring a body signal to an
    /// audio parameter without evidence for the link is exactly what this
    /// app does not do. The reading below is the evidence being gathered.
    static let steersAudio = false

    /// Whether the sensor may run at all. Off by default: continuous heart
    /// rate costs battery, and until the reading does something it is worth
    /// only what the wearer thinks it is worth.
    var isOn: Bool {
        didSet {
            defaults.set(isOn, forKey: "heartRate")
            if !isOn { stop() }
        }
    }

    /// The most recent reading, or nil when nothing is streaming.
    private(set) var bpm: Double?
    /// The readings so far this session, for `Coherence`.
    private(set) var beats: [Beat] = []

    private let defaults: UserDefaults
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var relay: HeartRateRelay?
    private var started: Date?

    init(defaults: UserDefaults) {
        self.defaults = defaults
        isOn = defaults.bool(forKey: "heartRate")
    }

    /// How closely the heart is following `pattern`, or nil before there is
    /// enough to say. See `Coherence` for what the number is and is not.
    func following(_ pattern: BreathingPattern) -> Double? {
        Coherence.correlation(of: beats, following: pattern)
    }

    /// Starts the sensor for a mode that has a body to watch. Rest is where
    /// the heart is the point — Meditate paces the breath and Relax asks
    /// for the same thing without the counting. Work modes and the sleep
    /// beds get nothing: eight hours of continuous heart rate to show a
    /// number nobody is awake to read is not a trade worth making.
    func start(for mode: Mode) async {
        guard isOn, mode.purpose == .rest, session == nil, HKHealthStore.isHealthDataAvailable() else { return }
        await authorize()
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .mindAndBody
        configuration.locationType = .indoor
        guard let session = try? HKWorkoutSession(healthStore: store, configuration: configuration) else { return }
        let builder = session.associatedWorkoutBuilder()
        // Heart rate only. The default set would also start the motion
        // sensors and the energy estimate, and nothing here reads them.
        let source = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: nil)
        source.enableCollection(for: HKQuantityType(.heartRate), predicate: nil)
        builder.dataSource = source
        let relay = HeartRateRelay(
            onBeat: { [weak self] bpm, date in
                Task { @MainActor in self?.record(bpm, at: date) }
            },
            onEnd: { [weak self] in
                Task { @MainActor in self?.stop() }
            }
        )
        session.delegate = relay
        builder.delegate = relay
        self.session = session
        self.builder = builder
        self.relay = relay
        started = .now
        session.startActivity(with: .now)
        try? await builder.beginCollection(at: .now)
    }

    /// A refusal is indistinguishable from a watch that never reports, and
    /// both leave the reading empty, which is a state the UI already draws.
    /// The workout type is asked for on the share side because a workout
    /// session cannot start without it; none is ever written.
    private func authorize() async {
        guard let status = try? await store.statusForAuthorizationRequest(
            toShare: [HKObjectType.workoutType()], read: [HKQuantityType(.heartRate)]
        ), status == .shouldRequest else { return }
        try? await store.requestAuthorization(
            toShare: [HKObjectType.workoutType()], read: [HKQuantityType(.heartRate)]
        )
    }

    func stop() {
        guard let session, let builder else { return }
        self.session = nil
        self.builder = nil
        relay = nil
        bpm = nil
        beats = []
        started = nil
        session.end()
        Task {
            try? await builder.endCollection(at: .now)
            // Health gains nothing: the wearer never asked for a workout,
            // and the session was only ever a way to keep the sensor on.
            builder.discardWorkout()
        }
    }

    /// Beats older than a few breathing cycles are dropped, so the
    /// correlation follows the last minutes rather than the whole session.
    private static let memory: Double = 4 * 60

    private func record(_ bpm: Double, at date: Date) {
        guard let started, bpm > 0 else { return }
        self.bpm = bpm
        let elapsed = date.timeIntervalSince(started)
        guard elapsed >= 0 else { return }
        beats.append(Beat(elapsed: elapsed, bpm: bpm))
        beats.removeAll { elapsed - $0.elapsed > Self.memory }
    }
}

/// The two HealthKit delegates in one object. Both are called on an
/// arbitrary queue, so nothing here is isolated and nothing is captured but
/// the two sendable closures that hop back to the main actor.
private final class HeartRateRelay: NSObject, HKLiveWorkoutBuilderDelegate, HKWorkoutSessionDelegate {
    private let onBeat: @Sendable (Double, Date) -> Void
    private let onEnd: @Sendable () -> Void

    init(onBeat: @escaping @Sendable (Double, Date) -> Void, onEnd: @escaping @Sendable () -> Void) {
        self.onBeat = onBeat
        self.onEnd = onEnd
    }

    func workoutBuilder(_ builder: HKLiveWorkoutBuilder, didCollectDataOf types: Set<HKSampleType>) {
        let heartRate = HKQuantityType(.heartRate)
        guard types.contains(heartRate),
              let statistics = builder.statistics(for: heartRate),
              let quantity = statistics.mostRecentQuantity()
        else { return }
        onBeat(
            quantity.doubleValue(for: .count().unitDivided(by: .minute())),
            statistics.mostRecentQuantityDateInterval()?.end ?? .now
        )
    }

    func workoutBuilderDidCollectEvent(_ builder: HKLiveWorkoutBuilder) {}

    func workoutSession(
        _ session: HKWorkoutSession, didChangeTo state: HKWorkoutSessionState,
        from previous: HKWorkoutSessionState, date: Date
    ) {
        if state == .ended || state == .stopped { onEnd() }
    }

    func workoutSession(_ session: HKWorkoutSession, didFailWithError error: any Error) {
        onEnd()
    }
}
#endif
