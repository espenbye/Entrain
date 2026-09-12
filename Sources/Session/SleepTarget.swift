import Foundation

/// The night you are aiming for, as opposed to the one you are having.
///
/// Everything else Entrain knows about sleep is descriptive: `SleepSignature`
/// measures the last fortnight and the suggestions follow it, so an app used
/// by someone going to bed at two in the morning quietly organises itself
/// around two in the morning. That is right for a sound that has to fit the
/// life it is played in, and useless to someone trying to change it. This is
/// the one prescriptive thing in the app: a wake time and a length, from
/// which a bedtime follows.
///
/// It is off by default and asks for nothing. An app that takes a target on
/// first launch is an app with an opinion about how you should live.
struct SleepTarget: Equatable, Codable, Sendable {
    /// Seconds from local midnight, like `SleepSignature`.
    var wake: TimeInterval
    /// How long the night should be.
    var hours: TimeInterval
    var isOn: Bool

    /// Seven-thirty and eight hours: the middle of the adult range (National
    /// Sleep Foundation 2015), and a starting point to move rather than a
    /// recommendation. Nothing uses it until the switch goes on.
    static let `default` = SleepTarget(wake: 7.5 * 3600, hours: 8 * 3600, isOn: false)

    /// The lengths the picker offers. Below six and above ten the figure is
    /// outside what the consensus recommends for an adult at all, and Entrain
    /// has no business helping someone aim there.
    static let lengths: [TimeInterval] = stride(from: 6.0, through: 10.0, by: 0.5).map { $0 * 3600 }

    /// The bedtime the target implies, wrapped onto the clock face.
    var bedtime: TimeInterval { (wake - hours).truncatingRemainder(dividingBy: 86400) + (wake - hours < 0 ? 86400 : 0) }

    var edges: SleepEdges { SleepEdges(bedtime: bedtime, wake: wake, source: .target, hasArrived: true) }
}

/// The two edges of tonight: when to be heading for bed, and when to be up.
///
/// Three things can supply them, in this order — the target, the measured
/// habit, and failing both the sun. The type exists so `Suggestion` asks one
/// question instead of unpicking that order in four places.
struct SleepEdges: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        /// Aiming at a target, or stepping toward one.
        case target
        /// Following what this person actually does.
        case habit
    }

    /// Seconds from local midnight.
    var bedtime: TimeInterval
    var wake: TimeInterval
    var source: Source
    /// Whether these are the target itself rather than a step on the way to
    /// it. False only while a habit is still being walked toward a goal.
    var hasArrived: Bool

    /// How far a night may move in one night.
    ///
    /// A body clock does not jump. Shifting sleep earlier faster than about
    /// half an hour a day does not work — the phase-response literature puts
    /// the ceiling on an unaided advance at roughly that (Duffy & Wright
    /// 2005; Burgess et al. 2003) — and an app that answers "I want to be up
    /// at seven" with "then be asleep at eleven tonight" is asking for the
    /// one thing that reliably fails. Twenty minutes sits inside the ceiling
    /// and is small enough not to be felt on any single night.
    static let step: TimeInterval = 20 * 60

    /// Tonight's edges, easing a measured habit toward the target rather
    /// than demanding it.
    ///
    /// There is no stored progress and no count of nights elapsed, because
    /// there needs to be none: the step is taken from the measured habit,
    /// and the measured habit is the last fortnight of real nights. Follow
    /// it and the average creeps earlier on its own, so the next step starts
    /// from further along. Stop following it and the average stops moving,
    /// which stalls the walk — which is the correct behaviour, not a bug. A
    /// counter ticking down toward a bedtime nobody was keeping would be
    /// worse than useless.
    ///
    /// Only a settled signature is walked from. A sleeper whose bedtimes are
    /// scattered over four hours has no habit to ease out of, and is also
    /// exactly the person a target is for, so the target applies at once.
    static func tonight(target: SleepTarget?, measured: SleepSignature?) -> SleepEdges? {
        let habit = measured?.isSettled == true ? measured : nil
        guard let target, target.isOn else {
            return habit.map { SleepEdges(bedtime: $0.bedtime, wake: $0.wake, source: .habit, hasArrived: true) }
        }
        guard let habit else { return target.edges }
        let toBed = offset(from: habit.bedtime, to: target.bedtime)
        let toWake = offset(from: habit.wake, to: target.wake)
        return SleepEdges(
            bedtime: wrap(habit.bedtime + min(step, max(-step, toBed))),
            wake: wrap(habit.wake + min(step, max(-step, toWake))),
            source: .target,
            hasArrived: abs(toBed) <= step && abs(toWake) <= step
        )
    }

    /// The signed shorter way round the clock from `a` to `b`, in
    /// -12h..<12h. Half past eleven is twenty minutes before ten to twelve
    /// and not twenty-three hours and forty minutes after it.
    static func offset(from a: TimeInterval, to b: TimeInterval) -> TimeInterval {
        wrap(b - a + 43200) - 43200
    }

    static func wrap(_ seconds: TimeInterval) -> TimeInterval {
        let remainder = seconds.truncatingRemainder(dividingBy: 86400)
        return remainder < 0 ? remainder + 86400 : remainder
    }

    /// The wake that ends the night on the day holding `date`, standing in
    /// for `SolarDay.sunrise`, and the bedtime that opens the night that day
    /// begins, standing in for `SolarDay.sunset`. A bedtime in the small
    /// hours belongs to the night the day opens, so it lands on the next one.
    func morning(on date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date).addingTimeInterval(wake)
    }

    func evening(on date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date).addingTimeInterval(bedtime + (bedtime < 12 * 3600 ? 86400 : 0))
    }
}
