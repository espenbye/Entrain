import Synchronization

/// Control values shared between the main actor and the audio render thread.
/// Written from the UI, read once per render block.
final class AudioParameters: Sendable {
    let modulationRate = Atomic<Double>(16)
    let modulationDepth = Atomic<Double>(0.5)
    let binauralCarrier = Atomic<Double>(200)
    let binauralLevel = Atomic<Double>(0)
    let soundscape = Atomic<Int>(0)
    /// 0 or 1. The synths ramp toward it over a second so play and pause fade.
    let master = Atomic<Double>(0)
}
