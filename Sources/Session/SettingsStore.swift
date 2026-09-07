import Foundation

/// The iCloud key-value store behind a seam, so tests can pass a fake and a
/// session without one keeps its settings to itself. Defaults stay the local
/// truth; the store is a mirror that reaches the other devices.
@MainActor
protocol SettingsStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: SettingsStore {}
