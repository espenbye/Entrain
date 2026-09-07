import Foundation

/// The intervals and the register the tuned voices share in a mode. Mood is
/// carried by the interval set more than by any filter: a minor scale reads
/// melancholic wherever the cutoff sits, which is the wrong thing to hand
/// someone who asked to be woken up. The pad and the drone read the same
/// one, so the two can no longer end up a fourth apart by accident.
///
/// Register is part of it. The tonic moves only a few semitones between the
/// three, enough to sit differently without moving either voice far enough
/// to need its own trim; `LoudnessTests` measures all three.
enum Tonality: Int, CaseIterable, Sendable {
    /// Fourths and fifths and no third at all, so nothing states major or
    /// minor. Nothing to feel about, and wide enough spacing that little of
    /// the pad lands where speech does.
    case open
    /// Major pentatonic. However the pad walks it every pair of degrees is
    /// consonant, and there is no leading tone anywhere to pull.
    case warm
    /// Minor pentatonic, low and narrow: the dark end, and near enough to
    /// static that a note change barely registers.
    case dark

    /// The tonic in Hz, in the octave the drone holds. The pad plays the
    /// same tonic an octave above it.
    var root: Float {
        switch self {
        case .open: 73.42   // D2
        case .warm: 82.41   // E2
        case .dark: 65.41   // C2
        }
    }

    /// Semitones above the pad's root. Static storage: a literal here would
    /// allocate on the render thread every time the pad asked.
    var degrees: [Float] {
        switch self {
        case .open: Self.openDegrees
        case .warm: Self.warmDegrees
        case .dark: Self.darkDegrees
        }
    }

    private static let openDegrees: [Float] = [0, 5, 7, 12, 17, 19, 24]
    private static let warmDegrees: [Float] = [0, 2, 4, 7, 9, 12, 14, 16, 19, 21]
    private static let darkDegrees: [Float] = [0, 3, 5, 7, 10, 12, 15, 17, 19, 22]
}

extension Mode {
    /// The intervals and register the pad and the drone share here. Only a
    /// filter cutoff used to move between modes, which left every mode on the
    /// same minor pentatonic: melancholic under Wake, and arguable under
    /// Relax. Work gets an open set with no third to read anything into, rest
    /// and waking a warm one, and what ends in bed keeps the dark one. It
    /// lives here rather than beside the rest of `Mode`, which the widget
    /// compiles too and which has no business knowing about oscillators.
    var tonality: Tonality {
        switch self {
        case .focus, .gamma: .open
        case .relax, .meditate, .wake: .warm
        case .windDown, .sleep, .deepSleep: .dark
        }
    }
}

/// The impacts scattered over the rain, kept apart from the bed they fall on
/// so each can be reasoned about, and measured, on its own.
///
/// The drops used to be sine pings, and a sine is the one thing a raindrop
/// never sounds like: a drop is an impact, broadband and gone. Each one here
/// is a burst of noise through a resonator, which lands as a click coloured
/// by whatever it fell on rather than as a tone.
///
/// The bigger tell was uniformity. Real rain is heavy-tailed — mostly fine
/// drops with the occasional fat one, and the fat ones are louder, lower and
/// longer together, because they are the same physical fact seen three ways.
/// One draw per drop sets all three, so they stay correlated, and a second
/// loosens the correlation enough that it does not read as a single knob
/// being turned. The rate drifts too: rain that arrives at a metronomic rate
/// is a shaker, not weather.
struct Drops {
    private var pool = [Drop](repeating: Drop(), count: 8)
    /// Multiplier on the arrival rate, redrawn every few seconds and glided
    /// to, so the fall thickens and thins the way real rain does.
    private var gust: Smoother
    private var untilGust: Int
    private let gustPeriod: Int
    private let perSample: Float
    /// Decay coefficients from a tick to a splash, geometrically spaced.
    /// `exp` is a libm call, so the eight the render path can ask for are
    /// worked out here once instead.
    private let decays: [Float]
    private let sampleRate: Float

    private struct Drop {
        var filter = Resonator()
        var frequency: Float = 0
        var damping: Float = 0
        var level: Float = 0
        var decay: Float = 0
    }

    /// Below this a drop is 66 dB down on its own onset and the slot is free.
    static let silence: Float = 0.0005

    init(sampleRate: Double) {
        self.sampleRate = Float(sampleRate)
        // The gust multiplier averages 1.5, so this is 27 drops a second in
        // the mean. Noise bursts crowd far better than pings did, which is
        // what lets the fall be dense enough to read as rain at all.
        perSample = 18 / Float(sampleRate)
        gust = Smoother(1.5, seconds: 1.5, sampleRate: sampleRate)
        gustPeriod = Int(sampleRate * 2.5)
        untilGust = 0
        decays = (0..<8).map { i in
            let seconds = 0.004 * pow(1.42, Double(i))   // 4 ms out to 45 ms
            return Float(exp(-1 / (seconds * sampleRate)))
        }
    }

    mutating func next(rng: inout XorShift) -> Float {
        untilGust -= 1
        if untilGust <= 0 {
            gust.target = 0.4 + 2.2 * rng.unit()
            untilGust = gustPeriod
        }
        if rng.unit() < perSample * gust.next(), let free = pool.firstIndex(where: { $0.level < Self.silence }) {
            // Reciprocal of a uniform: mostly near one, with a tail that
            // reaches four times that and no further. Everything about the
            // drop follows from it, so a fat drop is a fat drop in all of
            // level, pitch and length at once.
            let size = 1 / (0.32 + rng.unit())
            let jitter = 0.6 + 0.8 * rng.unit()
            let centre = min(7000, max(700, 4000 / size * jitter))
            let length = Int(min(7, max(0, (size - 0.76) * 2.2 + (jitter - 1) * 2 + 0.5)))
            pool[free].filter.reset()
            pool[free].frequency = Resonator.frequency(centre, sampleRate: sampleRate)
            pool[free].damping = Resonator.damping(q: 2 + 6 * rng.unit())
            // A bandpass passes a slice of the noise proportional to its own
            // width, so a low drop keeps back less of what it was given than
            // a high one, and squaring the size pays that back with enough
            // left over to leave about 18 dB between the finest drop and the
            // fattest. The constant is what brings a burst of noise up to the
            // level the sine it replaced arrived at.
            pool[free].level = 0.2 * size * size
            pool[free].decay = decays[length]
        }
        var s: Float = 0
        for i in pool.indices where pool[i].level >= Self.silence {
            s += pool[i].filter.process(rng.bipolar() * pool[i].level,
                                        frequency: pool[i].frequency,
                                        damping: pool[i].damping)
            pool[i].level *= pool[i].decay
        }
        return s
    }
}

/// Filtered pink noise with `Drops` falling on it.
struct Rain {
    private var noise = PinkNoise()
    private var lowpass = OnePoleLowpass()
    private var coefficient: Float = 0
    private var drops: Drops
    private let sampleRate: Float

    init(sampleRate: Double) {
        self.sampleRate = Float(sampleRate)
        drops = Drops(sampleRate: sampleRate)
        prepare(lfo: 0)
    }

    /// Once per block. `lfo` in -1...1 moves the filter cutoff; `brightness`
    /// scales it, 1 being where the voice was tuned.
    mutating func prepare(lfo: Float, brightness: Float = 1) {
        coefficient = OnePoleLowpass.coefficient(cutoff: (700 + 300 * lfo) * brightness, sampleRate: sampleRate)
    }

    mutating func next(rng: inout XorShift) -> Float {
        (lowpass.process(noise.next(&rng), coefficient) * 1.6 + drops.next(rng: &rng)) * Trim.rain
    }
}

/// Four detuned sine pairs walking the mode's scale, an octave above the
/// root the drone holds.
struct Pad {
    private struct Voice {
        var a = Phasor()
        var b = Phasor()
        var increment: Float = 0
        var level: Smoother
        var pendingNote: Int?
        /// Samples until this voice starts moving to a new tonality. Zero
        /// when there is nothing to move to.
        var retuneIn = 0
    }

    private var voices: [Voice]
    private var lowpass = OnePoleLowpass()
    private var coefficient: Float = 0
    private var untilChange: Int
    private var tonality: Tonality
    /// The current tonality's degrees, held here rather than reached for
    /// through the enum, so the render path only touches stored properties.
    private var degrees: [Float]
    private let sampleRate: Float
    /// How far apart the four voices start moving when the tonality changes.
    /// Retuning fades a voice out and back, so staggering them keeps at most
    /// two down at once instead of taking the whole pad away for three seconds.
    private let retuneStagger: Int

    init(sampleRate: Double, tonality: Tonality = .open) {
        self.sampleRate = Float(sampleRate)
        self.tonality = tonality
        degrees = tonality.degrees
        untilChange = Int(sampleRate * 4)
        retuneStagger = Int(sampleRate * 0.6)
        var rng = XorShift(state: 0xA53C_9F17)
        let scale = tonality.degrees
        voices = (0..<4).map { i in
            var v = Voice(level: Smoother(1, seconds: 3, sampleRate: sampleRate))
            let note = i * scale.count / 4 + Int(rng.unit() * 2)
            v.increment = Pad.frequency(note: note, of: tonality, degrees: scale) / Float(sampleRate)
            return v
        }
        prepare(lfo: 0, tonality: tonality)
    }

    /// The pad sits an octave above the tonic the drone holds.
    private static func frequency(note: Int, of tonality: Tonality, degrees: [Float]) -> Float {
        2 * tonality.root * pow(2, degrees[note % degrees.count] / 12)
    }

    /// Once per block. `lfo` in -1...1 moves the filter cutoff; `brightness`
    /// scales it, 1 being where the voice was tuned. A new `tonality` sends
    /// the four voices to it one after another.
    mutating func prepare(lfo: Float, brightness: Float = 1, tonality: Tonality) {
        coefficient = OnePoleLowpass.coefficient(cutoff: (900 + 500 * lfo) * brightness, sampleRate: sampleRate)
        guard tonality != self.tonality else { return }
        self.tonality = tonality
        degrees = tonality.degrees
        for i in voices.indices { voices[i].retuneIn = i * retuneStagger + 1 }
    }

    mutating func next(rng: inout XorShift) -> Float {
        untilChange -= 1
        if untilChange <= 0 {
            untilChange = Int(sampleRate * (8 + 12 * rng.unit()))
            let i = Int(rng.unit() * 4) % 4
            if voices[i].pendingNote == nil {
                voices[i].pendingNote = Int(rng.unit() * Float(degrees.count))
                voices[i].level.target = 0
            }
        }

        var s: Float = 0
        for i in voices.indices {
            if voices[i].retuneIn > 0 {
                voices[i].retuneIn -= 1
                if voices[i].retuneIn == 0, voices[i].pendingNote == nil {
                    voices[i].pendingNote = i * degrees.count / 4
                    voices[i].level.target = 0
                }
            }
            let level = voices[i].level.next()
            if let note = voices[i].pendingNote, level < 0.005 {
                voices[i].increment = Pad.frequency(note: note, of: tonality, degrees: degrees) / sampleRate
                voices[i].pendingNote = nil
                voices[i].level.target = 1
            }
            let inc = voices[i].increment
            let pa = voices[i].a.next(inc * 1.003)
            let pb = voices[i].b.next(inc * 0.997)
            let tone = SineTable.sin(cycles: pa) + SineTable.sin(cycles: pb) + 0.25 * SineTable.sin(cycles: 2 * pa)
            s += tone * level
        }
        return lowpass.process(s, coefficient) * Trim.pad
    }
}

/// The mode's tonic plus its fifth, with slowly beating harmonics.
struct Drone {
    /// Harmonic gains 1/n^1.4 for n in 1...6.
    private static let harmonicGains: [Float] = (1...6).map { pow(Float($0), -1.4) }

    private var root = Phasor()
    private var fifth = Phasor()
    private var fifthDetuned = Phasor()
    private var lowpass = OnePoleLowpass()
    private var coefficient: Float = 0
    /// How far the second fifth sits off the first, in Hz: what beats.
    private var detune: Float = 0
    /// The tonic. Glided rather than stepped, so a mode change moves the
    /// drone without a discontinuity and without a fade.
    private var base: Smoother
    private var tonality: Tonality
    private let perSample: Float

    init(sampleRate: Double, tonality: Tonality = .open) {
        self.tonality = tonality
        perSample = 1 / Float(sampleRate)
        base = Smoother(tonality.root, seconds: 2, sampleRate: sampleRate)
        prepare(lfo: 0, tonality: tonality)
    }

    /// Once per block. `lfo` in -1...1 moves the filter cutoff and the beat
    /// rate; `brightness` scales the cutoff, 1 being where the voice was
    /// tuned. A new `tonality` starts the glide to its tonic.
    mutating func prepare(lfo: Float, brightness: Float = 1, tonality: Tonality) {
        coefficient = OnePoleLowpass.coefficient(
            cutoff: (500 + 200 * lfo) * brightness, sampleRate: 1 / perSample
        )
        detune = 0.3 + 0.2 * lfo
        guard tonality != self.tonality else { return }
        self.tonality = tonality
        base.target = tonality.root
    }

    mutating func next() -> Float {
        let hz = base.next()
        let r = root.next(hz * perSample)
        let f = fifth.next(hz * 1.5 * perSample)
        let fd = fifthDetuned.next((hz * 1.5 + detune) * perSample)

        var s: Float = 0
        for (i, gain) in Drone.harmonicGains.enumerated() {
            s += SineTable.sin(cycles: Float(i + 1) * r) * gain
        }
        s += 0.5 * SineTable.sin(cycles: f) + 0.5 * SineTable.sin(cycles: fd)
        return lowpass.process(s, coefficient) * Trim.drone
    }
}

/// Brown noise with a little pink over it. White noise through a one-pole
/// at 60 Hz gives the 6 dB per octave slope; a matching high-pass at 40 Hz
/// drops the rumble speakers cannot reproduce and that would eat headroom.
/// Brown alone has almost nothing left where voices, traffic and doors sit,
/// so a measure of pink fills the mids in: at the same loudness the bed
/// masks more of the room. A one-pole lowpass on top is what the sleep
/// onset darkens, `brightness` moving it half an octave each way from
/// 1.2 kHz. No events, no drift.
struct Noise {
    /// Pink against brown, before either is trimmed. Brown carries the
    /// weight; pink lifts 300 Hz to 2 kHz by two to four decibels.
    private static let pinkBlend: Float = 0.1

    private var pink = PinkNoise()
    private var slope = OnePoleLowpass()
    private var rumble = OnePoleLowpass()
    private var lowpass = OnePoleLowpass()
    private let slopeCoefficient: Float
    private let rumbleCoefficient: Float
    private var coefficient: Float = 0
    private let sampleRate: Float

    init(sampleRate: Double) {
        self.sampleRate = Float(sampleRate)
        slopeCoefficient = OnePoleLowpass.coefficient(cutoff: 60, sampleRate: Float(sampleRate))
        rumbleCoefficient = OnePoleLowpass.coefficient(cutoff: 40, sampleRate: Float(sampleRate))
        prepare()
    }

    /// Once per block. `brightness` scales the lowpass, 1 being where the
    /// voice was tuned.
    mutating func prepare(brightness: Float = 1) {
        coefficient = OnePoleLowpass.coefficient(cutoff: 1200 * brightness, sampleRate: sampleRate)
    }

    mutating func next(rng: inout XorShift) -> Float {
        let brown = slope.process(rng.bipolar(), slopeCoefficient)
        let s = brown + pink.next(&rng) * Self.pinkBlend
        return lowpass.process(s - rumble.process(s, rumbleCoefficient), coefficient) * Trim.noise
    }
}

/// Output trims that put the four voices at the same K-weighted loudness.
/// `EntrainTests/LoudnessTests` fails if a voice drifts from the target.
enum Trim {
    static let rain: Float = 0.489
    static let pad: Float = 0.0497
    static let drone: Float = 0.108
    static let noise: Float = 3.48
}
