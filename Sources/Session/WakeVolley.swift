import Foundation

/// The times a Wake alarm rings when one ring is not enough.
///
/// The system alert always has a Stop button, and a heavy sleeper presses
/// it without waking. So the alarm is not one alarm: it is a first ring and
/// a row of followers two minutes apart, each its own alarm, so Stop only
/// ever silences the one that is ringing and the next one is already on
/// its way. Only scanning the registered code cancels the rest. The row is
/// capped at an hour: long enough that nobody sleeps through it, short
/// enough that a phone left at home is not ringing at lunch.
///
/// Pure date arithmetic, with no AlarmKit in it, so it compiles and is
/// tested on the Mac where the framework does not exist.
enum WakeVolley {
    /// Between rings.
    static let spacing: TimeInterval = 120
    /// Rings in a volley, the first included. The system has a cap on
    /// alarms it does not publish; `WakeAlarm` keeps what it gets.
    static let count = 30
    /// How long after the first ring the volley is still going.
    static var window: TimeInterval { spacing * Double(count) }
    /// The same, for a sentence.
    static var minutes: Int { Int(window / 60) }

    /// The first ring after `now`: the next occurrence of the time on one
    /// of the days, or of the time alone when there are no days.
    static func next(_ time: Date, days: Set<Locale.Weekday>, after now: Date, calendar: Calendar = .current) -> Date? {
        occurrence(time, days: days, from: now, direction: .forward, calendar: calendar)
    }

    /// The most recent first ring at or before `now`.
    static func last(_ time: Date, days: Set<Locale.Weekday>, before now: Date, calendar: Calendar = .current) -> Date? {
        // `nextDate` excludes its argument, and a ring exactly at `now` counts.
        occurrence(time, days: days, from: now.addingTimeInterval(1), direction: .backward, calendar: calendar)
    }

    /// The rings that follow a first ring at `first`.
    static func followers(after first: Date) -> [Date] {
        (1..<count).map { first.addingTimeInterval(spacing * Double($0)) }
    }

    /// When the volley that began at the last first ring has not run out.
    static func liveStart(_ time: Date, days: Set<Locale.Weekday>, at now: Date, calendar: Calendar = .current) -> Date? {
        guard let start = last(time, days: days, before: now, calendar: calendar),
              now.timeIntervalSince(start) < window else { return nil }
        return start
    }

    private static func occurrence(
        _ time: Date, days: Set<Locale.Weekday>, from date: Date,
        direction: Calendar.SearchDirection, calendar: Calendar
    ) -> Date? {
        var parts = calendar.dateComponents([.hour, .minute], from: time)
        guard !days.isEmpty else {
            return calendar.nextDate(after: date, matching: parts, matchingPolicy: .nextTime, direction: direction)
        }
        let candidates = days.compactMap { day -> Date? in
            parts.weekday = day.number
            return calendar.nextDate(after: date, matching: parts, matchingPolicy: .nextTime, direction: direction)
        }
        return direction == .forward ? candidates.min() : candidates.max()
    }
}

extension Locale.Weekday {
    /// The calendar's number for the day, Sunday first, as `DateComponents` wants it.
    var number: Int {
        let week: [Locale.Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        return week.firstIndex(of: self)! + 1
    }
}
