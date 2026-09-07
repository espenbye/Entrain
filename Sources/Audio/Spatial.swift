import AVFoundation
#if canImport(CoreMotion)
import CoreMotion
#endif

/// Where each soundscape sits around the listener, in metres. The listener
/// faces -z with +y up, AVAudioEnvironmentNode's default. Everything stays
/// inside `reach`, the environment node's reference distance, so a position
/// never changes a voice's loudness; only the direction does.
///
/// Sources move on slow orbits, minutes per turn, replacing the pan the
/// stereo bed sweeps. The intent is the same, to counter habituation, but
/// movement in a rendered room reads as environment rather than as the mix
/// wobbling. Nothing here moves at the entrainment rate.
enum Room {
    static let reach: Float = 4

    /// Position after `seconds` of play.
    static func position(of soundscape: Soundscape, at seconds: Double) -> AVAudio3DPoint {
        let t = Float(seconds)
        switch soundscape {
        case .rain:
            // Overhead and around, drifting across the ceiling once every 15 minutes.
            let sway = 2 * sin(twoPi * t / 900)
            return AVAudio3DPoint(x: sway, y: 2.5, z: -1 + 0.5 * cos(twoPi * t / 900))
        case .pad:
            // In front at a few metres, circling once every 25 minutes.
            let turn = twoPi * t / 1500
            return AVAudio3DPoint(x: 3 * sin(turn), y: 0.3, z: -3 * cos(turn))
        case .drone:
            // Low and behind, swaying a little over 20 minutes.
            return AVAudio3DPoint(x: 0.8 * sin(twoPi * t / 1200), y: -1, z: 2.5)
        case .noise:
            // Steady above and ahead: the sleep bed does not move.
            return AVAudio3DPoint(x: 0, y: 1.5, z: -1.2)
        }
    }
}

/// The room a mode is heard in: which space, how much of it comes back, and
/// how much of each source is sent into it. One fixed medium room served
/// eight different intents, which is one too few — a room is as much of what
/// a mode is for as its rate is. Focus is close and nearly dry, so nothing
/// arrives late enough to pull attention; Meditate and Relax are large and
/// far, where a sound has somewhere to go; the beds that end the night are
/// drier still, so nothing swims while you are trying to stop thinking.
struct Space: Equatable, Sendable {
    var preset: AVAudioUnitReverbPreset
    /// What comes back from the room, in dB.
    var level: Float
    /// How much of each source is sent into it, 0...1.
    var blend: Float
}

extension Room {
    static func space(for mode: Mode) -> Space {
        switch mode {
        case .focus: Space(preset: .smallRoom, level: -20, blend: 0.12)
        case .gamma: Space(preset: .smallRoom, level: -18, blend: 0.15)
        case .relax: Space(preset: .mediumRoom, level: -12, blend: 0.30)
        case .meditate: Space(preset: .largeRoom, level: -10, blend: 0.38)
        case .windDown: Space(preset: .mediumRoom, level: -12, blend: 0.28)
        case .wake: Space(preset: .mediumRoom, level: -14, blend: 0.22)
        case .sleep, .deepSleep: Space(preset: .smallRoom, level: -24, blend: 0.08)
        }
    }

    /// Where the send goes on the way between two rooms. The unit cannot
    /// cross-fade one preset into another, so a change of room is taken down
    /// to silence, swapped, and brought back up.
    static let silentSend: Float = -40
}

#if canImport(CoreMotion) && !os(watchOS)
/// Turns the listener with the head so the room stays where it is. Reads
/// AirPods and Beats motion; nothing else reports. Yaw is measured from
/// where the head pointed when tracking started, since the sensor has no
/// compass and its reference is arbitrary.
@MainActor
final class HeadTracker {
    static var isAvailable: Bool { CMHeadphoneMotionManager().isDeviceMotionAvailable }

    private let manager = CMHeadphoneMotionManager()
    private var yawOrigin: Double?
    private let onOrientation: @MainActor (AVAudio3DAngularOrientation) -> Void

    init(onOrientation: @escaping @MainActor (AVAudio3DAngularOrientation) -> Void) {
        self.onOrientation = onOrientation
    }

    var isRunning: Bool { manager.isDeviceMotionActive }

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        yawOrigin = nil
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let attitude = motion?.attitude else { return }
            MainActor.assumeIsolated { self.update(attitude) }
        }
    }

    func stop() {
        guard manager.isDeviceMotionActive else { return }
        manager.stopDeviceMotionUpdates()
        onOrientation(AVAudio3DAngularOrientation(yaw: 0, pitch: 0, roll: 0))
    }

    private func update(_ attitude: CMAttitude) {
        let origin = yawOrigin ?? attitude.yaw
        yawOrigin = origin
        onOrientation(Self.orientation(yaw: attitude.yaw - origin, pitch: attitude.pitch, roll: attitude.roll))
    }

    /// Core Motion radians to the environment node's degrees. Both count a
    /// left turn as positive yaw, so the axes pass straight through.
    nonisolated static func orientation(yaw: Double, pitch: Double, roll: Double) -> AVAudio3DAngularOrientation {
        let degrees = 180 / Double.pi
        return AVAudio3DAngularOrientation(
            yaw: Float(yaw * degrees), pitch: Float(pitch * degrees), roll: Float(roll * degrees)
        )
    }
}
#endif
