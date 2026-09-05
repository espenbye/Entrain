import SwiftUI

struct PlayerView: View {
    @Bindable var session: Session

    var body: some View {
        VStack(spacing: 16) {
            NowPlayingHeader(
                mode: session.mode,
                subtitle: "\(session.soundscape.title) · \(session.intensity.title)",
                remaining: session.remaining,
                isPlaying: session.isPlaying
            )
            ModeGrid(selection: $session.mode)
            SettingsCard(
                soundscape: $session.soundscape,
                intensity: $session.intensity,
                length: $session.length,
                binaural: $session.binaural
            )
            TransportButton(isPlaying: session.isPlaying, tint: session.mode.tint) {
                session.toggle()
            }
            Footer()
        }
        .padding(16)
        .frame(width: 320)
    }
}

struct NowPlayingHeader: View {
    let mode: Mode
    let subtitle: String
    let remaining: Int?
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: mode.symbol)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(mode.tint.gradient, in: .circle)
                .symbolEffect(.pulse, isActive: isPlaying)

            VStack(alignment: .leading, spacing: 2) {
                Text(mode.title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }

            Spacer()

            if let remaining {
                Text(Duration.seconds(remaining), format: .time(pattern: .minuteSecond))
                    .font(.system(.title3, design: .rounded, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(isPlaying ? .primary : .secondary)
                    .contentTransition(.numericText(countsDown: true))
            }
        }
    }
}

struct ModeGrid: View {
    @Binding var selection: Mode

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Mode.allCases) { mode in
                ModeTile(mode: mode, isSelected: mode == selection) {
                    withAnimation(.snappy) { selection = mode }
                }
            }
        }
    }
}

struct ModeTile: View {
    let mode: Mode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: mode.symbol).font(.title3)
                Text(mode.title).font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background(
                isSelected ? AnyShapeStyle(mode.tint.gradient) : AnyShapeStyle(.quaternary.opacity(0.5)),
                in: .rect(cornerRadius: 10)
            )
        }
        .buttonStyle(.plain)
        .help(Text("\(mode.rate, format: .number) Hz"))
    }
}

struct SettingsCard: View {
    @Binding var soundscape: Soundscape
    @Binding var intensity: Intensity
    @Binding var length: SessionLength
    @Binding var binaural: Bool

    var body: some View {
        VStack(spacing: 0) {
            SettingRow("Sound") {
                Picker("Sound", selection: $soundscape) {
                    ForEach(Soundscape.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Divider()
            SettingRow("Intensity") {
                Picker("Intensity", selection: $intensity) {
                    ForEach(Intensity.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Divider()
            SettingRow("Timer") {
                Picker("Timer", selection: $length) {
                    ForEach(SessionLength.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .fixedSize()
            }
            Divider()
            SettingRow("Binaural", detail: "Needs headphones") {
                Toggle("Binaural", isOn: $binaural)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
        .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 12))
    }
}

struct SettingRow<Control: View>: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey?
    let control: Control

    init(_ title: LocalizedStringKey, detail: LocalizedStringKey? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            control.labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct TransportButton: View {
    let isPlaying: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .controlSize(.large)
        .keyboardShortcut(.space, modifiers: [])
    }
}

struct Footer: View {
    var body: some View {
        HStack {
            Text("Entrain").font(.caption).foregroundStyle(.tertiary)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .keyboardShortcut("q")
        }
    }
}
