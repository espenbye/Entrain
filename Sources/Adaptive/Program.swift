import Foundation

/// The day as a session that runs itself. `Suggestion` already says what an
/// hour is for, from the solar day, the habitual bedtime and the strain
/// signals; the program is that same opinion read forward, so the session
/// moves between modes on its own and a listener can leave the sound on
/// rather than open the app. There is deliberately no schedule here: a
/// second table would say almost the same thing as the first, and the two
/// would drift the first time either was touched.
///
/// One thing the program will not do is put someone to bed. Walking Focus
/// to Relax changes the background; starting an eight-hour sleep bed at
/// eleven at night unasked is a different promise, and one the listener
/// should make rather than find made for them. Where the day says sleep,
/// the program holds Wind Down and names what it is holding back, so the
/// last step into bed stays a tap. Wake is not held: it is a fifteen-minute
/// ramp out of a nap, not a night.
struct Program {
    /// How far ahead the next change is looked for, and how finely. Every
    /// boundary `Suggestion` has falls on a solar or habitual time, none of
    /// which moves faster than five minutes, and 288 evaluations of a little
    /// arithmetic once per boundary is cheaper than a second copy of the
    /// schedule kept in step with the first.
    static let step: TimeInterval = 5 * 60
    static let horizon: TimeInterval = 24 * 3600

    /// What the program plays now, and what the day asks for next.
    struct Plan: Equatable, Sendable {
        /// The mode the session should be in.
        var mode: Mode
        /// The next mode the day asks for, as the day says it — bed included,
        /// so the player can name what the program is waiting on — and when.
        var next: Mode?
        var at: Date?

        /// Whether that next step is a bed the program will not enter itself.
        var asks: Bool { next?.isSleep == true }
    }

    /// The day's suggestion, held out of bed.
    static func mode(for suggestion: Mode) -> Mode { suggestion.isSleep ? .windDown : suggestion }

    static func at(
        _ date: Date, day: (Date) -> SolarDay, sleep: SleepSignature? = nil,
        target: SleepTarget? = nil, vitals: [BodyMetric: BodySignal] = [:], calendar: Calendar = .current
    ) -> Plan {
        func suggested(_ when: Date) -> Mode {
            Suggestion.at(when, day: day, sleep: sleep, target: target, vitals: vitals, calendar: calendar).mode
        }
        let now = suggested(date)
        var plan = Plan(mode: mode(for: now))
        var ahead = step
        while ahead <= horizon {
            let when = date.addingTimeInterval(ahead)
            let next = suggested(when)
            if next != now {
                plan.next = next
                plan.at = when
                break
            }
            ahead += step
        }
        return plan
    }
}
