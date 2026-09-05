import Foundation
import Testing
@testable import Entrain

/// Session logic against a fake engine and a throwaway defaults suite.
@MainActor
struct SessionTests {
    final class FakeAudio: SessionAudio {
        var onInterruption: (() -> Void)?
        var starts = 0
        var stops = 0
        var failsToStart = false

        struct Unavailable: Error {}

        func start() throws {
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
        #expect(session.title == "Focus · Noise")
        #expect(session.parameters.layers.load(ordering: .relaxed) == Soundscape.noise.bit)
    }

    @Test func engineIsCreatedOnFirstPlay() {
        var created = 0
        let session = Session(defaults: defaults, widgetDirectory: widgetDirectory) { [audio] _ in
            created += 1
            return audio
        }
        #expect(created == 0)
        session.play()
        session.pause()
        session.play()
        #expect(created == 1)
        #expect(audio.starts == 2)
    }

    @Test func playReportsWhenAudioIsUnavailable() {
        audio.failsToStart = true
        let session = makeSession()
        session.play()
        #expect(!session.isPlaying)
        #expect(session.error == "Audio unavailable")
        #expect(session.parameters.master.load(ordering: .relaxed) == 0)

        audio.failsToStart = false
        session.play()
        #expect(session.isPlaying)
        #expect(session.error == nil)
        #expect(session.parameters.master.load(ordering: .relaxed) == 1)
    }

    @Test func interruptionStopsTheSessionVisibly() {
        let session = makeSession()
        session.length = .fifteen
        session.play()
        #expect(session.isPlaying)

        audio.onInterruption?()
        #expect(!session.isPlaying)
        #expect(session.error == "Audio stopped")
        #expect(session.parameters.master.load(ordering: .relaxed) == 0)
        #expect(session.remaining == SessionLength.fifteen.seconds)
    }

    @Test func pauseKeepsTheCountdownAndNewLengthResetsIt() {
        let session = makeSession()
        session.length = .sixty
        session.play()
        session.pause()
        #expect(session.remaining == SessionLength.sixty.seconds)
        session.length = .fifteen
        #expect(session.remaining == SessionLength.fifteen.seconds)
        session.length = .endless
        #expect(session.remaining == nil)
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

    @Test func widgetSeesTheSession() {
        let session = makeSession()
        session.mode = .relax
        session.length = .thirty
        session.play()
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
        #expect(SessionLength.eightHours.title == "8 h")
    }
}
