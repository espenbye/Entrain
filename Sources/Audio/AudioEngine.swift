import AVFoundation

@MainActor
final class AudioEngine {
    let parameters = AudioParameters()

    private let engine = AVAudioEngine()
    private let bedNode: AVAudioSourceNode
    private let binauralNode: AVAudioSourceNode
    private let eq = AVAudioUnitEQ(numberOfBands: 1)
    private let reverb = AVAudioUnitReverb()

    init() throws {
        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
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
        try engine.connectNode(bedNode, to: eq, format: format)
        try engine.connectNode(eq, to: reverb, format: format)
        try engine.connectNode(reverb, to: engine.mainMixerNode, format: format)
        try engine.connectNode(binauralNode, to: engine.mainMixerNode, format: format)
        engine.prepare()
    }

    func start() throws {
        guard !engine.isRunning else { return }
        try engine.start()
    }

    func stop() {
        engine.pause()
    }
}
