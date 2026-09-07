import Foundation

/// Time of day and season as an input: brighter and a little deeper through
/// the morning, warmer and shallower after sunset. The arc is measured
/// against the sun, so a winter afternoon in Oslo already sounds like
/// evening while a June one does not, and the same mode never sounds the
/// same across a day.
///
/// The mapping rests on two findings and one caveat. Spectral brightness
/// tracks perceived arousal in sound (Ilie & Thompson 2006; Eerola, Ferrer
/// & Alluri 2012), so the carrier is brightest where circadian alertness
/// peaks, mid-morning, and warmest through the melatonin window that opens
/// two to three hours after dusk (Dijk & Czeisler 1994; Cajochen 2003).
/// Modulation depth scales the steady-state response the rhythm drives
/// (Picton et al. 2003), so it eases in the evening rather than pushing a
/// tired listener. No study ties a sound's spectrum to circadian phase, so
/// the whole effect stays inside half an octave and a fifth of the depth.
@MainActor
final class Circadian: AdaptiveInput {
    private(set) var adjustment: Adjustment = .none
    var onChange: (@MainActor () -> Void)?

    private let day: @MainActor (Date) -> SolarDay
    private let now: () -> Date
    private var task: Task<Void, Never>?

    init(day: @escaping @MainActor (Date) -> SolarDay, now: @escaping () -> Date = { .now }) {
        self.day = day
        self.now = now
    }

    convenience init(daylight: Daylight) {
        self.init(day: daylight.day(on:))
        daylight.onChange = { [weak self] in self?.refresh() }
    }

    /// Recomputed once a minute while playing: the arc moves a few
    /// thousandths per minute, and the synth smooths each step.
    func start(for mode: Mode) {
        refresh()
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func refresh() {
        let next = Self.adjustment(at: now(), day: day)
        guard next != adjustment else { return }
        adjustment = next
        onChange?()
    }

    /// Brightness and depth over the day, sunrise to sunset, as a fraction
    /// of daylight: dim at dawn, brightest a quarter of the way in, easing
    /// to neutral by sunset.
    private static let dayBrightness = Curve([(0, -0.2), (0.25, 0.5), (0.6, 0.3), (1, 0)])
    private static let dayDepth = Curve([(0, 0.9), (0.25, 1), (0.6, 1), (1, 0.95)])
    /// Over the night, sunset to sunrise: warmest and shallowest past the
    /// middle, climbing back toward dawn. The ends meet the day curves, so
    /// sunrise and sunset are not steps.
    private static let nightBrightness = Curve([(0, 0), (0.3, -0.5), (0.6, -0.7), (1, -0.2)])
    private static let nightDepth = Curve([(0, 0.95), (0.3, 0.85), (0.6, 0.8), (1, 0.9)])

    /// The adjustment at `date`, given the sun on any day around it.
    static func adjustment(at date: Date, day: @MainActor (Date) -> SolarDay) -> Adjustment {
        let today = day(date)
        if date < today.sunrise {
            let yesterday = day(date.addingTimeInterval(-86400))
            return night(progress(of: date, from: yesterday.sunset, to: today.sunrise))
        }
        if date < today.sunset {
            let p = progress(of: date, from: today.sunrise, to: today.sunset)
            return Adjustment(depth: dayDepth.value(at: p), brightness: dayBrightness.value(at: p))
        }
        let tomorrow = day(date.addingTimeInterval(86400))
        return night(progress(of: date, from: today.sunset, to: tomorrow.sunrise))
    }

    private static func night(_ p: Double) -> Adjustment {
        Adjustment(depth: nightDepth.value(at: p), brightness: nightBrightness.value(at: p))
    }

    private static func progress(of date: Date, from start: Date, to end: Date) -> Double {
        let span = end.timeIntervalSince(start)
        guard span > 0 else { return 0 }
        return min(1, max(0, date.timeIntervalSince(start) / span))
    }
}
