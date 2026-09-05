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
            parameters.soundscape.store(soundscape.index, ordering: .relaxed)
            let peak = renderer.render(seconds: 4)
            #expect(peak.isFinite && peak > 0, "\(soundscape.title) rendered \(peak)")
        }
    }

    @Test func switchingSoundscapesDoesNotSpike() {
        let parameters = AudioParameters()
        parameters.master.store(1, ordering: .relaxed)
        parameters.soundscape.store(Soundscape.rain.index, ordering: .relaxed)
        let synth = BedSynth(parameters: parameters, sampleRate: Self.sampleRate)
        var renderer = Renderer(synth: synth, block: Self.block)

        _ = renderer.render(seconds: 3)
        let rainPeak = renderer.render(seconds: 5)
        parameters.soundscape.store(Soundscape.drone.index, ordering: .relaxed)
        let transitionPeak = renderer.render(seconds: 3)
        let dronePeak = renderer.render(seconds: 5)

        #expect(transitionPeak <= max(rainPeak, dronePeak) * 1.2, "crossfade peaked at \(transitionPeak)")
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
