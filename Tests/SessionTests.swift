import Foundation
import Testing
@testable import Entrain

/// Session logic against a fake engine and a throwaway defaults suite.
@MainActor
struct SessionTests {
    final class FakeAudio: SessionAudio {
        var onInterruption: (() -> Void)?
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

    @Test func pauseKeepsTheCountdownAndNewLengthResetsIt() async {
        let session = makeSession()
        session.length = .sixty
        await session.play()
        session.pause()
        #expect(session.remaining == SessionLength.sixty.seconds)
        session.length = .fifteen
        #expect(session.remaining == SessionLength.fifteen.seconds)
        session.length = .endless
        #expect(session.remaining == nil)
    }

    @Test func rampModesWalkTheRate() {
        #expect(Mode.windDown.rate(elapsed: 0) == 10)
        #expect(Mode.windDown.rate(elapsed: 10 * 60) == 6)
        #expect(Mode.windDown.rate(elapsed: 60 * 60) == 2)
        #expect(Mode.wake.rate(elapsed: 0) == 2)
        #expect(Mode.wake.rate(elapsed: 15 * 60) == 16)
        #expect(Mode.focus.rate(elapsed: 60 * 60) == 16)
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

    @Test func countdownGrowsPastAnHour() {
        #expect(899.countdown == "14:59")
        #expect(3600.countdown == "1:00:00")
        #expect(SessionLength.eightHours.seconds.countdown == "8:00:00")
        #expect(SessionLength.eightHours.title == String(localized: "\(8) h"))
    }
}
