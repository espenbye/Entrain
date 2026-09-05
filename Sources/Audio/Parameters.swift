import Synchronization

/// Control values shared between the main actor and the audio render thread.
/// Written from the UI, read once per render block.
final class AudioParameters: Sendable {
    let modulationRate = Atomic<Double>(16)
    let modulationDepth = Atomic<Double>(0.5)
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
}
