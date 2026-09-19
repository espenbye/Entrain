import AppIntents
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
///
/// What it says, it can also do. Every size big enough for a button carries
/// one: the hour's mode, the stretches still to come, and the day itself,
/// so reading that the afternoon dip has started and doing something about
/// it are the same tap rather than a detour through the app.
struct DayWidget: Widget {
    private static let families: [WidgetFamily] = {
        #if os(macOS)
        [.systemSmall, .systemMedium, .systemLarge]
        #elseif os(iOS)
        [.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline]
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
    /// or a location. Written out by hand because `Suggestion` is not in
    /// this target, so it has to be kept honest by eye: without a
    /// signature the night's edges are the sun's, which puts Wind Down at
    /// sunset and the night three hours after it.
    private static func placeholder(at date: Date) -> CircadianDay {
        DayPhases(
            spans: [
                .init(phase: .night, mode: .sleep, start: 0),
                .init(phase: .wake, mode: .wake, start: 5 * 3600),
                .init(phase: .morning, mode: .focus, start: 7 * 3600),
                .init(phase: .sharpest, mode: .gamma, start: 11 * 3600 + 48 * 60),
                .init(phase: .dip, mode: .sprint, start: 14 * 3600 + 12 * 60),
                .init(phase: .afternoon, mode: .relax, start: 16 * 3600),
                .init(phase: .windDown, mode: .windDown, start: 19 * 3600),
                .init(phase: .night, mode: .sleep, start: 22 * 3600),
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
    private var next: CircadianDay.Span? { day.next(after: now) }

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
            // Nothing but the ring, and the ring is hidden from VoiceOver:
            // there is no text beside it here to read instead, so without
            // this the whole complication is an empty frame.
            DayRing(day: day, now: now, width: 8)
                .accessibilityElement()
                .accessibilityLabel(summary)
        #if os(watchOS)
        case .accessoryCorner:
            Image(systemName: span?.mode.symbol ?? "clock")
                .font(.title2)
                .widgetLabel { Text(span?.phase.title ?? "Your Day") }
        #endif
        case .systemMedium:
            HStack(spacing: 14) {
                DayRing(day: day, now: now, width: 16)
                    .frame(width: 96)
                VStack(alignment: .leading, spacing: 2) {
                    if let span {
                        Text(span.phase.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(span.range)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    if let next {
                        HStack(spacing: 4) {
                            Label(next.phase.title, systemImage: next.mode.symbol)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(next.interval.start.formatted(date: .omitted, time: .shortened))
                                .monospacedDigit()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    follow
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .systemLarge:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    DayRing(day: day, now: now, width: 14)
                        .frame(width: 88, height: 88)
                    if let span {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Now")
                                .font(.caption2.weight(.semibold))
                                .textCase(.uppercase)
                                .foregroundStyle(.secondary)
                            Text(span.phase.title)
                                .font(.headline)
                                .lineLimit(1)
                            Text(span.range)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            start(span)
                                .padding(.top, 2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if !rest.isEmpty {
                    Divider()
                    Text("Later Today")
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    VStack(spacing: 0) {
                        ForEach(Array(rest.enumerated()), id: \.element.id) { index, later in
                            if index > 0 { Divider().opacity(0.4) }
                            row(later)
                        }
                    }
                }
                Spacer(minLength: 0)
                follow
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
            // The ring hides itself from VoiceOver and so does the label
            // inside it, which leaves the small widget with nothing to say.
            .accessibilityElement()
            .accessibilityLabel(summary)
        }
    }

    /// How many of the stretches still to come the large widget lists. Four
    /// is what fits under the ring without shrinking the rows; a day has
    /// eight or so, and the ones past the fourth are tomorrow's problem.
    private static let rows = 4

    /// The stretches the large widget offers, cut to what fits under the ring.
    private var rest: [CircadianDay.Span] {
        Array(day.upcoming(after: now).prefix(Self.rows))
    }

    /// The ring in words, for the sizes where the ring is the whole widget.
    /// `DayRing` hides its canvas from VoiceOver because a canvas has
    /// nothing to say to it, and everywhere else the same day is carried in
    /// text beside it; here there is no beside.
    private var summary: String {
        guard let span else { return String(localized: "Your Day") }
        var parts = [String(localized: span.phase.title), span.mode.title, span.range]
        if let next {
            let at = next.interval.start.formatted(date: .omitted, time: .shortened)
            parts.append(String(localized: "Next: \(String(localized: next.phase.title)) at \(at)"))
        }
        return parts.joined(separator: ", ")
    }

    /// Hand the session over to the day. Tinted with the hour's own mode, so
    /// the button is the colour of the arc the marker is standing on.
    private var follow: some View {
        Button(intent: FollowDayIntent()) {
            Label("Follow the Day", systemImage: ModeChoice.symbol)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(span?.mode.tint ?? .accentColor)
    }

    /// Start one stretch's mode and nothing more, which is the deliberate
    /// step `Program` will not take on its own: a tap may put someone to
    /// bed, the day on its own may not.
    private func start(_ span: CircadianDay.Span) -> some View {
        Button(intent: StartSessionIntent(mode: span.mode)) {
            Label(span.mode.title, systemImage: "play.fill")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .tint(span.mode.tint)
    }

    /// One stretch still to come. The whole row is the button, so the tap
    /// target is the row rather than a symbol at the end of it.
    private func row(_ span: CircadianDay.Span) -> some View {
        Button(intent: StartSessionIntent(mode: span.mode)) {
            HStack(spacing: 10) {
                Text(span.interval.start.formatted(date: .omitted, time: .shortened))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .leading)
                Capsule()
                    .fill(span.mode.tint)
                    .frame(width: 3, height: 16)
                Text(span.phase.title)
                    .font(.subheadline)
                Spacer(minLength: 6)
                Label(span.mode.title, systemImage: span.mode.symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .padding(.vertical, 5)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
