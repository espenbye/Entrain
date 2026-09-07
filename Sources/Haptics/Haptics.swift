import Foundation

/// The tactile side of the modulation. The amplitude LFO that swells the bed
/// also drives a continuous haptic, so a beat felt at the wrist or through
/// the mattress is the same waveform as the beat heard: one pulse, two senses.
enum Haptics {
    /// Peak intensity of the continuous event. Well below full: this plays
    /// under a pillow for hours, not as a notification.
    static let ceiling: Double = 0.7

    /// The fastest beat worth rendering. The actuator cannot resolve a cycle
    /// much above this, so Gamma's 40 Hz would alias into a flat buzz rather
    /// than a pulse; those modes go without.
    static let maxRate: Double = 4

    /// Intensity 0...1 for a modulation `depth` at LFO `phase`, in cycles.
    /// The bed is loudest where the audio pulse subtracts nothing, at phase
    /// zero, so the tap lands there too; an unmodulated bed is felt not at
    /// all, which is how Sleep fades its haptics out as it settles.
    static func intensity(depth: Double, phase: Double) -> Double {
        ceiling * min(1, max(0, depth)) * (0.5 + 0.5 * cos(2 * .pi * phase))
    }
}

extension Mode {
    /// Whether the beat is slow enough to feel `elapsed` seconds in. Read
    /// from the rate the mode plays now, not the one it starts at, so Wind
    /// Down picks the haptics up as its ramp crosses down into delta and
    /// Wake drops them as it climbs back out.
    func feelsBeat(at elapsed: Double, length: SessionLength) -> Bool {
        rate(elapsed: elapsed, length: length) <= Haptics.maxRate
    }
}
