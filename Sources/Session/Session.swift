import Foundation
import Observation

@MainActor
@Observable
final class Session {
    var mode: Mode { didSet { apply() } }
    var intensity: Intensity { didSet { apply() } }
    var binaural: Bool { didSet { apply() } }
    var length: SessionLength { didSet { restartTimer() } }

    /// Each mode remembers its own soundscape. Steady modes ignore the choice.
    var soundscape: Soundscape {
        get { mode.isSteady ? mode.defaultSoundscape : soundscapes[mode] ?? mode.defaultSoundscape }
        set {
            guard !mode.isSteady else { return }
            soundscapes[mode] = newValue
            apply()
        }
    }
    private var soundscapes: [Mode: Soundscape]

    private(set) var isPlaying = false
    /// Seconds left in a timed session. Nil when endless.
    private(set) var remaining: Int?

    private let engine: AudioEngine
    private let defaults = UserDefaults.standard
    private var timerTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        engine = try! AudioEngine()
        mode = Mode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .focus
        intensity = Intensity(rawValue: defaults.string(forKey: "intensity") ?? "") ?? .medium
        binaural = defaults.object(forKey: "binaural") as? Bool ?? false
        length = SessionLength(rawValue: defaults.integer(forKey: "length")) ?? .endless
        soundscapes = Dictionary(uniqueKeysWithValues: Mode.allCases.compactMap { mode in
            Soundscape(rawValue: UserDefaults.standard.string(forKey: "soundscape.\(mode.rawValue)") ?? "").map { (mode, $0) }
        })
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
        isPlaying = true
        restartTimer()
        NowPlaying.update(self)
    }

    func pause() {
        isPlaying = false
        timerTask?.cancel()
        remaining = length == .endless ? nil : length.rawValue * 60
        applyMaster()
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
        applyMaster()

        defaults.set(mode.rawValue, forKey: "mode")
        defaults.set(intensity.rawValue, forKey: "intensity")
        defaults.set(binaural, forKey: "binaural")
        defaults.set(length.rawValue, forKey: "length")
        for (mode, soundscape) in soundscapes {
            defaults.set(soundscape.rawValue, forKey: "soundscape.\(mode.rawValue)")
        }
        NowPlaying.update(self)
    }

    /// Full level while playing, tapering linearly over the mode's fade-out
    /// as a timed session runs down. The synths smooth the one-second steps.
    private func applyMaster() {
        let gain = remaining.map { min(1, Double($0) / mode.fadeOut) } ?? 1
        engine.parameters.master.store(isPlaying ? gain : 0, ordering: .relaxed)
    }

    private func restartTimer() {
        defaults.set(length.rawValue, forKey: "length")
        timerTask?.cancel()
        remaining = length == .endless ? nil : length.rawValue * 60
        applyMaster()
        guard isPlaying, remaining != nil else { return }
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let left = remaining else { return }
                if left <= 1 {
                    pause()
                    return
                }
                remaining = left - 1
                applyMaster()
            }
        }
    }
}
