import SwiftUI

struct TransportSection: View {
    let isPlaying: Bool
    let title: String
    let countdown: Text?
    let error: String?
    let toggle: () async -> Void

    var body: some View {
        Section {
            Button(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill") {
                Task { await toggle() }
            }
            .spaceBarToggles()
        } header: {
            if let error {
                Text(verbatim: "\(title) · \(error)")
            } else if let countdown {
                Text("\(title) · \(countdown) left")
            } else {
                Text(title)
            }
        }
    }
}

extension Session {
    /// The countdown as text. While playing it is drawn from the deadline,
    /// so it ticks without a re-render; paused it is the frozen remainder.
    var countdown: Text? {
        if let deadline {
            return Text(timerInterval: Date.now...max(Date.now, deadline), countsDown: true)
        }
        // Not observed, but every change to it while paused comes with a
        // change to `length` or `isPlaying`, which every caller reads.
        return remaining.map { Text($0.countdown) }
    }
}

struct ModeSection: View {
    @Binding var selection: Mode

    var body: some View {
        Section {
            Picker("Mode", selection: $selection) {
                ForEach(Mode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.inline)
        }
    }
}

/// One check item per soundscape; any combination plays together.
struct LayerToggles: View {
    let layers: Set<Soundscape>
    let setLayer: (Soundscape, Bool) -> Void

    var body: some View {
        ForEach(Soundscape.allCases) { soundscape in
            Toggle(soundscape.title, isOn: Binding(
                get: { layers.contains(soundscape) },
                set: { setLayer(soundscape, $0) }
            ))
        }
    }
}

/// The exercise and its length, for Meditate. Shown only there: the other
/// modes have no breath to follow.
struct BreathingPickers: View {
    @Bindable var session: Session

    var body: some View {
        Picker("Breathing", selection: $session.breathing) {
            ForEach(BreathingPattern.allCases) { Text($0.title).tag($0) }
        }
        if session.breathing != .none {
            Picker("Breathing Length", selection: $session.breathingLength) {
                ForEach(BreathingLength.allCases) { Text($0.title).tag($0) }
            }
        }
    }
}

/// The breath as a circle: it swells over the inhale, holds, and shrinks
/// over the exhale, at the pace of the pattern, with the phase named under
/// it and the seconds left in the phase. With Reduce Motion the circle
/// keeps its size and the label alone carries the pace.
struct BreathingCircle: View {
    let guide: BreathGuide
    let tint: Color
    var size: CGFloat = 120
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Where the circle is heading: full after breathing in, small after
    /// breathing out. A hold stays where the last phase left it, which is
    /// why it looks at the step before.
    private var scale: CGFloat {
        guard let position = guide.position else { return 0.55 }
        switch position.phase {
        case .inhale: return 1
        case .exhale: return 0.55
        case .hold:
            let steps = guide.pattern.steps
            let before = steps[(position.index + steps.count - 1) % steps.count]
            return before.phase == .inhale ? 1 : 0.55
        }
    }

    var body: some View {
        let position = guide.position
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .strokeBorder(tint.opacity(0.35), lineWidth: 1.5)
                Circle()
                    .fill(tint.opacity(0.55))
                    .scaleEffect(reduceMotion ? 0.8 : scale)
                    .animation(.easeInOut(duration: position?.step.seconds ?? 0.6), value: scale)
                if let interval = guide.stepInterval {
                    TimelineView(.periodic(from: interval.start, by: 1)) { context in
                        let left = max(0, Int((interval.end.timeIntervalSince(context.date)).rounded(.up)))
                        Text(verbatim: "\(left)")
                            .font(.system(size: size * 0.3, weight: .light, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText(countsDown: true))
                            .animation(.default, value: left)
                    }
                }
            }
            .frame(width: size, height: size)
            if let position {
                Text(position.phase.title)
                    .font(.subheadline.weight(.medium))
                    .contentTransition(.opacity)
                    .animation(.default, value: position.phase)
                if let cycles = guide.cycles {
                    Text("Breath \(position.cycle + 1) of \(cycles)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    /// Space plays and pauses wherever there is a keyboard.
    func spaceBarToggles() -> some View {
        #if os(watchOS)
        self
        #else
        keyboardShortcut(.space, modifiers: [])
        #endif
    }
}
