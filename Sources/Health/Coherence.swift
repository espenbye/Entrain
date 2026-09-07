import Foundation

/// Whether a heart is following a paced breath.
///
/// Breathing moves heart rate: it rises through the inhale and falls
/// through the exhale. The swing is largest around six breaths a minute,
/// the resonance frequency where the respiratory rhythm and the baroreflex
/// line up, which is exactly where the Coherent pattern sits (Vaschillo,
/// Lehrer et al. 2002; Lehrer & Gevirtz 2014). So a listener actually
/// following the pacing shows a heart rate swinging with the cue, and one
/// who has drifted off it shows no relation to the cue at all.
///
/// Two honest limits, which is why this returns a number to read and not
/// one to steer anything with. A workout session delivers a heart rate
/// every few seconds, barely twice the rate the pattern asks for, so the
/// swing itself cannot be measured — only whether something is moving with
/// the cue. And the baroreflex lags the breath by a second or two, so the
/// correlation is an underestimate even when the listener is perfectly on
/// the pace.
/// One heart-rate reading, placed by how far into the session it arrived.
struct Beat: Equatable, Sendable {
    var elapsed: Double
    var bpm: Double

    init(elapsed: Double, bpm: Double) {
        self.elapsed = elapsed
        self.bpm = bpm
    }
}

enum Coherence {
    /// Samples needed before the correlation means anything.
    static let leastBeats = 12

    /// Pearson correlation between the heart rates in `beats` and where the
    /// breath should have been when each arrived. Nil when there is too
    /// little to go on, or when either series never moves.
    static func correlation(of beats: [Beat], following pattern: BreathingPattern) -> Double? {
        guard beats.count >= leastBeats else { return nil }
        let paired = beats.compactMap { beat in depth(of: pattern, at: beat.elapsed).map { ($0, beat.bpm) } }
        guard paired.count >= leastBeats else { return nil }
        return pearson(paired.map(\.0), paired.map(\.1))
    }

    /// How full the lungs should be `elapsed` seconds into the pattern,
    /// 0 to 1: the same curve the breathing circle draws. A hold stays
    /// where the phase before it left off.
    static func depth(of pattern: BreathingPattern, at elapsed: Double) -> Double? {
        guard let position = pattern.position(at: elapsed) else { return nil }
        switch position.phase {
        case .inhale: return position.progress
        case .exhale: return 1 - position.progress
        case .hold:
            let steps = pattern.steps
            return steps[(position.index + steps.count - 1) % steps.count].phase == .inhale ? 1 : 0
        }
    }

    private static func pearson(_ a: [Double], _ b: [Double]) -> Double? {
        let n = Double(a.count)
        let meanA = a.reduce(0, +) / n
        let meanB = b.reduce(0, +) / n
        var covariance = 0.0, varianceA = 0.0, varianceB = 0.0
        for (x, y) in zip(a, b) {
            covariance += (x - meanA) * (y - meanB)
            varianceA += (x - meanA) * (x - meanA)
            varianceB += (y - meanB) * (y - meanB)
        }
        guard varianceA > 0, varianceB > 0 else { return nil }
        return covariance / (varianceA * varianceB).squareRoot()
    }
}
