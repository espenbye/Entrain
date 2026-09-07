#if canImport(AppKit)
import AppKit
#endif
import Foundation
import Observation
import WidgetKit

@MainActor
@Observable
final class Session {
    static let shared = Session(defaults: .standard, mindful: health) { AudioEngine(parameters: $0) }

    var mode: Mode {
        didSet {
            endMindful()
            played = 0
            playStart = isPlaying ? .now : nil
            if isPlaying { startMindful() }
            apply()
        }
    }
    var intensity: Intensity { didSet { apply() } }
    var binaural: Bool { didSet { apply() } }
    /// Whether the output is headphones. Binaural beats need one carrier per
    /// ear, so over speakers the layer is muted and the UI says why.
    var headphones: Bool { didSet { apply() } }
    private var route: OutputRoute?
    var length: SessionLength { didSet { resetTimer(); save() } }
    /// Control Center and media keys. Off keeps the media keys with the music player.
    var nowPlaying: Bool {
        didSet {
            nowPlaying ? NowPlaying.attach(to: self) : NowPlaying.detach()
            engine?.mixesWithOthers = !nowPlaying
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
    /// Wall-clock end of the running timed session. Nil when endless or
    /// paused. Views count down from it themselves, so nothing observes
    /// the once-a-second tick.
    private(set) var deadline: Date?
    /// Seconds left in a timed session. Nil when endless. Pausing keeps it,
    /// so resuming picks up where the session stopped. Not observed: it
    /// changes every second, and only the fade and the paused label read it.
    @ObservationIgnored private(set) var remaining: Int?
    /// Why there is no sound although the user pressed play. Nil once audio is running.
    private(set) var error: String?

    let parameters = AudioParameters()
    private let defaults: UserDefaults
    /// The folder the widget reads. Tests pass a scratch directory.
    private let widgetDirectory: URL?
    private let makeEngine: @MainActor (AudioParameters) -> any SessionAudio
    private let mindful: (any MindfulLog)?
    /// Wall-clock start of the Meditate segment playing now.
    private var mindfulStart: Date?
    /// Created on first play: a login item should not touch audio hardware at launch.
    private var engine: (any SessionAudio)?
    /// The deadline on the monotonic clock. Remaining is derived from it, so
    /// the countdown cannot drift.
    private var tickDeadline: ContinuousClock.Instant?
    /// Play time in this mode, which is what a ramp walks along. `played`
    /// accumulates across pauses; `playStart` is set while playing.
    private var played: Double = 0
    private var playStart: ContinuousClock.Instant?
    private var tickTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    /// Set while a system interruption holds the session paused; cleared by
    /// anything the user does, so only the interruption's end resumes.
    private var interruptedByAudio = false
    /// What the widget last got. iOS budgets a few dozen reloads a day, so
    /// only a snapshot that differs from it is written and reloaded.
    private var widgetState: WidgetState?
    #if os(macOS)
    private var sleepObserver: NSObjectProtocol?
    #endif

    init(
        defaults: UserDefaults,
        widgetDirectory: URL? = WidgetState.directory,
        mindful: (any MindfulLog)? = nil,
        makeEngine: @escaping @MainActor (AudioParameters) -> any SessionAudio
    ) {
        self.defaults = defaults
        self.widgetDirectory = widgetDirectory
        self.mindful = mindful
        self.makeEngine = makeEngine
        widgetState = WidgetState.load(from: widgetDirectory)
        mode = Mode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .focus
        intensity = Intensity(rawValue: defaults.string(forKey: "intensity") ?? "") ?? .medium
        binaural = defaults.object(forKey: "binaural") as? Bool ?? false
        length = SessionLength(rawValue: defaults.integer(forKey: "length")) ?? .endless
        volume = defaults.object(forKey: "volume") as? Double ?? 1
        nowPlaying = defaults.object(forKey: "nowPlaying") as? Bool ?? Self.nowPlayingByDefault
        headphones = OutputRoute.headphones
        layersByMode = Dictionary(uniqueKeysWithValues: Mode.allCases.compactMap { mode in
            let stored = defaults.string(forKey: "layers.\(mode.rawValue)")?.split(separator: ",") ?? []
            let layers = Set(stored.compactMap { Soundscape(rawValue: String($0)) })
            return layers.isEmpty ? nil : (mode, layers)
        })
        remaining = length == .endless ? nil : length.seconds
        parameters.volume.store(volume, ordering: .relaxed)
        apply()
        if nowPlaying { NowPlaying.attach(to: self) }
        route = OutputRoute { [weak self] headphones in self?.headphones = headphones }

        #if os(macOS)
        // A session that outlives the Mac's sleep would otherwise resume on
        // wake, which for Sleep mode means brown noise at breakfast.
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
        }
        #endif
    }

    private static var health: (any MindfulLog)? {
        #if os(iOS) || os(watchOS)
        MindfulMinutes()
        #else
        nil
        #endif
    }

    /// On the Mac, Now Playing costs nothing but the media keys. On iOS it
    /// costs the blend: an app that owns the Lock Screen controls cannot mix
    /// under other audio, so there the soundscape sits under music by default.
    private static var nowPlayingByDefault: Bool {
        #if os(iOS)
        false
        #else
        true
        #endif
    }

    var title: String { "\(mode.title) · \(layers.title)" }

    /// Seconds into the current timed session. Nil when endless.
    var elapsed: Int? { remaining.map { length.seconds - $0 } }

    /// Seconds this mode has played, across pauses.
    private var playTime: Double {
        played + (playStart.map { Self.seconds(since: $0) } ?? 0)
    }

    func toggle() async {
        if isPlaying { pause() } else { await play() }
    }

    /// Async because the watch may have to ask which headphones to use before
    /// its audio route exists; on the Mac and iPhone the engine starts at once.
    func play() async {
        stopTask?.cancel()
        let engine = self.engine ?? {
            let engine = makeEngine(parameters)
            engine.onInterruption = { [weak self] in self?.interrupted() }
            engine.onInterruptionEnded = { [weak self] in await self?.interruptionEnded(shouldResume: $0) }
            engine.mixesWithOthers = !nowPlaying
            self.engine = engine
            return engine
        }()
        do {
            try await engine.start()
            error = nil
        } catch {
            self.error = String(localized: "Audio unavailable")
            return
        }
        interruptedByAudio = false
        isPlaying = true
        playStart = .now
        startMindful()
        startTimer()
        applyMaster()
        broadcast()
    }

    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        played = playTime
        playStart = nil
        endMindful()
        stopTimer()
        applyMaster()
        broadcast()
        // After the fade the engine is released outright, so an idle app holds
        // no audio hardware. `play()` builds a fresh one.
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, let self else { return }
            engine?.stop()
            engine = nil
        }
    }

    /// A Focus filter. A mode means its Focus turned on: start it, and
    /// remember whether it wants the session paused when it turns off. No
    /// mode and no stop flag is the empty filter the system sends once every
    /// Focus is off. The flag lives in defaults because that later call
    /// carries nothing of the filter that set it.
    func applyFocusFilter(mode: Mode?, length: SessionLength?, stopWhenOff: Bool) async {
        let key = "focusFilter.stopWhenOff"
        if let mode {
            defaults.set(stopWhenOff, forKey: key)
            self.mode = mode
            if let length { self.length = length }
            await play()
        } else if stopWhenOff {
            defaults.set(true, forKey: key)
        } else if defaults.bool(forKey: key) {
            defaults.set(false, forKey: key)
            pause()
        }
    }

    /// The engine stopped on its own. The engine is kept so the end of a
    /// system interruption still reaches it; a deliberate pause releases it.
    private func interrupted() {
        pause()
        stopTask?.cancel()
        interruptedByAudio = true
        error = String(localized: "Audio stopped")
    }

    /// Resumes when the system says so and nothing else happened in between;
    /// otherwise the idle engine is released like after any other pause.
    private func interruptionEnded(shouldResume: Bool) async {
        guard interruptedByAudio else { return }
        interruptedByAudio = false
        if shouldResume {
            await play()
        } else {
            engine?.stop()
            engine = nil
        }
    }

    // MARK: Mindful minutes

    /// Meditate is the one mode Health has a place for. Each stretch of play
    /// is its own segment, so a pause is a break, not part of the session.
    private func startMindful() {
        guard mode == .meditate else { return }
        mindfulStart = .now
        mindful?.prepare()
    }

    private func endMindful() {
        guard let start = mindfulStart else { return }
        mindfulStart = nil
        mindful?.log(DateInterval(start: start, end: .now))
    }

    private func apply() {
        let p = parameters
        applyRate()
        p.modulationDepth.store(mode.isSleep ? mode.depth : min(0.9, mode.depth * intensity.multiplier), ordering: .relaxed)
        p.binauralCarrier.store(mode.carrier, ordering: .relaxed)
        p.binauralLevel.store(binaural && headphones ? 0.12 : 0, ordering: .relaxed)
        p.layers.store(layers.mask, ordering: .relaxed)
        applyMaster()
        save()
        broadcast()
    }

    private func applyRate() {
        parameters.modulationRate.store(mode.rate(elapsed: playTime, length: length), ordering: .relaxed)
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
        let state = WidgetState(
            mode: mode,
            sound: layers.title,
            isPlaying: isPlaying,
            remaining: remaining,
            deadline: deadline
        )
        guard !state.matches(widgetState) else { return }
        widgetState = state
        state.save(to: widgetDirectory)
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
        applyRate()
        applyMaster()
        broadcast()
    }

    /// Ticks once a second while there is a countdown to keep or a ramp to
    /// walk. An endless session stops ticking once its ramp has arrived.
    private func startTimer() {
        let deadline = remaining.map { ContinuousClock.now + .seconds($0) }
        let rampSeconds = mode.rampSeconds(for: length)
        guard deadline != nil || rampSeconds != nil else { return }
        tickDeadline = deadline
        self.deadline = remaining.map { Date.now.addingTimeInterval(Double($0)) }
        tickTask = Task {
            while !Task.isCancelled {
                applyRate()
                guard let deadline else {
                    if let rampSeconds, playTime >= rampSeconds {
                        tickTask = nil
                        return
                    }
                    try? await Task.sleep(for: .seconds(1))
                    continue
                }
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
        tickDeadline = nil
        deadline = nil
    }

    /// The timed session ran out: stop, and arm the full length for next time.
    private func finish() {
        pause()
        remaining = length.seconds
        broadcast()
    }

    private static func secondsLeft(until deadline: ContinuousClock.Instant) -> Int {
        max(0, Int(seconds(since: .now, until: deadline).rounded(.up)))
    }

    private static func seconds(since start: ContinuousClock.Instant, until end: ContinuousClock.Instant = .now) -> Double {
        let parts = (end - start).components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
