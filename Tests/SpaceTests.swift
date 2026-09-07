import Foundation
import Testing
@testable import Entrain

/// The room each mode is heard in, and the diffuser that stands in for one
/// on the watch.
struct SpaceTests {
    static let sampleRate = 48000.0
    static let block = 512

    /// The intents have to be ordered the way they are described: work is
    /// close and dry, rest is large and far, and nothing that ends in bed is
    /// wetter than the daytime modes.
    @Test func roomsRunFromCloseToFar() {
        let space = { Room.space(for: $0) }
        #expect(space(.focus).blend < space(.relax).blend)
        #expect(space(.relax).blend < space(.meditate).blend)
        #expect(space(.focus).level < space(.meditate).level)
        for mode in [Mode.sleep, .deepSleep] {
            #expect(space(mode).blend < space(.focus).blend, "\(mode.title) is wetter than Focus")
            #expect(space(mode).level < space(.focus).level, "\(mode.title) is louder than Focus")
        }
    }

    /// Every send stays under the point where a room stops being one, and
    /// the silent send the cross-fade passes through is below all of them.
    @Test(arguments: Mode.allCases)
    func everyRoomIsARoomAndNotAHall(_ mode: Mode) {
        let space = Room.space(for: mode)
        #expect((0...1).contains(space.blend), "\(mode.title) blends \(space.blend)")
        #expect(space.level > Room.silentSend, "\(mode.title) sends \(space.level)")
        #expect(space.level <= -8, "\(mode.title) sends \(space.level), which is a hall")
    }

    /// The watch's diffuser mixes at equal power, so how much room the bed
    /// sits in is not also how loud it is. Measured across the whole range.
    @Test func theDiffuserDoesNotChangeTheLevel() {
        let levels = [0.0, 0.15, 0.4, 1.0].map { Self.bed(blend: $0).level }
        for (blend, level) in zip([0.0, 0.15, 0.4, 1.0], levels) {
            let decibels = 20 * log10(level / levels[0])
            #expect(abs(decibels) < 1, "at \(blend) the bed is \(decibels) dB off dry")
        }
    }

    /// And it does the one thing a dry mono bed cannot: it gives the two
    /// ears something different to hear. Dry, they are the same signal up to
    /// the pan; wet, they come apart.
    @Test func theDiffuserGivesTheTwoEarsDifferentSignals() {
        #expect(Self.bed(blend: 0).correlation > 0.999)
        #expect(Self.bed(blend: 0.4).correlation < 0.9, "wet, the ears still match")
    }

    /// Renders the watch bed and reports its level and how alike the ears are.
    static func bed(blend: Double) -> (level: Double, correlation: Double) {
        let parameters = AudioParameters()
        parameters.master.store(1, ordering: .relaxed)
        parameters.volume.store(1, ordering: .relaxed)
        parameters.modulationDepth.store(0, ordering: .relaxed)
        parameters.layers.store(Soundscape.noise.bit, ordering: .relaxed)
        parameters.space.store(blend, ordering: .relaxed)
        let bed = BedSynth(parameters: parameters, sampleRate: sampleRate)

        var left = [Float](repeating: 0, count: block)
        var right = [Float](repeating: 0, count: block)
        var power = 0.0
        var cross = 0.0
        var leftPower = 0.0
        var rightPower = 0.0
        var counted = 0.0
        // The level ramp and the blend smoother both settle within a few
        // seconds; only what comes after is measured.
        let settle = Int(4 * sampleRate) / block
        for i in 0..<Int(20 * sampleRate) / block {
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    bed.render(frames: block, left: l.baseAddress!, right: r.baseAddress!)
                }
            }
            guard i >= settle else { continue }
            for j in 0..<block {
                let l = Double(left[j])
                let r = Double(right[j])
                power += l * l + r * r
                leftPower += l * l
                rightPower += r * r
                cross += l * r
                counted += 1
            }
        }
        return ((power / (2 * counted)).squareRoot(), cross / (leftPower * rightPower).squareRoot())
    }
}
