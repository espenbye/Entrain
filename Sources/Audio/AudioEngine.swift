import AVFoundation

/// What the session needs from an audio backend. `AudioEngine` is the real one;
/// tests substitute a fake.
@MainActor
protocol SessionAudio: AnyObject {
    /// Called when playback stops for a reason the session did not ask for,
    /// such as an output device going away and the engine failing to restart.
    var onInterruption: (() -> Void)? { get set }
    func start() throws
    func stop()
}

@MainActor
final class AudioEngine: SessionAudio {
    var onInterruption: (() -> Void)?

    private let engine = AVAudioEngine()
    private let bedNode: AVAudioSourceNode
    private let binauralNode: AVAudioSourceNode
    private let eq = AVAudioUnitEQ(numberOfBands: 1)
    private let reverb = AVAudioUnitReverb()

    /// Graph wiring is fixed; if it failed, `start()` reports it instead of the
    /// app dying in the initializer.
    private var graphError: Error?
    /// Set by `start()` and `stop()`. After an output device change the engine
    /// stops on its own, so this says whether to bring it back.
    private var shouldRun = false
    private var configurationObserver: NSObjectProtocol?

    init(parameters: AudioParameters) {
        // Zero when no output device exists; the synths still need a real rate.
        let hardwareRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let sampleRate = hardwareRate > 0 ? hardwareRate : 48000
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!

        let bed = BedSynth(parameters: parameters, sampleRate: sampleRate)
        bedNode = AVAudioSourceNode(format: format) { @Sendable _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            bed.render(
                frames: Int(frameCount),
                left: buffers[0].mData!.assumingMemoryBound(to: Float.self),
                right: buffers[1].mData!.assumingMemoryBound(to: Float.self)
            )
            return noErr
        }

        let binaural = BinauralSynth(parameters: parameters, sampleRate: sampleRate)
        binauralNode = AVAudioSourceNode(format: format) { @Sendable _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            binaural.render(
                frames: Int(frameCount),
                left: buffers[0].mData!.assumingMemoryBound(to: Float.self),
                right: buffers[1].mData!.assumingMemoryBound(to: Float.self)
            )
            return noErr
        }

        let shelf = eq.bands[0]
        shelf.filterType = .highShelf
        shelf.frequency = 6000
        shelf.gain = -4
        shelf.bypass = false

        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = 25

        for node in [bedNode, binauralNode, eq, reverb] {
            engine.attach(node)
        }
        do {
            try engine.connectNode(bedNode, to: eq, format: format)
            try engine.connectNode(eq, to: reverb, format: format)
            try engine.connectNode(reverb, to: engine.mainMixerNode, format: format)
            try engine.connectNode(binauralNode, to: engine.mainMixerNode, format: format)
        } catch {
            graphError = error
        }
        engine.prepare()

        // Plugging in headphones or switching outputs stops the engine.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in self?.recover() }
        }
    }

    func start() throws {
        if let graphError { throw graphError }
        shouldRun = true
        guard !engine.isRunning else { return }
        try engine.start()
    }

    func stop() {
        shouldRun = false
        engine.pause()
    }

    /// Bring the engine back after a device change. If it will not start, the
    /// session hears about it so the UI does not claim to be playing.
    private func recover() {
        guard shouldRun, !engine.isRunning else { return }
        do {
            try engine.start()
        } catch {
            shouldRun = false
            onInterruption?()
        }
    }
}
