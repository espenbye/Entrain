import Testing
@testable import Entrain

/// Invariants of the full bed: every sample finite, and a soundscape switch
/// crossfades without a spike above either voice's own peak.
struct SynthTests {
    static let sampleRate = 48000.0
    static let block = 512

    @Test func outputStaysFiniteAcrossEverySoundscape() {
        let parameters = AudioParameters()
        parameters.master.store(1, ordering: .relaxed)
        let synth = BedSynth(parameters: parameters, sampleRate: Self.sampleRate)
        var renderer = Renderer(synth: synth, block: Self.block)

        for soundscape in Soundscape.allCases {
            parameters.layers.store(soundscape.bit, ordering: .relaxed)
            let peak = renderer.render(seconds: 4)
            #expect(peak.isFinite && peak > 0, "\(soundscape.title) rendered \(peak)")
        }
    }

    @Test func switchingSoundscapesDoesNotSpike() {
        let parameters = AudioParameters()
        parameters.master.store(1, ordering: .relaxed)
        parameters.layers.store(Soundscape.rain.bit, ordering: .relaxed)
        let synth = BedSynth(parameters: parameters, sampleRate: Self.sampleRate)
        var renderer = Renderer(synth: synth, block: Self.block)

        _ = renderer.render(seconds: 3)
        let rainPeak = renderer.render(seconds: 5)
        parameters.layers.store(Soundscape.drone.bit, ordering: .relaxed)
        let transitionPeak = renderer.render(seconds: 3)
        let dronePeak = renderer.render(seconds: 5)

        #expect(transitionPeak <= max(rainPeak, dronePeak) * 1.2, "crossfade peaked at \(transitionPeak)")
    }

    /// Two layers are scaled by 1/sqrt(2), so the mix must not exceed the sum
    /// of the two peaks at that gain, and it must not be quieter than the
    /// louder layer alone after scaling.
    @Test func mixingTwoLayersStaysInBounds() {
        let parameters = AudioParameters()
        parameters.master.store(1, ordering: .relaxed)
        let synth = BedSynth(parameters: parameters, sampleRate: Self.sampleRate)
        var renderer = Renderer(synth: synth, block: Self.block)

        parameters.layers.store(Soundscape.rain.bit, ordering: .relaxed)
        _ = renderer.render(seconds: 3)
        let rainPeak = renderer.render(seconds: 4)
        parameters.layers.store(Soundscape.drone.bit, ordering: .relaxed)
        _ = renderer.render(seconds: 3)
        let dronePeak = renderer.render(seconds: 4)
        parameters.layers.store(Soundscape.rain.bit | Soundscape.drone.bit, ordering: .relaxed)
        _ = renderer.render(seconds: 3)
        let mixPeak = renderer.render(seconds: 4)

        let scale = Float(1 / 2.0.squareRoot())
        #expect(mixPeak.isFinite && mixPeak > 0)
        #expect(mixPeak <= (rainPeak + dronePeak) * scale * 1.05, "mix peaked at \(mixPeak)")
        #expect(mixPeak >= max(rainPeak, dronePeak) * scale * 0.8, "mix only reached \(mixPeak)")
    }

    @Test func masterAtZeroIsSilent() {
        let parameters = AudioParameters()
        let synth = BedSynth(parameters: parameters, sampleRate: Self.sampleRate)
        var renderer = Renderer(synth: synth, block: Self.block)
        #expect(renderer.render(seconds: 2) == 0)
    }

    /// Drives a synth through fixed-size blocks like the engine does and
    /// returns the peak absolute sample over the span.
    struct Renderer {
        let synth: BedSynth
        let block: Int
        private var left: [Float]
        private var right: [Float]

        init(synth: BedSynth, block: Int) {
            self.synth = synth
            self.block = block
            left = [Float](repeating: 0, count: block)
            right = [Float](repeating: 0, count: block)
        }

        mutating func render(seconds: Double) -> Float {
            var peak: Float = 0
            let blocks = Int(seconds * SynthTests.sampleRate) / block
            for _ in 0..<blocks {
                left.withUnsafeMutableBufferPointer { l in
                    right.withUnsafeMutableBufferPointer { r in
                        synth.render(frames: block, left: l.baseAddress!, right: r.baseAddress!)
                    }
                }
                for i in 0..<block {
                    peak = max(peak, abs(left[i]), abs(right[i]))
                }
            }
            return peak
        }
    }
}
