import Carbon.HIToolbox

/// A fixed system-wide play/pause shortcut, ⌃⌥E. Carbon hot keys work inside
/// the sandbox and need no accessibility permission, unlike event taps.
@MainActor
enum HotKey {
    static let key = "globalShortcut"
    static let title = String(localized: "Global Shortcut ⌃⌥E")

    private static var hotKey: EventHotKeyRef?
    private static var handler: EventHandlerRef?
    private static var action: (() -> Void)?

    static func enable(_ action: @escaping () -> Void) {
        Self.action = action
        guard hotKey == nil else { return }
        if handler == nil {
            var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                // Carbon delivers application events on the main thread.
                MainActor.assumeIsolated { HotKey.action?() }
                return noErr
            }, 1, &pressed, nil, &handler)
        }
        let id = EventHotKeyID(signature: 0x454E_5452, id: 1) // "ENTR"
        RegisterEventHotKey(
            UInt32(kVK_ANSI_E), UInt32(controlKey | optionKey), id,
            GetApplicationEventTarget(), 0, &hotKey
        )
    }

    static func disable() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }
}
