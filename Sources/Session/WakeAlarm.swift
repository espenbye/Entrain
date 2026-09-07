#if canImport(AlarmKit)
import AlarmKit
import AppIntents
import Foundation
import Observation

/// A real alarm for Wake mode. It rings through silent mode and Focus like
/// the Clock app's, and its second button starts the Wake ramp. With no days
/// picked it rings once, at the next occurrence of the time, and is gone;
/// that one is scheduled as a countdown rather than a clock alarm so the
/// system shows it as a Live Activity until it rings. With days picked it is
/// a repeating clock alarm, which the system re-arms after each ring and
/// shows only while ringing.
@MainActor
@Observable
final class WakeAlarm {
    static let shared = WakeAlarm(defaults: .standard)

    private static let id = WakeAlarmMetadata.alarmID

    /// The time of day the alarm rings. Remembered between launches.
    var time: Date {
        didSet {
            save()
            if isOn { set(on: true) }
        }
    }
    /// The weekdays it repeats on. Empty means once.
    var days: Set<Locale.Weekday> {
        didSet {
            save()
            if isOn { set(on: true) }
        }
    }
    /// True while an alarm is scheduled or ringing.
    private(set) var isOn = false
    /// The user declined alarms; only Settings can turn them back on.
    private(set) var denied = false
    /// Why the last attempt to schedule failed. Nil once one succeeds.
    private(set) var error: String?

    private let defaults: UserDefaults
    /// The pending schedule or cancel. Each request replaces the last, so
    /// scrubbing the time picker ends with one alarm at the final time.
    private var work: Task<Void, Never>?

    init(defaults: UserDefaults) {
        self.defaults = defaults
        var parts = DateComponents()
        parts.hour = defaults.object(forKey: "wakeAlarm.hour") as? Int ?? 7
        parts.minute = defaults.object(forKey: "wakeAlarm.minute") as? Int ?? 0
        time = Calendar.current.date(from: parts) ?? .now
        let stored = defaults.string(forKey: "wakeAlarm.days")?.split(separator: ",") ?? []
        days = Set(stored.compactMap { Locale.Weekday(rawValue: String($0)) })
        denied = AlarmManager.shared.authorizationState == .denied
        isOn = (try? AlarmManager.shared.alarms)?.contains { $0.id == Self.id } ?? false
        Task { [weak self] in
            for await alarms in AlarmManager.shared.alarmUpdates {
                guard let self else { return }
                isOn = alarms.contains { $0.id == Self.id }
            }
        }
    }

    /// Schedules at the next occurrence of `time`, or cancels. Asks for
    /// permission the first time; a refusal leaves the switch off.
    func set(on: Bool) {
        work?.cancel()
        work = Task { await apply(on: on) }
    }

    private func apply(on: Bool) async {
        // The id is fixed, so an existing alarm has to go before its
        // replacement; scheduling over it fails.
        try? AlarmManager.shared.cancel(id: Self.id)
        guard on else {
            isOn = false
            return
        }
        do {
            let state = try await AlarmManager.shared.requestAuthorization()
            denied = state == .denied
            guard state == .authorized, !Task.isCancelled else { return }
            let alert = AlarmPresentation.Alert(
                title: "Wake",
                stopButton: AlarmButton(text: "Dismiss", textColor: .white, systemImageName: "xmark"),
                secondaryButton: AlarmButton(text: "Start Wake", textColor: .white, systemImageName: "sunrise"),
                secondaryButtonBehavior: .custom
            )
            // Only the one-shot counts down; a clock alarm with a countdown
            // presentation is rejected as an invalid configuration.
            let countdown = days.isEmpty ? AlarmPresentation.Countdown(title: "Wake") : nil
            let attributes = AlarmAttributes<WakeAlarmMetadata>(
                presentation: AlarmPresentation(alert: alert, countdown: countdown),
                tintColor: Mode.wake.tint
            )
            let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
            let configuration = days.isEmpty
                ? AlarmManager.AlarmConfiguration.timer(
                    duration: Self.secondsUntilNext(time),
                    attributes: attributes,
                    secondaryIntent: StartWakeIntent()
                )
                : AlarmManager.AlarmConfiguration.alarm(
                    schedule: .relative(.init(
                        time: .init(hour: parts.hour ?? 0, minute: parts.minute ?? 0),
                        repeats: .weekly(Locale.Weekday.ordered.filter(days.contains))
                    )),
                    attributes: attributes,
                    secondaryIntent: StartWakeIntent()
                )
            _ = try await AlarmManager.shared.schedule(id: Self.id, configuration: configuration)
            isOn = true
            self.error = nil
        } catch {
            guard !Task.isCancelled else { return }
            isOn = false
            self.error = error.localizedDescription
        }
    }

    /// Seconds to the next occurrence of the time of day, tomorrow if it has passed.
    static func secondsUntilNext(_ time: Date, from now: Date = .now) -> TimeInterval {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        let next = Calendar.current.nextDate(after: now, matching: parts, matchingPolicy: .nextTime) ?? now
        return max(60, next.timeIntervalSince(now))
    }

    /// "Once, at the next 07:00." or "Mon, Tue, Wed at 07:00."
    var summary: String {
        let clock = time.formatted(date: .omitted, time: .shortened)
        let weekdays: Set<Locale.Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
        if days.isEmpty { return String(localized: "Once, at the next \(clock).") }
        if days.count == 7 { return String(localized: "Every day at \(clock).") }
        if days == weekdays { return String(localized: "Weekdays at \(clock).") }
        let names = Locale.Weekday.ordered.filter(days.contains).map(\.shortName).formatted(.list(type: .and, width: .narrow))
        return String(localized: "\(names) at \(clock).")
    }

    private func save() {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        defaults.set(parts.hour, forKey: "wakeAlarm.hour")
        defaults.set(parts.minute, forKey: "wakeAlarm.minute")
        defaults.set(Locale.Weekday.ordered.filter(days.contains).map(\.rawValue).joined(separator: ","), forKey: "wakeAlarm.days")
    }
}

/// Behind the alarm's second button. A Live Activity intent runs in the app,
/// and foreground mode brings the app up, so the ramp starts on screen. An
/// endless timer becomes half an hour: the ramp takes fifteen minutes, and
/// a wake-up soundscape should not still be playing at lunch.
struct StartWakeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Wake"
    static var supportedModes: IntentModes { .foreground }

    @MainActor
    func perform() async throws -> some IntentResult {
        let session = Session.shared
        session.mode = .wake
        if session.length == .endless { session.length = .thirty }
        await session.play()
        return .result()
    }
}

extension Locale.Weekday {
    /// The week in the user's order, so Monday-first locales start on Monday.
    static var ordered: [Locale.Weekday] {
        let week: [Locale.Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        let first = Calendar.current.firstWeekday - 1
        return Array(week[first...] + week[..<first])
    }

    /// "Mon", in the user's language.
    var shortName: String {
        let week: [Locale.Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        return Calendar.current.shortStandaloneWeekdaySymbols[week.firstIndex(of: self)!]
    }

    /// "M", for a row of seven.
    var letter: String {
        let week: [Locale.Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        return Calendar.current.veryShortStandaloneWeekdaySymbols[week.firstIndex(of: self)!]
    }
}
#endif
