import SwiftUI

/// Everything set once rather than per session: the layers under the sound,
/// where the day comes from, and how Entrain sits with the system. The Mac
/// shows it as the Settings window, the iPhone as a sheet.
struct SettingsScreen: View {
    @Bindable var session: Session
    @Bindable private var daylight = Daylight.shared
    #if !os(macOS)
    @Environment(\.dismiss) private var dismiss
    #endif

    var body: some View {
        #if os(macOS)
        form
            .frame(width: 480)
        #else
        NavigationStack {
            form
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
        }
        .preferredColorScheme(.dark)
        #endif
    }

    private var form: some View {
        Form {
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
            if session.headTrackingAvailable {
                Section {
                    Toggle("Head Tracking", isOn: $session.headTracking)
                } footer: {
                    Text("Keeps the room in place when you turn your head, with AirPods or Beats. Stays off in Sleep and Wind Down.")
                }
            }
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
