import SwiftUI

/// Everything set once rather than per session: the layers under the sound,
/// where the day comes from, and how Entrain sits with the system. The Mac
/// shows it as the Settings window, the iPhone and iPad as the third tab.
struct SettingsScreen: View {
    @Bindable var session: Session
    @Bindable private var daylight = Daylight.shared

    var body: some View {
        #if os(macOS)
        form
            .frame(width: 480)
        #else
        NavigationStack {
            form
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
        #endif
    }

    private var form: some View {
        Form {
            // The same setting the first-launch question sets, in the same
            // words, so it reads as one thing moved rather than two.
            Section {
                Picker("Intensity", selection: $session.intensity) {
                    ForEach(Intensity.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Background Sound")
            } footer: {
                Text(session.intensity.blurb)
            }
            Section {
                Toggle("Binaural Beats", isOn: $session.binaural)
            } footer: {
                Text(session.binaural && !session.headphones
                    ? "Adds a slow beat between the ears. Needs headphones, so it is silent right now."
                    : "Adds a slow beat between the ears. Needs headphones.")
            }
            Section {
                Toggle("Daylight", isOn: $daylight.followsLocation)
            } footer: {
                if daylight.followsLocation && daylight.denied {
                    Text("Allow location for Entrain in Settings to follow local sunrise and sunset.")
                } else if daylight.followsLocation {
                    Text("Brighter in the morning, warmer after sunset, from your approximate location.")
                } else {
                    Text("Brighter in the morning, warmer after sunset, assuming a 7 to 19 day.")
                }
            }
            #if os(iOS)
            Section {
                Toggle("Haptics", isOn: $session.haptics)
            } footer: {
                Text("Taps in time with the sound, for the slow modes. Off above a few beats a second, where the pulse only buzzes.")
            }
            #endif
            if session.headTrackingAvailable {
                Section {
                    Toggle("Head Tracking", isOn: $session.headTracking)
                } footer: {
                    Text("Keeps the room in place when you turn your head, with AirPods or Beats. Stays off in Sleep and Wind Down.")
                }
            }
            SleepTargetSection(session: session)
            #if !os(macOS)
            BodySection()
            #endif
            Section {
                #if os(macOS)
                Toggle("Control Center & Media Keys", isOn: $session.nowPlaying)
                #else
                Toggle("Lock Screen Controls", isOn: $session.nowPlaying)
                #endif
            } footer: {
                Text("Off, Entrain blends under music and podcasts. On, it takes the playback controls and pauses other audio.")
            }
            #if os(macOS)
            SystemSection(session: session)
            #endif
        }
        .formStyle(.grouped)
        .tint(session.mode.tint)
    }
}

/// The night to aim at. Off, nothing here is read and the app follows the
/// sleep it measures, which is what it has always done.
private struct SleepTargetSection: View {
    @Bindable var session: Session

    private var target: SleepTarget { session.sleepTarget }

    var body: some View {
        Section {
            Toggle("Sleep Target", isOn: $session.sleepTarget.isOn)
            if target.isOn {
                DatePicker(
                    "Wake At",
                    selection: Binding(
                        get: { Self.date(target.wake) },
                        set: { session.sleepTarget.wake = Self.seconds($0) }
                    ),
                    displayedComponents: .hourAndMinute
                )
                Picker("Sleep For", selection: $session.sleepTarget.hours) {
                    ForEach(SleepTarget.lengths, id: \.self) { Text(Self.hours($0)).tag($0) }
                }
                LabeledContent("Bedtime", value: Self.clock(target.bedtime))
            }
        } header: {
            Text("Sleep")
        } footer: {
            Text(target.isOn
                ? "Wind Down opens three hours before this bedtime and Wake covers the two hours before this wake. Entrain moves toward it about twenty minutes a night from the sleep it measures, because a body clock will not jump."
                : "Off, Entrain follows the sleep it measures. On, you set a wake time and a length, and it walks your evenings toward them.")
        }
    }

    /// The picker wants a Date; only its time of day is ever read, so any
    /// day will do and today is the one whose clock the reader is on.
    private static func date(_ seconds: TimeInterval) -> Date {
        Calendar.current.startOfDay(for: .now).addingTimeInterval(seconds)
    }

    private static func seconds(_ date: Date) -> TimeInterval {
        date.timeIntervalSince(Calendar.current.startOfDay(for: date))
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        date(seconds).formatted(date: .omitted, time: .shortened)
    }

    private static func hours(_ seconds: TimeInterval) -> String {
        let allowed: Set<Duration.UnitsFormatStyle.Unit> = seconds.truncatingRemainder(dividingBy: 3600) == 0
            ? [.hours] : [.hours, .minutes]
        return Duration.seconds(seconds).formatted(.units(allowed: allowed, width: .abbreviated))
    }
}
