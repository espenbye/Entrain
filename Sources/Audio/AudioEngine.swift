import AVFoundation

/// What the session needs from an audio backend. `AudioEngine` is the real one;
/// tests substitute a fake.
@MainActor
protocol SessionAudio: AnyObject {
    /// Called when playback stops for a reason the session did not ask for,
    /// such as an output device going away and the engine failing to restart,
    /// or a phone call taking the output.
    var onInterruption: (() -> Void)? { get set }
    /// Called when the interruption is over. True when the system says the
    /// app should pick up where it left off, as after a call it paused.
    var onInterruptionEnded: ((_ shouldResume: Bool) async -> Void)? { get set }
    /// Whether other apps keep playing underneath. On iOS a session that mixes
    /// gives up Now Playing, so this follows the Now Playing toggle.
    var mixesWithOthers: Bool { get set }
    /// Whether the output is headphones. Over headphones the room is rendered
    /// with HRTFs; over speakers it falls back to panning.
    var headphones: Bool { get set }
    /// Whether the listener turns with the head, so the room stays put.
    /// Needs headphones that report motion; otherwise it is a no-op.
    var headTracking: Bool { get set }
    func start() async throws
    func stop()
}

@MainActor
final class AudioEngine: SessionAudio {
    var onInterruption: (() -> Void)?
    var onInterruptionEnded: ((Bool) async -> Void)?
    var mixesWithOthers = false {
        didSet { Self.configureSession(mixesWithOthers: mixesWithOthers) }
    }

    #if os(watchOS)
    // The watch plays a stereo bed with no room, so these have nothing to drive.
    var headphones = true
    var headTracking = false
    #else
    var headphones = true {
        didSet { applyRendering() }
    }
    var headTracking = false {
        didSet { applyHeadTracking() }
    }
    #endif

    private let engine = AVAudioEngine()
    private let binauralNode: AVAudioSourceNode
    /// The breathing cues, stereo and outside the room like the beat.
    private let cueNode: AVAudioSourceNode
    #if os(watchOS)
    private let bedNode: AVAudioSourceNode
    #else
    /// One mono node per soundscape, in `Soundscape.allCases` order, so each
    /// sits at its own place in the room.
    private let voiceNodes: [AVAudioSourceNode]
    private let environment = AVAudioEnvironmentNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 1)
    private var orbit: Task<Void, Never>?
    private var tracker: HeadTracker?
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

        #if os(watchOS)
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
        #else
        let mono = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        voiceNodes = Soundscape.allCases.map { soundscape in
            let voice = VoiceSynth(soundscape, parameters: parameters, sampleRate: sampleRate)
            return AVAudioSourceNode(format: mono) { @Sendable _, _, frameCount, audioBufferList in
                let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
                voice.render(frames: Int(frameCount), into: buffers[0].mData!.assumingMemoryBound(to: Float.self))
                return noErr
            }
        }
        #endif

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

        let cues = CueSynth(parameters: parameters, sampleRate: sampleRate)
        cueNode = AVAudioSourceNode(format: format) { @Sendable _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            cues.render(
                frames: Int(frameCount),
                left: buffers[0].mData!.assumingMemoryBound(to: Float.self),
                right: buffers[1].mData!.assumingMemoryBound(to: Float.self)
            )
            return noErr
        }

        engine.attach(binauralNode)
        engine.attach(cueNode)
        #if os(watchOS)
        // watchOS has no environment node; the bed goes straight to the mixer.
        engine.attach(bedNode)
        engine.connect(bedNode, to: engine.mainMixerNode, format: format)
        #else
        // The room. Sources within `reach` keep their loudness, so a position
        // is a direction, not a level. A small room's reverb is part of the
        // same model rather than a hall pasted on after the mix.
        environment.distanceAttenuationParameters.referenceDistance = Room.reach
        environment.distanceAttenuationParameters.maximumDistance = Room.reach * 4
        environment.reverbParameters.enable = true
        environment.reverbParameters.loadFactoryReverbPreset(.mediumRoom)
        environment.reverbParameters.level = -14
        engine.attach(environment)
        for (node, soundscape) in zip(voiceNodes, Soundscape.allCases) {
            engine.attach(node)
            engine.connect(node, to: environment, format: mono)
            node.position = Room.position(of: soundscape, at: 0)
            node.reverbBlend = 0.25
        }
        applyRendering()

        // A gentle high shelf takes the edge off rain and droplets.
        let shelf = eq.bands[0]
        shelf.filterType = .highShelf
        shelf.frequency = 6000
        shelf.gain = -4
        shelf.bypass = false
        engine.attach(eq)
        engine.connect(environment, to: eq, format: format)
        engine.connect(eq, to: engine.mainMixerNode, format: format)
        #endif
        engine.connect(binauralNode, to: engine.mainMixerNode, format: format)
        engine.connect(cueNode, to: engine.mainMixerNode, format: format)
        engine.prepare()

        // Plugging in headphones or switching outputs stops the engine.
        observers.append(NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in self?.recover() }
        })
        #if !os(macOS)
        // A call or another app's audio takes the output. The session pauses;
        // it comes back only when the system says so, which it does after a
        // call and not after the user started something else.
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: nil
        ) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            switch raw.flatMap(AVAudioSession.InterruptionType.init) {
            case .began:
                Task { @MainActor in self?.interrupted() }
            case .ended:
                let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let shouldResume = AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume)
                Task { @MainActor in await self?.onInterruptionEnded?(shouldResume) }
            default:
                break
            }
        })
        #endif
    }

    func start() async throws {
        shouldRun = true
        guard !engine.isRunning else { return }
        try await activateSession()
        try engine.start()
        #if !os(watchOS)
        startOrbit()
        applyHeadTracking()
        #endif
    }

    /// `stop()` rather than `pause()`: a paused engine keeps its output unit
    /// initialised, which leaves the process attached to the device (and in
    /// coreaudiod's overload reports) for as long as it lives.
    func stop() {
        shouldRun = false
        #if !os(watchOS)
        orbit?.cancel()
        orbit = nil
        tracker?.stop()
        #endif
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

    // MARK: Room

    #if !os(watchOS)
    /// HRTF rendering needs headphones; anything else gets equal-power panning.
    private func applyRendering() {
        let algorithm: AVAudio3DMixingRenderingAlgorithm = headphones ? .HRTFHQ : .equalPowerPanning
        for node in voiceNodes where node.renderingAlgorithm != algorithm {
            node.renderingAlgorithm = algorithm
        }
    }

    /// Moves the sources along their orbits. A step every two seconds is a
    /// fraction of a degree at these speeds, well under what the ear resolves.
    private func startOrbit() {
        guard orbit == nil else { return }
        let began = ContinuousClock.now
        orbit = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let seconds = Double(began.duration(to: .now).components.seconds)
                for (node, soundscape) in zip(voiceNodes, Soundscape.allCases) where soundscape != .noise {
                    node.position = Room.position(of: soundscape, at: seconds)
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func applyHeadTracking() {
        guard headTracking, shouldRun else {
            tracker?.stop()
            return
        }
        let tracker = self.tracker ?? HeadTracker { [weak self] orientation in
            self?.environment.listenerAngularOrientation = orientation
        }
        self.tracker = tracker
        tracker.start()
    }
    #endif

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
