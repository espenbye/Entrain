import Foundation

/// Renders the soundscape and applies amplitude modulation to its mid band.
/// Owned by the render thread. Only `AudioParameters` crosses in.
final class BedSynth: @unchecked Sendable {
    private let parameters: AudioParameters
    private let sampleRate: Float

    private var rain: Rain
    private var pad: Pad
    private var drone: Drone
    private var layerGain: [Smoother]
    private var rng = XorShift()

    private var modulation = Phasor()
    private var depth: Smoother
    private var master: Smoother
    private var slowLFO = Phasor()
    private var crossover = OnePoleLowpass()
    private let crossoverCoefficient: Float

    init(parameters: AudioParameters, sampleRate: Double) {
        self.parameters = parameters
        self.sampleRate = Float(sampleRate)
        rain = Rain(sampleRate: sampleRate)
        pad = Pad(sampleRate: sampleRate)
        drone = Drone(sampleRate: sampleRate)
        layerGain = (0..<3).map { _ in Smoother(0, seconds: 1.5, sampleRate: sampleRate) }
        depth = Smoother(0.5, seconds: 0.05, sampleRate: sampleRate)
        master = Smoother(0, seconds: 1, sampleRate: sampleRate)
        crossoverCoefficient = OnePoleLowpass.coefficient(cutoff: 200, sampleRate: Float(sampleRate))
    }

    func render(frames: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        let rateIncrement = Float(parameters.modulationRate.load(ordering: .relaxed)) / sampleRate
        depth.target = Float(parameters.modulationDepth.load(ordering: .relaxed))
        master.target = Float(parameters.master.load(ordering: .relaxed))
        let active = parameters.soundscape.load(ordering: .relaxed)
        for i in layerGain.indices {
            layerGain[i].target = i == active ? 1 : 0
        }

        // Slow drift for filters and pan, evaluated once per block.
        let lfo = sin(twoPi * slowLFO.next(0.05 / sampleRate * Float(frames)))
        let pan = 0.3 * lfo
        let panL = cos((pan + 1) * Float.pi / 4)
        let panR = sin((pan + 1) * Float.pi / 4)

        for i in 0..<frames {
            var s: Float = 0
            let gRain = layerGain[0].next()
            let gPad = layerGain[1].next()
            let gDrone = layerGain[2].next()
            if gRain > 0.0005 { s += rain.next(lfo: lfo, rng: &rng) * gRain }
            if gPad > 0.0005 { s += pad.next(lfo: lfo, rng: &rng) * gPad }
            if gDrone > 0.0005 { s += drone.next(lfo: lfo) * gDrone }

            // Modulate only above the crossover so the low end stays steady.
            let low = crossover.process(s, crossoverCoefficient)
            let mid = s - low
            let gain = 1 - depth.next() * (0.5 - 0.5 * cos(twoPi * modulation.next(rateIncrement)))
            let out = (low + mid * gain) * master.next()

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

    init(parameters: AudioParameters, sampleRate: Double) {
        self.parameters = parameters
        self.sampleRate = Float(sampleRate)
        level = Smoother(0, seconds: 0.5, sampleRate: sampleRate)
        master = Smoother(0, seconds: 1, sampleRate: sampleRate)
    }

    func render(frames: Int, left outL: UnsafeMutablePointer<Float>, right outR: UnsafeMutablePointer<Float>) {
        let carrier = Float(parameters.binauralCarrier.load(ordering: .relaxed))
        let beat = Float(parameters.modulationRate.load(ordering: .relaxed))
        level.target = Float(parameters.binauralLevel.load(ordering: .relaxed))
        master.target = Float(parameters.master.load(ordering: .relaxed))
        let incL = carrier / sampleRate
        let incR = (carrier + beat) / sampleRate

        for i in 0..<frames {
            let g = level.next() * master.next()
            outL[i] = sin(twoPi * left.next(incL)) * g
            outR[i] = sin(twoPi * right.next(incR)) * g
        }
    }
}
