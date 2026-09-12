import Foundation
import Observation
import UserNotifications

/// A note when a stretch of the day begins, one switch per phase.
///
/// The day ring already knows when each phase starts; this is the same
/// day, delivered instead of drawn. Nothing is computed here: the
/// requests come straight from the `DayPhases` snapshot the widget reads,
/// so a notification can never arrive at a minute the ring disagrees with.
///
/// Times of day, repeating daily, for the same reason the widget stores
/// times rather than dates: the phones of people who do not open Entrain
/// every morning should still be told. The app rewrites the set whenever
/// the day is republished, so the times drift with the sun and with the
/// nights Health reports, a minute or two at a time.
@MainActor
@Observable
final class PhaseNotifications {
    static let shared = PhaseNotifications(defaults: .standard)

    /// One pending request, in a form a test can look at.
    struct Request: Equatable, Sendable {
        var id: String
        var phase: CircadianPhase
        var mode: Mode
        /// Seconds from local midnight.
        var start: TimeInterval
    }

    /// The phases that get a note when they begin.
    private(set) var enabled: Set<CircadianPhase> {
        didSet {
            defaults.set(enabled.map(\.rawValue).sorted(), forKey: Self.key)
            reschedule()
        }
    }
    /// The user declined notifications; only Settings can turn them back on.
    private(set) var denied = false

    nonisolated private static let key = "phaseNotifications"
    nonisolated private static let prefix = "phase."
    private let defaults: UserDefaults
    private var phases: DayPhases?
    private var work: Task<Void, Never>?

    init(defaults: UserDefaults) {
        self.defaults = defaults
        let stored = defaults.stringArray(forKey: Self.key) ?? []
        enabled = Set(stored.compactMap(CircadianPhase.init(rawValue:)))
    }

    func isOn(_ phase: CircadianPhase) -> Bool { enabled.contains(phase) }

    /// Turns one phase on or off. The first switch on asks for permission;
    /// a refusal leaves every switch off.
    func set(_ phase: CircadianPhase, on: Bool) {
        if on { enabled.insert(phase) } else { enabled.remove(phase) }
    }

    /// The day these notes follow. `DayPublisher` calls this with every
    /// snapshot it writes, so the two are always the same day.
    func follow(_ phases: DayPhases) {
        guard phases != self.phases else { return }
        self.phases = phases
        reschedule()
    }

    /// What would be scheduled: a note at the start of each span whose
    /// phase is on. A span beginning at midnight continues the night
    /// before it rather than starting anything, so it is skipped when the
    /// day ends in the same phase.
    nonisolated static func requests(for phases: DayPhases, enabled: Set<CircadianPhase>) -> [Request] {
        phases.spans.enumerated().compactMap { index, span in
            guard enabled.contains(span.phase) else { return nil }
            if index == 0, span.start == 0, phases.spans.last?.phase == span.phase, phases.spans.count > 1 { return nil }
            return Request(id: "\(prefix)\(span.phase.rawValue).\(index)", phase: span.phase, mode: span.mode, start: span.start)
        }
    }

    private func reschedule() {
        work?.cancel()
        work = Task { await apply() }
    }

    private func apply() async {
        let center = UNUserNotificationCenter.current()
        let stale = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)
        guard let phases, !enabled.isEmpty else { return }
        let requests = Self.requests(for: phases, enabled: enabled)
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            denied = !granted
            guard granted, !Task.isCancelled else { return }
            for request in requests {
                let content = UNMutableNotificationContent()
                content.title = String(localized: request.phase.title)
                content.body = String(localized: "\(request.mode.title) fits the hour.")
                content.sound = .default
                content.interruptionLevel = .timeSensitive
                var parts = DateComponents()
                parts.hour = Int(request.start) / 3600
                parts.minute = Int(request.start) % 3600 / 60
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: true)
                try await center.add(UNNotificationRequest(identifier: request.id, content: content, trigger: trigger))
            }
        } catch {
            return
        }
    }
}
