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
        #expect(Mode.wake.rampSeconds(for: .sixty) == 60 * 60)
        #expect(Mode.wake.rate(elapsed: 30 * 60, length: .sixty) == 9)
        #expect(Mode.wake.rate(elapsed: 60 * 60, length: .sixty) == 16)
        // Wind Down reaches 2 Hz when its five-minute taper begins.
        #expect(Mode.windDown.rampSeconds(for: .fifteen) == 10 * 60)
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

        session.mode = .sleep
        session.setLayer(.pad, on: true)
        #expect(session.layers == [.noise])
        #expect(p.modulationDepth.load(ordering: .relaxed) == 0)
        #expect(p.layers.load(ordering: .relaxed) == Soundscape.noise.bit)

        session.mode = .deepSleep
        session.setLayer(.pad, on: true)
        #expect(session.layers == [.noise])
        #expect(p.modulationRate.load(ordering: .relaxed) == 1)
        #expect(p.modulationDepth.load(ordering: .relaxed) == 0.5)
        #expect(p.binauralCarrier.load(ordering: .relaxed) == 100)

        session.mode = .gamma
        session.intensity = .medium
        #expect(p.modulationRate.load(ordering: .relaxed) == 40)
        #expect(p.modulationDepth.load(ordering: .relaxed) == 0.3)
        #expect(p.layers.load(ordering: .relaxed) == Soundscape.pad.bit)
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
}
