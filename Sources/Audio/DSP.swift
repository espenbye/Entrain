import Foundation

let twoPi = Float(2 * Double.pi)

/// Shared sine wavetable for the render thread. Linear interpolation over
/// 4096 points keeps distortion below -80 dB, far under the noise floor of
/// every voice, and replaces a libm call with two loads and a multiply.
enum SineTable {
    private static let size = 4096
    private static let mask = size - 1
    private static let table: [Float] = (0..<size).map {
        Float(Foundation.sin(2 * Double.pi * Double($0) / Double(size)))
    }

    /// `cycles` is a phase in cycles, so 1.0 is one full period. Any value
    /// at or above zero wraps; a `Phasor` output times a harmonic number is fine.
    @inline(__always)
    static func sin(cycles: Float) -> Float {
        let x = cycles * Float(size)
        let i = Int(x)
        let f = x - Float(i)
        let a = table[i & mask]
        let b = table[(i + 1) & mask]
        return a + (b - a) * f
    }
}

/// One-pole parameter smoother. Call `next()` once per sample.
struct Smoother {
    var value: Float
    var target: Float
    let k: Float

    init(_ initial: Float, seconds: Double, sampleRate: Double) {
        value = initial
        target = initial
        k = Float(1 - exp(-1 / (seconds * sampleRate)))
    }

    mutating func next() -> Float {
        value += (target - value) * k
        return value
    }
}

struct Phasor {
    var phase: Float = 0

    mutating func next(_ increment: Float) -> Float {
        let p = phase
        phase += increment
        if phase >= 1 { phase -= 1 }
        return p
    }
}

/// Fast pseudo random source for noise. Never use the system RNG per sample.
struct XorShift {
    var state: UInt32 = 0x9E37_79B9

    mutating func next() -> UInt32 {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        return state
    }

    /// Uniform in -1...1.
    mutating func bipolar() -> Float {
        Float(Int32(bitPattern: next())) / Float(Int32.max)
    }

    /// Uniform in 0..<1.
    mutating func unit() -> Float {
        Float(next() >> 8) / Float(1 << 24)
    }
}

/// Paul Kellet's pink noise approximation.
struct PinkNoise {
    private var b: (Float, Float, Float, Float, Float, Float, Float) = (0, 0, 0, 0, 0, 0, 0)

    mutating func next(_ rng: inout XorShift) -> Float {
        let w = rng.bipolar()
        b.0 = 0.99886 * b.0 + w * 0.0555179
        b.1 = 0.99332 * b.1 + w * 0.0750759
        b.2 = 0.96900 * b.2 + w * 0.1538520
        b.3 = 0.86650 * b.3 + w * 0.3104856
        b.4 = 0.55000 * b.4 + w * 0.5329522
        b.5 = -0.7616 * b.5 - w * 0.0168980
        let pink = b.0 + b.1 + b.2 + b.3 + b.4 + b.5 + b.6 + w * 0.5362
        b.6 = w * 0.115926
        return pink * 0.11
    }
}

struct OnePoleLowpass {
    var z: Float = 0

    static func coefficient(cutoff: Float, sampleRate: Float) -> Float {
        1 - exp(-twoPi * cutoff / sampleRate)
    }

    mutating func process(_ x: Float, _ coefficient: Float) -> Float {
        z += (x - z) * coefficient
        return z
    }
}

/// Two-pole state-variable filter, Chamberlin's form, bandpass tap only.
/// Two multiply-adds and two adds a sample with no libm anywhere: the tuning
/// coefficient is a sine, which the table already has.
///
/// It is deliberately not a high-Q resonator. A ring long enough to hear as
/// a tail would need a Q in the hundreds, and a filter that narrow passes a
/// sine however it is excited, which is the sound this replaced. Held to
/// single figures it colours a burst of noise instead of replacing it.
struct Resonator {
    private var low: Float = 0
    private var band: Float = 0

    /// The tuning coefficient for a centre frequency. Chamberlin's form goes
    /// unstable as the centre approaches a sixth of the sample rate, so the
    /// centre is clamped there; nothing asks for anywhere near it.
    static func frequency(_ hz: Float, sampleRate: Float) -> Float {
        2 * SineTable.sin(cycles: 0.5 * min(hz, sampleRate / 6) / sampleRate)
    }

    /// `q` is the reciprocal of Q, so larger is broader and more damped.
    static func damping(q: Float) -> Float { 1 / max(0.5, q) }

    mutating func reset() {
        low = 0
        band = 0
    }

    @inline(__always)
    mutating func process(_ x: Float, frequency f: Float, damping d: Float) -> Float {
        low += f * band
        let high = x - low - d * band
        band += f * high
        return band * d
    }
}

/// The gate applied to one modulation cycle. The curve is the raised cosine
/// the modulation has always used; what moves is where in the cycle it peaks.
/// `peak` is that point as a fraction of the period: at 0.5 the warp below is
/// the identity and the shape is exactly the old sine, and under it the
/// envelope rises fast and falls slowly. A sharp onset drives a stronger
/// steady-state response than a symmetric swell and reads as a pulse rather
/// than as tremolo, which is what 16 Hz and up need.
///
/// The warp is a Möbius map, which buys three things a piecewise curve does
/// not. It is smooth in phase, with zero slope at both ends of the cycle at
/// every setting, so there is no corner to catch however sharp the pulse. It
/// is smooth in `peak` as well, so the setting can be smoothed per sample
/// from one mode's shape to the next without a discontinuity appearing on
/// the way. And it costs one divide and two multiplies over the lookup that
/// was there before.
///
/// The trough is `peak` deep whatever the shape, so the shape changes when
/// the gain falls, never how far. Its mean does move: a sharp pulse spends
/// less of the cycle attenuating, which lifts the modulated band by up to
/// half a decibel at the settings in `Mode.envelope`.
struct PulseShape {
    /// Where the envelope peaks, followed over 0.2 s so a mode change morphs
    /// the shape rather than stepping it.
    private var peak: Smoother

    init(peak: Float, sampleRate: Double) {
        self.peak = Smoother(Self.clamped(peak), seconds: 0.2, sampleRate: sampleRate)
    }

    var target: Float {
        get { peak.target }
        set { peak.target = Self.clamped(newValue) }
    }

    /// Away from the ends the warp keeps its shape; at them it degenerates.
    private static func clamped(_ peak: Float) -> Float { min(0.9, max(0.1, peak)) }

    /// 0 at the start of the cycle, 1 at `peak`, back to 0 at the end.
    /// `phase` is in cycles, 0..<1.
    @inline(__always)
    mutating func next(phase: Float) -> Float {
        let a = peak.next()
        let warped = phase * (1 - a) / (a + phase * (1 - 2 * a))
        return 0.5 - 0.5 * SineTable.sin(cycles: warped + 0.25)
    }
}

/// A small stereo diffuser, for the platform with no room to put a source in.
/// The watch has no environment node and no reverb unit, so its bed went to
/// the mixer as dry as it was synthesised: two ears hearing exactly the same
/// signal, which is the one thing a real space never does.
///
/// This is not a reverb and does not try to be. A pre-delay into two
/// Schroeder allpasses per side, at lengths that share no factors between
/// the ears, decorrelates the two channels and puts a short scatter behind
/// the bed — enough for it to sit somewhere rather than inside the head, at
/// four multiply-adds a sample. The allpasses pass every frequency at full
/// level and only rearrange phase, so the bed's spectrum and its measured
/// loudness are unchanged; a lowpass on the tail keeps the scatter from
/// reading as metallic.
struct Diffuser {
    /// Delay lengths in milliseconds. Mutual primes as sample counts at any
    /// ordinary rate, so no two taps line up and ring.
    private static let predelay = (left: 7.0, right: 9.1)
    private static let allpasses = (left: (13.7, 19.3), right: (15.1, 21.7))
    private static let feedback: Float = 0.5

    private var left: Side
    private var right: Side
    private var wet: Smoother

    init(sampleRate: Double, blend: Float) {
        left = Side(
            predelay: Self.predelay.left, allpasses: Self.allpasses.left, sampleRate: sampleRate
        )
        right = Side(
            predelay: Self.predelay.right, allpasses: Self.allpasses.right, sampleRate: sampleRate
        )
        wet = Smoother(blend, seconds: 1.5, sampleRate: sampleRate)
    }

    /// How much of the room comes through, 0...1. Followed over a second and
    /// a half, so a mode change moves the space rather than switching it.
    var target: Float {
        get { wet.target }
        set { wet.target = min(1, max(0, newValue)) }
    }

    /// Dry and wet are mixed at equal power, so the blend moves where the
    /// bed sits without moving how loud it is.
    @inline(__always)
    mutating func next(_ l: Float, _ r: Float) -> (Float, Float) {
        let blend = wet.next()
        let wetGain = SineTable.sin(cycles: 0.25 * blend)
        let dryGain = SineTable.sin(cycles: 0.25 * blend + 0.25)
        return (
            l * dryGain + left.next(l) * wetGain,
            r * dryGain + right.next(r) * wetGain
        )
    }

    /// One ear: a delay into two allpasses, with the tail rolled off.
    private struct Side {
        private var predelay: Delay
        private var first: Allpass
        private var second: Allpass
        private var tone = OnePoleLowpass()
        private let toneCoefficient: Float

        init(predelay ms: Double, allpasses: (Double, Double), sampleRate: Double) {
            self.predelay = Delay(milliseconds: ms, sampleRate: sampleRate)
            first = Allpass(milliseconds: allpasses.0, sampleRate: sampleRate)
            second = Allpass(milliseconds: allpasses.1, sampleRate: sampleRate)
            toneCoefficient = OnePoleLowpass.coefficient(cutoff: 3000, sampleRate: Float(sampleRate))
        }

        @inline(__always)
        mutating func next(_ x: Float) -> Float {
            tone.process(second.next(first.next(predelay.next(x))), toneCoefficient)
        }
    }

    /// A fixed delay line. Its buffer is taken once, at init.
    private struct Delay {
        private var buffer: [Float]
        private var write = 0

        init(milliseconds: Double, sampleRate: Double) {
            buffer = [Float](repeating: 0, count: max(1, Int(milliseconds * sampleRate / 1000)))
        }

        @inline(__always)
        mutating func next(_ x: Float) -> Float {
            let out = buffer[write]
            buffer[write] = x
            write += 1
            if write == buffer.count { write = 0 }
            return out
        }
    }

    /// A Schroeder allpass: flat in magnitude, so it scatters a signal in
    /// time without colouring it.
    private struct Allpass {
        private var buffer: [Float]
        private var write = 0

        init(milliseconds: Double, sampleRate: Double) {
            buffer = [Float](repeating: 0, count: max(1, Int(milliseconds * sampleRate / 1000)))
        }

        @inline(__always)
        mutating func next(_ x: Float) -> Float {
            let delayed = buffer[write]
            let stored = x + Diffuser.feedback * delayed
            buffer[write] = stored
            write += 1
            if write == buffer.count { write = 0 }
            return delayed - Diffuser.feedback * stored
        }
    }
}
