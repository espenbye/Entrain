#if os(iOS) || os(watchOS)
import SwiftUI

/// What Entrain read from Health, in the settings, so the reading is
/// visible rather than implied. Health cannot say whether it was allowed to
/// answer — a refusal and an empty store come back identically — so there
/// is nothing here to explain a blank, and the section simply does not
/// appear until there is something in it.
struct BodySection: View {
    private let health = HealthSignals.shared

    var body: some View {
        if health.sleep != nil || !health.vitals.isEmpty {
            Section {
                if let sleep = health.sleep {
                    LabeledContent("Usual Bedtime", value: Self.clock(sleep.bedtime))
                    LabeledContent("Usual Wake", value: Self.clock(sleep.wake))
                    if let onset = sleep.onset {
                        LabeledContent("Falls Asleep In", value: Self.minutes(onset))
                    }
                }
                ForEach(BodyMetric.allCases, id: \.self) { metric in
                    if let signal = health.vitals[metric] {
                        LabeledContent(String(localized: metric.title)) {
                            Text(signal.summary)
                        }
                    }
                }
            } header: {
                Text("Health")
            } footer: {
                if let sleep = health.sleep {
                    Text("From the last \(sleep.nights) nights on this device. Entrain reads Health; it never writes anything but your Meditate minutes, and nothing leaves the device.")
                }
            }
        }
    }

    /// Seconds from midnight as a time, in the reader's own clock.
    private static func clock(_ seconds: TimeInterval) -> String {
        Calendar.current.startOfDay(for: .now)
            .addingTimeInterval(seconds)
            .formatted(date: .omitted, time: .shortened)
    }

    private static func minutes(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.minutes], width: .abbreviated))
    }
}
#endif

#if os(watchOS)
/// The heart while a session plays: the switch that lets the sensor run,
/// and the reading it produces. Read-only on purpose — see
/// `LiveHeartRate.steersAudio` for why nothing is wired to the sound yet.
struct HeartRateSection: View {
    @Bindable var session: Session
    @Bindable private var heart = LiveHeartRate.shared

    var body: some View {
        Section {
            Toggle("Heart Rate", isOn: $heart.isOn)
            if let bpm = heart.bpm {
                LabeledContent("Now", value: "\(Int(bpm.rounded())) BPM")
                if session.breathing != .none, let following = heart.following(session.breathing) {
                    LabeledContent("Following the Breath", value: following.formatted(.number.precision(.fractionLength(2))))
                }
            }
        } footer: {
            Text("Shows your heart rate through Meditate and Relax, and how closely it follows the breathing. Keeps the heart sensor running, so it costs battery.")
        }
    }
}
#endif
