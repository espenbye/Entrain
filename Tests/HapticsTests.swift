import Foundation
import Testing
@testable import Entrain

/// The two pure halves of the haptic path: what the LFO is worth as
/// intensity, and which modes get to feel it at all.
@MainActor
struct HapticsTests {
    @Test func intensityFollowsTheSameLFOAsTheBed() {
        // Loudest where the audio pulse subtracts nothing, silent half a
        // cycle later, and symmetric around both.
        #expect(Haptics.intensity(depth: 1, phase: 0) == Haptics.ceiling)
        #expect(abs(Haptics.intensity(depth: 1, phase: 0.5)) < 1e-12)
        #expect(abs(Haptics.intensity(depth: 1, phase: 0.25) - Haptics.ceiling / 2) < 1e-12)
        #expect(abs(Haptics.intensity(depth: 1, phase: 0.75) - Haptics.ceiling / 2) < 1e-12)
        #expect(abs(Haptics.intensity(depth: 1, phase: 1) - Haptics.ceiling) < 1e-12)

        // Depth scales the whole swell, so an unmodulated bed is felt not at all.
        #expect(Haptics.intensity(depth: 0, phase: 0) == 0)
        #expect(abs(Haptics.intensity(depth: 0.5, phase: 0) - Haptics.ceiling / 2) < 1e-12)

        // Nothing leaves 0...1, whatever the caller passes.
        for phase in stride(from: 0.0, through: 1.0, by: 0.05) {
            #expect((0...1).contains(Haptics.intensity(depth: 2, phase: phase)))
            #expect((0...1).contains(Haptics.intensity(depth: -1, phase: phase)))
        }
    }

    /// Sleep and Deep Sleep are felt throughout; Gamma's 40 Hz never is.
    @Test func onlySlowBeatsAreFelt() {
        #expect(Mode.sleep.feelsBeat(at: 0, length: .endless))
        #expect(Mode.sleep.feelsBeat(at: 8 * 3600, length: .endless))
        #expect(Mode.deepSleep.feelsBeat(at: 0, length: .endless))
        #expect(!Mode.gamma.feelsBeat(at: 0, length: .endless))
        #expect(!Mode.focus.feelsBeat(at: 0, length: .endless))
        #expect(!Mode.relax.feelsBeat(at: 0, length: .endless))
        #expect(!Mode.meditate.feelsBeat(at: 0, length: .endless))
    }

    /// The gate reads the rate the mode plays now, so Wind Down picks the
    /// haptics up as its ramp crosses into delta and Wake drops them as it
    /// climbs back out.
    @Test func rampingModesCrossTheGateMidSession() {
        let windDown = Mode.windDown
        #expect(!windDown.feelsBeat(at: 0, length: .endless))
        // 10 Hz to 2 Hz over twenty minutes reaches 4 Hz three quarters in.
        #expect(!windDown.feelsBeat(at: 0.74 * 20 * 60, length: .endless))
        #expect(windDown.feelsBeat(at: 0.76 * 20 * 60, length: .endless))
        #expect(windDown.feelsBeat(at: 20 * 60, length: .endless))
        // A timed session stretches the same crossing over its own timer.
        #expect(!windDown.feelsBeat(at: 20 * 60, length: .eightHours))

        let wake = Mode.wake
        #expect(wake.feelsBeat(at: 0, length: .endless))
        #expect(!wake.feelsBeat(at: 15 * 60, length: .endless))
    }
}
