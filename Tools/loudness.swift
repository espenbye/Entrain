import Foundation

/// Renders each voice unmodulated and reports its ITU-R BS.1770 K-weighted
/// loudness and peak, so the trims in `Voices.swift` can be matched.
///
///     swiftc -O Sources/Audio/DSP.swift Sources/Audio/Voices.swift Tools/loudness.swift -o /tmp/loudness && /tmp/loudness
@main
struct Loudness {
    static let sampleRate = 48000.0
    static let seconds = 120

    static func main() {
        var rng = XorShift()
        var rain = Rain(sampleRate: sampleRate)
        var pad = Pad(sampleRate: sampleRate)
        var drone = Drone(sampleRate: sampleRate)
        var noise = Noise(sampleRate: sampleRate)

        report("rain") { rain.next(lfo: $0, rng: &rng) }
        report("pad") { pad.next(lfo: $0, rng: &rng) }
        report("drone") { drone.next(lfo: $0) }
        report("noise") { _ in noise.next(rng: &rng) }
    }

    static func report(_ name: String, _ voice: (Float) -> Float) {
        var weighting = KWeighting()
        var sumSquares = 0.0
        var peak: Float = 0
        let frames = Int(sampleRate) * seconds
        let warmup = Int(sampleRate) * 2
        for i in 0..<(frames + warmup) {
            let lfo = sin(2 * Float.pi * Float(i) / (Float(sampleRate) * 900))
            let s = voice(lfo)
            if i < warmup { continue }
            peak = max(peak, abs(s))
            let w = weighting.process(s)
            sumSquares += Double(w * w)
        }
        let lufs = -0.691 + 10 * log10(sumSquares / Double(frames))
        let peakdB = 20 * log10(Double(peak))
        print(String(format: "%-6@ %7.2f LUFS  peak %6.2f dBFS", name as NSString, lufs, peakdB))
    }
}

/// BS.1770-4 pre-filter pair at 48 kHz: high shelf, then high-pass.
struct KWeighting {
    private var shelf = Biquad(
        b0: 1.53512485958697, b1: -2.69169618940638, b2: 1.19839281085285,
        a1: -1.69065929318241, a2: 0.73248077421585
    )
    private var highpass = Biquad(
        b0: 1.0, b1: -2.0, b2: 1.0,
        a1: -1.99004745483398, a2: 0.99007225036621
    )

    mutating func process(_ x: Float) -> Float {
        highpass.process(shelf.process(x))
    }
}

struct Biquad {
    let b0, b1, b2, a1, a2: Float
    private var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0

    init(b0: Float, b1: Float, b2: Float, a1: Float, a2: Float) {
        self.b0 = b0; self.b1 = b1; self.b2 = b2; self.a1 = a1; self.a2 = a2
    }

    mutating func process(_ x: Float) -> Float {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x
        y2 = y1; y1 = y
        return y
    }
}
