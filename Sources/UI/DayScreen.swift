import SwiftUI

/// The day Entrain is already reading, drawn.
///
/// Every adaptive part of the app has an opinion about the hour — the
/// suggestion card, Follow the Day, the brightness of the carrier — and
/// until now none of it was visible: you flipped a switch and trusted it.
/// This screen is that opinion as a twenty-four hour ring, so the trust has
/// something to rest on. It computes nothing of its own; `CircadianDay`
/// samples `Suggestion` forward, which is the same call the program makes.
///
/// It is deliberately not a score. Entrain cannot measure circadian phase —
/// nothing on a wrist can — and the footer says so rather than letting a
/// ring imply otherwise.
struct DayScreen: View {
    @Bindable var session: Session
    @Bindable private var daylight = Daylight.shared
    private let health = HealthSignals.shared
    #if os(macOS)
    @Environment(\.dismiss) private var dismiss
    #endif

    var body: some View {
        #if os(macOS)
        content
            .frame(width: 460, height: 620)
            .preferredColorScheme(.dark)
            .overlay(alignment: .topTrailing) {
                Button("Done") { dismiss() }
                    .buttonStyle(.borderless)
                    .padding(16)
            }
        #else
        // A tab root, not a sheet: nothing to dismiss, so no Done. The
        // title carries the name the tab abbreviates to "Day".
        NavigationStack {
            content
                .navigationTitle("Your Day")
                .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
        #endif
    }

    /// Rebuilt once a minute, like the suggestion card: the ring's marker
    /// moves a quarter of a degree in that time and every boundary on it
    /// falls on a five-minute grid.
    private var content: some View {
        TimelineView(.everyMinute) { context in
            let day = CircadianDay.on(
                context.date, day: daylight.day(on:), sleep: health.sleep,
                target: session.sleepTarget, vitals: health.vitals
            )
            ScrollView {
                VStack(spacing: 20) {
                    DayRing(day: day, now: context.date) {
                        if let span = day.span(at: context.date) {
                            VStack(spacing: 4) {
                                Text(span.phase.title)
                                    .font(.headline)
                                Text(span.range)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(height: 260)
                        // The Mac sheet has no title bar to hang Done off,
                        // so it floats in the corner and the ring starts
                        // below it rather than under it.
                        .padding(.top, ringTop)
                    if let span = day.span(at: context.date) {
                        NowCard(span: span, session: session)
                    }
                    PhaseList(day: day, now: context.date, session: session)
                    TargetCard(target: session.sleepTarget, measured: health.sleep)
                    RhythmCard(sleep: health.sleep, daylight: health.vitals[.timeInDaylight])
                    Text(footer(day))
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Backdrop(mode: session.mode))
        }
    }
}

extension DayScreen {
    #if os(macOS)
    var ringTop: CGFloat { 36 }
    #else
    var ringTop: CGFloat { 8 }
    #endif

    /// What the ring is actually resting on, which is two separate
    /// questions. Without location the sun is a 7-to-19 assumption; without
    /// a settled signature the night's edges are the sun's rather than this
    /// person's. Either can be true on its own, so the note names the one
    /// that is, and never offers a switch that is already on.
    func footer(_ day: CircadianDay) -> LocalizedStringResource {
        if !daylight.followsLocation {
            return "The day is assumed to run 7 to 19. Turn on Daylight in Settings to follow the real sun where you are."
        }
        if !day.isAnchored {
            return "The night's edges come from the sun until Health has enough nights to know your own bedtime."
        }
        return "Entrain cannot measure your body clock, and nothing can from a wrist. These phases are estimated from when you actually sleep and where the sun is, and nothing more."
    }
}

/// The phase now, what the body is doing in it, and the mode that fits.
private struct NowCard: View {
    let span: CircadianDay.Span
    @Bindable var session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: span.mode.symbol)
                    .font(.body.weight(.medium))
                    .foregroundStyle(span.mode.tint)
                    .frame(width: 34, height: 34)
                    .background(span.mode.tint.opacity(0.25), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Now")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    Text(span.phase.title)
                        .font(.headline)
                }
                Spacer(minLength: 8)
                Button(span.mode.title) {
                    session.mode = span.mode
                    Task { await session.play() }
                }
                .buttonStyle(.glassProminent)
                .tint(span.mode.tint)
                .foregroundStyle(span.mode.onTint)
                .font(.subheadline.weight(.semibold))
            }
            Text(span.phase.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}

/// The whole day in text, which is also the ring's accessible form. A tap
/// starts that stretch's mode — including a sleep bed, because a tap is
/// exactly the deliberate step `Program` refuses to take on its own.
private struct PhaseList: View {
    let day: CircadianDay
    let now: Date
    @Bindable var session: Session

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(day.spans.enumerated()), id: \.element.id) { index, span in
                if index > 0 { Divider().opacity(0.4) }
                Button {
                    session.mode = span.mode
                    Task { await session.play() }
                } label: {
                    HStack(spacing: 12) {
                        Text(span.interval.start.formatted(date: .omitted, time: .shortened))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 58, alignment: .leading)
                        Capsule()
                            .fill(span.mode.tint)
                            .frame(width: 3)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(span.phase.title)
                                .font(.subheadline.weight(.medium))
                            Text(span.mode.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        if span.interval.contains(now) {
                            Text("Now")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(span.mode.tint.opacity(0.3), in: .capsule)
                        }
                    }
                    .padding(.vertical, 9)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}

/// The night being aimed at, tonight's step toward it, and the night
/// actually being had. Three rows, because the distance between them is the
/// whole point: a target you cannot see yourself missing is a wish.
///
/// It is not a streak and not a score. Nothing here counts nights kept or
/// congratulates anyone; it reports the gap and stops, which is the same
/// thing `BodySignal` does with a resting heart rate.
private struct TargetCard: View {
    let target: SleepTarget
    let measured: SleepSignature?

    private var tonight: SleepEdges? { SleepEdges.tonight(target: target, measured: measured) }

    var body: some View {
        if target.isOn {
            VStack(alignment: .leading, spacing: 10) {
                Text("Sleep Target")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                row("Aiming For", Self.night(target.bedtime, target.wake), Self.length(target.hours))
                if let tonight, !tonight.hasArrived {
                    row("Tonight", Self.night(tonight.bedtime, tonight.wake), nil)
                    Text("Twenty minutes earlier than your last fortnight. A body clock will not jump, so Entrain walks your evenings toward the target rather than asking for it tonight.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let measured, measured.isSettled {
                    Text("You are sleeping the night you are aiming for.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if let measured, measured.isSettled {
                    row("You Usually Sleep", Self.night(measured.bedtime, measured.wake), nil)
                } else {
                    Text("Entrain aims straight at the target until Health has enough settled nights to walk from.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 18))
        }
    }

    private func row(_ title: LocalizedStringResource, _ value: String, _ trailing: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
        }
    }

    private static func night(_ bedtime: TimeInterval, _ wake: TimeInterval) -> String {
        "\(clock(bedtime))–\(clock(wake))"
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        Calendar.current.startOfDay(for: .now)
            .addingTimeInterval(seconds)
            .formatted(date: .omitted, time: .shortened)
    }

    private static func length(_ seconds: TimeInterval) -> String {
        let allowed: Set<Duration.UnitsFormatStyle.Unit> = seconds.truncatingRemainder(dividingBy: 3600) == 0
            ? [.hours] : [.hours, .minutes]
        return Duration.seconds(seconds).formatted(.units(allowed: allowed, width: .abbreviated))
    }
}

/// How steady the rhythm itself is, which is the one thing here a person
/// can change. Both figures come out of nights Entrain has already read:
/// nothing extra is queried for this card, and nothing acts on it.
private struct RhythmCard: View {
    let sleep: SleepSignature?
    let daylight: BodySignal?

    var body: some View {
        if sleep != nil || daylight != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("Rhythm")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                if let sleep {
                    row("Bedtime Varies By", Self.duration(sleep.spread),
                        "A steadier bedtime is the single thing that moves a body clock the most.")
                    if let drift = sleep.drift, abs(drift) >= 15 * 60 {
                        row("Free Nights Shift", Self.duration(abs(drift)),
                            "The middle of your sleep moves this far between working nights and free ones — a small time-zone change every week.")
                    }
                }
                if let daylight {
                    row("Daylight Today", Self.duration(daylight.today * 60), nil, summary: daylight.summary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 18))
        }
    }

    @ViewBuilder
    private func row(
        _ title: LocalizedStringResource, _ value: String,
        _ detail: LocalizedStringResource?, summary: LocalizedStringResource? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline)
                Spacer(minLength: 8)
                if let summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(value)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "—" }
        let allowed: Set<Duration.UnitsFormatStyle.Unit> = seconds >= 3600 ? [.hours, .minutes] : [.minutes]
        return Duration.seconds(seconds.rounded()).formatted(.units(allowed: allowed, width: .abbreviated))
    }
}
