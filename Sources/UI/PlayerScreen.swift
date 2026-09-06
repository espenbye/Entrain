import SwiftUI

/// The player on iPhone, iPad and in the Mac window. One screen: what is
/// playing, a big transport, the modes as chips, then the settings in a glass
/// card. The backdrop takes the mode's tint so switching modes changes the
/// room, not just a label.
struct PlayerScreen: View {
    static let windowID = "player"
    @Bindable var session: Session

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
        .animation(.smooth(duration: 0.6), value: session.mode)
        #if os(macOS)
        .frame(width: 380, height: 760)
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
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(.white)
                    .symbolEffect(.breathe, options: .repeating, isActive: session.isPlaying)
            }
            .frame(height: 170)

            VStack(spacing: 6) {
                Text(session.mode.title)
                    .font(.largeTitle.weight(.semibold))
                Text(session.layers.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let remaining = session.remaining {
                Text(remaining.countdown)
                    .font(.system(size: 34, weight: .light, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
            }

            Button {
                Task { await session.toggle() }
            } label: {
                Image(systemName: session.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 84, height: 84)
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
        let sleep = session.mode.isSleep
        return VStack(spacing: 0) {
            Row("Sound") {
                LayerToggles(layers: session.layers, setLayer: session.setLayer)
                    .toggleStyle(.button)
                    .buttonStyle(.glass)
                    .tint(session.mode.tint)
                    .font(.footnote.weight(.medium))
            }
            .disabled(sleep)
            Divider()
            Row("Intensity") {
                Picker("Intensity", selection: $session.intensity) {
                    ForEach(Intensity.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 220)
            }
            .disabled(sleep)
            Divider()
            Row("Timer") {
                Picker("Timer", selection: $session.length) {
                    ForEach(SessionLength.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(.primary)
            }
            Divider()
            Row("Binaural Beats") {
                Toggle("Binaural Beats", isOn: $session.binaural).labelsHidden()
            }
            Divider()
            HStack(spacing: 12) {
                Image(systemName: "speaker.fill")
                Slider(value: $session.volume, in: 0...1)
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
                        .foregroundStyle(mode == selection ? .white : .primary)
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

extension Mode {
    /// One colour per mode, cool for the calm end and warm for the alert end.
    var tint: Color {
        switch self {
        case .focus: Color(red: 0.35, green: 0.62, blue: 1.0)
        case .gamma: Color(red: 1.0, green: 0.72, blue: 0.30)
        case .relax: Color(red: 0.45, green: 0.85, blue: 0.62)
        case .meditate: Color(red: 0.72, green: 0.55, blue: 1.0)
        case .sleep: Color(red: 0.45, green: 0.50, blue: 0.95)
        case .deepSleep: Color(red: 0.30, green: 0.32, blue: 0.75)
        case .windDown: Color(red: 0.95, green: 0.55, blue: 0.50)
        case .wake: Color(red: 1.0, green: 0.85, blue: 0.45)
        }
    }
}
