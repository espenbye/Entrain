import SwiftUI

/// The menu bar menu. Every child is a real menu item, so the look is macOS's own.
struct PlayerMenu: View {
    @Bindable var session: Session
    @Environment(\.openWindow) private var openWindow
    @AppStorage(DockIcon.key) private var showInDock = false
    @AppStorage(HotKey.key) private var globalShortcut = false
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        PlayerControls(session: session, inMenu: true)
        Divider()
        Button("Open Entrain…") {
            openWindow(id: PlayerWindow.id)
            NSApplication.shared.activate()
        }
        .keyboardShortcut("o")
        Toggle(HotKey.title, isOn: Binding(
            get: { globalShortcut },
            set: { on in
                globalShortcut = on
                on ? HotKey.enable { Task { await session.toggle() } } : HotKey.disable()
            }
        ))
        Toggle("Control Center & Media Keys", isOn: $session.nowPlaying)
        Toggle("Show in Dock", isOn: Binding(
            get: { showInDock },
            set: { showInDock = $0; DockIcon.apply($0) }
        ))
        Toggle("Launch at Login", isOn: Binding(
            get: { launchAtLogin },
            set: { LaunchAtLogin.set($0); launchAtLogin = LaunchAtLogin.isEnabled }
        ))
        Divider()
        Button("Quit Entrain") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// What the menu bar shows: the waveform, plus the mode and countdown while playing.
/// Laid out by hand: a `Label` in a status item renders icon-only. The symbol
/// does not animate: a status item redrawing all day is a battery cost for
/// an app meant to sit in the background.
struct MenuBarLabel: View {
    let isPlaying: Bool
    let mode: Mode
    let remaining: Int?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "waveform")
            if isPlaying {
                if let remaining {
                    Text(verbatim: "\(mode.title) \(remaining.countdown)")
                        .monospacedDigit()
                } else {
                    Text(mode.title)
                }
            }
        }
    }
}
