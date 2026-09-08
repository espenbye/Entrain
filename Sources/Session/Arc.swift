import Foundation

/// How a mode moves on its own over a session, as one keyframe table per
/// mode. Nothing here reads the clock: the session passes play time in, so
/// pausing holds the arc and switching mode starts it over.
///
/// The first stretch of a sleep bed is the onset. Sleep latency in the
/// healthy adult is ten to twenty minutes, so the bed is at its most
/// present when the listener is awake and processing the room, and settles
/// once they are past that: a little slow modulation to follow, a brighter
/// bed that masks more, at full level; then no modulation, a darker bed, a
/// few decibels down. Sound that stays loud past onset lifts arousals for
/// the rest of the night, and a bed that is featureless from the first
/// second gives the waking mind nothing to hold on to. Twenty minutes is
/// the population figure; where Health knows how long this listener
/// actually takes to fall asleep, the session builds the table around that
/// instead (`SleepSignature.onset`).
///
/// Deep Sleep swells the bed at 1 Hz, the slow-oscillation rate, but not
/// evenly: slow-wave sleep peaks in the middle of each ninety-minute cycle
/// and gives way to REM at its end, so the depth follows that cycle, deep
/// around the forty-fifth minute of each and shallow between. The cycle is
/// counted from sleep onset, which is where the sleep literature measures
/// it from, and not from the tap that started the sound, so it waits the
/// onset out first. Open-loop modulation cannot find the up-phase the way
/// closed-loop stimulation does, so it stays moderate and steps out of the
/// way where the cycle is lightest rather than pushing all night.
///
/// Wind Down walks alpha to delta at bedtime and Wake walks delta back to
/// beta after a nap. Their rate keyframes are written over a nominal ramp
/// and stretched to the session's; see `rampSeconds(for:)`.
extension Mode {
    /// Seconds over which a sleep bed settles, before Health knows better.
    static let onsetSeconds: Double = 20 * 60
    /// One sleep cycle.
    static let cycleSeconds: Double = 90 * 60

    /// The whole of a mode's behaviour over time. Every mode names its rate
    /// and depth at time zero; a channel no keyframe names holds its default,
    /// which is a flat bed at full level.
    func keyframes(onset: Double = Mode.onsetSeconds) -> [Keyframe] {
        switch self {
        case .focus: [Keyframe(0, rate: 16, depth: 0.5)]
        // Gamma sits at 40 Hz, the best-replicated auditory steady-state
        // response, and shallow: 40 Hz modulation sits in the roughness
        // range and turns into a buzz at ordinary depth.
        case .gamma: [Keyframe(0, rate: 40, depth: 0.3)]
        case .relax: [Keyframe(0, rate: 10, depth: 0.4)]
        case .meditate: [Keyframe(0, rate: 6, depth: 0.5)]
        case .sleep: [
            Keyframe(0, rate: 2, depth: 0.3, brightness: 0.3, level: 1),
            Keyframe(onset, depth: 0, brightness: -0.6, level: 0.6),
        ]
        // The depth keyframes run from the onset, so the cycle starts where
        // sleep does; `Track` repeats over the last cycle's worth of them.
        case .deepSleep: [
            Keyframe(0, rate: 1, depth: 0.15, brightness: 0.3, level: 1),
            Keyframe(onset, depth: 0.15, brightness: -0.6, level: 0.6),
            Keyframe(onset + Self.cycleSeconds / 2, depth: 0.5),
            Keyframe(onset + Self.cycleSeconds, depth: 0.15),
        ]
        case .windDown: [Keyframe(0, rate: 10, depth: 0.4), Keyframe(20 * 60, rate: 2)]
        case .wake: [Keyframe(0, rate: 2, depth: 0.5), Keyframe(15 * 60, rate: 16)]
        }
    }

    /// Where the modulation envelope peaks, as a fraction of the cycle. At
    /// 0.5 it is the symmetric raised cosine the modulation started as; under
    /// it the gain drops fast and recovers slowly, which reads as a pulse
    /// rather than as tremolo and puts a transient at the top of every cycle
    /// for the auditory system to lock to. It does not move over a session:
    /// the arc says how fast and how deep a mode pulses, this says what one
    /// pulse is shaped like, and that is a property of the mode itself.
    ///
    /// A sharp onset costs roughness: it spreads the envelope over harmonics
    /// of the rate, and those land in the band around 70 Hz the ear hears as
    /// rough. How much depends on where the rate sits. At 6 and 10 Hz the
    /// harmonics march straight into that band, so Meditate, Relax and Wind
    /// Down stay near the sine. At 16 Hz there is room for a real pulse. At
    /// 40 Hz the fundamental is already inside the band and the harmonics
    /// fall past it, so Gamma can take the sharpest shape here and measure
    /// slightly smoother than the sine it replaces; `EnvelopeTests` holds it
    /// to that. Nothing that ends in bed gets a transient at all.
    var envelope: Double {
        switch self {
        case .focus, .wake: 0.25
        case .gamma: 0.3
        case .relax: 0.4
        case .meditate, .windDown: 0.45
        case .sleep, .deepSleep: 0.5
        }
    }

    /// The keyframes as curves, built once. Deep Sleep is the one mode with a
    /// cycle, and only its depth reaches the end of it, so only its depth repeats.
    var arc: Arc { Self.arcs[self]! }

    /// The same, around a listener's own sleep onset. The usual twenty
    /// minutes is compiled once per mode at launch; anything else is built
    /// here, so the session holds the result rather than asking each tick.
    func arc(onset: Double) -> Arc {
        onset == Self.onsetSeconds
            ? arc
            : Arc(keyframes(onset: onset), cycle: self == .deepSleep ? Self.cycleSeconds : nil)
    }

    private static let arcs: [Mode: Arc] = Dictionary(uniqueKeysWithValues: Mode.allCases.map {
        ($0, Arc($0.keyframes(), cycle: $0 == .deepSleep ? cycleSeconds : nil))
    })

    /// How long the rate ramp takes: a timed session ramps over the whole
    /// timer, less the taper, so Wind Down arrives at 2 Hz before it fades
    /// out. Endless sessions use the table's own length. Nil for steady modes.
    func rampSeconds(for length: SessionLength) -> Double? {
        let nominal = arc.rate.end
        guard nominal > 0 else { return nil }
        guard length != .endless else { return nominal }
        return max(1, Double(length.seconds) - (tapers ? fadeOut : 0))
    }

    /// Rate after `elapsed` seconds of play, with the ramp stretched over the
    /// session's own length. Linear in Hz: a ramp should walk at a steady
    /// hertz per minute, where a level wants the arc's raised cosine.
    func rate(elapsed: Double, length: SessionLength) -> Double {
        guard let seconds = rampSeconds(for: length) else { return arc.rate.value(at: 0) }
        return arc.rate.value(at: elapsed * arc.rate.end / seconds)
    }

    /// Modulation depth `elapsed` seconds in, before intensity.
    func depth(elapsed: Double) -> Double { arc.depth.value(at: elapsed) }

    /// Carrier brightness `elapsed` seconds in, -1...1, from the mode alone.
    func brightness(elapsed: Double) -> Double { arc.brightness.value(at: elapsed) }

    /// Level `elapsed` seconds in, 0...1, on top of the timer's taper.
    func level(elapsed: Double) -> Double { arc.level.value(at: elapsed) }

    /// Whether the sound is still moving on its own `elapsed` seconds in: a
    /// rate ramp under way, an onset settling, or the Deep Sleep cycle,
    /// which never rests. An endless session stops ticking once this is false.
    func evolves(at elapsed: Double, length: SessionLength, in arc: Arc? = nil) -> Bool {
        if let seconds = rampSeconds(for: length), elapsed < seconds { return true }
        return elapsed < (arc ?? self.arc).settles
    }

    /// The modulation rate as the mode plays it, for the person who wants
    /// the number: one figure for a steady mode, the span for a ramping one.
    var frequency: String {
        let first = rate(elapsed: 0, length: .endless)
        let last = arc.rate.value(at: arc.rate.end)
        return first == last
            ? String(localized: "\(Self.hertz(first)) Hz")
            : String(localized: "\(Self.hertz(first)) to \(Self.hertz(last)) Hz")
    }

    /// The deepest the mode ever modulates, before intensity, as a percentage.
    var depthRange: String {
        let deepest = stride(from: 0.0, through: 3 * 3600, by: 60).map { depth(elapsed: $0) }.max() ?? 0
        return deepest.formatted(.percent.precision(.fractionLength(0)))
    }

    private static func hertz(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// The signature that opens the modes that end in bed. Always the same
    /// sound, and never heard anywhere else, so that after a few nights it
    /// means bedtime by itself: a cue that reliably precedes sleep comes to
    /// bring it on, the way a fixed bedtime routine does.
    var cue: Cue? { tapers ? .bedtime : nil }
}

/// The rate handover when the program moves the session from one mode to
/// the next on its own. It lives beside the ramps rather than in `Program`
/// because it is the same kind of thing they are: a modulation rate walked
/// linearly in hertz over play time, for the same reason. Wind Down walks 10
/// to 2 Hz over twenty minutes and nobody hears it move; the same eight
/// hertz stepped in one buffer is unmistakable, and a program the listener
/// catches switching is a program they turn off. Everything else about a
/// mode change is already gradual — the room cross-fades, the key glides,
/// the audio never stops — so the rate was the one seam left.
///
/// Three minutes is long enough that the walk is under a hertz a minute for
/// every pair of modes the day puts next to each other, and short enough to
/// be over long before the incoming mode's own arc has gone anywhere.
struct RateGlide: Sendable {
    static let seconds: Double = 3 * 60
    /// The rate the outgoing mode was playing at the moment it handed over.
    let from: Double

    /// The rate to play `elapsed` seconds into the new mode, on its way to
    /// where that mode's own arc wants to be.
    func rate(to target: Double, elapsed: Double) -> Double {
        let blend = min(1, max(0, elapsed / Self.seconds))
        return from + (target - from) * blend
    }

    func isOver(elapsed: Double) -> Bool { elapsed >= Self.seconds }
}

/// One point on a mode's arc, in seconds of play. A keyframe names only the
/// channels that move at that time: a channel no keyframe names is not part
/// of its track, so Deep Sleep's ninety-minute depth cycle and its
/// twenty-minute onset share one table without either bending the other.
struct Keyframe: Sendable {
    let time: Double
    let rate: Double?
    let depth: Double?
    let brightness: Double?
    let level: Double?

    init(
        _ time: Double, rate: Double? = nil, depth: Double? = nil,
        brightness: Double? = nil, level: Double? = nil
    ) {
        self.time = time
        self.rate = rate
        self.depth = depth
        self.brightness = brightness
        self.level = level
    }
}

/// A keyframe table compiled to one curve per channel.
struct Arc: Sendable {
    let rate: Track
    let depth: Track
    let brightness: Track
    let level: Track
    /// Play seconds after which nothing but the rate ramp moves; infinite
    /// while a track repeats.
    let settles: Double

    /// A track whose keyframes span `cycle` repeats over its last cycle's
    /// worth of them; one that ends sooner holds its last value, which is
    /// what keeps the Deep Sleep onset from starting over every ninety
    /// minutes.
    init(_ keyframes: [Keyframe], cycle: Double? = nil) {
        rate = Track(keyframes, \.rate, default: 0, shape: .linear, cycle: cycle)
        depth = Track(keyframes, \.depth, default: 0, cycle: cycle)
        brightness = Track(keyframes, \.brightness, default: 0, cycle: cycle)
        level = Track(keyframes, \.level, default: 1, cycle: cycle)
        settles = max(depth.settles, brightness.settles, level.settles)
    }
}

/// One channel of an arc.
struct Track: Sendable {
    private let curve: Curve
    /// Set when the track repeats: how long one turn takes, and when the
    /// first one begins. Deep Sleep's cycle starts at sleep onset rather
    /// than at the tap, so the repeat needs a start as well as a length.
    private let cycle: (length: Double, start: Double)?
    /// The last keyframe that names this channel. Zero when it never moves.
    let end: Double

    init(
        _ keyframes: [Keyframe], _ channel: KeyPath<Keyframe, Double?>,
        default fallback: Double, shape: Curve.Shape = .cosine, cycle: Double? = nil
    ) {
        let points = keyframes.compactMap { key in key[keyPath: channel].map { (key.time, $0) } }
        curve = Curve(points.isEmpty ? [(0, fallback)] : points, shape: shape)
        let last = points.last?.0 ?? 0
        end = last
        self.cycle = cycle.flatMap { $0 > 0 && last >= $0 ? (length: $0, start: last - $0) : nil }
    }

    /// Play seconds after which the track holds still.
    var settles: Double { cycle == nil ? end : .infinity }

    func value(at time: Double) -> Double {
        guard let cycle, time > cycle.start else { return curve.value(at: time) }
        return curve.value(at: cycle.start + (time - cycle.start).truncatingRemainder(dividingBy: cycle.length))
    }
}

/// A curve through points, each segment blended so the slope is zero at
/// every point: no corners for the ear to catch.
struct Curve: Sendable {
    /// How a segment gets from one point to the next. Levels take the raised
    /// cosine; a rate ramp is linear, so it walks at a steady hertz per minute.
    enum Shape: Sendable { case cosine, linear }

    private let points: [(x: Double, y: Double)]
    private let shape: Shape

    init(_ points: [(Double, Double)], shape: Shape = .cosine) {
        self.points = points.map { (x: $0.0, y: $0.1) }
        self.shape = shape
    }

    func value(at x: Double) -> Double {
        guard let first = points.first, let last = points.last else { return 0 }
        if x <= first.x { return first.y }
        if x >= last.x { return last.y }
        let i = points.firstIndex { $0.x > x }!
        let (a, b) = (points[i - 1], points[i])
        let t = (x - a.x) / (b.x - a.x)
        let blend = shape == .linear ? t : 0.5 - 0.5 * cos(t * .pi)
        return a.y + (b.y - a.y) * blend
    }
}
