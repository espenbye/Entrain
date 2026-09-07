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
    /// Whether this voice publishes the modulation phase. Every voice keeps
    /// the same clock, so one of them speaks for the bed; a silenced voice
    /// still advances, so it does not matter which layers are playing.
    private let leads: Bool

    private var rain: Rain
    private var pad: Pad
    private var drone: Drone
    private var noise: Noise
    private var rng: XorShift
    private var layerGain: Smoother

    private var modulation = Phasor()
    /// Where in the modulation cycle this soundscape sits. See
    /// `modulationOffset`.
    private let modulationOffset: Float
    /// The shape of one modulation cycle, set by the mode.
    private var shape: PulseShape
    private var depth: Smoother
    private var master: Smoother
    private var volume: Smoother

    /// Texture drift for the filters. One cycle every 15 minutes: the
    /// carrier evolves slowly to counter habituation while the rate stays fixed.
    private var drift = Phasor()
    private let driftIncrement: Float
    /// The brightness atomic, followed over about two seconds so a switch
    /// of day model is a swell rather than a step. Stepped once per block.
    private var brightness: Float = 0
    private let brightnessRate: Float

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
        leads = soundscape == Soundscape.allCases.first
        rain = Rain(sampleRate: sampleRate)
        // Built on the mode's own tonality, so a session that starts in Wind
        // Down is in its key from the first sample instead of retuning into
        // it a moment after the fade-in.
        let tonality = Tonality(rawValue: parameters.tonality.load(ordering: .relaxed)) ?? .open
        pad = Pad(sampleRate: sampleRate, tonality: tonality)
        drone = Drone(sampleRate: sampleRate, tonality: tonality)
        noise = Noise(sampleRate: sampleRate)
        // A seed per voice, so two noise-based voices never share a stream.
        rng = XorShift(state: 0x9E37_79B9 &+ UInt32(soundscape.index) &* 0x632B_E5AB)
        layerGain = Smoother(0, seconds: 1.5, sampleRate: sampleRate)
        modulationOffset = Self.modulationOffset(soundscape)
        shape = PulseShape(peak: 0.5, sampleRate: sampleRate)
        depth = Smoother(0.5, seconds: 0.05, sampleRate: sampleRate)
        master = Smoother(0, seconds: 1, sampleRate: sampleRate)
        volume = Smoother(1, seconds: 0.05, sampleRate: sampleRate)
        driftIncrement = 1 / (900 * Float(sampleRate))
        brightnessRate = 1 / (2 * Float(sampleRate))
        bandLowCoefficient = OnePoleLowpass.coefficient(cutoff: 200, sampleRate: Float(sampleRate))
        bandHighCoefficient = OnePoleLowpass.coefficient(cutoff: 1000, sampleRate: Float(sampleRate))
    }

    /// The slice of the modulation cycle a soundscape's envelope is rotated
    /// by, so two layers do not pulse in lockstep. Four voices falling
    /// together doubles the mechanical quality of the pulse; rotated, total
    /// energy stays roughly where it was and the emphasis moves between them
    /// instead. Pad sits opposite Rain and Drone between the two. Noise is
    /// the sleep bed, which never plays with anything else, so it has no one
    /// to be offset from.
    ///
    /// This is applied at the lookup, not to the phasor: every voice keeps
    /// the same clock, so a rate change still lands identically on all four
    /// and a session started later is in the same relationship.
    private static func modulationOffset(_ soundscape: Soundscape) -> Float {
        switch soundscape {
        case .rain: 0
        case .pad: 0.5
        case .drone: 0.25
        case .noise: 0
        }
    }

    /// Writes `frames` samples to `out`, replacing what was there.
    func render(frames: Int, into out: UnsafeMutablePointer<Float>) {
        let rateIncrement = Float(parameters.modulationRate.load(ordering: .relaxed)) / sampleRate
        depth.target = Float(parameters.modulationDepth.load(ordering: .relaxed))
        shape.target = Float(parameters.modulationShape.load(ordering: .relaxed))
        master.target = Float(parameters.master.load(ordering: .relaxed))
        volume.target = Float(parameters.volume.load(ordering: .relaxed))
        // Each voice is trimmed to the same loudness, so a mix of n layers is
        // scaled by 1/sqrt(n) to land near the level of one.
        let active = parameters.layers.load(ordering: .relaxed)
        let mixGain = 1 / sqrt(Float(max(1, active.nonzeroBitCount)))
        layerGain.target = active & soundscape.bit != 0 ? mixGain : 0

        // Evaluated once per block; far too slow to need per-sample resolution.
        let lfo = sin(twoPi * drift.next(driftIncrement * Float(frames)))
        let target = Float(parameters.brightness.load(ordering: .relaxed))
        brightness += (target - brightness) * min(1, brightnessRate * Float(frames))
        // Half an octave each way at the ends of the range.
        let scale = exp2(0.5 * brightness)
        let tonality = Tonality(rawValue: parameters.tonality.load(ordering: .relaxed)) ?? .open
        switch soundscape {
        case .rain: rain.prepare(lfo: lfo, brightness: scale)
        case .pad: pad.prepare(lfo: lfo, brightness: scale, tonality: tonality)
        case .drone: drone.prepare(lfo: lfo, brightness: scale, tonality: tonality)
        case .noise: noise.prepare(brightness: scale)
        }

        for i in 0..<frames {
            let gain = layerGain.next()
            let rotated = modulation.next(rateIncrement) + modulationOffset
            let pulse = depth.next() * shape.next(phase: rotated < 1 ? rotated : rotated - 1)
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
        if leads { parameters.modulationPhase.store(Double(modulation.phase), ordering: .relaxed) }
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

/// The cues: one tone each, straight to the mixer so it is not modulated
/// with the bed. Breathe in glides up a fifth, hold sits on one note,
/// breathe out glides back down, and the end of the exercise is a longer
/// note. The bedtime signature is nothing like them: a low note sinking a
/// whole octave over a few seconds, the one sound that only ever means
/// bed. Silent between cues, and after `master` like everything else, so
/// a pause cuts a cue with the bed. Owned by the render thread.
final class CueSynth: @unchecked Sendable {
    /// Peak amplitude of a breathing cue. The beds sit near -22 LUFS, so
    /// this is clearly above them without startling.
    static let level: Float = 0.22
    /// The bedtime signature sits closer to the bed: it is a cue to notice,
    /// not one to act on.
    static let bedtimeLevel: Float = 0.15

    private let parameters: AudioParameters
    private let sampleRate: Float
    private var lastCue: Int
    private var phasor = Phasor()
    private var master: Smoother
    private var volume: Smoother
    /// The note under way: samples left and its total, and its glide.
    private var remaining = 0
    private var length = 1
    private var startHz: Float = 0
    private var endHz: Float = 0
    private var level: Float = 0

    init(parameters: AudioParameters, sampleRate: Double) {
        self.parameters = parameters
        self.sampleRate = Float(sampleRate)
        lastCue = parameters.cue.load(ordering: .relaxed)
        master = Smoother(0, seconds: 1, sampleRate: sampleRate)
        volume = Smoother(1, seconds: 0.05, sampleRate: sampleRate)
    }

    /// Start frequency, end frequency, length and peak level of each cue's tone.
    static func tone(for cue: Cue) -> (start: Float, end: Float, seconds: Float, level: Float) {
        switch cue {
        case .breath(.inhale): (392, 587.33, 1.0, level)
        case .breath(.hold): (523.25, 523.25, 0.6, level)
        case .breath(.exhale): (587.33, 392, 1.0, level)
        case .breath(.finished): (440, 440, 1.8, level)
        case .bedtime: (220, 110, 3.5, bedtimeLevel)
        }
    }

    func render(frames: Int, left outL: UnsafeMutablePointer<Float>, right outR: UnsafeMutablePointer<Float>) {
        let cue = parameters.cue.load(ordering: .relaxed)
        if cue != lastCue {
            lastCue = cue
            let tone = Self.tone(for: Cue.decode(cue))
            startHz = tone.start
            endHz = tone.end
            level = tone.level
            length = max(1, Int(tone.seconds * sampleRate))
            remaining = length
            phasor = Phasor()
        }
        master.target = Float(parameters.master.load(ordering: .relaxed))
        volume.target = Float(parameters.volume.load(ordering: .relaxed))

        for i in 0..<frames {
            let trim = master.next() * volume.next()
            guard remaining > 0 else {
                outL[i] = 0
                outR[i] = 0
                continue
            }
            // A raised-cosine window over the whole note: no attack or release
            // edge to click, and it swells the way a breath does.
            let t = 1 - Float(remaining) / Float(length)
            let envelope = 0.5 - 0.5 * SineTable.sin(cycles: t + 0.25)
            let hz = startHz + (endHz - startHz) * t
            let p = phasor.next(hz / sampleRate)
            let s = (SineTable.sin(cycles: p) + 0.3 * SineTable.sin(cycles: 2 * p)) * envelope * level * trim
            outL[i] = s
            outR[i] = s
            remaining -= 1
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
