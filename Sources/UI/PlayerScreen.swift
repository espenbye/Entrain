import SwiftUI

/// The player on iPhone, iPad and in the Mac window. One screen: what is
/// playing, a big transport, the modes as chips, then the settings in a glass
/// card. The backdrop takes the mode's tint so switching modes changes the
/// room, not just a label.
struct PlayerScreen: View {
    static let windowID = "player"
    @Bindable var session: Session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize = 64.0
    @ScaledMetric(relativeTo: .title) private var countdownSize = 34.0
    @ScaledMetric(relativeTo: .title) private var transportSize = 30.0
    @Bindable private var daylight = Daylight.shared
    #if canImport(AlarmKit)
    @Bindable private var alarm = WakeAlarm.shared
    #endif

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                hero
                ModeChips(selection: $session.mode)
                settings
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Backdrop(mode: session.mode))
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : .smooth(duration: 0.6), value: session.mode)
        #if os(macOS)
        .frame(minWidth: 380, idealWidth: 380, minHeight: 520, idealHeight: 760)
        #endif
    }

    private var hero: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(session.mode.tint.opacity(0.35))
                    .blur(radius: 40)
                    .frame(width: 180, height: 180)
                Image(systemName: session.mode.symbol)
                    .font(.system(size: heroSize, weight: .light))
                    .foregroundStyle(.white)
                    .symbolEffect(.breathe, options: .repeating, isActive: session.isPlaying && !reduceMotion)
            }
            .frame(height: 170)

            VStack(spacing: 6) {
                Text(session.mode.title)
                    .font(.largeTitle.weight(.semibold))
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
                    .frame(width: transportSize * 2.8, height: transportSize * 2.8)
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
        .padding(.top, 24)
    }

    private var settings: some View {
        VStack(spacing: 0) {
            if !session.mode.isSleep {
                Row("Sound") {
                    LayerToggles(layers: session.layers, setLayer: session.setLayer)
                        .toggleStyle(.button)
                        .buttonStyle(.glass)
                        .tint(session.mode.tint)
                        .font(.footnote.weight(.medium))
                }
                Divider()
                Row("Intensity") {
                    Picker("Intensity", selection: $session.intensity) {
                        ForEach(Intensity.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 220)
                }
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
            Divider()
            Row("Binaural Beats") {
                Toggle("Binaural Beats", isOn: $session.binaural).labelsHidden()
            }
            if session.binaural && !session.headphones {
                Text("Binaural beats need headphones.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 12)
            }
            Divider()
            Row("Daylight") {
                Toggle("Daylight", isOn: $daylight.followsLocation).labelsHidden()
            }
            Group {
                if daylight.followsLocation && daylight.denied {
                    Text("Allow location for Entrain in Settings to follow local sunrise and sunset.")
                } else if daylight.followsLocation {
                    Text("Brighter in the morning, warmer after sunset, from your approximate location.")
                } else {
                    Text("Brighter in the morning, warmer after sunset, assuming a 7 to 19 day.")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 12)
            if session.headTrackingAvailable {
                Divider()
                Row("Head Tracking") {
                    Toggle("Head Tracking", isOn: $session.headTracking).labelsHidden()
                }
                if session.headTracking {
                    Text("Keeps the room in place when you turn your head, with AirPods or Beats. Stays off in Sleep and Wind Down.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 12)
                }
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
            .padding(.vertical, 12)
            Divider()
            #if os(macOS)
            Row("Control Center & Media Keys") {
                Toggle("Control Center & Media Keys", isOn: $session.nowPlaying).labelsHidden()
            }
            #else
            Row("Lock Screen Controls") {
                Toggle("Lock Screen Controls", isOn: $session.nowPlaying).labelsHidden()
            }
            Text("Off, Entrain blends under music and podcasts. On, it takes the playback controls and pauses other audio.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)
            #endif
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

/// Six modes as one scrolling row of glass chips. The current one is filled
/// with its tint; the rest stay translucent.
private struct ModeChips: View {
    @Binding var selection: Mode

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    ForEach(Mode.allCases) { mode in
                        Button {
                            selection = mode
                        } label: {
                            Label(mode.title, systemImage: mode.symbol)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(mode == selection ? .regular.tint(mode.tint).interactive() : .regular.interactive(), in: .capsule)
                        .foregroundStyle(mode == selection ? mode.onTint : .primary)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .padding(.horizontal, -20)
    }
}

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
