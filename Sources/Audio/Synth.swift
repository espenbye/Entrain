import Foundation

/// Renders the soundscape and applies amplitude modulation to its mid band.
/// Owned by the render thread. Only `AudioParameters` crosses in.
final class BedSynth: @unchecked Sendable {
    private let parameters: AudioParameters
    private let sampleRate: Float

    private var rain: Rain
    private var pad: Pad
    private var drone: Drone
    private var noise: Noise
    private var layerGain: [Smoother]
    private var rng = XorShift()

    private var modulation = Phasor()
    private var depth: Smoother
    private var master: Smoother
    private var volume: Smoother

    /// Texture drift for filters and pan. One cycle every 15 minutes: the
    /// carrier evolves slowly to counter habituation while the rate stays fixed.
    private var drift = Phasor()
    private let driftIncrement: Float

    /// Modulation is confined to 200 Hz...1 kHz. Below, the bass stays steady;
    /// above, rain droplets and pad harmonics do not flutter.
    private var bandLow = OnePoleLowpass()
    private var bandHigh = OnePoleLowpass()
    private let bandLowCoefficient: Float
    private let bandHighCoefficient: Float

    init(parameters: AudioParameters, sampleRate: Double) {
        self.parameters = parameters
        self.sampleRate = Float(sampleRate)
        rain = Rain(sampleRate: sampleRate)
        pad = Pad(sampleRate: sampleRate)
        drone = Drone(sampleRate: sampleRate)
        noise = Noise(sampleRate: sampleRate)
        layerGain = (0..<4).map { _ in Smoother(0, seconds: 1.5, sampleRate: sampleRate) }
        depth = Smoother(0.5, seconds: 0.05, sampleRate: sampleRate)
        master = Smoother(0, seconds: 1, sampleRate: sampleRate)
        volume = Smoother(1, seconds: 0.05, sampleRate: sampleRate)
        driftIncrement = 1 / (900 * Float(sampleRate))
        bandLowCoefficient = OnePoleLowpass.coefficient(cutoff: 200, sampleRate: Float(sampleRate))
        bandHighCoefficient = OnePoleLowpass.coefficient(cutoff: 1000, sampleRate: Float(sampleRate))
    }

    func render(frames: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        let rateIncrement = Float(parameters.modulationRate.load(ordering: .relaxed)) / sampleRate
        depth.target = Float(parameters.modulationDepth.load(ordering: .relaxed))
        master.target = Float(parameters.master.load(ordering: .relaxed))
        volume.target = Float(parameters.volume.load(ordering: .relaxed))
        let active = parameters.soundscape.load(ordering: .relaxed)
        for i in layerGain.indices {
            layerGain[i].target = i == active ? 1 : 0
        }

        // Evaluated once per block; far too slow to need per-sample resolution.
        let lfo = sin(twoPi * drift.next(driftIncrement * Float(frames)))
        let pan = 0.3 * lfo
        let panL = cos((pan + 1) * Float.pi / 4)
        let panR = sin((pan + 1) * Float.pi / 4)
        rain.prepare(lfo: lfo)
        pad.prepare(lfo: lfo)
        drone.prepare(lfo: lfo)

        for i in 0..<frames {
            var s: Float = 0
            let gRain = layerGain[0].next()
            let gPad = layerGain[1].next()
            let gDrone = layerGain[2].next()
            let gNoise = layerGain[3].next()
            if gRain > 0.0005 { s += rain.next(rng: &rng) * gRain }
            if gPad > 0.0005 { s += pad.next(rng: &rng) * gPad }
            if gDrone > 0.0005 { s += drone.next() * gDrone }
            if gNoise > 0.0005 { s += noise.next(rng: &rng) * gNoise }

            let low = bandLow.process(s, bandLowCoefficient)
            let mid = bandHigh.process(s, bandHighCoefficient) - low
            let pulse = depth.next() * (0.5 - 0.5 * cos(twoPi * modulation.next(rateIncrement)))
            let out = (s - mid * pulse) * master.next() * volume.next()

            left[i] = out * panL
            right[i] = out * panR
        }
    }
}

/// Pure tones, one per ear, offset by the mode's rate. Bypasses modulation and reverb.
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
            outL[i] = sin(twoPi * left.next(incL)) * g
            outR[i] = sin(twoPi * right.next(incR)) * g
        }
    }
}
