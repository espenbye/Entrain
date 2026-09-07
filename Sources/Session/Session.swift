#if canImport(AppKit)
import AppKit
#endif
import Foundation
import Observation
import WidgetKit

@MainActor
@Observable
final class Session {
    static let shared = Session(defaults: .standard, mindful: health, cloud: NSUbiquitousKeyValueStore.default) {
        AudioEngine(parameters: $0)
    }

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
    /// Whether the room turns with the head over motion-reporting headphones.
    /// Off by default and never in bed: see `Mode.tracksHead`. Local, like
    /// Now Playing: it is about the headphones on this device.
    var headTracking: Bool {
        didSet {
            apply()
            defaults.set(headTracking, forKey: "headTracking")
        }
    }
    /// Whether any headphones on this platform can report motion.
    let headTrackingAvailable: Bool
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
    /// iCloud's key-value store: a setting changed on one device reaches the
    /// others. Nil in tests. Without the entitlement or an account the store
    /// just does not sync, so a development build runs unchanged.
    private let cloud: (any SettingsStore)?
    private var cloudObserver: NSObjectProtocol?
    /// Off until launch has taken the store in, and while a remote change is
    /// applied, so the store's own values are not sent back over each other.
    private var mirrors = false
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
    #if os(iOS)
    private let activity = SessionLiveActivity()
    #endif
    #if os(macOS)
    private var sleepObserver: NSObjectProtocol?
    #endif

    init(
        defaults: UserDefaults,
        widgetDirectory: URL? = WidgetState.directory,
        mindful: (any MindfulLog)? = nil,
        cloud: (any SettingsStore)? = nil,
        makeEngine: @escaping @MainActor (AudioParameters) -> any SessionAudio
    ) {
        self.defaults = defaults
        self.widgetDirectory = widgetDirectory
        self.mindful = mindful
        self.cloud = cloud
        self.makeEngine = makeEngine
        widgetState = WidgetState.load(from: widgetDirectory)
        mode = Mode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .focus
        intensity = Intensity(rawValue: defaults.string(forKey: "intensity") ?? "") ?? .medium
        binaural = defaults.object(forKey: "binaural") as? Bool ?? false
        length = SessionLength(rawValue: defaults.integer(forKey: "length")) ?? .endless
        volume = defaults.object(forKey: "volume") as? Double ?? 1
        nowPlaying = defaults.object(forKey: "nowPlaying") as? Bool ?? Self.nowPlayingByDefault
        headphones = OutputRoute.headphones
        headTracking = defaults.bool(forKey: "headTracking")
        #if canImport(CoreMotion) && !os(watchOS)
        headTrackingAvailable = HeadTracker.isAvailable
        #else
        headTrackingAvailable = false
        #endif
        layersByMode = Dictionary(uniqueKeysWithValues: Mode.allCases.compactMap { mode in
            let layers = Self.layers(from: defaults.string(forKey: Self.layersKey(mode)))
            return layers.isEmpty ? nil : (mode, layers)
        })
        remaining = length == .endless ? nil : length.seconds
        parameters.volume.store(volume, ordering: .relaxed)
        apply()
        if nowPlaying { NowPlaying.attach(to: self) }
        route = OutputRoute { [weak self] headphones in self?.headphones = headphones }

        if let cloud {
            // Changes that arrived while the app was not running are in the
            // store already; later ones come as notifications.
            cloud.synchronize()
            pull(Self.syncedKeys)
            mirrors = true
            cloudObserver = NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, queue: .main
            ) { [weak self] note in
                let keys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? Self.syncedKeys
                MainActor.assumeIsolated { self?.pull(keys) }
            }
        }

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

    /// Head tracking as the engine should run it now.
    private var tracksHead: Bool { headTracking && headphones && mode.tracksHead }

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
        interruptedByAudio = false
        stopTask?.cancel()
        let engine = self.engine ?? {
            let engine = makeEngine(parameters)
            engine.onInterruption = { [weak self] in self?.interrupted() }
            engine.onInterruptionEnded = { [weak self] in await self?.interruptionEnded(shouldResume: $0) }
            engine.mixesWithOthers = !nowPlaying
            engine.headphones = headphones
            engine.headTracking = tracksHead
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
        isPlaying = true
        playStart = .now
        startMindful()
        startTimer()
        applyMaster()
        broadcast()
    }

    func pause() {
        interruptedByAudio = false
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
        engine?.headphones = headphones
        engine?.headTracking = tracksHead
        applyMaster()
        save()
        broadcast()
    }

    private func applyRate() {
        parameters.modulationRate.store(mode.rate(elapsed: playTime, length: length), ordering: .relaxed)
    }

    private func save() {
        store(mode.rawValue, forKey: "mode")
        store(intensity.rawValue, forKey: "intensity")
        store(binaural, forKey: "binaural")
        store(length.rawValue, forKey: "length")
        store(volume, forKey: "volume")
        // Now Playing means something else on each platform, so it stays local.
        defaults.set(nowPlaying, forKey: "nowPlaying")
        for (mode, layers) in layersByMode {
            store(Soundscape.allCases.filter(layers.contains).map(\.rawValue).joined(separator: ","), forKey: Self.layersKey(mode))
        }
    }

    // MARK: iCloud

    /// Defaults get every value; the cloud only what differs from it, so a
    /// value that just arrived from another device is not sent straight back.
    private func store<V: Equatable>(_ value: V, forKey key: String) {
        defaults.set(value, forKey: key)
        guard mirrors, let cloud, cloud.object(forKey: key) as? V != value else { return }
        cloud.set(value, forKey: key)
    }

    private static let syncedKeys = ["mode", "intensity", "binaural", "length", "volume"] + Mode.allCases.map { layersKey($0) }

    nonisolated private static func layersKey(_ mode: Mode) -> String { "layers.\(mode.rawValue)" }

    nonisolated private static func layers(from stored: String?) -> Set<Soundscape> {
        Set((stored ?? "").split(separator: ",").compactMap { Soundscape(rawValue: String($0)) })
    }

    /// Takes the store's values for `keys` into the session. Only what differs
    /// is assigned, so the setters do the rest: defaults, atomics, widget.
    /// A playing device hears the change; an idle one only remembers it.
    private func pull(_ keys: [String]) {
        guard let cloud else { return }
        let mirrored = mirrors
        mirrors = false
        defer { mirrors = mirrored }
        for key in keys {
            switch key {
            case "mode":
                if let value = (cloud.object(forKey: key) as? String).flatMap(Mode.init), value != mode { mode = value }
            case "intensity":
                if let value = (cloud.object(forKey: key) as? String).flatMap(Intensity.init), value != intensity { intensity = value }
            case "binaural":
                if let value = cloud.object(forKey: key) as? Bool, value != binaural { binaural = value }
            case "length":
                if let value = (cloud.object(forKey: key) as? Int).flatMap(SessionLength.init), value != length { length = value }
            case "volume":
                if let value = cloud.object(forKey: key) as? Double, value != volume { volume = value }
            default:
                guard key.hasPrefix("layers."), let mode = Mode(rawValue: String(key.dropFirst("layers.".count))) else { continue }
                let layers = Self.layers(from: cloud.object(forKey: key) as? String)
                guard !layers.isEmpty, layers != layersByMode[mode] else { continue }
                layersByMode[mode] = layers
                mode == self.mode ? apply() : save()
            }
        }
    }

    /// Full level while playing, tapering linearly over the mode's fade-out
    /// as a timed session runs down. The synths smooth the one-second steps.
    private func applyMaster() {
        let gain = isPlaying ? Self.masterGain(remaining: remaining, fadeOut: mode.fadeOut) : 0
        parameters.master.store(gain, ordering: .relaxed)
    }

    /// Tells Now Playing, the Live Activity, the widget and Control Center
    /// about a state change. The last two read the snapshot file, so they
    /// need no live connection.
    private func broadcast() {
        NowPlaying.update(self)
        #if os(iOS)
        activity.update(SessionActivityAttributes.ContentState.snapshot(
            mode: mode, sound: layers.title, isPlaying: isPlaying, remaining: remaining, deadline: deadline
        ))
        #endif
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

    /// A new length starts the countdown over, even mid-session, and the
    /// ramp with it: a timed ramp is measured against the timer.
    private func resetTimer() {
        stopTimer()
        remaining = length == .endless ? nil : length.seconds
        played = 0
        playStart = isPlaying ? .now : nil
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
        #if os(iOS)
        activity.end()
        #endif
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
