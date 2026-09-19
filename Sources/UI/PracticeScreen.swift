import SwiftUI

/// The practice: a breath to follow, the bed it runs over, and what Health
/// has of the sittings already done.
///
/// The player answers "what should be playing" for all eleven modes at once,
/// and this screen does not try to answer it a second time. It asks the
/// other question a practice starts from — which breath, and for how long —
/// and picks the bed underneath afterwards, which is the reverse of the
/// player's order and the whole reason the screen is worth its place in the
/// bar. Until now the exercise could only be reached by knowing to select
/// Meditate first, where it appeared as two rows in the session card
/// between Intensity and Timer, and the mindful minutes Entrain has been
/// writing to Health since the beginning were shown nowhere in Entrain.
///
/// Deliberately not a course and not a streak: see `PracticeHistory` for
/// why there is a record here and no score.
struct PracticeScreen: View {
    static let symbol = "figure.mind.and.body"

    @Bindable var session: Session
    /// The bed the next sitting will run over, once it has been picked by
    /// hand. Nil falls back to whatever the session is on when that is a
    /// rest mode, so arriving here from a Meditate session does not silently
    /// offer to start a different one.
    @State private var bed: Mode?
    @State private var history: PracticeHistory = .empty
    #if os(macOS)
    @Environment(\.dismiss) private var dismiss
    #endif

    private var bedMode: Mode { bed ?? (session.mode.guidesBreath ? session.mode : .meditate) }

    /// True while a practice is actually under way, which is a rest mode
    /// playing. The exercise takes the screen then and the pickers give way
    /// to it, the way the breathing circle takes the player's hero.
    private var sitting: Bool { session.isPlaying && session.mode.guidesBreath }

    /// What the backdrop and the tints follow: the mode being practised
    /// while one is, the mode about to be otherwise.
    private var tinting: Mode { sitting ? session.mode : bedMode }

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
        NavigationStack {
            content
                .navigationTitle("Practice")
                .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
        #endif
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 20) {
                if sitting {
                    Sitting(session: session)
                    RunningCard(session: session)
                } else {
                    Patterns(session: session, tint: tinting)
                    Beds(bed: bedMode, tint: tinting) { bed = $0 }
                    StartCard(session: session, bed: bedMode)
                }
                #if !os(macOS)
                PracticeCard(history: history, tint: tinting)
                #endif
            }
            .padding(.horizontal, 20)
            .padding(.top, topPadding)
            .padding(.bottom, 32)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Backdrop(mode: tinting))
        .animation(.default, value: sitting)
        .task(id: session.isPlaying) {
            history = await session.practice()
            // The sitting that just ended is still on its way into Health:
            // `MindfulMinutes.log` saves in a task of its own, and the store
            // takes a moment to accept it, so the read above is a sitting
            // behind. One more a couple of seconds later catches it rather
            // than leaving the screen stale until it is next opened. The
            // same second read happens once on first appearance, which costs
            // one query of a store that was just read and is cheaper than
            // knowing which of the two cases this is.
            guard !session.isPlaying else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            history = await session.practice()
        }
    }

    // The Mac sheet has no title bar to hang Done off, so it floats in the
    // corner and the content starts below it rather than under it. Same
    // trade as `DayScreen.ringTop`.
    #if os(macOS)
    private var topPadding: CGFloat { 56 }
    #else
    private var topPadding: CGFloat { 0 }
    #endif
}

/// The exercise, once it is running: the circle with its phase and count,
/// what is playing under it, and the one control that matters here.
private struct Sitting: View {
    @Bindable var session: Session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize = 48.0
    @ScaledMetric(relativeTo: .title) private var transportSize = 24.0

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(session.mode.tint.opacity(0.35))
                    .blur(radius: 40)
                    .frame(width: 180, height: 180)
                if session.breath.isActive {
                    // Twice the player's circle. The player has a mode grid
                    // and a session card to fit around it; this screen has
                    // one job while the exercise runs.
                    BreathingCircle(guide: session.breath, tint: session.mode.tint, size: 220)
                        .transition(.opacity)
                } else {
                    // No pattern, or the exercise has run its length and the
                    // soundscape carries on, which is what it is meant to do.
                    Image(systemName: session.mode.symbol)
                        .font(.system(size: symbolSize, weight: .light))
                        .foregroundStyle(.white)
                        .symbolEffect(.breathe, options: .repeating, isActive: !reduceMotion)
                        .transition(.opacity)
                }
            }
            .frame(minHeight: 220)
            .animation(.default, value: session.breath.isActive)

            VStack(spacing: 4) {
                Text(session.mode.blurb)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(verbatim: "\(session.mode.title) · \(session.layers.title)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let countdown = session.countdown {
                countdown
                    .font(.title3.weight(.light).monospacedDigit())
                    .contentTransition(.numericText())
            }

            Button {
                session.pause()
            } label: {
                Image(systemName: "pause.fill")
                    .font(.system(size: transportSize, weight: .semibold))
                    .frame(width: transportSize * 2.7, height: transportSize * 2.7)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .tint(session.mode.tint)
            .accessibilityLabel("Pause")
        }
        .padding(.top, 8)
    }
}

/// The two things still worth changing mid-sitting. Changing either starts
/// the exercise over from its first breath, which is what it has always
/// done and what somebody reaching for it here is asking for.
private struct RunningCard: View {
    @Bindable var session: Session

    var body: some View {
        VStack(spacing: 0) {
            PracticeRow("Breathing") {
                Picker("Breathing", selection: $session.breathing) {
                    ForEach(BreathingPattern.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(.primary)
            }
            if session.breathing != .none {
                Divider()
                PracticeRow("Length") {
                    Picker("Length", selection: $session.breathingLength) {
                        ForEach(BreathingLength.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .tint(.primary)
                }
            }
        }
        .padding(.horizontal, 16)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}

/// Every pattern as a tile, Off included: a sitting with no count is a
/// legitimate thing to want, and hiding it behind a menu made it read as a
/// failure to choose rather than a choice.
private struct Patterns: View {
    @Bindable var session: Session
    let tint: Mode

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Breath")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(BreathingPattern.allCases) { pattern in
                        PatternTile(
                            pattern: pattern,
                            selected: session.breathing == pattern,
                            tint: tint
                        ) { session.breathing = pattern }
                    }
                }
            }
        }
    }
}

private struct PatternTile: View {
    let pattern: BreathingPattern
    let selected: Bool
    let tint: Mode
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 4) {
                Text(pattern.title)
                    .font(.subheadline.weight(.medium))
                Text(pattern.blurb)
                    .font(.caption)
                    .opacity(0.7)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .glassEffect(selected ? .regular.tint(tint.tint).interactive() : .regular.interactive(), in: .rect(cornerRadius: 18))
        .foregroundStyle(selected ? tint.onTint : .primary)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The three modes a breath may run over, in the order the rest shelf has
/// them: see `Mode.guidesBreath`. Named a bed because that is what it is —
/// the sound the count sits on, not the point of the sitting.
private struct Beds: View {
    let bed: Mode
    let tint: Mode
    let select: (Mode) -> Void

    private var beds: [Mode] { Mode.allCases.filter(\.guidesBreath) }

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Underneath")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                    ForEach(beds) { mode in
                        BedTile(mode: mode, selected: mode == bed, tint: tint) { select(mode) }
                    }
                }
            }
        }
    }
}

private struct BedTile: View {
    let mode: Mode
    let selected: Bool
    let tint: Mode
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 6) {
                Image(systemName: mode.symbol)
                    .font(.body.weight(.medium))
                Text(mode.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.vertical, 10)
            .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .glassEffect(selected ? .regular.tint(tint.tint).interactive() : .regular.interactive(), in: .rect(cornerRadius: 18))
        .foregroundStyle(selected ? tint.onTint : .primary)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The length, a line on what the bed is for, and the one button. Begin
/// switches the session to the bed and plays it; a session already running
/// something else changes mode rather than starting over, which is what
/// `Session.start` does everywhere else in the app.
private struct StartCard: View {
    @Bindable var session: Session
    let bed: Mode

    var body: some View {
        VStack(spacing: 0) {
            if session.breathing != .none {
                PracticeRow("Length") {
                    Picker("Length", selection: $session.breathingLength) {
                        ForEach(BreathingLength.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .tint(.primary)
                }
                Divider()
            }
            Text(bed.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
            Button {
                Task { await session.start(.mode(bed)) }
            } label: {
                Text("Begin")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.glassProminent)
            .tint(bed.tint)
            .foregroundStyle(bed.onTint)
            .padding(.bottom, 14)
        }
        .padding(.horizontal, 16)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}

/// What Health has. Not a streak and not a target: `PracticeHistory` has
/// the argument for why this counts minutes and stops there.
private struct PracticeCard: View {
    let history: PracticeHistory
    let tint: Mode

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Your Practice")
                .padding(.bottom, 8)
            VStack(spacing: 0) {
                if history.isEmpty {
                    Text("Nothing here yet. A Meditate or Restore session lasting a minute or more is logged to Health as mindful minutes, and shows up here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 14)
                } else {
                    PracticeRow("Today") {
                        Text(history.today.practiceMinutes)
                            .font(.body.monospacedDigit())
                            .foregroundStyle(history.today > 0 ? tint.tint : .secondary)
                    }
                    Divider()
                    PracticeRow("Last 7 Days") {
                        Text(history.lastWeek.practiceMinutes)
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ForEach(history.sessions, id: \.start) { sitting in
                        Divider()
                        PracticeRow(verbatim: Self.when(sitting.start)) {
                            Text(sitting.duration.practiceMinutes)
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    Text("Mindful minutes as Health has them, over the last \(PracticeHistory.window) days. That includes sessions other apps logged: writing to Health is what puts a sitting on the same chart as Mindfulness and Breathe, and reading only Entrain's own back would say less than the write does.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 16)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
        }
    }

    /// Today's sittings are placed by the clock, older ones by the day as
    /// well: "14:20" reads wrong under a row that says Today when it was
    /// last Thursday.
    private static func when(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(date: .abbreviated, time: .shortened)
    }
}

/// The shelf captions, in the player's own words and weight.
private struct SectionLabel: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) { self.title = title }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A card row: label left, value or control right. `PlayerScreen` has the
/// same thing privately; this is a copy rather than a shared type because
/// the two screens are free to drift apart and a shared row would make
/// every change to one a change to both.
private struct PracticeRow<Content: View>: View {
    private let title: Text
    @ViewBuilder let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = Text(title)
        self.content = content()
    }

    init(verbatim title: String, @ViewBuilder content: () -> Content) {
        self.title = Text(verbatim: title)
        self.content = content()
    }

    var body: some View {
        HStack {
            title
            Spacer(minLength: 12)
            HStack(spacing: 6) { content }
        }
        .padding(.vertical, 12)
    }
}
