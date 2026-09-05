import Foundation
import Observation

@MainActor
@Observable
final class Session {
    var mode: Mode { didSet { apply() } }
    var soundscape: Soundscape { didSet { apply() } }
    var intensity: Intensity { didSet { apply() } }
    var binaural: Bool { didSet { apply() } }
    var length: SessionLength { didSet { restartTimer() } }

    private(set) var isPlaying = false
    /// Seconds left in a timed session. Nil when endless.
    private(set) var remaining: Int?

    private let engine: AudioEngine
    private let defaults = UserDefaults.standard
    private var timerTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?

    init() {
        engine = try! AudioEngine()
        mode = Mode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .focus
        soundscape = Soundscape(rawValue: defaults.string(forKey: "soundscape") ?? "") ?? .rain
        intensity = Intensity(rawValue: defaults.string(forKey: "intensity") ?? "") ?? .medium
        binaural = defaults.object(forKey: "binaural") as? Bool ?? false
        length = SessionLength(rawValue: defaults.integer(forKey: "length")) ?? .endless
        apply()
        NowPlaying.attach(to: self)
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func play() {
        stopTask?.cancel()
        do {
            try engine.start()
        } catch {
            return
        }
        engine.parameters.master.store(1, ordering: .relaxed)
        isPlaying = true
        restartTimer()
        NowPlaying.update(self)
    }

    func pause() {
        engine.parameters.master.store(0, ordering: .relaxed)
        isPlaying = false
        timerTask?.cancel()
        remaining = length == .endless ? nil : length.rawValue * 60
        NowPlaying.update(self)
        stopTask = Task { [engine] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            engine.stop()
        }
    }

    var title: String { "\(mode.title) · \(soundscape.title)" }

    private func apply() {
        let p = engine.parameters
        p.modulationRate.store(mode.rate, ordering: .relaxed)
        p.modulationDepth.store(min(0.9, mode.depth * intensity.multiplier), ordering: .relaxed)
        p.binauralCarrier.store(mode.carrier, ordering: .relaxed)
        p.binauralLevel.store(binaural ? 0.12 : 0, ordering: .relaxed)
        p.soundscape.store(soundscape.index, ordering: .relaxed)

        defaults.set(mode.rawValue, forKey: "mode")
        defaults.set(soundscape.rawValue, forKey: "soundscape")
        defaults.set(intensity.rawValue, forKey: "intensity")
        defaults.set(binaural, forKey: "binaural")
        defaults.set(length.rawValue, forKey: "length")
        NowPlaying.update(self)
    }

    private func restartTimer() {
        defaults.set(length.rawValue, forKey: "length")
        timerTask?.cancel()
        guard length != .endless else {
            remaining = nil
            return
        }
        remaining = length.rawValue * 60
        guard isPlaying else { return }
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let left = remaining else { return }
                if left <= 1 {
                    pause()
                    return
                }
                remaining = left - 1
            }
        }
    }
}
