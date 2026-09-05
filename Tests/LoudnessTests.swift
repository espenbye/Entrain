import Foundation
import Testing
@testable import Entrain

/// The four voices are trimmed to the same K-weighted loudness so switching
/// does not invite a volume change. Adjust `Trim` if a voice fails here.
struct LoudnessTests {
    static let sampleRate = 48000.0
    static let target = -22.0
    static let tolerance = 1.0

    @Test(arguments: Soundscape.allCases)
    func voiceSitsAtTargetLoudness(_ soundscape: Soundscape) {
        let measured = Meter.loudness(of: soundscape, sampleRate: Self.sampleRate, seconds: 60)
        #expect(
            abs(measured.lufs - Self.target) <= Self.tolerance,
            "\(soundscape.title) is \(measured.lufs) LUFS, target \(Self.target)"
        )
        #expect(measured.peak < 1, "\(soundscape.title) clips at \(measured.peak)")
    }
}

/// Renders a voice with the same slow drift the engine applies and reports
/// its ITU-R BS.1770 loudness and sample peak.
enum Meter {
    struct Reading {
        var lufs: Double
        var peak: Float
    }

    static func loudness(of soundscape: Soundscape, sampleRate: Double, seconds: Int) -> Reading {
        var rng = XorShift()
        var rain = Rain(sampleRate: sampleRate)
        var pad = Pad(sampleRate: sampleRate)
        var drone = Drone(sampleRate: sampleRate)
        var noise = Noise(sampleRate: sampleRate)
        var weighting = KWeighting()
        var sumSquares = 0.0
        var peak: Float = 0

        let block = 512
        let warmup = Int(sampleRate) * 2
        let frames = Int(sampleRate) * seconds
        var i = 0
        while i < frames + warmup {
            let lfo = sin(2 * Float.pi * Float(i) / (Float(sampleRate) * 900))
            rain.prepare(lfo: lfo)
            pad.prepare(lfo: lfo)
            drone.prepare(lfo: lfo)
            for _ in 0..<block {
                let s: Float = switch soundscape {
                case .rain: rain.next(rng: &rng)
                case .pad: pad.next(rng: &rng)
                case .drone: drone.next()
                case .noise: noise.next(rng: &rng)
                }
                if i >= warmup {
                    peak = max(peak, abs(s))
                    let w = weighting.process(s)
                    sumSquares += Double(w * w)
                }
                i += 1
            }
        }
        let counted = Double(i - warmup)
        return Reading(lufs: -0.691 + 10 * log10(sumSquares / counted), peak: peak)
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
