import SwiftUI

/// How the Mac app sits in the system: the shortcut, the Dock, login.
struct SystemSection: View {
    @Bindable var session: Session
    @AppStorage(DockIcon.key) private var showInDock = false
    @AppStorage(HotKey.key) private var globalShortcut = false
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Section {
            Toggle(HotKey.title, isOn: Binding(
                get: { globalShortcut },
                set: { on in
                    globalShortcut = on
                    on ? HotKey.enable { Task { await session.toggle() } } : HotKey.disable()
                }
            ))
            Toggle("Show in Dock", isOn: Binding(
                get: { showInDock },
                set: { showInDock = $0; DockIcon.apply($0) }
            ))
            Toggle("Launch at Login", isOn: Binding(
                get: { launchAtLogin },
                set: { LaunchAtLogin.set($0); launchAtLogin = LaunchAtLogin.isEnabled }
            ))
        }
    }
}
