import SwiftUI

/// Twenty-four hours as a ring, midnight at the top and the day running
/// clockwise. One arc per span in its mode's tint, ticks for the sun and
/// for this person's own bedtime and wake, and a marker at now.
///
/// Drawn in a `Canvas` rather than as stacked shapes: it is one pass over
/// at most a dozen arcs and no view identity to keep, and it redraws once a
/// minute. VoiceOver gets nothing from it, so it is hidden here and the
/// caller carries the same day in text.
///
/// Shared with the widget, which is why it takes a `CircadianDay` and no
/// session: a widget has nothing to start and nothing to bind to. The
/// stroke is a parameter because the same ring has to read at 30 points on
/// a watch face and at 260 in the app, and the centre is the caller's, so
/// a complication can leave it empty.
struct DayRing<Label: View>: View {
    let day: CircadianDay
    let now: Date
    var width: CGFloat = 26
    @ViewBuilder var label: () -> Label

    var body: some View {
        ZStack {
            Canvas { context, size in
                let side = min(size.width, size.height)
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = (side - width) / 2

                for span in day.spans {
                    var path = Path()
                    path.addArc(
                        center: center, radius: radius,
                        startAngle: angle(day.progress(of: span.interval.start)),
                        endAngle: angle(day.progress(of: span.interval.end)),
                        clockwise: false
                    )
                    context.stroke(
                        path, with: .color(span.mode.tint.opacity(0.85)),
                        style: StrokeStyle(lineWidth: width, lineCap: .butt)
                    )
                }

                // The sun, and the sleeper's own edges over it. Short ticks
                // across the band rather than labels: four numbers around a
                // ring at this size are unreadable, and the caller has them.
                for mark in marks {
                    let p = angle(day.progress(of: mark))
                    var tick = Path()
                    tick.move(to: point(center, radius - width / 2, p))
                    tick.addLine(to: point(center, radius + width / 2, p))
                    context.stroke(
                        tick, with: .color(.white.opacity(day.isAnchored ? 0.8 : 0.55)),
                        style: StrokeStyle(lineWidth: max(1, width / 13), lineCap: .round)
                    )
                }

                // Now: a line across the band and a dot outside it, so the
                // marker reads against every tint the ring can be.
                let p = angle(day.progress(of: now))
                let overhang = width / 6.5
                var needle = Path()
                needle.move(to: point(center, radius - width / 2 - overhang, p))
                needle.addLine(to: point(center, radius + width / 2 + overhang, p))
                context.stroke(
                    needle, with: .color(.white),
                    style: StrokeStyle(lineWidth: max(1.5, width / 8.7), lineCap: .round)
                )
                let dot = point(center, radius + width / 2 + width / 2.9, p)
                let size = max(3, width / 3.25)
                context.fill(
                    Path(ellipseIn: CGRect(x: dot.x - size / 2, y: dot.y - size / 2, width: size, height: size)),
                    with: .color(.white)
                )
            }
            .accessibilityHidden(true)

            label()
                .padding(.horizontal, 12)
                .accessibilityHidden(true)
        }
    }

    /// The habitual edges replace the sun where Health has them, exactly as
    /// `Suggestion` replaces them, so the ring never shows two nights.
    private var marks: [Date] {
        if let bedtime = day.bedtime, let wake = day.wake { return [bedtime, wake] }
        return [day.sunrise, day.sunset]
    }

    /// Midnight at the top, clockwise. SwiftUI's zero angle is at three
    /// o'clock and grows clockwise in the view's flipped space, so the whole
    /// ring is one quarter turn back from that.
    private func angle(_ progress: Double) -> Angle { .degrees(progress * 360 - 90) }

    private func point(_ center: CGPoint, _ radius: CGFloat, _ angle: Angle) -> CGPoint {
        CGPoint(x: center.x + radius * cos(angle.radians), y: center.y + radius * sin(angle.radians))
    }
}

extension DayRing where Label == EmptyView {
    init(day: CircadianDay, now: Date, width: CGFloat = 26) {
        self.init(day: day, now: now, width: width) { EmptyView() }
    }
}

extension CircadianDay.Span {
    /// The stretch as a clock range, for a ring's centre or a list row.
    var range: String {
        "\(interval.start.formatted(date: .omitted, time: .shortened))–\(interval.end.formatted(date: .omitted, time: .shortened))"
    }
}
