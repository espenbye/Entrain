import SwiftUI

/// The player on iPhone, iPad and in the Mac window. What is playing and a
/// transport, the mode the time of day suggests, every mode on three
/// shelves, then what changes per session in a glass card. Everything set
/// once lives behind the gear. The backdrop takes the mode's tint so
/// switching modes changes the room, not just a label. The Mac window is
/// wide enough for two columns, so nothing scrolls there, and the window
/// is the size of its content.
struct PlayerScreen: View {
    static let windowID = "player"
    @Bindable var session: Session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if !os(macOS)
    @State private var showsSettings = false
    #endif

    var body: some View {
        layout
            .background(Backdrop(mode: session.mode))
            .preferredColorScheme(.dark)
            .animation(reduceMotion ? nil : .smooth(duration: 0.6), value: session.mode)
            .overlay(alignment: .topTrailing) {
                settingsButton
                    .padding(16)
            }
    }

    @ViewBuilder
    private var layout: some View {
        #if os(macOS)
        // Both columns hang from the same top edge, below the gear.
        HStack(alignment: .top, spacing: 0) {
            // Meditate's breathing rows and circle can outgrow the window
            // height; the column scrolls only then.
            ScrollView {
                VStack(spacing: 24) {
                    Hero(session: session)
                    SessionCard(session: session)
                }
                .frame(width: 340)
                .padding(.horizontal, 24)
                .padding(.top, 64)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            Divider()
            ScrollView {
                VStack(spacing: 16) {
                    SuggestionCard(session: session)
                    ModeGrid(session: session)
                }
                .padding(.horizontal, 24)
                .padding(.top, 64)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(width: 760, height: 640)
        #else
        ScrollView {
            VStack(spacing: 20) {
                Hero(session: session)
                SuggestionCard(session: session)
                ModeGrid(session: session)
                SessionCard(session: session)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .scrollBounceBehavior(.basedOnSize)
        .sheet(isPresented: $showsSettings) {
            SettingsScreen(session: session)
        }
        #endif
    }

    private var settingsButton: some View {
        Group {
            #if os(macOS)
            SettingsLink { Image(systemName: "gearshape") }
            #else
            Button("Settings", systemImage: "gearshape") { showsSettings = true }
                .labelStyle(.iconOnly)
            #endif
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .accessibilityLabel("Settings")
    }
}

/// The current mode, its sound, the countdown and the transport.
private struct Hero: View {
    @Bindable var session: Session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize = 48.0
    @ScaledMetric(relativeTo: .title) private var countdownSize = 26.0
    @ScaledMetric(relativeTo: .title) private var transportSize = 24.0

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(session.mode.tint.opacity(0.35))
                    .blur(radius: 30)
                    .frame(width: 120, height: 120)
                if session.breath.isActive {
                    // The exercise takes the symbol's place while it runs.
                    BreathingCircle(guide: session.breath, tint: session.mode.tint, size: 140)
                        .transition(.opacity)
                } else {
                    Image(systemName: session.mode.symbol)
                        .font(.system(size: heroSize, weight: .light))
                        .foregroundStyle(.white)
                        .symbolEffect(.breathe, options: .repeating, isActive: session.isPlaying && !reduceMotion)
                        .transition(.opacity)
                }
            }
            .frame(minHeight: 120)
            .animation(.default, value: session.breath.isActive)

            VStack(spacing: 4) {
                Text(session.mode.title)
                    .font(.title.weight(.semibold))
                Text(session.layers.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let countdown = session.countdown {
                countdown
                    .font(.system(size: countdownSize, weight: .light, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
            }

            Button {
                Task { await session.toggle() }
            } label: {
                Image(systemName: session.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: transportSize, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: transportSize * 2.7, height: transportSize * 2.7)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .tint(session.mode.tint)
            .accessibilityLabel(session.isPlaying ? "Pause" : "Play")

            if let error = session.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The mode the time of day suggests, with the timer already set: one tap
/// starts it. Rechecked each minute, and gone while something plays.
private struct SuggestionCard: View {
    @Bindable var session: Session
    @Bindable private var daylight = Daylight.shared
    private let health = HealthSignals.shared

    var body: some View {
        if !session.isPlaying {
            TimelineView(.everyMinute) { context in
                let suggestion = Suggestion.at(
                    context.date, day: daylight.day(on:), sleep: health.sleep, vitals: health.vitals
                )
                HStack(spacing: 12) {
                    Image(systemName: suggestion.mode.symbol)
                        .font(.body.weight(.medium))
                        .foregroundStyle(suggestion.mode.tint)
                        .frame(width: 36, height: 36)
                        .background(suggestion.mode.tint.opacity(0.25), in: .circle)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.reason)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text("\(suggestion.mode.title), \(session.length.title)")
                            .font(.subheadline.weight(.semibold))
                    }
                    Spacer(minLength: 8)
                    Button("Start") {
                        session.mode = suggestion.mode
                        Task { await session.play() }
                    }
                    .buttonStyle(.glassProminent)
                    .tint(suggestion.mode.tint)
                    .foregroundStyle(suggestion.mode.onTint)
                    .font(.subheadline.weight(.semibold))
                }
                .padding(12)
                .glassEffect(.regular, in: .rect(cornerRadius: 18))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Every mode on three shelves, two to a row: all of them visible, the
/// current one filled with its tint, each with a line on what it is for.
/// A tap picks the mode, and starts it when nothing is playing.
private struct ModeGrid: View {
    @Bindable var session: Session

    private var selection: Mode { session.mode }

    /// Makes `mode` current and, if nothing is playing, starts it. While a
    /// session plays, the tap only switches the mode so it does not restart.
    private func select(_ mode: Mode) {
        session.mode = mode
        if !session.isPlaying {
            Task { await session.play() }
        }
    }

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Purpose.allCases) { purpose in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(purpose.title)
                            .font(.caption.weight(.semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(purpose.modes) { mode in
                                ModeTile(mode: mode, selected: mode == selection) { select(mode) }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct ModeTile: View {
    let mode: Mode
    let selected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: mode.symbol)
                    .font(.body.weight(.medium))
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 1) {
                    Text(mode.title)
                        .font(.subheadline.weight(.medium))
                    Text(mode.blurb)
                        .font(.caption)
                        .opacity(0.7)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .glassEffect(selected ? .regular.tint(mode.tint).interactive() : .regular.interactive(), in: .rect(cornerRadius: 18))
        .foregroundStyle(selected ? mode.onTint : .primary)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// One sound layer as a chip. On is a filled, tinted capsule; off is a plain
/// glass outline with dimmed text, so the two states read apart at a glance.
private struct LayerChip: View {
    let soundscape: Soundscape
    let on: Bool
    let tint: Color
    let onTint: Color
    let setLayer: (Soundscape, Bool) -> Void

    var body: some View {
        Button { setLayer(soundscape, !on) } label: {
            Text(soundscape.title)
                .font(.footnote.weight(on ? .semibold : .medium))
                .frame(minWidth: 44, minHeight: 24)
                .padding(.horizontal, 10)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(on ? .regular.tint(tint).interactive() : .regular.interactive(), in: .capsule)
        .foregroundStyle(on ? onTint : .secondary)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// What changes per session: sound, intensity, timer, the Wake alarm, volume.
private struct SessionCard: View {
    @Bindable var session: Session
    #if canImport(AlarmKit)
    @Bindable private var alarm = WakeAlarm.shared
    #endif

    var body: some View {
        VStack(spacing: 0) {
            if !session.mode.isSleep {
                Row("Sound") {
                    ForEach(Soundscape.allCases) { soundscape in
                        LayerChip(
                            soundscape: soundscape,
                            on: session.layers.contains(soundscape),
                            tint: session.mode.tint,
                            onTint: session.mode.onTint,
                            setLayer: session.setLayer
                        )
                    }
                }
                Divider()
                Row("Intensity") {
                    Picker("Intensity", selection: $session.intensity) {
                        ForEach(Intensity.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 200)
                }
                Divider()
            }
            if session.mode == .meditate {
                Row("Breathing") {
                    Picker("Breathing", selection: $session.breathing) {
                        ForEach(BreathingPattern.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .tint(.primary)
                }
                if session.breathing != .none {
                    Row("Breathing Length") {
                        Picker("Breathing Length", selection: $session.breathingLength) {
                            ForEach(BreathingLength.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .tint(.primary)
                    }
                }
                Text(session.breathing.blurb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 12)
                Divider()
            }
            Row("Timer") {
                Picker("Timer", selection: $session.length) {
                    ForEach(SessionLength.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(.primary)
            }
            #if canImport(AlarmKit)
            if session.mode == .wake {
                Divider()
                Row("Alarm") {
                    DatePicker("Alarm", selection: $alarm.time, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Toggle("Alarm", isOn: Binding(
                        get: { alarm.isOn },
                        set: { alarm.set(on: $0) }
                    ))
                    .labelsHidden()
                }
                WeekdayPicker(selection: $alarm.days)
                    .padding(.bottom, 12)
                Group {
                    if alarm.denied {
                        Text("Allow alarms for Entrain in Settings to use the Wake alarm.")
                    } else if let error = alarm.error {
                        Text(verbatim: error)
                    } else {
                        Text(verbatim: alarm.summary + " ") + Text("Rings even on silent. Start Wake on the alarm plays the ramp for 30 minutes.")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)
            }
            #endif
            if session.binaural && !session.headphones {
                Divider()
                Text("Binaural beats need headphones.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            }
            Divider()
            HStack(spacing: 12) {
                Image(systemName: "speaker.fill")
                Slider(value: $session.volume, in: 0...1)
                    .accessibilityLabel("Volume")
                Image(systemName: "speaker.wave.3.fill")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.vertical, 14)
        }
        .padding(.horizontal, 16)
        .toggleStyle(.switch)
        .tint(session.mode.tint)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}

/// A settings row: label left, control right, a comfortable height.
private struct Row<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            HStack(spacing: 6) { content }
        }
        .padding(.vertical, 12)
    }
}

#if canImport(AlarmKit)
/// Seven circles, Monday first where the locale says so. None selected
/// means the alarm rings once.
private struct WeekdayPicker: View {
    @Binding var selection: Set<Locale.Weekday>

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Locale.Weekday.ordered, id: \.self) { day in
                let on = selection.contains(day)
                Button {
                    if on { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(day.letter)
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .glassEffect(on ? .regular.tint(Mode.wake.tint).interactive() : .regular.interactive(), in: .circle)
                .foregroundStyle(on ? Mode.wake.onTint : .primary)
                .accessibilityLabel(day.shortName)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}
#endif

/// Night gradient from the icon, warmed by the mode's tint at the top.
private struct Backdrop: View {
    let mode: Mode

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.07, green: 0.06, blue: 0.20), Color(red: 0.03, green: 0.13, blue: 0.18)],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [mode.tint.opacity(0.45), .clear],
                center: .init(x: 0.5, y: 0.12), startRadius: 0, endRadius: 420
            )
        }
        .ignoresSafeArea()
    }
}
