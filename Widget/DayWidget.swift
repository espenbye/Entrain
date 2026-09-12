import SwiftUI
import WidgetKit

/// The day on the Home Screen, the Lock Screen and the watch face.
///
/// It draws `DayPhases` and computes nothing: the widget process has no
/// HealthKit and no Core Location, so the day it would work out on its own
/// would be a worse day than the app's. `DayPublisher` writes the snapshot;
/// this reads it, lays it over today, and builds one timeline entry per
/// phase boundary — a dozen at most — so the ring turns and the label
/// changes without the app being involved again.
struct DayWidget: Widget {
    private static let families: [WidgetFamily] = {
        #if os(macOS)
        [.systemSmall, .systemMedium]
        #elseif os(iOS)
        [.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline]
        #else
        [.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline]
        #endif
    }()

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: DayPhases.kind, provider: DayProvider()) { entry in
            DayWidgetView(day: entry.day, now: entry.date)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Your Day")
        .description("The phase you are in and the ones around it.")
        .supportedFamilies(Self.families)
    }
}

struct DayEntry: TimelineEntry {
    let date: Date
    let day: CircadianDay
}

/// Entries to the end of the day, then a reload. The whole day is known in
/// advance, so there is nothing to poll and nothing to wake the app for;
/// the reload at midnight is what picks up tomorrow's sun.
struct DayProvider: TimelineProvider {
    /// How often the ring gets a new entry. A widget only draws at the
    /// dates its timeline names, so the marker would otherwise sit still
    /// for the hours between two phases — on a sleep bed, all night. A
    /// quarter hour is four degrees of the ring, small enough to read as
    /// the marker having moved and coarse enough that a day is a hundred
    /// entries rather than three hundred. Entries are not reloads: the
    /// system renders these from one timeline and never wakes the app.
    private static let step: TimeInterval = 15 * 60

    /// What a fresh install draws before the app has ever run: the clock
    /// day, which is the same fallback everything else uses without Health
    /// or a location.
    private static func placeholder(at date: Date) -> CircadianDay {
        DayPhases(
            spans: [
                .init(phase: .night, mode: .sleep, start: 0),
                .init(phase: .wake, mode: .wake, start: 5 * 3600),
                .init(phase: .morning, mode: .focus, start: 7 * 3600),
                .init(phase: .sharpest, mode: .gamma, start: 11 * 3600 + 48 * 60),
                .init(phase: .afternoon, mode: .relax, start: 14 * 3600 + 12 * 60),
                .init(phase: .windDown, mode: .windDown, start: 16 * 3600),
                .init(phase: .night, mode: .sleep, start: 19 * 3600),
            ],
            sunrise: 7 * 3600, sunset: 19 * 3600
        ).day(on: date)
    }

    private static func day(at date: Date) -> CircadianDay {
        (DayPhases.load() ?? nil).map { $0.day(on: date) } ?? placeholder(at: date)
    }

    func placeholder(in context: Context) -> DayEntry {
        DayEntry(date: .now, day: Self.placeholder(at: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) {
        completion(DayEntry(date: .now, day: Self.day(at: .now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        let now = Date.now
        let day = Self.day(at: now)
        var dates: Set<Date> = [now]
        dates.formUnion(day.spans.map(\.interval.start).filter { $0 > now })
        var at = now.addingTimeInterval(Self.step)
        while at < day.end {
            dates.insert(at)
            at = at.addingTimeInterval(Self.step)
        }
        let entries = dates.sorted().map { DayEntry(date: $0, day: day) }
        // Tomorrow is the same shape a few minutes shifted, so the reload is
        // at midnight rather than at every boundary.
        completion(Timeline(entries: entries, policy: .after(day.end)))
    }
}

struct DayWidgetView: View {
    let day: CircadianDay
    let now: Date
    @Environment(\.widgetFamily) private var family

    private var span: CircadianDay.Span? { day.span(at: now) }

    var body: some View {
        switch family {
        case .accessoryInline:
            if let span {
                Label(String(localized: span.phase.title), systemImage: span.mode.symbol)
            }
        case .accessoryRectangular:
            HStack(spacing: 8) {
                DayRing(day: day, now: now, width: 9)
                if let span {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(span.phase.title)
                            .font(.headline)
                        Text(span.mode.title)
                            .foregroundStyle(.secondary)
                        Text(span.range)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .accessoryCircular:
            DayRing(day: day, now: now, width: 8)
        #if os(watchOS)
        case .accessoryCorner:
            Image(systemName: span?.mode.symbol ?? "clock")
                .font(.title2)
                .widgetLabel { Text(span?.phase.title ?? "Your Day") }
        #endif
        case .systemMedium:
            HStack(spacing: 16) {
                DayRing(day: day, now: now, width: 18)
                    .frame(width: 108)
                if let span {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(span.phase.title)
                            .font(.headline)
                        Text(span.range)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if let next = day.spans.first(where: { $0.interval.start > now }) {
                            Divider()
                            Text("Next")
                                .font(.caption2.weight(.semibold))
                                .textCase(.uppercase)
                                .foregroundStyle(.secondary)
                            Label(next.phase.title, systemImage: next.mode.symbol)
                                .font(.subheadline)
                            Text(next.interval.start.formatted(date: .omitted, time: .shortened))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        default:
            DayRing(day: day, now: now, width: 16) {
                if let span {
                    VStack(spacing: 2) {
                        Text(span.phase.title)
                            .font(.caption.weight(.semibold))
                            .minimumScaleFactor(0.7)
                        Text(span.mode.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                }
            }
        }
    }
}
