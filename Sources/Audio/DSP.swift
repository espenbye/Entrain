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
