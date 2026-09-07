import Foundation
import Testing
@testable import Entrain

/// How the four voices sit against each other in the modulation cycle. Each
/// carries the pulse in full on its own; what the offsets change is where in
/// the cycle each one falls, so two layers do not drop together.
struct ModulationTests {
    static let sampleRate = 48000.0
    static let rate = 4.0
    static let block = 512

    /// Parameters with the modulation wide open at a rate the envelope
    /// measurement can resolve in a few seconds.
    static func parameters(layers: Int) -> AudioParameters {
        let parameters = AudioParameters()
        parameters.master.store(1, ordering: .relaxed)
        parameters.volume.store(1, ordering: .relaxed)
        parameters.modulationRate.store(rate, ordering: .relaxed)
        parameters.modulationDepth.store(0.9, ordering: .relaxed)
        parameters.layers.store(layers, ordering: .relaxed)
        return parameters
    }

    /// The same, set up as a mode leaves them.
    static func parameters(layers: Int, mode: Mode) -> AudioParameters {
        let parameters = parameters(layers: layers)
        store(mode, into: parameters)
        return parameters
    }

    static func store(_ mode: Mode, into parameters: AudioParameters) {
        parameters.modulationRate.store(mode.rate, ordering: .relaxed)
        parameters.modulationDepth.store(mode.depth, ordering: .relaxed)
        parameters.modulationShape.store(mode.envelope, ordering: .relaxed)
        parameters.tonality.store(mode.tonality.rawValue, ordering: .relaxed)
    }

    /// The offsets are exactly the rotations they are meant to be: Pad half a
    /// cycle from Rain, Drone a quarter, Noise together with Rain. Measured
    /// off the rendered audio, so it covers the lookup as well as the table.
    @Test func voicesPulseAtTheirOwnPointInTheCycle() {
        var phases: [Soundscape: Double] = [:]
        var strengths: [Soundscape: Double] = [:]
        for soundscape in Soundscape.allCases {
            let component = Self.component(of: Self.modulation(of: soundscape, seconds: 8, settle: 3))
            phases[soundscape] = component.phase
            strengths[soundscape] = component.strength
        }

        // A voice offset by o reaches the top of its cycle o of a turn before
        // Rain does, so against Rain it measures at -o.
        for (soundscape, offset) in [(Soundscape.pad, 0.5), (.drone, 0.25), (.noise, 0.0)] {
            let turn = (phases[soundscape]! - phases[.rain]! + 1).truncatingRemainder(dividingBy: 1)
            let expected = (1 - offset).truncatingRemainder(dividingBy: 1)
            let off = min(abs(turn - expected), 1 - abs(turn - expected))
            #expect(off < 0.02, "\(soundscape.title) sits \(turn) of a cycle from Rain, expected \(expected)")
        }
        // Rotating a voice does not weaken it: every one is modulated to the
        // same extent, which is why a solo layer sounds no different for
        // having been moved.
        let extremes = (strengths.values.min()!, strengths.values.max()!)
        #expect(extremes.1 / extremes.0 < 1.05, "modulation ranges from \(extremes.0) to \(extremes.1)")
    }

    /// Two layers at opposite points in the cycle partly cancel: the bed's
    /// own level moves less than either voice's does alone, so the pair reads
    /// as emphasis moving between them rather than as one louder pulse. In
    /// lockstep this would instead land between the two strengths.
    @Test func twoLayersDoNotPulseTogether() {
        let alone = [Soundscape.rain, .pad].map { soundscape -> Double in
            let parameters = Self.parameters(layers: soundscape.bit)
            let bed = BedSynth(parameters: parameters, sampleRate: Self.sampleRate)
            return Self.component(of: Self.envelope(of: bed, seconds: 8, settle: 4)).strength
        }
        let parameters = Self.parameters(layers: Soundscape.rain.bit | Soundscape.pad.bit)
        let bed = BedSynth(parameters: parameters, sampleRate: Self.sampleRate)
        let together = Self.component(of: Self.envelope(of: bed, seconds: 8, settle: 4)).strength

        #expect(
            together < 0.7 * min(alone[0], alone[1]),
            "Rain and Pad together modulate \(together), alone \(alone[0]) and \(alone[1])"
        )
    }

    /// A mode change moves the rate, the envelope shape and the tonality at
    /// once, none of which may be heard as a click. The two tuned voices are
    /// the exposed ones, and each is measured alone: the pad has to retune
    /// four oscillators and the drone has to glide, and neither has noise to
    /// hide a step under.
    ///
    /// A click is an edge the signal could not have produced on its own, so
    /// the transition is held against both settled ends rather than against
    /// the one it starts from. The two are not alike: the dark drone's
    /// partials sit further inside its lowpass than the open drone's, so it
    /// legitimately carries more edge once it arrives.
    ///
    /// It answers to a gross discontinuity, not to a subtle one: both voices
    /// end in a one-pole lowpass, which damps a step badly enough that a
    /// single oscillator changing pitch mid-cycle lands well under what the
    /// voice already carries. What it does catch is a whole voice appearing
    /// or vanishing, which is what a retune without a fade would be.
    @Test(arguments: Soundscape.tuned)
    func changingModeDoesNotClick(_ soundscape: Soundscape) {
        let ends = [Mode.focus, .windDown].map { mode -> Float in
            let bed = BedSynth(parameters: Self.parameters(layers: soundscape.bit, mode: mode), sampleRate: Self.sampleRate)
            _ = Self.sharpestEdge(of: bed, seconds: 5)
            return Self.sharpestEdge(of: bed, seconds: 10)
        }

        let parameters = Self.parameters(layers: soundscape.bit, mode: .focus)
        let bed = BedSynth(parameters: parameters, sampleRate: Self.sampleRate)
        _ = Self.sharpestEdge(of: bed, seconds: 5)
        Self.store(Mode.windDown, into: parameters)
        // Long enough to cover the glide, all four staggered retunes and the
        // three-second fade the last of them ends with.
        let changing = Self.sharpestEdge(of: bed, seconds: 10)

        let settled = max(ends[0], ends[1])
        #expect(changing <= settled * 1.2, "\(soundscape.title) edged \(changing), settled ends edge \(ends)")
    }

    /// The sharpest edge in the span. A fourth difference is a steep
    /// high-pass: it all but ignores what these voices are made of, none of
    /// which survives their own lowpass much above a kilohertz, and answers
    /// to the near-vertical edge a click is.
    static func sharpestEdge(of bed: BedSynth, seconds: Double) -> Float {
        var left = [Float](repeating: 0, count: block)
        var right = [Float](repeating: 0, count: block)
        var sharpest: Float = 0
        var history: (Float, Float, Float, Float) = (0, 0, 0, 0)
        for _ in 0..<Int(seconds * sampleRate) / block {
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    bed.render(frames: block, left: l.baseAddress!, right: r.baseAddress!)
                }
            }
            for sample in left {
                let edge = sample - 4 * history.0 + 6 * history.1 - 4 * history.2 + history.3
                sharpest = max(sharpest, abs(edge))
                history = (sample, history.0, history.1, history.2)
            }
        }
        return sharpest
    }

    /// What the modulation alone does to a voice, one value per block. The
    /// same voice is rendered twice, modulated and flat: a `VoiceSynth` is
    /// deterministic, so the two carry an identical soundscape and the
    /// difference between them is the modulation and nothing else. Measuring
    /// that instead of the voice's own level keeps Rain's droplets and the
    /// Pad's note changes out of the reading.
    static func modulation(of soundscape: Soundscape, seconds: Double, settle: Double) -> [Double] {
        let flatParameters = parameters(layers: soundscape.bit)
        flatParameters.modulationDepth.store(0, ordering: .relaxed)
        let modulated = VoiceSynth(soundscape, parameters: parameters(layers: soundscape.bit), sampleRate: sampleRate)
        let flat = VoiceSynth(soundscape, parameters: flatParameters, sampleRate: sampleRate)
        var a = [Float](repeating: 0, count: block)
        var b = [Float](repeating: 0, count: block)
        var envelope: [Double] = []
        for i in 0..<Int((seconds + settle) * sampleRate) / block {
            a.withUnsafeMutableBufferPointer { modulated.render(frames: block, into: $0.baseAddress!) }
            b.withUnsafeMutableBufferPointer { flat.render(frames: block, into: $0.baseAddress!) }
            guard Double(i * block) >= settle * sampleRate else { continue }
            envelope.append((0..<block).reduce(0.0) {
                let d = Double(b[$1] - a[$1])
                return $0 + d * d
            } / Double(block))
        }
        return envelope
    }

    static func envelope(of bed: BedSynth, seconds: Double, settle: Double) -> [Double] {
        var left = [Float](repeating: 0, count: block)
        var right = [Float](repeating: 0, count: block)
        var envelope: [Double] = []
        for i in 0..<Int((seconds + settle) * sampleRate) / block {
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    bed.render(frames: block, left: l.baseAddress!, right: r.baseAddress!)
                }
            }
            guard Double(i * block) >= settle * sampleRate else { continue }
            envelope.append(left.reduce(0) { $0 + Double($1 * $1) } / Double(block))
        }
        return envelope
    }

    /// The modulation in an envelope: how far the level swings at the rate,
    /// as a fraction of the mean, and where in the cycle the swing peaks.
    static func component(of envelope: [Double]) -> (strength: Double, phase: Double) {
        let n = Double(envelope.count)
        let mean = envelope.reduce(0, +) / n
        // Cycles across the window, so the measurement lands in one bin.
        let cycles = (rate * n * Double(block) / sampleRate).rounded()
        var re = 0.0
        var im = 0.0
        for (i, value) in envelope.enumerated() {
            let angle = 2 * .pi * cycles * Double(i) / n
            re += 2 * value * cos(angle) / n
            im += 2 * value * sin(angle) / n
        }
        return ((re * re + im * im).squareRoot() / mean, atan2(im, re) / (2 * .pi))
    }
}
