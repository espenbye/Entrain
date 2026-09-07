import Foundation

/// One soundscape, mono, with the amplitude modulation applied to its mid
/// band. On iPhone and Mac each voice is its own engine node, placed in the
/// room by the environment node; the watch sums four of these into a stereo
/// bed. Owned by the render thread. Only `AudioParameters` crosses in.
///
/// Every voice keeps its own modulation clock and reads the same atomics
/// once per block, so four voices rendered from the same parameters pulse
/// in step: a rate change read a block apart shifts the phase by the rate
/// step times one block, a few millionths of a cycle.
final class VoiceSynth: @unchecked Sendable {
    private let parameters: AudioParameters
    private let sampleRate: Float
    private let soundscape: Soundscape

    private var rain: Rain
    private var pad: Pad
    private var drone: Drone
    private var noise: Noise
    private var rng: XorShift
    private var layerGain: Smoother

    private var modulation = Phasor()
    private var depth: Smoother
    private var master: Smoother
    private var volume: Smoother

    /// Texture drift for the filters. One cycle every 15 minutes: the
    /// carrier evolves slowly to counter habituation while the rate stays fixed.
    private var drift = Phasor()
    private let driftIncrement: Float

    /// Modulation is confined to 200 Hz...1 kHz. Below, the bass stays steady;
    /// above, rain droplets and pad harmonics do not flutter.
    private var bandLow = OnePoleLowpass()
    private var bandHigh = OnePoleLowpass()
    private let bandLowCoefficient: Float
    private let bandHighCoefficient: Float

    init(_ soundscape: Soundscape, parameters: AudioParameters, sampleRate: Double) {
        self.parameters = parameters
        self.sampleRate = Float(sampleRate)
        self.soundscape = soundscape
        rain = Rain(sampleRate: sampleRate)
        pad = Pad(sampleRate: sampleRate)
        drone = Drone(sampleRate: sampleRate)
        noise = Noise(sampleRate: sampleRate)
        // A seed per voice, so two noise-based voices never share a stream.
        rng = XorShift(state: 0x9E37_79B9 &+ UInt32(soundscape.index) &* 0x632B_E5AB)
        layerGain = Smoother(0, seconds: 1.5, sampleRate: sampleRate)
        depth = Smoother(0.5, seconds: 0.05, sampleRate: sampleRate)
        master = Smoother(0, seconds: 1, sampleRate: sampleRate)
        volume = Smoother(1, seconds: 0.05, sampleRate: sampleRate)
        driftIncrement = 1 / (900 * Float(sampleRate))
        bandLowCoefficient = OnePoleLowpass.coefficient(cutoff: 200, sampleRate: Float(sampleRate))
        bandHighCoefficient = OnePoleLowpass.coefficient(cutoff: 1000, sampleRate: Float(sampleRate))
    }

    /// Writes `frames` samples to `out`, replacing what was there.
    func render(frames: Int, into out: UnsafeMutablePointer<Float>) {
        let rateIncrement = Float(parameters.modulationRate.load(ordering: .relaxed)) / sampleRate
        depth.target = Float(parameters.modulationDepth.load(ordering: .relaxed))
        master.target = Float(parameters.master.load(ordering: .relaxed))
        volume.target = Float(parameters.volume.load(ordering: .relaxed))
        // Each voice is trimmed to the same loudness, so a mix of n layers is
        // scaled by 1/sqrt(n) to land near the level of one.
        let active = parameters.layers.load(ordering: .relaxed)
        let mixGain = 1 / sqrt(Float(max(1, active.nonzeroBitCount)))
        layerGain.target = active & soundscape.bit != 0 ? mixGain : 0

        // Evaluated once per block; far too slow to need per-sample resolution.
        let lfo = sin(twoPi * drift.next(driftIncrement * Float(frames)))
        switch soundscape {
        case .rain: rain.prepare(lfo: lfo)
        case .pad: pad.prepare(lfo: lfo)
        case .drone: drone.prepare(lfo: lfo)
        case .noise: break
        }

        for i in 0..<frames {
            let gain = layerGain.next()
            let pulse = depth.next() * (0.5 - 0.5 * SineTable.sin(cycles: modulation.next(rateIncrement) + 0.25))
            let trim = master.next() * volume.next()
            // A silent voice still advances its clocks, so it comes back in phase.
            guard gain > 0.0005 else {
                out[i] = 0
                continue
            }
            let sample: Float = switch soundscape {
            case .rain: rain.next(rng: &rng)
            case .pad: pad.next(rng: &rng)
            case .drone: drone.next()
            case .noise: noise.next(rng: &rng)
            }
            let s = sample * gain
            let low = bandLow.process(s, bandLowCoefficient)
            let mid = bandHigh.process(s, bandHighCoefficient) - low
            out[i] = (s - mid * pulse) * trim
        }
    }
}

/// The four voices summed to stereo with a slow constant-power pan. The
/// watch has no environment node, so it plays this straight into the mixer.
/// Owned by the render thread.
final class BedSynth: @unchecked Sendable {
    private let voices: [VoiceSynth]
    private var drift = Phasor()
    private let driftIncrement: Float
    /// Scratch for one voice's block. Sized once for the largest block the
    /// hardware asks for, so the render path never allocates.
    private var scratch = [Float](repeating: 0, count: 4096)

    init(parameters: AudioParameters, sampleRate: Double) {
        voices = Soundscape.allCases.map { VoiceSynth($0, parameters: parameters, sampleRate: sampleRate) }
        driftIncrement = 1 / (900 * Float(sampleRate))
    }

    func render(frames: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        let pan = 0.3 * sin(twoPi * drift.next(driftIncrement * Float(frames)))
        let panL = cos((pan + 1) * Float.pi / 4)
        let panR = sin((pan + 1) * Float.pi / 4)
        left.initialize(repeating: 0, count: frames)
        scratch.withUnsafeMutableBufferPointer { scratch in
            let buffer = scratch.baseAddress!
            for voice in voices {
                voice.render(frames: min(frames, scratch.count), into: buffer)
                for i in 0..<min(frames, scratch.count) { left[i] += buffer[i] }
            }
        }
        for i in 0..<frames {
            let out = left[i]
            left[i] = out * panL
            right[i] = out * panR
        }
    }
}

/// Pure tones, one per ear, offset by the mode's rate. Bypasses modulation,
/// the room and its reverb: the beat only works when the two carriers reach
/// the ears unmixed.
final class BinauralSynth: @unchecked Sendable {
    private let parameters: AudioParameters
    private let sampleRate: Float
    private var left = Phasor()
    private var right = Phasor()
    private var level: Smoother
    private var master: Smoother
    private var volume: Smoother

    init(parameters: AudioParameters, sampleRate: Double) {
        self.parameters = parameters
        self.sampleRate = Float(sampleRate)
        level = Smoother(0, seconds: 0.5, sampleRate: sampleRate)
        master = Smoother(0, seconds: 1, sampleRate: sampleRate)
        volume = Smoother(1, seconds: 0.05, sampleRate: sampleRate)
    }

    func render(frames: Int, left outL: UnsafeMutablePointer<Float>, right outR: UnsafeMutablePointer<Float>) {
        let carrier = Float(parameters.binauralCarrier.load(ordering: .relaxed))
        let beat = Float(parameters.modulationRate.load(ordering: .relaxed))
        level.target = Float(parameters.binauralLevel.load(ordering: .relaxed))
        master.target = Float(parameters.master.load(ordering: .relaxed))
        volume.target = Float(parameters.volume.load(ordering: .relaxed))
        let incL = carrier / sampleRate
        let incR = (carrier + beat) / sampleRate

        for i in 0..<frames {
            let g = level.next() * master.next() * volume.next()
            outL[i] = SineTable.sin(cycles: left.next(incL)) * g
            outR[i] = SineTable.sin(cycles: right.next(incR)) * g
        }
    }
}
