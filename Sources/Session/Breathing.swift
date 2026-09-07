import Foundation
import Observation

/// A breathing exercise laid over Meditate: a few phases of fixed seconds
/// that repeat for the exercise's length while the soundscape plays under
/// them. Each phase gets a tone and the player draws a circle that swells
/// and shrinks with the breath.
enum BreathingPattern: String, CaseIterable, Identifiable, Codable, Sendable {
    case none, coherent, box, relaxing, longExhale

    var id: Self { self }
    var title: String { String(localized: name) }
    var name: LocalizedStringResource {
        switch self {
        case .none: "Off"
        case .coherent: "Coherent"
        case .box: "Box"
        case .relaxing: "4-7-8"
        case .longExhale: "Long Exhale"
        }
    }

    /// The counts, in a line: "4 in, hold 7, 8 out".
    var blurb: LocalizedStringResource {
        switch self {
        case .none: "No breathing cues"
        case .coherent: "5 in, 5 out. Six breaths a minute, the resonance rate."
        case .box: "4 in, hold 4, 4 out, hold 4. Steadies attention."
        case .relaxing: "4 in, hold 7, 8 out. Slows the body down."
        case .longExhale: "4 in, 6 out. A longer exhale for calm."
        }
    }

    /// The phases of one breath, in order. Empty for `none`.
    var steps: [BreathStep] {
        switch self {
        case .none: []
        case .coherent: [BreathStep(.inhale, 5), BreathStep(.exhale, 5)]
        case .box: [BreathStep(.inhale, 4), BreathStep(.hold, 4), BreathStep(.exhale, 4), BreathStep(.hold, 4)]
        case .relaxing: [BreathStep(.inhale, 4), BreathStep(.hold, 7), BreathStep(.exhale, 8)]
        case .longExhale: [BreathStep(.inhale, 4), BreathStep(.exhale, 6)]
        }
    }

    /// Seconds per breath.
    var cycleSeconds: Double { steps.reduce(0) { $0 + $1.seconds } }

    /// How many breaths fit `seconds`: whole breaths, the nearest count, and
    /// at least one, so an exercise never stops mid-breath. Nil means the
    /// exercise runs for the whole session.
    func cycles(in seconds: Double?) -> Int? {
        guard let seconds, cycleSeconds > 0 else { return nil }
        return max(1, Int((seconds / cycleSeconds).rounded()))
    }

    /// Where a breath is `elapsed` seconds into the exercise. Nil once
    /// `cycles` breaths are over, or for `none`.
    func position(at elapsed: Double, cycles: Int? = nil) -> BreathPosition? {
        let steps = steps
        guard !steps.isEmpty, elapsed >= 0 else { return nil }
        let cycle = Int(elapsed / cycleSeconds)
        if let cycles, cycle >= cycles { return nil }
        var into = elapsed - Double(cycle) * cycleSeconds
        for (index, step) in steps.enumerated() {
            if into < step.seconds || index == steps.count - 1 {
                return BreathPosition(cycle: cycle, index: index, step: step, elapsed: min(into, step.seconds))
            }
            into -= step.seconds
        }
        return nil
    }
}

struct BreathStep: Equatable, Sendable {
    let phase: BreathPhase
    let seconds: Double

    init(_ phase: BreathPhase, _ seconds: Double) {
        self.phase = phase
        self.seconds = seconds
    }
}

/// One phase of a breath. `hold` follows either the inhale or the exhale;
/// the circle stays where the last phase left it.
enum BreathPhase: Int, CaseIterable, Sendable {
    case inhale, hold, exhale

    var title: LocalizedStringResource {
        switch self {
        case .inhale: "Breathe in"
        case .hold: "Hold"
        case .exhale: "Breathe out"
        }
    }

    var cue: BreathCue {
        switch self {
        case .inhale: .inhale
        case .hold: .hold
        case .exhale: .exhale
        }
    }
}

/// What the cue synth plays: a rising tone to breathe in, a steady one to
/// hold, a falling one to breathe out, and a longer one when the exercise
/// is over. The raw value travels to the render thread in `AudioParameters.cue`.
enum BreathCue: Int, CaseIterable, Sendable {
    case inhale, hold, exhale, finished

    /// The low two bits carry the cue; the rest count triggers, so the
    /// same cue twice in a row still reads as a change on the render thread.
    static func encode(_ cue: BreathCue, trigger: Int) -> Int { trigger << 2 | cue.rawValue }
    static func decode(_ value: Int) -> BreathCue { BreathCue(rawValue: value & 3)! }
}

struct BreathPosition: Equatable, Sendable {
    /// Breaths completed before this one.
    let cycle: Int
    /// Index into the pattern's steps.
    let index: Int
    let step: BreathStep
    /// Seconds into the step.
    let elapsed: Double

    var phase: BreathPhase { step.phase }
    var progress: Double { step.seconds > 0 ? elapsed / step.seconds : 1 }
}

/// How long the exercise runs. The soundscape keeps playing after it ends.
enum BreathingLength: Int, CaseIterable, Identifiable, Sendable {
    case session = 0
    case one = 1
    case three = 3
    case five = 5
    case ten = 10

    var id: Self { self }
    var title: String {
        switch self {
        case .session: String(localized: "Whole session")
        default: String(localized: "\(rawValue) min")
        }
    }
    /// Nil when the exercise lasts the session.
    var seconds: Double? { self == .session ? nil : Double(rawValue) * 60 }
}

/// Runs a breathing pattern in wall-clock time: steps through its phases,
/// tells the session when each starts so a cue sounds, and holds the
/// current position for the views. Everything happens on the main actor;
/// the render thread only sees the cue atomic.
@MainActor
@Observable
final class BreathGuide {
    private(set) var pattern: BreathingPattern = .none
    /// The step under way. Nil while idle, and again once the exercise is over.
    private(set) var position: BreathPosition?
    /// Wall-clock span of the current step, for a countdown that ticks on its own.
    private(set) var stepInterval: DateInterval?
    /// Breaths in the exercise. Nil when it lasts the session.
    private(set) var cycles: Int?
    /// True from the first breath until the last one ends.
    var isActive: Bool { position != nil }

    /// Called on the main actor at the start of each step and once at the end.
    var onCue: ((BreathCue) -> Void)?
    private var task: Task<Void, Never>?

    /// Starts `pattern` from its first breath, replacing whatever ran before.
    func start(_ pattern: BreathingPattern, length: BreathingLength) {
        stop()
        let steps = pattern.steps
        guard !steps.isEmpty else { return }
        self.pattern = pattern
        let total = pattern.cycles(in: length.seconds)
        cycles = total
        // The first breath begins now, before the caller returns, so the
        // circle and the cue do not wait on the scheduler.
        let began = ContinuousClock.now
        begin(steps[0], cycle: 0, index: 0)
        task = Task { [weak self] in
            var offset = steps[0].seconds
            var cycle = 0
            var index = 1
            while !Task.isCancelled {
                // Each boundary is measured from the start, so the breaths
                // do not drift by the scheduler's lateness.
                try? await Task.sleep(until: began + .seconds(offset))
                guard !Task.isCancelled, let self else { return }
                if index == steps.count {
                    index = 0
                    cycle += 1
                }
                if let total, cycle >= total {
                    finish()
                    return
                }
                begin(steps[index], cycle: cycle, index: index)
                offset += steps[index].seconds
                index += 1
            }
        }
    }

    private func begin(_ step: BreathStep, cycle: Int, index: Int) {
        position = BreathPosition(cycle: cycle, index: index, step: step, elapsed: 0)
        stepInterval = DateInterval(start: .now, duration: step.seconds)
        onCue?(step.phase.cue)
    }

    /// Ends the exercise quietly: a pause or a mode switch, not a completion.
    func stop() {
        task?.cancel()
        task = nil
        position = nil
        stepInterval = nil
        cycles = nil
    }

    private func finish() {
        task = nil
        position = nil
        stepInterval = nil
        onCue?(.finished)
    }
}
