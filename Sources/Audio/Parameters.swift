import Synchronization

/// Control values shared between the main actor and the audio render thread.
/// Written from the UI, read once per render block.
final class AudioParameters: Sendable {
    let modulationRate = Atomic<Double>(16)
    let modulationDepth = Atomic<Double>(0.5)
    /// Where the modulation envelope peaks within its cycle, 0.1...0.9. The
    /// mode sets it; see `Mode.envelope` for what the shape is for.
    let modulationShape = Atomic<Double>(0.5)
    /// -1...1: the voice filters half an octave down or up from where the
    /// texture drift puts them. Time of day sets it; see `Circadian`.
    let brightness = Atomic<Double>(0)
    let binauralCarrier = Atomic<Double>(200)
    let binauralLevel = Atomic<Double>(0)
    /// Bitmask of active soundscapes, one bit per `Soundscape` index.
    let layers = Atomic<Int>(1)
    /// 0...1. The synths ramp toward it over a second, so play and pause fade
    /// and a timed session can taper over its last minutes.
    let master = Atomic<Double>(0)
    /// 0...1 user volume, independent of the system output level. Smoothed
    /// over 50 ms so a slider drag is immediate but click-free.
    let volume = Atomic<Double>(1)
    /// The bed's LFO phase in cycles, 0..<1, written once per render block by
    /// the voice that leads the bed. Haptics read it rather than keeping a
    /// clock of their own, so touch and sound cannot drift apart over a night.
    let modulationPhase = Atomic<Double>(0)
    /// A cue, `Cue.encode`d: every new value plays one tone. The trigger
    /// count in the high bits makes a repeat of the same cue a change.
    let cue = Atomic<Int>(0)
}

/// What the cue synth can play: a breathing phase, or the signature that
/// opens a mode that ends in bed.
enum Cue: Equatable, Sendable {
    case breath(BreathCue)
    case bedtime

    /// The low three bits carry the cue; the rest count triggers, so the
    /// same cue twice in a row still reads as a change on the render thread.
    static func encode(_ cue: Cue, trigger: Int) -> Int { trigger << 3 | cue.code }
    static func decode(_ value: Int) -> Cue { Cue(code: value & 7) }

    private var code: Int {
        switch self {
        case .breath(let phase): phase.rawValue
        case .bedtime: 4
        }
    }

    private init(code: Int) {
        self = code == 4 ? .bedtime : .breath(BreathCue(rawValue: code & 3)!)
    }
}
