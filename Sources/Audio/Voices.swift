import Foundation

/// Filtered pink noise with sparse high droplets.
struct Rain {
    private var noise = PinkNoise()
    private var lowpass = OnePoleLowpass()
    private var drops = [Drop](repeating: Drop(), count: 8)
    private let dropsPerSample: Float
    private let dropDecay: Float
    private let sampleRate: Float

    private struct Drop {
        var phasor = Phasor()
        var increment: Float = 0
        var level: Float = 0
    }

    init(sampleRate: Double) {
        self.sampleRate = Float(sampleRate)
        dropsPerSample = 10 / Float(sampleRate)
        dropDecay = Float(exp(-1 / (0.025 * sampleRate)))
    }

    /// `lfo` in -1...1 moves the filter cutoff.
    mutating func next(lfo: Float, rng: inout XorShift) -> Float {
        let cutoff = 700 + 300 * lfo
        var s = lowpass.process(noise.next(&rng), OnePoleLowpass.coefficient(cutoff: cutoff, sampleRate: sampleRate))
        s *= 1.6

        if rng.unit() < dropsPerSample, let free = drops.firstIndex(where: { $0.level < 0.001 }) {
            drops[free].increment = (1500 + 3000 * rng.unit()) / sampleRate
            drops[free].level = 0.08 + 0.06 * rng.unit()
        }
        for i in drops.indices where drops[i].level >= 0.001 {
            s += sin(twoPi * drops[i].phasor.next(drops[i].increment)) * drops[i].level
            drops[i].level *= dropDecay
        }
        return s
    }
}

/// Four detuned sine pairs walking a minor pentatonic scale.
struct Pad {
    private static let scale: [Float] = [0, 3, 5, 7, 10, 12, 15, 17, 19, 22]
    private static let root: Float = 110

    private struct Voice {
        var a = Phasor()
        var b = Phasor()
        var increment: Float = 0
        var level: Smoother
        var pendingNote: Int?
    }

    private var voices: [Voice]
    private var lowpass = OnePoleLowpass()
    private var untilChange: Int
    private let sampleRate: Float

    init(sampleRate: Double) {
        self.sampleRate = Float(sampleRate)
        untilChange = Int(sampleRate * 4)
        var rng = XorShift(state: 0xA53C_9F17)
        voices = (0..<4).map { i in
            var v = Voice(level: Smoother(1, seconds: 3, sampleRate: sampleRate))
            v.increment = Pad.frequency(note: i * 2 + Int(rng.unit() * 2)) / Float(sampleRate)
            return v
        }
    }

    private static func frequency(note: Int) -> Float {
        root * pow(2, scale[note % scale.count] / 12)
    }

    mutating func next(lfo: Float, rng: inout XorShift) -> Float {
        untilChange -= 1
        if untilChange <= 0 {
            untilChange = Int(sampleRate * (8 + 12 * rng.unit()))
            let i = Int(rng.unit() * 4) % 4
            if voices[i].pendingNote == nil {
                voices[i].pendingNote = Int(rng.unit() * Float(Pad.scale.count))
                voices[i].level.target = 0
            }
        }

        var s: Float = 0
        for i in voices.indices {
            let level = voices[i].level.next()
            if let note = voices[i].pendingNote, level < 0.005 {
                voices[i].increment = Pad.frequency(note: note) / sampleRate
                voices[i].pendingNote = nil
                voices[i].level.target = 1
            }
            let inc = voices[i].increment
            let pa = voices[i].a.next(inc * 1.003)
            let pb = voices[i].b.next(inc * 0.997)
            let tone = sin(twoPi * pa) + sin(twoPi * pb) + 0.25 * sin(twoPi * 2 * pa)
            s += tone * level
        }
        let cutoff = 900 + 500 * lfo
        return lowpass.process(s * 0.12, OnePoleLowpass.coefficient(cutoff: cutoff, sampleRate: sampleRate))
    }
}

/// Root plus fifth with slowly beating harmonics.
struct Drone {
    private var root = Phasor()
    private var fifth = Phasor()
    private var fifthDetuned = Phasor()
    private var lowpass = OnePoleLowpass()
    private let sampleRate: Float

    init(sampleRate: Double) {
        self.sampleRate = Float(sampleRate)
    }

    mutating func next(lfo: Float) -> Float {
        let base: Float = 82.41
        let r = root.next(base / sampleRate)
        let f = fifth.next(base * 1.5 / sampleRate)
        let fd = fifthDetuned.next((base * 1.5 + 0.3 + 0.2 * lfo) / sampleRate)

        var s: Float = 0
        for n in 1...6 {
            s += sin(twoPi * Float(n) * r) / pow(Float(n), 1.4)
        }
        s += 0.5 * sin(twoPi * f) + 0.5 * sin(twoPi * fd)
        let cutoff = 500 + 200 * lfo
        return lowpass.process(s * 0.2, OnePoleLowpass.coefficient(cutoff: cutoff, sampleRate: sampleRate))
    }
}
