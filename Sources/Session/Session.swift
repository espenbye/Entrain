import AppKit
import Foundation
import Observation
import WidgetKit

@MainActor
@Observable
final class Session {
    static let shared = Session(defaults: .standard) { AudioEngine(parameters: $0) }

    var mode: Mode { didSet { apply() } }
    var intensity: Intensity { didSet { apply() } }
    var binaural: Bool { didSet { apply() } }
    var length: SessionLength { didSet { resetTimer(); save() } }
    /// Control Center and media keys. Off keeps the media keys with the music player.
    var nowPlaying: Bool {
        didSet {
            nowPlaying ? NowPlaying.attach(to: self) : NowPlaying.detach()
            save()
        }
    }
    /// 0...1, on top of the system output level.
    var volume: Double {
        didSet {
            parameters.volume.store(volume, ordering: .relaxed)
            save()
        }
    }

    /// The soundscapes playing together, remembered per mode. Steady modes
    /// keep their fixed bed.
    var layers: Set<Soundscape> {
        mode.isSleep ? mode.defaultLayers : layersByMode[mode] ?? mode.defaultLayers
    }
    private var layersByMode: [Mode: Set<Soundscape>]

    /// Adds or removes one layer. The last layer stays: silence is pause, not a mix.
    func setLayer(_ soundscape: Soundscape, on: Bool) {
        guard !mode.isSleep else { return }
        var layers = layers
        if on { layers.insert(soundscape) } else if layers.count > 1 { layers.remove(soundscape) }
        layersByMode[mode] = layers
        apply()
    }

    private(set) var isPlaying = false
    /// Seconds left in a timed session. Nil when endless. Pausing keeps it,
    /// so resuming picks up where the session stopped.
    private(set) var remaining: Int?
    /// Why there is no sound although the user pressed play. Nil once audio is running.
    private(set) var error: String?

    let parameters = AudioParameters()
    private let defaults: UserDefaults
    /// The folder the widget reads. Tests pass a scratch directory.
    private let widgetDirectory: URL?
    private let makeEngine: @MainActor (AudioParameters) -> any SessionAudio
    /// Created on first play: a login item should not touch audio hardware at launch.
    private var engine: (any SessionAudio)?
    /// Wall-clock end of the running timed session. Remaining is derived from
    /// it, so the countdown cannot drift.
    private var deadline: ContinuousClock.Instant?
    private var tickTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    private var sleepObserver: NSObjectProtocol?

    init(
        defaults: UserDefaults,
        widgetDirectory: URL? = WidgetState.directory,
        makeEngine: @escaping @MainActor (AudioParameters) -> any SessionAudio
    ) {
        self.defaults = defaults
        self.widgetDirectory = widgetDirectory
        self.makeEngine = makeEngine
        mode = Mode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .focus
        intensity = Intensity(rawValue: defaults.string(forKey: "intensity") ?? "") ?? .medium
        binaural = defaults.object(forKey: "binaural") as? Bool ?? false
        length = SessionLength(rawValue: defaults.integer(forKey: "length")) ?? .endless
        volume = defaults.object(forKey: "volume") as? Double ?? 1
        nowPlaying = defaults.object(forKey: "nowPlaying") as? Bool ?? true
        layersByMode = Dictionary(uniqueKeysWithValues: Mode.allCases.compactMap { mode in
            let stored = defaults.string(forKey: "layers.\(mode.rawValue)")?.split(separator: ",") ?? []
            let layers = Set(stored.compactMap { Soundscape(rawValue: String($0)) })
            return layers.isEmpty ? nil : (mode, layers)
        })
        remaining = length == .endless ? nil : length.seconds
        parameters.volume.store(volume, ordering: .relaxed)
        apply()
        if nowPlaying { NowPlaying.attach(to: self) }

        // A session that outlives the Mac's sleep would otherwise resume on
        // wake, which for Sleep mode means brown noise at breakfast.
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
        }
    }

    var title: String { "\(mode.title) · \(layers.title)" }

    /// Seconds into the current timed session. Nil when endless.
    var elapsed: Int? { remaining.map { length.seconds - $0 } }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func play() {
        stopTask?.cancel()
        let engine = self.engine ?? {
            let engine = makeEngine(parameters)
            engine.onInterruption = { [weak self] in self?.interrupted() }
            self.engine = engine
            return engine
        }()
        do {
            try engine.start()
            error = nil
        } catch {
            self.error = String(localized: "Audio unavailable")
            return
        }
        isPlaying = true
        startTimer()
        applyMaster()
        broadcast()
    }

    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        stopTimer()
        applyMaster()
        broadcast()
        stopTask = Task { [engine] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            engine?.stop()
        }
    }

    /// The engine stopped on its own and could not come back.
    private func interrupted() {
        pause()
        error = String(localized: "Audio stopped")
    }

    private func apply() {
        let p = parameters
        p.modulationRate.store(mode.rate, ordering: .relaxed)
        p.modulationDepth.store(mode.isSleep ? mode.depth : min(0.9, mode.depth * intensity.multiplier), ordering: .relaxed)
        p.binauralCarrier.store(mode.carrier, ordering: .relaxed)
        p.binauralLevel.store(binaural ? 0.12 : 0, ordering: .relaxed)
        p.layers.store(layers.mask, ordering: .relaxed)
        applyMaster()
        save()
        broadcast()
    }

    private func save() {
        defaults.set(mode.rawValue, forKey: "mode")
        defaults.set(intensity.rawValue, forKey: "intensity")
        defaults.set(binaural, forKey: "binaural")
        defaults.set(length.rawValue, forKey: "length")
        defaults.set(volume, forKey: "volume")
        defaults.set(nowPlaying, forKey: "nowPlaying")
        for (mode, layers) in layersByMode {
            let stored = Soundscape.allCases.filter(layers.contains).map(\.rawValue).joined(separator: ",")
            defaults.set(stored, forKey: "layers.\(mode.rawValue)")
        }
    }

    /// Full level while playing, tapering linearly over the mode's fade-out
    /// as a timed session runs down. The synths smooth the one-second steps.
    private func applyMaster() {
        let gain = isPlaying ? Self.masterGain(remaining: remaining, fadeOut: mode.fadeOut) : 0
        parameters.master.store(gain, ordering: .relaxed)
    }

    /// Tells Now Playing, the widget and Control Center about a state change.
    /// Both read the snapshot file, so they need no live connection.
    private func broadcast() {
        NowPlaying.update(self)
        WidgetState(
            mode: mode,
            sound: layers.title,
            isPlaying: isPlaying,
            remaining: remaining,
            deadline: isPlaying ? remaining.map { Date.now.addingTimeInterval(Double($0)) } : nil
        ).save(to: widgetDirectory)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetState.kind)
        ControlCenter.shared.reloadAllControls()
    }

    static func masterGain(remaining: Int?, fadeOut: Double) -> Double {
        remaining.map { min(1, Double($0) / fadeOut) } ?? 1
    }

    // MARK: Timer

    /// A new length starts the countdown over, even mid-session.
    private func resetTimer() {
        stopTimer()
        remaining = length == .endless ? nil : length.seconds
        if isPlaying { startTimer() }
        applyMaster()
        broadcast()
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
        broadcast()
    }

    private static func secondsLeft(until deadline: ContinuousClock.Instant) -> Int {
        let parts = (deadline - .now).components
        let seconds = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
        return max(0, Int(seconds.rounded(.up)))
    }
}
