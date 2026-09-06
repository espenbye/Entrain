import AVFoundation

/// What the session needs from an audio backend. `AudioEngine` is the real one;
/// tests substitute a fake.
@MainActor
protocol SessionAudio: AnyObject {
    /// Called when playback stops for a reason the session did not ask for,
    /// such as an output device going away and the engine failing to restart,
    /// or a phone call taking the output.
    var onInterruption: (() -> Void)? { get set }
    /// Whether other apps keep playing underneath. On iOS a session that mixes
    /// gives up Now Playing, so this follows the Now Playing toggle.
    var mixesWithOthers: Bool { get set }
    func start() async throws
    func stop()
}

@MainActor
final class AudioEngine: SessionAudio {
    var onInterruption: (() -> Void)?
    var mixesWithOthers = false {
        didSet { Self.configureSession(mixesWithOthers: mixesWithOthers) }
    }

    private let engine = AVAudioEngine()
    private let bedNode: AVAudioSourceNode
    private let binauralNode: AVAudioSourceNode
    #if !os(watchOS)
    private let eq = AVAudioUnitEQ(numberOfBands: 1)
    private let reverb = AVAudioUnitReverb()
    #endif

    /// Set by `start()` and `stop()`. After an output device change the engine
    /// stops on its own, so this says whether to bring it back.
    private var shouldRun = false
    private var observers: [NSObjectProtocol] = []

    isolated deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    init(parameters: AudioParameters) {
        Self.configureSession(mixesWithOthers: false)
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

        engine.attach(bedNode)
        engine.attach(binauralNode)
        #if os(watchOS)
        // watchOS has no EQ or reverb units; the bed goes straight to the mixer.
        engine.connect(bedNode, to: engine.mainMixerNode, format: format)
        #else
        let shelf = eq.bands[0]
        shelf.filterType = .highShelf
        shelf.frequency = 6000
        shelf.gain = -4
        shelf.bypass = false

        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = 25

        engine.attach(eq)
        engine.attach(reverb)
        engine.connect(bedNode, to: eq, format: format)
        engine.connect(eq, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)
        #endif
        engine.connect(binauralNode, to: engine.mainMixerNode, format: format)
        engine.prepare()

        // Plugging in headphones or switching outputs stops the engine.
        observers.append(NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in self?.recover() }
        })
        #if !os(macOS)
        // A call or another app's audio takes the output. The session pauses
        // and stays paused: nothing resumes unattended, as on Mac sleep.
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: nil
        ) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw.flatMap(AVAudioSession.InterruptionType.init) == .began else { return }
            Task { @MainActor in self?.interrupted() }
        })
        #endif
    }

    func start() async throws {
        shouldRun = true
        guard !engine.isRunning else { return }
        try await activateSession()
        try engine.start()
    }

    /// `stop()` rather than `pause()`: a paused engine keeps its output unit
    /// initialised, which leaves the process attached to the device (and in
    /// coreaudiod's overload reports) for as long as it lives.
    func stop() {
        shouldRun = false
        engine.stop()
        #if !os(macOS)
        // Hands the output back so the music underneath resumes.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    /// Bring the engine back after a device change. If it will not start, the
    /// session hears about it so the UI does not claim to be playing.
    private func recover() {
        guard shouldRun, !engine.isRunning else { return }
        do {
            try engine.start()
        } catch {
            interrupted()
        }
    }

    private func interrupted() {
        guard shouldRun else { return }
        shouldRun = false
        onInterruption?()
    }

    // MARK: Audio session

    /// The Mac has no audio session. iOS plays in the background and, when
    /// mixing, sits under other audio. The watch needs the long-form policy:
    /// it is the only way to keep playing with the wrist down.
    private static func configureSession(mixesWithOthers: Bool) {
        #if os(watchOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio)
        #elseif !os(macOS)
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .default, options: mixesWithOthers ? .mixWithOthers : []
        )
        #endif
    }

    private func activateSession() async throws {
        #if os(watchOS)
        // Prompts for headphones when none are connected; the user can cancel.
        guard try await AVAudioSession.sharedInstance().activate(options: []) else {
            throw CancellationError()
        }
        #elseif !os(macOS)
        try AVAudioSession.sharedInstance().setActive(true)
        #endif
    }
}
