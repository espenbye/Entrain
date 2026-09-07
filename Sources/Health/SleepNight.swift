import Foundation

/// One sleep stage as Health records it, without HealthKit in the way. The
/// reduction below is arithmetic on intervals, so it compiles and is tested
/// on every platform; the store only has to translate its category values
/// into these three.
struct SleepStageSample: Equatable, Sendable {
    enum Stage: Equatable, Sendable {
        /// Any of the asleep values: core, deep, REM or unspecified. Which
        /// stage it was does not matter here, only that it was sleep.
        case asleep
        /// A wakening inside the night. Never counted as sleep, and never
        /// used to bound one either.
        case awake
        /// Lights out, from a phone's bedtime schedule or a third-party app.
        /// Time in bed is not time asleep, so it only supplies the latency.
        case inBed
    }

    var stage: Stage
    var interval: DateInterval
    /// The bundle identifier of the app or device that wrote the sample.
    var source: String

    init(_ stage: Stage, _ interval: DateInterval, source: String) {
        self.stage = stage
        self.interval = interval
        self.source = source
    }
}

/// One night, reduced from whatever Health happened to hold for it.
///
/// Health is not a tidy record of nights. A watch writes staged sleep, a
/// phone writes time in bed from the Sleep Focus, a third-party app may
/// write its own take on the same hours, and all three overlap. Summing
/// them counts one night several times; interleaving them invents
/// wakenings that never happened. So a night is reduced to the account of
/// the single source that recorded most of it, which is the device that
/// was actually on the wrist, and the rest is dropped.
struct SleepNight: Equatable, Codable, Sendable {
    /// The night this belongs to, as the start of the day it began on: the
    /// small hours belong to the evening before.
    var night: Date
    /// Falling asleep to waking for the last time.
    var interval: DateInterval
    /// Time actually asleep inside that, so a long wakening in the middle
    /// does not count as sleep.
    var asleep: TimeInterval
    /// Getting into bed to falling asleep, when some source recorded time
    /// in bed before sleep started. Nil otherwise, which is the common case:
    /// most watches only write stages.
    var latency: TimeInterval?

    var bedtime: Date { interval.start }
    var wake: Date { interval.end }
}

extension SleepNight {
    /// A night has to be long enough to be a night. Below this it is a nap,
    /// a watch that came off, or a recording that started late, and it is
    /// dropped rather than dragged into the average.
    static let shortest: TimeInterval = 3 * 3600
    /// Asleep stretches further apart than this belong to different sleeps,
    /// so an afternoon nap does not fuse with the night that follows it.
    static let separation: TimeInterval = 3 * 3600
    /// The longest gap between getting into bed and falling asleep that is
    /// still that night's onset rather than an unrelated in-bed sample.
    static let longestLatency: TimeInterval = 3 * 3600

    /// The nights in `samples`, oldest first, at most one per night.
    ///
    /// Nights with nothing recorded simply do not appear: a missing night is
    /// an absence of evidence, not a night of no sleep, and averaging zeros
    /// into the signature would drag every derived time earlier.
    static func nights(from samples: [SleepStageSample], calendar: Calendar = .current) -> [SleepNight] {
        let asleep = samples.filter { $0.stage == .asleep && $0.interval.duration > 0 }
        guard !asleep.isEmpty else { return [] }

        // Every source's asleep time together, split where nothing at all was
        // recorded for longer than `separation`. Sources that describe the
        // same night overlap, so they land in the same episode; a nap and the
        // night after it do not.
        var episodes: [DateInterval] = []
        for interval in asleep.map(\.interval).sorted(by: { $0.start < $1.start }) {
            if let last = episodes.last, interval.start.timeIntervalSince(last.end) <= separation {
                episodes[episodes.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                episodes.append(interval)
            }
        }

        var nights: [Date: SleepNight] = [:]
        for episode in episodes {
            // The source that recorded most of the episode owns it. Ties break
            // on the identifier so the same input always reduces the same way.
            var coverage: [String: TimeInterval] = [:]
            for sample in asleep {
                guard let overlap = sample.interval.intersection(with: episode) else { continue }
                coverage[sample.source, default: 0] += overlap.duration
            }
            guard let source = coverage
                .sorted(by: { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value })
                .first?.key
            else { continue }

            let merged = merge(asleep.compactMap { $0.source == source ? $0.interval.intersection(with: episode) : nil })
            guard let first = merged.first, let last = merged.last else { continue }
            let interval = DateInterval(start: first.start, end: last.end)
            let time = merged.reduce(0) { $0 + $1.duration }
            guard time >= shortest else { continue }

            let night = SleepNight(
                night: key(for: interval.start, calendar: calendar),
                interval: interval,
                asleep: time,
                // Any source may hold the in-bed sample: the phone writes it
                // while the watch writes the stages. The latest one that
                // starts before sleep is this night's lights-out.
                latency: samples
                    .filter { $0.stage == .inBed && $0.interval.start < interval.start }
                    .map { interval.start.timeIntervalSince($0.interval.start) }
                    .filter { $0 > 0 && $0 <= longestLatency }
                    .min()
            )
            // A segmented sleeper can leave two long episodes in one night;
            // the longer one is the night.
            if let existing = nights[night.night], existing.asleep >= time { continue }
            nights[night.night] = night
        }
        return nights.values.sorted { $0.night < $1.night }
    }

    /// The night a sleep starting at `start` belongs to. Shifting back
    /// twelve hours first puts 23:40 and 01:20 on the same night, and keeps
    /// a nap on the day it was taken.
    static func key(for start: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: start.addingTimeInterval(-12 * 3600))
    }

    private static func merge(_ intervals: [DateInterval]) -> [DateInterval] {
        var merged: [DateInterval] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) where interval.duration > 0 {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        return merged
    }
}
