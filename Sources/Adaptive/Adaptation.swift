import Foundation

/// What one input asks of the sound, on top of what the mode sets. Inputs
/// never write parameters themselves: the session composes every adjustment
/// and stores the result, so two inputs cannot fight over an atomic.
struct Adjustment: Equatable, Sendable {
    /// Multiplier on the modulation depth. 1 leaves it alone.
    var depth: Double = 1
    /// Carrier brightness in -1...1: half an octave down or up on the voice
    /// filters. 0 leaves them where the mode put them.
    var brightness: Double = 0

    static let none = Adjustment()

    /// Depths multiply and brightness adds, then the sum is clamped, so
    /// several inputs pulling the same way still land inside the range the
    /// synth is tuned for.
    func combined(with other: Adjustment) -> Adjustment {
        Adjustment(
            depth: depth * other.depth,
            brightness: min(1, max(-1, brightness + other.brightness))
        )
    }
}

/// One source of context or body signal: daylight, heart rate, cadence. The
/// session starts every input when play begins and stops it on pause, so no
/// sensor runs while nothing plays. An input calls `onChange` from the main
/// actor when its adjustment moved; the session reads `adjustment` then.
@MainActor
protocol AdaptiveInput: AnyObject {
    var adjustment: Adjustment { get }
    var onChange: (@MainActor () -> Void)? { get set }
    func start(for mode: Mode)
    func stop()
}
