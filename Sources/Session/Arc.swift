import Foundation

/// How a sleep mode moves on its own over a night. Nothing here reads the
/// clock: the session passes play time in, so pausing holds the arc and
/// switching mode starts it over, like the rate ramps in `Mode`.
///
/// The first twenty minutes are the onset. Sleep latency in the healthy
/// adult is ten to twenty minutes, so the bed is at its most present when
/// the listener is awake and processing the room, and settles once they are
/// past that: a little slow modulation to follow, a brighter bed that masks
/// more, at full level; then no modulation, a darker bed, a few decibels
/// down. Sound that stays loud past onset lifts arousals for the rest of
/// the night, and a bed that is featureless from the first second gives
/// the waking mind nothing to hold on to.
///
/// Deep Sleep swells the bed at 1 Hz, the slow-oscillation rate, but not
/// evenly: slow-wave sleep peaks in the middle of each ninety-minute cycle
/// and gives way to REM at its end, so the depth follows that cycle, deep
/// around the forty-fifth minute of each and shallow between. Open-loop
/// modulation cannot find the up-phase the way closed-loop stimulation
/// does, so it stays moderate and steps out of the way where the cycle is
/// lightest rather than pushing all night.
extension Mode {
    /// Seconds over which a sleep bed settles.
    static let onsetSeconds: Double = 20 * 60
    /// One sleep cycle.
    static let cycleSeconds: Double = 90 * 60

    private static let onsetBrightness = Curve([(0, 0.3), (1, -0.6)])
    private static let onsetLevel = Curve([(0, 1), (1, 0.6)])
    private static let sleepDepth = Curve([(0, 0.3), (1, 0)])

    /// Modulation depth `elapsed` seconds in, before intensity. Steady
    /// modes hold their `depth`; the sleep beds walk their arc.
    func depth(elapsed: Double) -> Double {
        switch self {
        case .sleep: Self.sleepDepth.value(at: onset(elapsed))
        case .deepSleep: 0.15 + (depth - 0.15) * (0.5 - 0.5 * cos(2 * .pi * elapsed / Self.cycleSeconds))
        default: depth
        }
    }

    /// Carrier brightness `elapsed` seconds in, -1...1, from the mode alone.
    func brightness(elapsed: Double) -> Double {
        isSleep ? Self.onsetBrightness.value(at: onset(elapsed)) : 0
    }

    /// Level `elapsed` seconds in, 0...1, on top of the timer's taper.
    func level(elapsed: Double) -> Double {
        isSleep ? Self.onsetLevel.value(at: onset(elapsed)) : 1
    }

    /// Whether the sound is still moving on its own `elapsed` seconds in: a
    /// rate ramp under way, an onset settling, or the Deep Sleep cycle,
    /// which never rests. An endless session stops ticking once this is false.
    func evolves(at elapsed: Double, length: SessionLength) -> Bool {
        if let seconds = rampSeconds(for: length), elapsed < seconds { return true }
        switch self {
        case .sleep: return elapsed < Self.onsetSeconds
        case .deepSleep: return true
        default: return false
        }
    }

    /// The signature that opens the modes that end in bed. Always the same
    /// sound, and never heard anywhere else, so that after a few nights it
    /// means bedtime by itself: a cue that reliably precedes sleep comes to
    /// bring it on, the way a fixed bedtime routine does.
    var cue: Cue? { tapers ? .bedtime : nil }

    private func onset(_ elapsed: Double) -> Double { min(1, elapsed / Self.onsetSeconds) }
}

/// A curve through points, each segment blended with a raised cosine so
/// the slope is zero at every point: no corners for the ear to catch.
struct Curve: Sendable {
    private let points: [(x: Double, y: Double)]

    init(_ points: [(Double, Double)]) {
        self.points = points.map { (x: $0.0, y: $0.1) }
    }

    func value(at x: Double) -> Double {
        guard let first = points.first, let last = points.last else { return 0 }
        if x <= first.x { return first.y }
        if x >= last.x { return last.y }
        let i = points.firstIndex { $0.x > x }!
        let (a, b) = (points[i - 1], points[i])
        let t = (x - a.x) / (b.x - a.x)
        let blend = 0.5 - 0.5 * cos(t * .pi)
        return a.y + (b.y - a.y) * blend
    }
}
