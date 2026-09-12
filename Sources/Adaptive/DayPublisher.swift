import Foundation
import WidgetKit

/// Keeps the day widget's snapshot current.
///
/// `Session.broadcast` publishes what is playing; this publishes what the
/// day is, which is a different clock entirely. The session changes when
/// someone taps; the day changes when the sun moves, when Health learns
/// another night, or when the strain signals do — none of which a tap is
/// involved in, so it would be wrong to hang this off `broadcast` and it
/// would not fire on the days that matter.
///
/// Nothing here is on a timer. The snapshot covers a whole day and the
/// widget builds its own timeline from it, so this runs at launch and again
/// when an input says it has something new.
@MainActor
final class DayPublisher {
    static let shared = DayPublisher()

    private var published: DayPhases?
    private let daylight: Daylight
    private let health: HealthSignals
    private let now: () -> Date

    init(daylight: Daylight = .shared, health: HealthSignals = .shared, now: @escaping () -> Date = { .now }) {
        self.daylight = daylight
        self.health = health
        self.now = now
    }

    /// Writes the day and reloads the widget, unless it would write the same
    /// day twice. Cheap enough to call on any hint that an input moved: it
    /// is 288 evaluations of arithmetic and a small file.
    func publish(to directory: URL? = WidgetState.directory) {
        let phases = CircadianDay.on(
            now(), day: daylight.day(on:), sleep: health.sleep, vitals: health.vitals
        ).phases
        guard phases != published else { return }
        published = phases
        phases.save(to: directory)
        WidgetCenter.shared.reloadTimelines(ofKind: DayPhases.kind)
    }
}
