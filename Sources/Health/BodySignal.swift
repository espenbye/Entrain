import Foundation

/// A daily body measure Health can supply.
enum BodyMetric: String, CaseIterable, Sendable {
    case restingHeartRate
    case heartRateVariability

    var title: LocalizedStringResource {
        switch self {
        case .restingHeartRate: "Resting Heart Rate"
        case .heartRateVariability: "Heart Rate Variability"
        }
    }

    /// Heart rate variability is right-skewed: the spread of SDNN across
    /// days has a long tail upward, and the standard treatment is to take
    /// logarithms before any mean or standard deviation (Task Force of the
    /// ESC and NASPE, 1996). Baselining on the log makes a deviation a
    /// ratio rather than a difference, which is what "down 20 %" means for
    /// a variability figure. Resting heart rate is near enough symmetric to
    /// take as it stands.
    var isLogNormal: Bool { self == .heartRateVariability }
}

/// One day against this person's own recent history.
///
/// Absolute numbers do not travel: 48 bpm resting is a runner's ordinary
/// morning and a warning in someone else, and an SDNN of 60 ms means
/// nothing without knowing what 60 ms is for that person. Only the
/// deviation from their own baseline carries information, so that is all
/// this exposes. What it is worth acting on is not decided here.
struct BodySignal: Equatable, Sendable {
    var metric: BodyMetric
    /// Today's value, in the metric's own unit: beats per minute, or
    /// milliseconds.
    var today: Double
    /// The middle of the recent range, same unit. For a log-normal metric
    /// this is the geometric mean, which is the median of the fitted
    /// distribution rather than its arithmetic mean.
    var baseline: Double
    /// Today in standard deviations from that baseline, clamped. Above zero
    /// is above this person's own normal, whatever "normal" is for them.
    var deviation: Double
    /// Days the baseline rests on. Days Health had nothing for are absent,
    /// not zero.
    var days: Int
}

extension BodySignal {
    /// Where today sits, in words. The bands are the conventional ones for a
    /// standard score and describe the number, not the body: "below your
    /// usual" means this reading is unusual for this person, and nothing
    /// about why or whether it matters.
    var summary: LocalizedStringResource {
        switch deviation {
        case ..<(-1.5): "well below your usual"
        case ..<(-0.5): "below your usual"
        case 1.5...: "well above your usual"
        case 0.5...: "above your usual"
        default: "about usual"
        }
    }

    /// The rolling window. Sixty days is long enough that a bad fortnight
    /// does not become the new normal and short enough to follow a season
    /// of training or illness; it is also the window iOS's own Vitals uses,
    /// so Entrain and Health will not disagree about what is unusual.
    static let window = 60
    /// Below this the standard deviation is mostly noise and a deviation
    /// says nothing, so no signal is published at all.
    static let leastDays = 14
    /// Deviations are clamped here: past three standard deviations the
    /// number is an artefact — a missed strap, a fever — not a gradation.
    static let limit = 3.0

    /// Today against `history`, which is the preceding days and must not
    /// include today. Nil when there is not enough history to say anything,
    /// which is the state a fresh install and a Health-less Mac are both in.
    static func from(history: [Double], today: Double, metric: BodyMetric) -> BodySignal? {
        let values = history.suffix(window).filter { $0 > 0 }
        guard values.count >= leastDays, today > 0 else { return nil }
        let scaled = metric.isLogNormal ? values.map(log) : Array(values)
        let point = metric.isLogNormal ? log(today) : today
        let mean = scaled.reduce(0, +) / Double(scaled.count)
        let variance = scaled.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(scaled.count - 1)
        let spread = variance.squareRoot()
        guard spread.isFinite, spread > 0 else { return nil }
        return BodySignal(
            metric: metric,
            today: today,
            baseline: metric.isLogNormal ? exp(mean) : mean,
            deviation: min(limit, max(-limit, (point - mean) / spread)),
            days: scaled.count
        )
    }
}
