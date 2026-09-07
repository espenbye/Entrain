import Foundation
import Testing
@testable import Entrain

/// The shape of one modulation cycle. `PulseShape` warps the phase of a
/// raised cosine, so what has to hold is that the curve still reaches 0 and
/// 1, peaks where the mode asked, joins smoothly at the cycle boundary, and
/// does not spread the envelope into the band the ear hears as rough.
struct EnvelopeTests {
    static let sampleRate = 48000.0
    static let points = 4096

    /// One cycle of a shape. `PulseShape` starts settled on the peak it is
    /// built with, so this is the shape at rest.
    static func cycle(peak: Float) -> [Float] {
        var shape = PulseShape(peak: peak, sampleRate: sampleRate)
        return (0..<points).map { shape.next(phase: Float($0) / Float(points)) }
    }

    @Test(arguments: Mode.allCases)
    func envelopeSpansTheWholeRangeAndPeaksWhereTheModeAsked(_ mode: Mode) {
        let curve = Self.cycle(peak: Float(mode.envelope))
        let top = curve.firstIndex(of: curve.max()!)!
        #expect(curve.min()! < 0.0001, "\(mode.title) never closes: \(curve.min()!)")
        #expect(curve.max()! > 0.9999, "\(mode.title) never opens: \(curve.max()!)")
        #expect(
            abs(Double(top) / Double(Self.points) - mode.envelope) < 0.01,
            "\(mode.title) peaks at \(Double(top) / Double(Self.points)), asked for \(mode.envelope)"
        )
    }

    /// A corner anywhere in the cycle is a click at the modulation rate. The
    /// warp is smooth in phase and flat at both ends, so the second
    /// difference stays small everywhere, including across the wrap.
    @Test(arguments: Mode.allCases)
    func envelopeHasNoCorner(_ mode: Mode) {
        let curve = Self.cycle(peak: Float(mode.envelope))
        var worst: Float = 0
        for i in curve.indices {
            let before = curve[(i + Self.points - 1) % Self.points]
            let after = curve[(i + 1) % Self.points]
            worst = max(worst, abs(after - 2 * curve[i] + before))
        }
        #expect(worst < 0.001, "\(mode.title) bends by \(worst) in one step")
    }

    /// The trough is the same depth whatever the shape: a mode picks when
    /// the gain falls, never how far, so intensity keeps its meaning.
    @Test func everyShapeReachesTheSameDepth() {
        for peak in stride(from: Float(0.15), through: 0.5, by: 0.05) {
            let curve = Self.cycle(peak: peak)
            #expect(abs(curve.max()! - 1) < 0.0005, "peak \(peak) tops out at \(curve.max()!)")
        }
    }

    /// Gamma's guard, and the sleep beds': 40 Hz modulation already sits in
    /// the roughness band, so its shape may not put more energy there than
    /// the plain sine did at the same depth, and nothing that ends in bed may
    /// gain any either.
    @Test(arguments: [Mode.gamma, .sleep, .deepSleep])
    func theSmoothModesDoNotGainRoughness(_ mode: Mode) {
        let sine = Roughness.of(Spectrum(peak: 0.5), rate: mode.rate, depth: mode.depth)
        let shaped = Roughness.of(Spectrum(peak: Float(mode.envelope)), rate: mode.rate, depth: mode.depth)
        #expect(shaped <= sine, "\(mode.title) roughness rose from \(sine) to \(shaped)")
    }

    /// The rest buy their transient with roughness, but none may end up
    /// rougher than the roughest thing the app already played: Gamma's 40 Hz
    /// sine, which is why Gamma's depth is where it is. Ramping modes are
    /// checked at every rate they pass through, not just the one they start on.
    @Test(arguments: Mode.allCases)
    func noModeIsRougherThanGammaAlreadyWas(_ mode: Mode) {
        let ceiling = Roughness.of(Spectrum(peak: 0.5), rate: Mode.gamma.rate, depth: Mode.gamma.depth)
        let spectrum = Spectrum(peak: Float(mode.envelope))
        let last = mode.ramp?.to ?? mode.rate
        for step in 0...8 {
            let rate = mode.rate + (last - mode.rate) * Double(step) / 8
            let measured = Roughness.of(spectrum, rate: rate, depth: mode.depth)
            #expect(measured <= ceiling, "\(mode.title) at \(rate) Hz measures \(measured), ceiling \(ceiling)")
        }
    }
}

/// The harmonics of one envelope shape: its mean, and the amplitude of each
/// harmonic of the modulation rate. Neither depends on the rate or the depth,
/// so one of these serves every rate a mode passes through.
struct Spectrum {
    let mean: Double
    /// Amplitude of harmonics 1 through 12, indexed from zero.
    let amplitudes: [Double]

    init(peak: Float) {
        let curve = EnvelopeTests.cycle(peak: peak).map(Double.init)
        let n = Double(curve.count)
        mean = curve.reduce(0, +) / n
        amplitudes = (1...12).map { harmonic in
            var re = 0.0
            var im = 0.0
            for (i, value) in curve.enumerated() {
                let angle = 2 * .pi * Double(harmonic) * Double(i) / n
                re += 2 * value * cos(angle) / n
                im += 2 * value * sin(angle) / n
            }
            return (re * re + im * im).squareRoot()
        }
    }
}

/// How rough a shape's modulation sounds: the amplitude modulation index at
/// each harmonic of the rate, weighted by the ear's sensitivity to roughness
/// at that frequency and summed as power.
enum Roughness {
    static func of(_ spectrum: Spectrum, rate: Double, depth: Double) -> Double {
        var total = 0.0
        for (i, amplitude) in spectrum.amplitudes.enumerated() {
            // The mid band is scaled by 1 - depth * envelope, so this is the
            // modulation index the harmonic actually reaches the ear at.
            let index = depth * amplitude / (1 - depth * spectrum.mean)
            total += weight(Double(i + 1) * rate) * index * index
        }
        return total
    }

    /// Zwicker and Fastl's roughness curve: a modulation is roughest around
    /// 70 Hz and falls away either side, log-normally.
    private static func weight(_ hz: Double) -> Double {
        hz <= 0 ? 0 : exp(-pow(log(hz / 70), 2) / (2 * 0.75 * 0.75))
    }
}
