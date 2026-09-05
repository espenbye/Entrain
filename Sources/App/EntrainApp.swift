import ServiceManagement
import SwiftUI

@main
struct EntrainApp: App {
    private let session = Session.shared
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    init() {
        DockIcon.apply(UserDefaults.standard.bool(forKey: DockIcon.key))
    }

    var body: some Scene {
        MenuBarExtra {
            PlayerMenu(session: session)
        } label: {
            MenuBarLabel(isPlaying: session.isPlaying, mode: session.mode, remaining: session.remaining)
                .reopensPlayerWindow(delegate)
        }
        .menuBarExtraStyle(.menu)

        Window("Entrain", id: PlayerWindow.id) {
            PlayerWindow(session: session)
        }
        .defaultSize(width: 320, height: 480)
        .windowResizability(.contentSize)
    }
}

/// Whether the app appears in the Dock and app switcher. Launch is always
/// menubar-only (LSUIElement); this raises the policy at runtime.
@MainActor
enum DockIcon {
    static let key = "showInDock"

    static func apply(_ show: Bool) {
        NSApplication.shared.setActivationPolicy(show ? .regular : .accessory)
    }
}

/// Registers the app as a login item. The system owns the state, so it is
/// read back rather than stored.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) {
        let service = SMAppService.mainApp
        if enabled {
            try? service.register()
        } else {
            try? service.unregister()
        }
    }
}

/// Clicking the Dock icon with no window open reopens the player.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var openPlayer: (() -> Void)?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { openPlayer?() }
        return true
    }
}

private struct ReopenPlayerWindow: ViewModifier {
    let delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onAppear { delegate.openPlayer = { openWindow(id: PlayerWindow.id) } }
    }
}

extension View {
    /// The menu bar label is always alive, so it is where the reopen hook gets its openWindow action.
    func reopensPlayerWindow(_ delegate: AppDelegate) -> some View {
        modifier(ReopenPlayerWindow(delegate: delegate))
    }
}
