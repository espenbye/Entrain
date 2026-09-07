import Testing
import Foundation
@testable import Entrain

/// The drops are the part of the bed a listener is most likely to catch as
/// synthetic, so these hold the two things that gave the old ones away: they
/// were tones, and they were all the same drop.
@Suite struct RainTests {
    static let sampleRate = 48000.0

    // MARK: The resonator

    /// A bandpass that does not pass its band is a gain stage. Driven at the
    /// centre it should dominate; two octaves either side it should be well
    /// down, and the same coefficients should hold that shape wherever in
    /// the drops' range the centre is put.
    @Test(arguments: [900.0, 2500.0, 7000.0] as [Double])
    func theResonatorPassesItsBandAndRejectsTheRest(_ centre: Double) {
        let f = Resonator.frequency(Float(centre), sampleRate: Float(Self.sampleRate))
        let d = Resonator.damping(q: 4)
        func response(at hz: Double) -> Double {
            var filter = Resonator()
            var phasor = Phasor()
            var sum = 0.0
            let increment = Float(hz / Self.sampleRate)
            for i in 0..<Int(Self.sampleRate) {
                let y = filter.process(SineTable.sin(cycles: phasor.next(increment)), frequency: f, damping: d)
                if i > Int(Self.sampleRate) / 2 { sum += Double(y * y) }
            }
            return sum
        }
        let band = response(at: centre)
        for side in [centre / 4, centre * 4] where side < Self.sampleRate / 3 {
            let ratio = 10 * log10(band / response(at: side))
            #expect(ratio > 18, "\(Int(centre)) Hz is only \(ratio) dB over \(Int(side)) Hz")
        }
    }

    /// Chamberlin's form is only conditionally stable, and the drops pick
    /// their centre and their damping independently. Every corner of the
    /// range the rain can ask for has to stay bounded under noise.
    @Test func theResonatorIsStableEverywhereTheDropsCanReach() {
        var rng = XorShift()
        for centre in [700.0, 4000.0, 7000.0] as [Double] {
            for q in [2.0, 5.0, 8.0] as [Double] {
                var filter = Resonator()
                let f = Resonator.frequency(Float(centre), sampleRate: Float(Self.sampleRate))
                let d = Resonator.damping(q: Float(q))
                var peak: Float = 0
                for _ in 0..<Int(Self.sampleRate * 5) {
                    peak = max(peak, abs(filter.process(rng.bipolar(), frequency: f, damping: d)))
                }
                #expect(peak < 8, "\(Int(centre)) Hz at Q \(q) reached \(peak)")
            }
        }
    }

    // MARK: The fall

    /// Level, brightness and length all have to move, and the levels have to
    /// be heavy-tailed rather than merely noisy: mostly fine drops with a few
    /// fat ones, which is what rain is. A uniform spread would satisfy a
    /// variance test and still sound like a shaker.
    ///
    /// Brightness and length are read off the drops above the median level
    /// only. A drop that barely clears the detection floor is measured over
    /// a handful of samples, and how long a thing lasts is not a question
    /// worth asking of something that was never properly there.
    @Test func noTwoDropsAreAlike() {
        let fall = Self.fall(seconds: 90)
        #expect(fall.drops.count > 1000, "only \(fall.drops.count) drops in 90 s")
        #expect((10.0...35.0).contains(fall.rate), "\(fall.rate) drops a second")

        let levels = fall.drops.map(\.level).sorted()
        #expect(Self.at(0.95, levels) / Self.at(0.5, levels) > 3,
                "the loudest twentieth of drops is only \(Self.at(0.95, levels) / Self.at(0.5, levels))x the median")
        #expect(Self.at(0.5, levels) / Self.at(0.05, levels) > 1.8,
                "the quietest twentieth is only \(Self.at(0.5, levels) / Self.at(0.05, levels)) below the median")

        let median = Self.at(0.5, levels)
        let clear = fall.drops.filter { $0.level > median }
        let brightness = clear.map(\.crossings).sorted()
        #expect(Self.at(0.9, brightness) / Self.at(0.1, brightness) > 2,
                "the brightest tenth is only \(Self.at(0.9, brightness) / Self.at(0.1, brightness))x the dullest")

        let lengths = clear.map(\.length).sorted()
        #expect(Self.at(0.9, lengths) / Self.at(0.1, lengths) > 3,
                "the longest tenth is only \(Self.at(0.9, lengths) / Self.at(0.1, lengths))x the shortest")
    }

    /// Real rain thickens and thins over seconds. How much of each second the
    /// fall is sounding has to move, and — the part that separates weather
    /// from a fast coin flip — it has to move slowly enough that one second
    /// tells you something about the next. Around 20 seconds it should tell
    /// you nothing again, or the rain is not gusting but drifting away.
    @Test func theFallGustsRatherThanTicking() {
        let busy = Self.fall(seconds: 120).busy
        let sorted = busy.sorted()
        let spread = Self.at(0.9, sorted) / Self.at(0.1, sorted)
        #expect(spread > 1.8, "the busiest tenth of seconds is only \(spread)x the quietest")

        let near = Self.correlation(busy, lag: 1)
        #expect(near > 0.15, "one second only predicts the next at \(near)")
        #expect(Self.correlation(busy, lag: 20) < near / 2,
                "the fall is still correlated 20 s out, so this is a drift and not a gust")
    }

    // MARK: Measuring the fall

    private struct Drop {
        var level: Double
        /// Zero crossings a second over the drop's first 8 ms, standing in
        /// for its centre frequency without needing a transform.
        var crossings: Double
        /// Seconds from the peak to 18 dB below it.
        var length: Double
    }

    private struct Fall {
        var drops: [Drop]
        var rate: Double
        /// Fraction of each second the fall was above the detection floor.
        var busy: [Double]
    }

    /// Renders the drops on their own — they are their own type precisely so
    /// this can be measured without the bed in the way — and picks them back
    /// out of the render. Loud drops overlap and are counted once, so the
    /// rate reads a little under what the fall actually draws.
    private static func fall(seconds: Int) -> Fall {
        var rng = XorShift()
        var drops = Drops(sampleRate: sampleRate)
        let frames = Int(sampleRate) * seconds
        var x = [Float](repeating: 0, count: frames)
        for i in 0..<frames { x[i] = drops.next(rng: &rng) }

        var follower = OnePoleLowpass()
        let coefficient = OnePoleLowpass.coefficient(cutoff: 150, sampleRate: Float(sampleRate))
        var level = [Float](repeating: 0, count: frames)
        var mean = 0.0
        for i in 0..<frames {
            level[i] = follower.process(abs(x[i]), coefficient)
            mean += Double(level[i])
        }
        let floor = Float(mean / Double(frames)) * 0.6

        var found: [Drop] = []
        var busy = [Double](repeating: 0, count: seconds)
        var i = 1
        while i < frames - 1 {
            guard level[i] > floor, level[i - 1] <= floor else {
                i += 1
                continue
            }
            var peak: Float = 0
            var top = i
            var end = i
            while end < min(frames, i + Int(sampleRate * 0.4)), level[end] > floor {
                if level[end] > peak {
                    peak = level[end]
                    top = end
                }
                end += 1
            }
            var quiet = end
            for k in top..<end where level[k] < peak / 8 {
                quiet = k
                break
            }
            var crossings = 0
            let window = min(frames - 1, i + Int(sampleRate * 0.008))
            for k in i..<window where (x[k] < 0) != (x[k + 1] < 0) { crossings += 1 }
            found.append(Drop(level: Double(peak),
                              crossings: Double(crossings) / 0.008,
                              length: Double(quiet - i) / sampleRate))
            busy[min(seconds - 1, i / Int(sampleRate))] += Double(end - i) / sampleRate
            // A drop that rings past the floor and dips back under it inside
            // the refractory window is the same drop, not a new one.
            i = max(end, i + Int(sampleRate * 0.012))
        }
        return Fall(drops: found, rate: Double(found.count) / Double(seconds), busy: busy)
    }

    private static func at(_ quantile: Double, _ sorted: [Double]) -> Double {
        sorted[min(sorted.count - 1, Int(Double(sorted.count) * quantile))]
    }

    private static func correlation(_ series: [Double], lag: Int) -> Double {
        let mean = series.reduce(0, +) / Double(series.count)
        let variance = series.map { ($0 - mean) * ($0 - mean) }.reduce(0, +)
        let covariance = (0..<(series.count - lag))
            .map { (series[$0] - mean) * (series[$0 + lag] - mean) }
            .reduce(0, +)
        return covariance / variance
    }
}
