import Foundation

let twoPi = Float(2 * Double.pi)

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
