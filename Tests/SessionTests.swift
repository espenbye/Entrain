import Foundation
import Testing
@testable import Entrain

/// Session logic against a fake engine and a throwaway defaults suite.
@MainActor
struct SessionTests {
    final class FakeAudio: SessionAudio {
        var onInterruption: (() -> Void)?
        var onInterruptionEnded: ((Bool) async -> Void)?
        var mixesWithOthers = false
        var headphones = true
        var headTracking = false
        var starts = 0
        var stops = 0
        var failsToStart = false

        struct Unavailable: Error {}

        func start() async throws {
            if failsToStart { throw Unavailable() }
            starts += 1
        }

        func stop() { stops += 1 }
    }

    final class FakeMindful: MindfulLog {
        var prepared = 0
        var segments: [DateInterval] = []
        func prepare() { prepared += 1 }
        func log(_ segment: DateInterval) { segments.append(segment) }
    }

    /// The iCloud store as a dictionary. `changed` plays the other device.
    final class FakeCloud: SettingsStore {
        var values: [String: Any] = [:]
        var writes = 0
        func object(forKey key: String) -> Any? { values[key] }
        func set(_ value: Any?, forKey key: String) {
            values[key] = value
            writes += 1
        }
        func synchronize() -> Bool { true }
        func changed(_ keys: [String]) {
            NotificationCenter.default.post(
                name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: self,
                userInfo: [NSUbiquitousKeyValueStoreChangedKeysKey: keys]
            )
        }
    }

    let defaults: UserDefaults
    let widgetDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let audio = FakeAudio()

    init() {
        let suite = "entrain.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.createDirectory(at: widgetDirectory, withIntermediateDirectories: true)
    }

    func makeSession() -> Session {
        Session(defaults: defaults, widgetDirectory: widgetDirectory) { [audio] _ in audio }
    }

    @Test func settingsSurviveRelaunch() {
        let first = makeSession()
        first.mode = .relax
        first.setLayer(.drone, on: true)
        first.mode = .meditate
        first.intensity = .high
        first.binaural = true
        first.length = .thirty
        first.volume = 0.4
        first.nowPlaying = false

        let second = makeSession()
        #expect(second.mode == .meditate)
        #expect(second.intensity == .high)
        #expect(second.binaural)
        #expect(second.length == .thirty)
        #expect(second.volume == 0.4)
        #expect(!second.nowPlaying)
        #expect(second.layers == [.pad])
        second.mode = .relax
        #expect(second.layers == [.pad, .drone])
    }

    @Test func settingsReachTheCloudAndComeBack() async {
        let cloud = FakeCloud()
        let session = Session(defaults: defaults, widgetDirectory: widgetDirectory, cloud: cloud) { [audio] _ in audio }
        session.mode = .relax
        session.setLayer(.drone, on: true)
        session.length = .thirty
        session.nowPlaying = false
        #expect(cloud.values["mode"] as? String == "relax")
        #expect(cloud.values["layers.relax"] as? String == "pad,drone")
        #expect(cloud.values["length"] as? Int == SessionLength.thirty.rawValue)
        #expect(cloud.values["nowPlaying"] == nil)

        // Another device changed its settings; this one follows without echoing them back.
        let writes = cloud.writes
        cloud.values["mode"] = "meditate"
        cloud.values["intensity"] = "high"
        cloud.values["binaural"] = true
        cloud.values["volume"] = 0.3
        cloud.values["layers.meditate"] = "pad,rain"
        cloud.changed(["mode", "intensity", "binaural", "volume", "layers.meditate"])
        #expect(session.mode == .meditate)
        #expect(session.intensity == .high)
        #expect(session.binaural)
        #expect(session.volume == 0.3)
        #expect(session.layers == [.pad, .rain])
        #expect(session.parameters.layers.load(ordering: .relaxed) == Soundscape.pad.bit | Soundscape.rain.bit)
        #expect(cloud.writes == writes)
        #expect(!session.isPlaying)
        #expect(audio.starts == 0)
        #expect(defaults.string(forKey: "mode") == "meditate")

        // A change that arrived while the app was closed is read at launch.
        cloud.values["length"] = SessionLength.sixty.rawValue
        let relaunched = Session(defaults: defaults, widgetDirectory: widgetDirectory, cloud: cloud) { [audio] _ in audio }
        #expect(relaunched.length == .sixty)
        #expect(relaunched.mode == .meditate)
    }

    @Test func focusFilterStartsItsModeAndStopsWhenAsked() async {
        let session = makeSession()
        await session.applyFocusFilter(mode: .relax, length: .thirty, stopWhenOff: true)
        #expect(session.isPlaying)
        #expect(session.mode == .relax)
        #expect(session.length == .thirty)

        // Every Focus off: the filter arrives empty.
        await session.applyFocusFilter(mode: nil, length: nil, stopWhenOff: false)
        #expect(!session.isPlaying)

        // A filter that does not ask to stop leaves the session alone at the end.
        await session.applyFocusFilter(mode: .focus, length: nil, stopWhenOff: false)
        #expect(session.length == .thirty)
        await session.applyFocusFilter(mode: nil, length: nil, stopWhenOff: false)
        #expect(session.isPlaying)
    }

    /// A Focus filter landing on a session that is already playing a timed
    /// session replaces its timer rather than adding one: after the pause
    /// nothing ticks, and the countdown is the filter's, not the old one.
    @Test func focusFilterOnARunningSessionReplacesItsTimer() async {
        let session = makeSession()
        session.mode = .focus
        session.length = .sixty
        await session.play()
        let first = session.deadline
        #expect(first != nil)

        await session.applyFocusFilter(mode: .relax, length: .fifteen, stopWhenOff: false)
        #expect(session.isPlaying)
        #expect(session.remaining == SessionLength.fifteen.seconds)
        #expect(session.deadline != first)
        #expect(audio.starts == 2)

        session.pause()
        #expect(!session.isPlaying)
        #expect(session.deadline == nil)
        #expect(session.remaining == SessionLength.fifteen.seconds)
        session.length = .thirty
        #expect(session.remaining == SessionLength.thirty.seconds)
        #expect(session.parameters.master.load(ordering: .relaxed) == 0)
    }

    @Test func focusFilterStopFlagSurvivesRelaunch() async {
        await makeSession().applyFocusFilter(mode: nil, length: nil, stopWhenOff: true)
        let session = makeSession()
        await session.play()
        await session.applyFocusFilter(mode: nil, length: nil, stopWhenOff: false)
        #expect(!session.isPlaying)
        // Consumed: the next empty filter is not a stop.
        await session.play()
        await session.applyFocusFilter(mode: nil, length: nil, stopWhenOff: false)
        #expect(session.isPlaying)
    }

    @Test func theLastLayerCannotBeRemoved() {
        let session = makeSession()
        session.mode = .focus
        #expect(session.layers == [.rain])
        session.setLayer(.rain, on: false)
        #expect(session.layers == [.rain])
        session.setLayer(.noise, on: true)
        session.setLayer(.rain, on: false)
        #expect(session.layers == [.noise])
        #expect(session.title == "\(Mode.focus.title) · \(Soundscape.noise.title)")
        #expect(session.parameters.layers.load(ordering: .relaxed) == Soundscape.noise.bit)
    }

    @Test func engineIsCreatedOnFirstPlay() async {
        var created = 0
        let session = Session(defaults: defaults, widgetDirectory: widgetDirectory) { [audio] _ in
            created += 1
            return audio
        }
        #expect(created == 0)
        await session.play()
        session.pause()
        await session.play()
        #expect(created == 1)
        #expect(audio.starts == 2)
    }

    @Test func playReportsWhenAudioIsUnavailable() async {
        audio.failsToStart = true
        let session = makeSession()
        await session.play()
        #expect(!session.isPlaying)
        #expect(session.error == String(localized: "Audio unavailable"))
        #expect(session.parameters.master.load(ordering: .relaxed) == 0)

        audio.failsToStart = false
        await session.play()
        #expect(session.isPlaying)
        #expect(session.error == nil)
        #expect(session.parameters.master.load(ordering: .relaxed) == 1)
    }

    @Test func interruptionStopsTheSessionVisibly() async {
        let session = makeSession()
        session.length = .fifteen
        await session.play()
        #expect(session.isPlaying)

        audio.onInterruption?()
        #expect(!session.isPlaying)
        #expect(session.error == String(localized: "Audio stopped"))
        #expect(session.parameters.master.load(ordering: .relaxed) == 0)
        #expect(session.remaining == SessionLength.fifteen.seconds)
    }

    @Test func interruptionResumesOnlyWhenTheSystemSaysSo() async {
        let session = makeSession()
        session.length = .fifteen
        await session.play()
        audio.onInterruption?()
        #expect(!session.isPlaying)
        #expect(audio.stops == 0)

        await audio.onInterruptionEnded?(true)
        #expect(session.isPlaying)
        #expect(session.error == nil)
        #expect(audio.starts == 2)
        #expect(session.deadline != nil)

        // Without the resume flag the session stays paused and lets the engine go.
        audio.onInterruption?()
        await audio.onInterruptionEnded?(false)
        #expect(!session.isPlaying)
        #expect(audio.stops == 1)

        // A spurious end after the user resumed changes nothing.
        await session.play()
        await audio.onInterruptionEnded?(false)
        #expect(session.isPlaying)
        #expect(audio.stops == 1)

        // A stop of the user's own during the interruption disarms the resume.
        audio.onInterruption?()
        session.pause()
        await audio.onInterruptionEnded?(true)
        #expect(!session.isPlaying)
    }

    @Test func pauseKeepsTheCountdownAndNewLengthResetsIt() async {
        let session = makeSession()
        session.length = .sixty
        await session.play()
        #expect(session.deadline != nil)
        session.pause()
        #expect(session.deadline == nil)
        #expect(session.remaining == SessionLength.sixty.seconds)
        session.length = .fifteen
        #expect(session.remaining == SessionLength.fifteen.seconds)
        session.length = .endless
        #expect(session.remaining == nil)
    }

    @Test func newLengthRestartsTheRamp() async {
        let session = makeSession()
        session.mode = .windDown
        session.length = .fifteen
        await session.play()
        session.length = .sixty
        #expect(session.remaining == SessionLength.sixty.seconds)
        // Back at the start of the ramp, give or take the microseconds since.
        #expect(session.parameters.modulationRate.load(ordering: .relaxed) > 9.99)
    }

    @Test func endlessRampsWalkTheirFixedLength() {
        #expect(Mode.windDown.rate(elapsed: 0, length: .endless) == 10)
        #expect(Mode.windDown.rate(elapsed: 10 * 60, length: .endless) == 6)
        #expect(Mode.windDown.rate(elapsed: 60 * 60, length: .endless) == 2)
        #expect(Mode.wake.rate(elapsed: 0, length: .endless) == 2)
        #expect(Mode.wake.rate(elapsed: 15 * 60, length: .endless) == 16)
        #expect(Mode.focus.rate(elapsed: 60 * 60, length: .endless) == 16)
        #expect(Mode.focus.rampSeconds(for: .sixty) == nil)
    }

    @Test func timedRampsFollowTheTimer() {
        // Wake ramps over the whole timer.
        #expect(Mode.wake.rampSeconds(for: .sixty) == 3600.0)
        #expect(Mode.wake.rate(elapsed: 30 * 60, length: .sixty) == 9)
        #expect(Mode.wake.rate(elapsed: 60 * 60, length: .sixty) == 16)
        // Wind Down reaches 2 Hz when its five-minute taper begins.
        #expect(Mode.windDown.rampSeconds(for: .fifteen) == 600.0)
        #expect(Mode.windDown.rate(elapsed: 5 * 60, length: .fifteen) == 6)
        #expect(Mode.windDown.rate(elapsed: 10 * 60, length: .fifteen) == 2)
        #expect(Mode.windDown.rate(elapsed: 10 * 60, length: .eightHours) > 9)
    }

    @Test func rampModesStartAtTheirFirstRate() {
        let session = makeSession()
        session.mode = .windDown
        #expect(session.parameters.modulationRate.load(ordering: .relaxed) == 10)
        #expect(session.layers == [.rain])
        session.setLayer(.noise, on: true)
        #expect(session.layers == [.rain, .noise])
        #expect(session.mode.fadeOut == 300)
        session.mode = .wake
        #expect(session.parameters.modulationRate.load(ordering: .relaxed) == 2)
    }

    @Test func modeDrivesTheAudioParameters() {
        let session = makeSession()
        session.mode = .focus
        session.intensity = .high
        session.binaural = true
        session.headphones = true
        let p = session.parameters
        #expect(p.modulationRate.load(ordering: .relaxed) == 16)
        #expect(p.modulationDepth.load(ordering: .relaxed) == 0.6)
        #expect(p.binauralLevel.load(ordering: .relaxed) == 0.12)
        #expect(p.layers.load(ordering: .relaxed) == Soundscape.rain.bit)

        // The sleep beds start their onset: a little modulation, a brighter bed.
        session.mode = .sleep
        session.setLayer(.pad, on: true)
        #expect(session.layers == [.noise])
        #expect(p.modulationDepth.load(ordering: .relaxed) == 0.3)
        #expect(p.brightness.load(ordering: .relaxed) == 0.3)
        #expect(p.layers.load(ordering: .relaxed) == Soundscape.noise.bit)

        session.mode = .deepSleep
        session.setLayer(.pad, on: true)
        #expect(session.layers == [.noise])
        #expect(p.modulationRate.load(ordering: .relaxed) == 1)
        #expect(p.modulationDepth.load(ordering: .relaxed) == 0.15)
        #expect(p.binauralCarrier.load(ordering: .relaxed) == 100)

        session.mode = .gamma
        session.intensity = .medium
        #expect(p.modulationRate.load(ordering: .relaxed) == 40)
        #expect(p.modulationDepth.load(ordering: .relaxed) == 0.3)
        #expect(p.layers.load(ordering: .relaxed) == Soundscape.pad.bit)
    }

    /// Twenty minutes in, Sleep has no modulation left, sits darker and a
    /// few decibels down, and holds there; Deep Sleep swells deepest in the
    /// middle of each ninety-minute cycle and never settles.
    @Test func sleepBedsWalkTheirArc() {
        let onset = Mode.onsetSeconds
        #expect(Mode.sleep.depth(elapsed: 0) == 0.3)
        #expect(abs(Mode.sleep.depth(elapsed: onset / 2) - 0.15) < 1e-9)
        #expect(Mode.sleep.depth(elapsed: onset) == 0)
        #expect(Mode.sleep.depth(elapsed: 8 * 3600) == 0)
        #expect(Mode.sleep.brightness(elapsed: 0) == 0.3)
        #expect(Mode.sleep.brightness(elapsed: onset) == -0.6)
        #expect(Mode.sleep.level(elapsed: 0) == 1)
        #expect(abs(Mode.sleep.level(elapsed: onset / 2) - 0.8) < 1e-9)
        #expect(Mode.sleep.level(elapsed: 3 * 3600) == 0.6)
        #expect(Mode.sleep.evolves(at: onset - 1, length: .endless))
        #expect(!Mode.sleep.evolves(at: onset, length: .endless))

        let cycle = Mode.cycleSeconds
        #expect(Mode.deepSleep.depth(elapsed: 0) == 0.15)
        #expect(abs(Mode.deepSleep.depth(elapsed: cycle / 2) - 0.5) < 1e-9)
        #expect(abs(Mode.deepSleep.depth(elapsed: cycle) - 0.15) < 1e-9)
        #expect(abs(Mode.deepSleep.depth(elapsed: 2.5 * cycle) - 0.5) < 1e-9)
        #expect(Mode.deepSleep.level(elapsed: 0) == 1)
        #expect(Mode.deepSleep.brightness(elapsed: onset) == -0.6)
        #expect(Mode.deepSleep.evolves(at: 12 * 3600, length: .endless))

        // Steady modes hold, and Wind Down only moves while its rate ramps.
        #expect(Mode.focus.depth(elapsed: 3600) == 0.5)
        #expect(Mode.focus.brightness(elapsed: 3600) == 0)
        #expect(Mode.focus.level(elapsed: 3600) == 1)
        #expect(!Mode.focus.evolves(at: 0, length: .endless))
        #expect(Mode.windDown.evolves(at: 0, length: .endless))
        #expect(!Mode.windDown.evolves(at: 20 * 60, length: .endless))
        #expect(Mode.windDown.evolves(at: 20 * 60, length: .eightHours))
    }

    /// The keyframe tables against the closed forms they replaced: the
    /// twenty-minute onset, the ninety-minute Deep Sleep cycle and the linear
    /// rate ramps, sampled where a night is interesting.
    @Test func keyframeArcsMatchTheOldClosedForms() {
        /// The raised cosine each onset segment was blended with.
        func onset(_ elapsed: Double, from: Double, to: Double) -> Double {
            let t = min(1, elapsed / Mode.onsetSeconds)
            return from + (to - from) * (0.5 - 0.5 * cos(t * .pi))
        }
        func cycle(_ elapsed: Double) -> Double {
            0.15 + (0.5 - 0.15) * (0.5 - 0.5 * cos(2 * .pi * elapsed / Mode.cycleSeconds))
        }
        func ramp(_ elapsed: Double, from: Double, to: Double, over seconds: Double) -> Double {
            from + (to - from) * min(1, max(0, elapsed / seconds))
        }

        for minutes in [0.0, 10, 20, 45, 90] {
            let t = minutes * 60
            #expect(abs(Mode.sleep.depth(elapsed: t) - onset(t, from: 0.3, to: 0)) < 1e-12)
            #expect(abs(Mode.sleep.brightness(elapsed: t) - onset(t, from: 0.3, to: -0.6)) < 1e-12)
            #expect(abs(Mode.sleep.level(elapsed: t) - onset(t, from: 1, to: 0.6)) < 1e-12)

            #expect(abs(Mode.deepSleep.depth(elapsed: t) - cycle(t)) < 1e-12)
            #expect(abs(Mode.deepSleep.brightness(elapsed: t) - onset(t, from: 0.3, to: -0.6)) < 1e-12)
            #expect(abs(Mode.deepSleep.level(elapsed: t) - onset(t, from: 1, to: 0.6)) < 1e-12)

            let windDown = Mode.windDown.rate(elapsed: t, length: .endless)
            #expect(abs(windDown - ramp(t, from: 10, to: 2, over: 20 * 60)) < 1e-12)
            let wake = Mode.wake.rate(elapsed: t, length: .endless)
            #expect(abs(wake - ramp(t, from: 2, to: 16, over: 15 * 60)) < 1e-12)
            // A timed session stretches the same ramp over its own timer.
            let timed = Mode.windDown.rate(elapsed: t, length: .ninety)
            #expect(abs(timed - ramp(t, from: 10, to: 2, over: 90 * 60 - 300)) < 1e-12)

            // Steady modes hold every channel, whatever the play time.
            #expect(Mode.focus.depth(elapsed: t) == 0.5)
            #expect(Mode.gamma.depth(elapsed: t) == 0.3)
            #expect(Mode.relax.rate(elapsed: t, length: .endless) == 10)
            #expect(Mode.meditate.rate(elapsed: t, length: .endless) == 6)
        }
    }

    /// The sleep beds ignore the inputs; the arc is the whole story there.
    @Test func inputsStayOutOfTheSleepBeds() async {
        final class Dim: AdaptiveInput {
            var adjustment = Adjustment(depth: 0.5, brightness: -1)
            var onChange: (@MainActor () -> Void)?
            func start(for mode: Mode) {}
            func stop() {}
        }
        let session = Session(defaults: defaults, widgetDirectory: widgetDirectory, inputs: [Dim()]) { [audio] _ in audio }
        session.mode = .relax
        await session.play()
        #expect(session.parameters.modulationDepth.load(ordering: .relaxed) == 0.2)
        #expect(session.parameters.brightness.load(ordering: .relaxed) == -1)
        // A hair into the onset, give or take the microseconds since.
        session.mode = .sleep
        #expect(abs(session.parameters.modulationDepth.load(ordering: .relaxed) - 0.3) < 1e-6)
        #expect(abs(session.parameters.brightness.load(ordering: .relaxed) - 0.3) < 1e-6)
    }

    /// The bedtime signature plays as a mode that ends in bed starts, and
    /// only then: a steady mode has none, and a switch to one plays it.
    @Test func bedtimeCueOpensTheSleepModes() async {
        let session = makeSession()
        let p = session.parameters
        session.mode = .focus
        await session.play()
        #expect(p.cue.load(ordering: .relaxed) == 0)

        session.mode = .sleep
        let first = p.cue.load(ordering: .relaxed)
        #expect(Cue.decode(first) == .bedtime)
        session.pause()
        await session.play()
        let second = p.cue.load(ordering: .relaxed)
        #expect(second != first)
        #expect(Cue.decode(second) == .bedtime)

        session.mode = .relax
        #expect(p.cue.load(ordering: .relaxed) == second)
        session.mode = .windDown
        #expect(Cue.decode(p.cue.load(ordering: .relaxed)) == .bedtime)
        session.mode = .wake
        #expect(Cue.decode(p.cue.load(ordering: .relaxed)) == .bedtime)
        #expect(p.cue.load(ordering: .relaxed) == Cue.encode(.bedtime, trigger: 3))
    }

    @Test func masterTapersOverTheFadeOut() {
        #expect(Session.masterGain(remaining: nil, fadeOut: 300) == 1)
        #expect(Session.masterGain(remaining: 600, fadeOut: 300) == 1)
        #expect(Session.masterGain(remaining: 150, fadeOut: 300) == 0.5)
        #expect(Session.masterGain(remaining: 0, fadeOut: 300) == 0)
        #expect(Session.masterGain(remaining: 30, fadeOut: 1) == 1)
    }

    @Test func binauralIsMutedOverSpeakers() {
        let session = makeSession()
        session.binaural = true
        session.headphones = true
        #expect(session.parameters.binauralLevel.load(ordering: .relaxed) == 0.12)
        session.headphones = false
        #expect(session.parameters.binauralLevel.load(ordering: .relaxed) == 0)
        #expect(session.binaural)
        session.headphones = true
        #expect(session.parameters.binauralLevel.load(ordering: .relaxed) == 0.12)
        #expect(makeSession().binaural)
    }

    @Test func widgetSeesTheSession() async {
        let session = makeSession()
        session.mode = .relax
        session.length = .thirty
        await session.play()
        let playing = WidgetState.load(from: widgetDirectory)
        #expect(playing?.mode == .relax)
        #expect(playing?.sound == "Pad")
        #expect(playing?.isPlaying == true)
        #expect(playing?.deadline != nil)

        session.pause()
        let paused = WidgetState.load(from: widgetDirectory)
        #expect(paused?.isPlaying == false)
        #expect(paused?.remaining == SessionLength.thirty.seconds)
        #expect(paused?.deadline == nil)
    }

    /// iOS budgets widget reloads, so a change the widget cannot see must not rewrite its snapshot.
    @Test func widgetSnapshotOnlyChangesWhenVisible() throws {
        let session = makeSession()
        let file = widgetDirectory.appending(path: "widget.json")
        session.mode = .relax
        let written = try #require(WidgetState.load(from: widgetDirectory))
        let stamp = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date
        session.intensity = .high
        session.binaural = true
        session.volume = 0.2
        #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date == stamp)
        #expect(written.matches(WidgetState.load(from: widgetDirectory)))
        session.setLayer(.drone, on: true)
        #expect(WidgetState.load(from: widgetDirectory)?.sound == "Pad + Drone")
    }

    @Test func meditateSegmentsReachTheMindfulLog() async {
        let mindful = FakeMindful()
        let session = Session(defaults: defaults, widgetDirectory: widgetDirectory, mindful: mindful) { [audio] _ in audio }
        session.mode = .focus
        await session.play()
        session.pause()
        #expect(mindful.prepared == 0)
        #expect(mindful.segments.isEmpty)

        session.mode = .meditate
        await session.play()
        #expect(mindful.prepared == 1)
        session.pause()
        #expect(mindful.segments.count == 1)

        // Switching mode mid-play closes the segment; switching back opens a new one.
        await session.play()
        session.mode = .relax
        #expect(mindful.segments.count == 2)
        session.mode = .meditate
        #expect(mindful.prepared == 3)
        session.pause()
        #expect(mindful.segments.count == 3)
        #expect(mindful.segments.allSatisfy { $0.duration >= 0 && $0.end <= .now })
    }

    @Test func widgetTreatsAPastDeadlineAsStopped() {
        let playing = WidgetState(mode: .relax, sound: "Pad", isPlaying: true, remaining: nil, deadline: .now.addingTimeInterval(60))
        #expect(playing.at(.now).isPlaying)
        let over = playing.at(.now.addingTimeInterval(120))
        #expect(!over.isPlaying)
        #expect(over.deadline == nil)
        #expect(over.mode == .relax)
        let endless = WidgetState(mode: .relax, sound: "Pad", isPlaying: true, remaining: nil, deadline: nil)
        #expect(endless.at(.distantFuture).isPlaying)
    }

    @Test func countdownGrowsPastAnHour() {
        #expect(899.countdown == "14:59")
        #expect(3600.countdown == "1:00:00")
        #expect(SessionLength.eightHours.seconds.countdown == "8:00:00")
        #expect(SessionLength.eightHours.title == String(localized: "\(8) h"))
    }

    @Test func liveActivityFollowsTheTimer() {
        typealias State = SessionActivityAttributes.ContentState
        let now = Date.now
        let deadline = now.addingTimeInterval(600)
        #expect(State.snapshot(mode: .focus, sound: "Rain", isPlaying: true, remaining: nil, deadline: nil) == nil)

        let playing = State.snapshot(mode: .focus, sound: "Rain", isPlaying: true, remaining: 600, deadline: deadline, now: now)
        #expect(playing == State(mode: .focus, sound: "Rain", deadline: deadline, pausedAt: nil))
        #expect(playing?.isPlaying == true)

        // Paused: the countdown freezes at `now`, showing the seconds kept.
        let paused = State.snapshot(mode: .focus, sound: "Rain", isPlaying: false, remaining: 600, deadline: nil, now: now)
        #expect(paused?.pausedAt == now)
        #expect(paused?.deadline == deadline)
        #expect(paused?.isPlaying == false)
    }
}

@MainActor
extension SessionTests {
    /// Head tracking reaches the engine only over headphones, in a mode
    /// that allows it, and persists across launches.
    @Test func headTrackingIsGatedByModeAndRoute() async {
        let session = makeSession()
        session.headphones = true
        session.mode = .meditate
        session.headTracking = true
        await session.play()
        #expect(audio.headTracking)
        session.mode = .sleep
        #expect(!audio.headTracking)
        session.mode = .windDown
        #expect(!audio.headTracking)
        session.mode = .focus
        #expect(audio.headTracking)
        session.headphones = false
        #expect(!audio.headTracking)
        #expect(!audio.headphones)
        session.headphones = true
        session.headTracking = false
        #expect(!audio.headTracking)
        session.headTracking = true
        #expect(makeSession().headTracking)
    }
}

@MainActor
extension SessionTests {
    /// An input as the session sees it: an adjustment and a change callback.
    final class FakeInput: AdaptiveInput {
        var adjustment = Adjustment.none
        var onChange: (@MainActor () -> Void)?
        var running: Mode?
        var starts = 0
        func start(for mode: Mode) { running = mode; starts += 1 }
        func stop() { running = nil }
        func change(to adjustment: Adjustment) {
            self.adjustment = adjustment
            onChange?()
        }
    }

    /// Inputs run only while the session plays, start over on a mode
    /// change, and their adjustment lands on depth and brightness without
    /// touching the sleep beds' fixed depth.
    @Test func inputsRunWhilePlayingAndShapeTheSound() async {
        let daylight = FakeInput()
        let body = FakeInput()
        let session = Session(defaults: defaults, widgetDirectory: widgetDirectory, inputs: [daylight, body]) { [audio] _ in audio }
        let p = session.parameters
        session.mode = .focus
        session.intensity = .medium
        #expect(daylight.running == nil)

        await session.play()
        #expect(daylight.running == .focus && body.running == .focus)
        daylight.change(to: Adjustment(depth: 0.8, brightness: -0.5))
        #expect(p.modulationDepth.load(ordering: .relaxed) == 0.4)
        #expect(p.brightness.load(ordering: .relaxed) == -0.5)
        body.change(to: Adjustment(depth: 0.5, brightness: -0.8))
        #expect(p.modulationDepth.load(ordering: .relaxed) == 0.2)
        #expect(p.brightness.load(ordering: .relaxed) == -1)

        session.mode = .deepSleep
        #expect(daylight.starts == 2 && daylight.running == .deepSleep)
        #expect(abs(p.modulationDepth.load(ordering: .relaxed) - 0.15) < 1e-6)

        session.pause()
        #expect(daylight.running == nil && body.running == nil)
        session.mode = .relax
        #expect(daylight.starts == 2)
    }
}
