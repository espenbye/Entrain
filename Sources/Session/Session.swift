import Foundation
import Observation

@MainActor
@Observable
final class Session {
    var mode: Mode { didSet { apply() } }
    var intensity: Intensity { didSet { apply() } }
    var binaural: Bool { didSet { apply() } }
    var length: SessionLength { didSet { resetTimer(); save() } }
    /// 0...1, on top of the system output level.
    var volume: Double {
        didSet {
            engine.parameters.volume.store(volume, ordering: .relaxed)
            save()
        }
    }

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
    /// Seconds left in a timed session. Nil when endless. Pausing keeps it,
    /// so resuming picks up where the session stopped.
    private(set) var remaining: Int?
    /// Why the last play attempt produced no sound. Nil once audio is running.
    private(set) var error: String?

    private let engine = AudioEngine()
    private let defaults = UserDefaults.standard
    /// Wall-clock end of the running timed session. Remaining is derived from
    /// it, so the countdown cannot drift.
    private var deadline: ContinuousClock.Instant?
    private var tickTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        mode = Mode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .focus
        intensity = Intensity(rawValue: defaults.string(forKey: "intensity") ?? "") ?? .medium
        binaural = defaults.object(forKey: "binaural") as? Bool ?? false
        length = SessionLength(rawValue: defaults.integer(forKey: "length")) ?? .endless
        volume = defaults.object(forKey: "volume") as? Double ?? 1
        soundscapes = Dictionary(uniqueKeysWithValues: Mode.allCases.compactMap { mode in
            Soundscape(rawValue: defaults.string(forKey: "soundscape.\(mode.rawValue)") ?? "").map { (mode, $0) }
        })
        remaining = length == .endless ? nil : length.seconds
        engine.parameters.volume.store(volume, ordering: .relaxed)
        apply()
        NowPlaying.attach(to: self)
    }

    var title: String { "\(mode.title) · \(soundscape.title)" }

    /// Seconds into the current timed session. Nil when endless.
    var elapsed: Int? { remaining.map { length.seconds - $0 } }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func play() {
        stopTask?.cancel()
        do {
            try engine.start()
            error = nil
        } catch {
            self.error = "Audio unavailable"
            return
        }
        isPlaying = true
        startTimer()
        applyMaster()
        NowPlaying.update(self)
    }

    func pause() {
        isPlaying = false
        stopTimer()
        applyMaster()
        NowPlaying.update(self)
        stopTask = Task { [engine] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            engine.stop()
        }
    }

    private func apply() {
        let p = engine.parameters
        p.modulationRate.store(mode.rate, ordering: .relaxed)
        p.modulationDepth.store(min(0.9, mode.depth * intensity.multiplier), ordering: .relaxed)
        p.binauralCarrier.store(mode.carrier, ordering: .relaxed)
        p.binauralLevel.store(binaural ? 0.12 : 0, ordering: .relaxed)
        p.soundscape.store(soundscape.index, ordering: .relaxed)
        applyMaster()
        save()
        NowPlaying.update(self)
    }

    private func save() {
        defaults.set(mode.rawValue, forKey: "mode")
        defaults.set(intensity.rawValue, forKey: "intensity")
        defaults.set(binaural, forKey: "binaural")
        defaults.set(length.rawValue, forKey: "length")
        defaults.set(volume, forKey: "volume")
        for (mode, soundscape) in soundscapes {
            defaults.set(soundscape.rawValue, forKey: "soundscape.\(mode.rawValue)")
        }
    }

    /// Full level while playing, tapering linearly over the mode's fade-out
    /// as a timed session runs down. The synths smooth the one-second steps.
    private func applyMaster() {
        let gain = remaining.map { min(1, Double($0) / mode.fadeOut) } ?? 1
        engine.parameters.master.store(isPlaying ? gain : 0, ordering: .relaxed)
    }

    // MARK: Timer

    /// A new length starts the countdown over, even mid-session.
    private func resetTimer() {
        stopTimer()
        remaining = length == .endless ? nil : length.seconds
        if isPlaying { startTimer() }
        applyMaster()
        NowPlaying.update(self)
    }

    private func startTimer() {
        guard let remaining else { return }
        let deadline = ContinuousClock.now + .seconds(remaining)
        self.deadline = deadline
        tickTask = Task {
            while !Task.isCancelled {
                let left = Self.secondsLeft(until: deadline)
                self.remaining = left
                applyMaster()
                if left <= 0 {
                    finish()
                    return
                }
                try? await Task.sleep(until: deadline - .seconds(left - 1))
            }
        }
    }

    private func stopTimer() {
        tickTask?.cancel()
        tickTask = nil
        deadline = nil
    }

    /// The timed session ran out: stop, and arm the full length for next time.
    private func finish() {
        pause()
        remaining = length.seconds
    }

    private static func secondsLeft(until deadline: ContinuousClock.Instant) -> Int {
        let parts = (deadline - .now).components
        let seconds = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
        return max(0, Int(seconds.rounded(.up)))
    }
}
