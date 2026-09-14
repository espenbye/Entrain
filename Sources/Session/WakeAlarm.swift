#if canImport(AlarmKit)
import ActivityKit
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
///
/// With Scan to Stop on, the first ring is followed by a row more two minutes
/// apart (see `WakeVolley`), and the only thing that cancels the followers
/// is scanning the code registered here. The first ring is the alarm above,
/// so a morning slept through does not cost the next one; the followers are
/// one-shot alarms re-armed for the next morning after every scan and
/// every launch.
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
    /// Whether the alarm keeps ringing until the code is scanned.
    var scanToStop: Bool {
        didSet {
            save()
            if isOn { set(on: true) }
        }
    }
    /// The barcode or QR payload that ends a volley. Nil until one is registered.
    private(set) var code: String?
    /// True while an alarm is scheduled or ringing.
    private(set) var isOn = false
    /// True while a volley is going on, which is when the app is the scanner.
    private(set) var live = false
    /// The user declined alarms; only Settings can turn them back on.
    private(set) var denied = false
    /// Why the last attempt to schedule failed. Nil once one succeeds.
    private(set) var error: String?
    /// How many rings the last volley got: all of them, or as many as the
    /// system allowed.
    private(set) var rings = WakeVolley.count

    private let defaults: UserDefaults
    /// Every alarm of ours the system holds, by id, with the follower's
    /// fixed time where it has one.
    private var scheduled: [UUID: Date?] = [:]
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
        scanToStop = defaults.bool(forKey: "wakeAlarm.scanToStop")
        code = defaults.string(forKey: "wakeAlarm.code")
        denied = AlarmManager.shared.authorizationState == .denied
        read((try? AlarmManager.shared.alarms) ?? [])
        Task { [weak self] in
            for await alarms in AlarmManager.shared.alarmUpdates {
                guard let self else { return }
                read(alarms)
            }
        }
    }

    private func read(_ alarms: [Alarm]) {
        scheduled = Dictionary(uniqueKeysWithValues: alarms.filter { Self.isOurs($0.id) }.map { alarm in
            if case .fixed(let date) = alarm.schedule { return (alarm.id, date) }
            return (alarm.id, nil)
        })
        isOn = !scheduled.isEmpty
        live = isLive(at: .now)
    }

    /// Whether a volley is going on right now: a first ring within the last
    /// hour, and a follower of that ring still to come. Tomorrow's
    /// followers, armed after a scan, sit a day away and do not count.
    private func isLive(at now: Date) -> Bool {
        guard scanToStop, code != nil,
              let start = WakeVolley.liveStart(time, days: days, at: now) else { return false }
        let end = start.addingTimeInterval(WakeVolley.window)
        return scheduled.values.contains { date in
            guard let date else { return false }
            return date >= start && date < end
        }
    }

    /// Scanning the registered code. Ends the volley, arms the next
    /// morning's, and starts the Wake ramp, which is what the alarm was for.
    func pass(_ scanned: String) -> Bool {
        guard scanned == code else { return false }
        cancel(Self.followerIDs)
        // A follower the system would not let go keeps the gate up, and the
        // reason is under the switch; nothing plays over a ring still to come.
        guard !live else { return true }
        work?.cancel()
        work = Task { await armFollowers() }
        Self.startWake()
        return true
    }

    /// Cancels what the system still holds of these, then reads back what
    /// it holds now. The list is the state: a cancel that failed leaves its
    /// alarm in it, and a schedule over that id would fail too.
    private func cancel(_ ids: [UUID]) {
        for id in ids {
            // Every id goes, in case the list is behind; only one the list
            // said was there is a failure worth reporting.
            do { try AlarmManager.shared.cancel(id: id) } catch where scheduled.keys.contains(id) {
                self.error = error.localizedDescription
            } catch {}
        }
        read((try? AlarmManager.shared.alarms) ?? [])
    }

    /// Remembers the code that ends a volley.
    func register(_ code: String) {
        self.code = code
        defaults.set(code, forKey: "wakeAlarm.code")
    }

    /// Forgets it, which turns Scan to Stop off with it.
    func forgetCode() {
        code = nil
        defaults.removeObject(forKey: "wakeAlarm.code")
        scanToStop = false
    }

    /// Called whenever the app comes forward. A volley that ran out
    /// without a scan left nothing armed for the next morning; this arms
    /// it. During a volley it does nothing, so the followers stay put.
    func refresh(at now: Date = .now) {
        live = isLive(at: now)
        guard isOn, scanToStop, code != nil, !live else { return }
        work?.cancel()
        work = Task { await armFollowers(from: now) }
    }

    /// Schedules at the next occurrence of `time`, or cancels. Asks for
    /// permission the first time; a refusal leaves the switch off.
    func set(on: Bool) {
        work?.cancel()
        work = Task { await apply(on: on) }
    }

    private func apply(on: Bool) async {
        // The ids are fixed, so an existing alarm has to go before its
        // replacement; scheduling over it fails.
        cancel(Self.ids)
        guard on else { return }
        do {
            let state = try await AlarmManager.shared.requestAuthorization()
            denied = state == .denied
            guard state == .authorized, !Task.isCancelled else { return }
            let hard = scanToStop && code != nil
            let secondary: any LiveActivityIntent = hard ? GetUpIntent() : StartWakeIntent()
            let attributes = attributes(countdown: days.isEmpty)
            let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
            let configuration = days.isEmpty
                ? AlarmManager.AlarmConfiguration.timer(
                    duration: Self.secondsUntilNext(time),
                    attributes: attributes,
                    secondaryIntent: secondary,
                    sound: Self.sound
                )
                : AlarmManager.AlarmConfiguration.alarm(
                    schedule: .relative(.init(
                        time: .init(hour: parts.hour ?? 0, minute: parts.minute ?? 0),
                        repeats: .weekly(Locale.Weekday.ordered.filter(days.contains))
                    )),
                    attributes: attributes,
                    secondaryIntent: secondary,
                    sound: Self.sound
                )
            _ = try await AlarmManager.shared.schedule(id: Self.id, configuration: configuration)
            scheduled[Self.id] = .some(nil)
            isOn = true
            if hard { try await scheduleFollowers(from: .now) }
            live = isLive(at: .now)
            self.error = nil
        } catch {
            guard !Task.isCancelled else { return }
            // Off means off: the first ring and any followers that got in
            // before the failure go too, or the switch would say off over
            // an alarm that rings.
            cancel(Self.ids)
            self.error = error.localizedDescription
        }
    }

    /// Replaces the followers with the next morning's.
    private func armFollowers(from now: Date = .now) async {
        cancel(Self.followerIDs)
        do {
            try await scheduleFollowers(from: now)
            error = nil
        } catch {
            guard !Task.isCancelled else { return }
            cancel(Self.followerIDs)
            self.error = error.localizedDescription
        }
    }

    /// The system caps how many alarms an app may hold and does not say
    /// where. A volley cut short at the cap is still a volley, so the
    /// followers it refused are simply not there, and the tab says how
    /// many rings there are.
    private func scheduleFollowers(from now: Date) async throws {
        guard let first = WakeVolley.next(time, days: days, after: now) else { return }
        let attributes = attributes(countdown: false)
        rings = WakeVolley.count
        for (index, (id, date)) in zip(Self.followerIDs, WakeVolley.followers(after: first)).enumerated() {
            guard !Task.isCancelled else { return }
            do {
                _ = try await AlarmManager.shared.schedule(
                    id: id,
                    configuration: .alarm(schedule: .fixed(date), attributes: attributes, secondaryIntent: GetUpIntent(), sound: Self.sound)
                )
                scheduled[id] = date
            } catch AlarmManager.AlarmError.maximumLimitReached {
                rings = index + 1
                return
            }
        }
    }

    private func attributes(countdown: Bool) -> AlarmAttributes<WakeAlarmMetadata> {
        let hard = scanToStop && code != nil
        let alert = AlarmPresentation.Alert(
            title: "Wake",
            stopButton: AlarmButton(
                text: hard ? "Stop" : "Dismiss", textColor: .white, systemImageName: "xmark"
            ),
            secondaryButton: AlarmButton(
                text: hard ? "I'm Up" : "Start Wake", textColor: .white,
                systemImageName: hard ? "figure.walk" : "sunrise"
            ),
            secondaryButtonBehavior: .custom
        )
        // Only the one-shot counts down; a clock alarm with a countdown
        // presentation is rejected as an invalid configuration.
        return AlarmAttributes<WakeAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert, countdown: countdown ? .init(title: "Wake") : nil),
            tintColor: Mode.wake.tint
        )
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

    /// The Wake ramp, on screen. An endless timer becomes half an hour, so
    /// the ramp has a length to follow and a wake-up soundscape is not
    /// still playing at lunch.
    static func startWake() {
        let session = Session.shared
        session.mode = .wake
        if session.length == .endless { session.length = .thirty }
        Task { await session.play() }
    }

    private func save() {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        defaults.set(parts.hour, forKey: "wakeAlarm.hour")
        defaults.set(parts.minute, forKey: "wakeAlarm.minute")
        defaults.set(Locale.Weekday.ordered.filter(days.contains).map(\.rawValue).joined(separator: ","), forKey: "wakeAlarm.days")
        defaults.set(scanToStop, forKey: "wakeAlarm.scanToStop")
    }

    /// Rendered by Tools/alarm.swift: full-scale beeps, made to be loud.
    /// How loud is the ringer volume in Settings, which the app cannot raise.
    private static let sound = AlertConfiguration.AlertSound.named("Alarm.caf")

    private static let ids = [id] + followerIDs
    private static let followerIDs = WakeAlarmMetadata.followerIDs
    private static func isOurs(_ id: UUID) -> Bool { id == Self.id || followerIDs.contains(id) }
}

/// Behind the alarm's second button. A Live Activity intent runs in the app,
/// and foreground mode brings the app up, so the ramp starts on screen.
struct StartWakeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Wake"
    static var supportedModes: IntentModes { .foreground }

    @MainActor
    func perform() async throws -> some IntentResult {
        WakeAlarm.startWake()
        return .result()
    }
}

/// The second button while Scan to Stop is on. It only brings the app up:
/// the app sees a volley in progress and shows the scanner, and nothing
/// short of the code gets past it.
struct GetUpIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "I'm Up"
    static var supportedModes: IntentModes { .foreground }

    func perform() async throws -> some IntentResult {
        .result()
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
