import Foundation
import Testing
@testable import Entrain

/// The breathing patterns' arithmetic, the guide's lifecycle in the session
/// and the cue synth that sounds each phase.
struct BreathingTests {
    @Test func patternsAddUpAndRepeat() {
        #expect(BreathingPattern.box.cycleSeconds == 16)
        #expect(BreathingPattern.relaxing.cycleSeconds == 19)
        #expect(BreathingPattern.coherent.cycleSeconds == 10)
        #expect(BreathingPattern.longExhale.cycleSeconds == 10)
        #expect(BreathingPattern.none.steps.isEmpty)
        #expect(BreathingPattern.none.position(at: 3) == nil)

        let box = BreathingPattern.box
        #expect(box.position(at: 0)?.phase == .inhale)
        #expect(box.position(at: 3.9)?.phase == .inhale)
        #expect(box.position(at: 4)?.phase == .hold)
        #expect(box.position(at: 8)?.phase == .exhale)
        #expect(box.position(at: 12)?.phase == .hold)
        #expect(box.position(at: 12)?.index == 3)
        // The second breath starts over, and progress is measured within the step.
        let second = box.position(at: 18)
        #expect(second?.cycle == 1)
        #expect(second?.phase == .inhale)
        #expect(second?.elapsed == 2)
        #expect(second?.progress == 0.5)
    }

    /// A timed exercise ends on a whole breath, the nearest count and never none.
    @Test func lengthsRoundToWholeBreaths() {
        #expect(BreathingPattern.box.cycles(in: 60) == 4)
        #expect(BreathingPattern.relaxing.cycles(in: 60) == 3)
        #expect(BreathingPattern.coherent.cycles(in: 300) == 30)
        #expect(BreathingPattern.box.cycles(in: 5) == 1)
        #expect(BreathingPattern.box.cycles(in: nil) == nil)
        #expect(BreathingPattern.none.cycles(in: 60) == nil)
        #expect(BreathingPattern.box.position(at: 70, cycles: 4) == nil)
        #expect(BreathingPattern.box.position(at: 63, cycles: 4)?.cycle == 3)
        #expect(BreathingLength.session.seconds == nil)
        #expect(BreathingLength.five.seconds == 300)
        #expect(BreathingLength.one.title == String(localized: "\(1) min"))
    }

    /// The cue and the trigger count share one atomic; a repeated cue still
    /// differs from the one before it.
    @Test func cuesEncodeWithTheirTrigger() {
        let first = BreathCue.encode(.hold, trigger: 1)
        let second = BreathCue.encode(.hold, trigger: 2)
        #expect(first != second)
        #expect(BreathCue.decode(first) == .hold)
        #expect(BreathCue.decode(second) == .hold)
        for cue in BreathCue.allCases {
            #expect(BreathCue.decode(BreathCue.encode(cue, trigger: 1234)) == cue)
        }
        #expect(BreathPhase.inhale.cue == .inhale)
        #expect(BreathPhase.exhale.cue == .exhale)
    }

    /// Silent until a cue lands, then a finite tone that dies away and
    /// leaves silence again, with no click at either end.
    @Test func cueSynthPlaysOneToneperCue() {
        let parameters = AudioParameters()
        parameters.master.store(1, ordering: .relaxed)
        let synth = CueSynth(parameters: parameters, sampleRate: 48000)
        var renderer = Renderer(synth: synth, block: 512)
        // The master smoother needs a moment to reach full level.
        #expect(renderer.render(seconds: 2) == 0)

        parameters.cue.store(BreathCue.encode(.inhale, trigger: 1), ordering: .relaxed)
        let onset = renderer.render(seconds: 0.05)
        #expect(onset.isFinite && onset > 0 && onset < 0.05, "the window should open softly, peaked at \(onset)")
        let body = renderer.render(seconds: 0.5)
        #expect(body.isFinite && body > 0.15 && body <= CueSynth.level * 1.3, "peaked at \(body)")
        _ = renderer.render(seconds: 0.6)
        #expect(renderer.render(seconds: 1) == 0)

        // The same cue again, with a new trigger, plays again.
        parameters.cue.store(BreathCue.encode(.inhale, trigger: 2), ordering: .relaxed)
        #expect(renderer.render(seconds: 0.6) > 0.15)

        // Master at zero fades a cue away like the bed; the smoother only
        // approaches zero, so what is left is a rounding of silence.
        parameters.master.store(0, ordering: .relaxed)
        _ = renderer.render(seconds: 3)
        parameters.cue.store(BreathCue.encode(.exhale, trigger: 3), ordering: .relaxed)
        #expect(renderer.render(seconds: 1) < 0.02)
    }

    struct Renderer {
        let synth: CueSynth
        let block: Int
        private var left: [Float]
        private var right: [Float]

        init(synth: CueSynth, block: Int) {
            self.synth = synth
            self.block = block
            left = [Float](repeating: 0, count: block)
            right = [Float](repeating: 0, count: block)
        }

        mutating func render(seconds: Double) -> Float {
            var peak: Float = 0
            let blocks = Int(seconds * 48000) / block
            for _ in 0..<blocks {
                left.withUnsafeMutableBufferPointer { l in
                    right.withUnsafeMutableBufferPointer { r in
                        synth.render(frames: block, left: l.baseAddress!, right: r.baseAddress!)
                    }
                }
                for i in 0..<block {
                    peak = max(peak, abs(left[i]), abs(right[i]))
                }
            }
            return peak
        }
    }
}

@MainActor
struct BreathGuideTests {
    let defaults: UserDefaults
    let widgetDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let audio = SessionTests.FakeAudio()

    init() {
        let suite = "entrain.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.createDirectory(at: widgetDirectory, withIntermediateDirectories: true)
    }

    func makeSession() -> Session {
        Session(defaults: defaults, widgetDirectory: widgetDirectory) { [audio] _ in audio }
    }

    /// The guide runs only while Meditate plays with a pattern chosen, and
    /// the first breath's cue reaches the render thread at once.
    @Test func guideFollowsMeditateAndPlay() async {
        let session = makeSession()
        let p = session.parameters
        session.mode = .meditate
        session.breathing = .box
        #expect(!session.breath.isActive)
        #expect(p.cue.load(ordering: .relaxed) == 0)

        await session.play()
        #expect(session.breath.isActive)
        #expect(session.breath.position?.phase == .inhale)
        #expect(session.breath.position?.cycle == 0)
        #expect(session.breath.cycles == nil)
        #expect(BreathCue.decode(p.cue.load(ordering: .relaxed)) == .inhale)
        let cue = p.cue.load(ordering: .relaxed)

        // Another mode has no breath to follow; back in Meditate it starts over.
        session.mode = .relax
        #expect(!session.breath.isActive)
        session.mode = .meditate
        #expect(session.breath.position?.phase == .inhale)
        #expect(p.cue.load(ordering: .relaxed) != cue)

        session.breathing = .none
        #expect(!session.breath.isActive)
        session.breathing = .coherent
        #expect(session.breath.isActive)
        session.breathingLength = .one
        #expect(session.breath.cycles == 6)

        session.pause()
        #expect(!session.breath.isActive)
        #expect(session.breath.stepInterval == nil)
    }

    @Test func breathingSettingsSurviveRelaunchAndSync() {
        let session = makeSession()
        session.breathing = .relaxing
        session.breathingLength = .ten
        let relaunched = makeSession()
        #expect(relaunched.breathing == .relaxing)
        #expect(relaunched.breathingLength == .ten)
        #expect(makeSession().breath.pattern == .none)

        let cloud = SessionTests.FakeCloud()
        let synced = Session(defaults: defaults, widgetDirectory: widgetDirectory, cloud: cloud) { [audio] _ in audio }
        synced.breathing = .box
        #expect(cloud.values["breathing"] as? String == "box")
        cloud.values["breathing"] = "coherent"
        cloud.values["breathingLength"] = BreathingLength.three.rawValue
        cloud.changed(["breathing", "breathingLength"])
        #expect(synced.breathing == .coherent)
        #expect(synced.breathingLength == .three)
    }

    /// The guide steps its phases in real time and ends with a final cue.
    @Test func guideStepsThroughThePatternAndFinishes() async throws {
        let guide = BreathGuide()
        var cues: [BreathCue] = []
        guide.onCue = { cues.append($0) }
        // A one-minute Box exercise rounds to four breaths; this test only
        // needs to see the phases advance, so it watches the first step.
        guide.start(.box, length: .one)
        #expect(guide.cycles == 4)
        #expect(guide.position?.phase == .inhale)
        #expect(cues == [.inhale])
        let interval = try #require(guide.stepInterval)
        #expect(abs(interval.duration - 4) < 0.001)

        try await Task.sleep(for: .seconds(4.3))
        #expect(guide.position?.phase == .hold)
        #expect(guide.position?.index == 1)
        #expect(cues == [.inhale, .hold])

        guide.stop()
        #expect(guide.position == nil)
        try await Task.sleep(for: .seconds(0.2))
        #expect(cues.count == 2)
    }
}
