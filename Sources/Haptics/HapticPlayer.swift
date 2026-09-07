import Foundation
#if os(watchOS)
import WatchKit
#elseif canImport(CoreHaptics)
import CoreHaptics
#endif
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

/// Plays the modulation as touch. The phase comes from the audio render
/// clock, so over a ninety-minute session the tap cannot drift away from the
/// swell it belongs to; only the resolution of the taps is this player's,
/// because `sendParameters` takes locks and has no business on the render
/// thread. The session hands it a depth and the player does the rest.
///
/// Silence is the whole of the off state: an unmodulated bed sends depth
/// zero, which releases the actuator and the engine with it, so a mode
/// without haptics costs nothing.
@MainActor
final class HapticPlayer {
    /// About one audio block. Fifteen updates over the slowest beat Entrain
    /// plays and sixty over Deep Sleep's, which the skin reads as continuous.
    private static let interval = Duration.milliseconds(16)
    /// How long a failed start is left alone. In the background the engine
    /// refuses outright, and a sleep session would otherwise ask every second.
    private static let backoff = Duration.seconds(30)

    private let parameters: AudioParameters
    /// The modulation depth to render, zero when the beat is not to be felt.
    private var depth: Double = 0
    /// Whether the actuator should be running. Not the same as whether it is:
    /// the engine can be down and this still true, which is what revives it.
    private var isOn = false
    private var driver: Task<Void, Never>?
    private var retryAfter: ContinuousClock.Instant?

    init(parameters: AudioParameters) {
        self.parameters = parameters
    }

    /// The beat as it stands. Called once a second by the session's tick and
    /// on every change of mode, intensity or setting.
    func update(depth: Double) {
        self.depth = depth
        let wanted = depth > 0.0005 && !reducesMotion
        guard wanted != isOn else { return }
        isOn = wanted
        wanted ? begin() : end()
    }

    /// The session paused, or gave the audio up. Nothing holds the actuator.
    func stop() {
        depth = 0
        isOn = false
        end()
    }

    /// Reduce Motion is the setting a person reaches for when movement they
    /// did not ask for is unwelcome, and an all-night pulse against the skin
    /// is exactly that. The Silent switch needs nothing: the system already
    /// suppresses haptics when the device's are off, and there is no way to
    /// read it that would not second-guess that.
    private var reducesMotion: Bool {
        #if os(watchOS)
        WKAccessibilityIsReduceMotionEnabled()
        #elseif canImport(UIKit)
        UIAccessibility.isReduceMotionEnabled
        #else
        false
        #endif
    }

    // MARK: The driver

    /// Reads the phase the render thread published and sends it on. One task
    /// rather than a timer per beat: the pattern plays continuously and only
    /// its intensity moves.
    private func drive() {
        driver?.cancel()
        driver = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, isOn else { return }
                send(phase: parameters.modulationPhase.load(ordering: .relaxed))
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    private func end() {
        driver?.cancel()
        driver = nil
        release()
    }

    /// A start that failed is not tried again at once.
    private func failed() {
        retryAfter = .now + Self.backoff
        isOn = false
        end()
    }

    private func begin() {
        if let retryAfter, .now < retryAfter { isOn = false; return }
        retryAfter = nil
        guard acquire() else { return failed() }
        drive()
    }

    #if !os(watchOS) && canImport(CoreHaptics)
    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?

    /// A flat continuous event, looped: the shape comes from the intensity
    /// parameter, not from the pattern. Soft rather than crisp, since this
    /// is a swell to sink into and not a tap to notice.
    private static func pattern() throws -> CHHapticPattern {
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2),
            ],
            relativeTime: 0,
            duration: 30
        )
        return try CHHapticPattern(events: [event], parameters: [])
    }

    private func acquire() -> Bool {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return false }
        do {
            let engine = try self.engine ?? makeEngine()
            self.engine = engine
            try engine.start()
            let player = try engine.makeAdvancedPlayer(with: Self.pattern())
            // Zero loops at the end of the last event, so the thirty-second
            // event repeats for as long as the session does.
            player.loopEnabled = true
            // Silent until the first phase arrives, so it starts on the beat.
            try player.sendParameters([Self.intensity(0)], atTime: CHHapticTimeImmediate)
            try player.start(atTime: CHHapticTimeImmediate)
            self.player = player
            return true
        } catch {
            return false
        }
    }

    private func makeEngine() throws -> CHHapticEngine {
        let engine = try CHHapticEngine()
        // No audio from this engine: the bed is the sound, and a second
        // audio graph would fight the first for the session.
        engine.playsHapticsOnly = true
        // The engine going down is not an error to recover from here. Both
        // handlers put the player back to square one and let the session's
        // next tick rebuild it, which is a second away for every mode that
        // has haptics at all, and never a retry loop.
        engine.resetHandler = { [weak self] in
            Task { @MainActor in self?.lost() }
        }
        engine.stoppedHandler = { [weak self] _ in
            Task { @MainActor in self?.lost() }
        }
        return engine
    }

    /// The engine reset or was stopped by the system, for a phone call, the
    /// app suspending, or the hardware itself.
    private func lost() {
        guard isOn else { return }
        isOn = false
        end()
    }

    private func release() {
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
        engine?.stop()
        engine = nil
    }

    private func send(phase: Double) {
        try? player?.sendParameters(
            [Self.intensity(Haptics.intensity(depth: depth, phase: phase))],
            atTime: CHHapticTimeImmediate
        )
    }

    private static func intensity(_ value: Double) -> CHHapticDynamicParameter {
        CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: Float(value), relativeTime: 0)
    }
    #elseif os(watchOS)
    /// The watch has no Core Haptics, so the LFO is felt as one tap where it
    /// peaks rather than as a swell: the same beat, at the resolution the
    /// Taptic Engine offers here.
    private var lastPhase: Double = 1

    private func acquire() -> Bool {
        lastPhase = 1
        return true
    }

    private func release() {}

    private func send(phase: Double) {
        defer { lastPhase = phase }
        guard phase < lastPhase else { return }
        WKInterfaceDevice.current().play(.click)
    }
    #else
    private func acquire() -> Bool { false }
    private func release() {}
    private func send(phase: Double) {}
    #endif
}
