import AVFoundation
import SwiftUI

/// The Wake alarm, as its own tab. It used to be a row in the Wake session
/// card, which put it a mode away from anyone who wanted it; an alarm is
/// set the night before, not while Wake is playing.
///
/// Scan to Stop is what makes it an alarm for a heavy sleeper: the alarm
/// keeps ringing every two minutes for twenty, and the only thing that
/// stops it is scanning a code registered here, which lives wherever you
/// want to end up. Nothing done in bed passes. Steps can be shaken out of a
/// phone lying down and sums can be done half asleep, so there is no other
/// task and no fallback, because a fallback is a way past.
struct AlarmScreen: View {
    @Bindable var session: Session
    @Bindable private var alarm = WakeAlarm.shared
    @State private var registering = false
    @State private var cameraDenied = false

    var body: some View {
        NavigationStack {
            form
                .navigationTitle("Alarm")
                .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $registering) {
            RegisterCodeSheet { code in
                alarm.register(code)
                alarm.scanToStop = true
            }
        }
    }

    private var form: some View {
        Form {
            Section {
                DatePicker("Time", selection: $alarm.time, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                WeekdayPicker(selection: $alarm.days)
                Toggle("Alarm", isOn: Binding(
                    get: { alarm.isOn },
                    set: { alarm.set(on: $0) }
                ))
            } footer: {
                if alarm.denied {
                    Text("Allow alarms for Entrain in Settings to use the Wake alarm.")
                } else if let error = alarm.error {
                    Text(verbatim: error)
                } else {
                    Text(verbatim: alarm.summary + " ") + Text("Rings even on silent.")
                }
            }
            Section {
                Toggle("Scan to Stop", isOn: $alarm.scanToStop)
                    .disabled(alarm.code == nil)
                if let code = alarm.code {
                    LabeledContent("Code") {
                        Text(verbatim: code)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Button("Register Another Code") { register() }
                    Button("Forget Code", role: .destructive) { alarm.forgetCode() }
                } else {
                    Button("Register a Code") { register() }
                }
            } header: {
                Text("Get Me Up")
            } footer: {
                if cameraDenied {
                    Text("Allow the camera for Entrain in Settings to register a code.")
                } else if alarm.code == nil {
                    Text("Scan any barcode or QR code that lives where you want to end up, like the toothpaste. On, the alarm rings again every 2 minutes for 20 minutes, and only scanning that code stops it.")
                } else {
                    Text("On, Stop only silences the ring in progress. The alarm rings again every 2 minutes for 20 minutes until you scan the code, and then Wake plays.")
                }
            }
        }
        .formStyle(.grouped)
        .tint(session.mode.tint)
    }

    private func register() {
        Task {
            let granted = await CodeScanner.requestAccess()
            cameraDenied = !granted
            registering = granted
        }
    }
}

/// The camera, until it reads one code. Which code is not checked here: the
/// first one seen is the one registered.
private struct RegisterCodeSheet: View {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var done = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                CodeScanner { code in
                    guard !done else { return }
                    done = true
                    onScan(code)
                    dismiss()
                }
                .clipShape(.rect(cornerRadius: 24))
                .aspectRatio(1, contentMode: .fit)
                Text("Point the camera at the barcode or QR code that will stop the alarm.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Backdrop(mode: .wake))
            .navigationTitle("Register a Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// What the whole app is while a volley is going: the camera, and the
/// reason it is there. It cannot be dismissed; scanning the registered
/// code is the way out, and it ends the volley and starts Wake. A code
/// that is not the one is said so. A denied camera is pointed at Settings,
/// and the volley runs out on its own after twenty minutes either way.
struct WakeGate: View {
    @Bindable private var alarm = WakeAlarm.shared
    @State private var wrong = false
    @State private var cameraDenied = false
    @State private var siren = Siren()

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "alarm.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Mode.wake.tint)
                Text("Time to get up")
                    .font(.title.weight(.semibold))
                Text("Scan the code you registered to stop the alarm.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if cameraDenied {
                VStack(spacing: 12) {
                    Text("Entrain has no camera. Allow it in Settings to scan the code.")
                        .multilineTextAlignment(.center)
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        Link("Open Settings", destination: url)
                            .buttonStyle(.borderedProminent)
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
            } else {
                CodeScanner { code in
                    if alarm.pass(code) { wrong = false } else { wrong = true }
                }
                .clipShape(.rect(cornerRadius: 24))
                .aspectRatio(1, contentMode: .fit)
            }
            Text(wrong ? "Not that one." : "It rings again every 2 minutes for 20 minutes until you do.")
                .font(.footnote)
                .foregroundStyle(wrong ? Mode.wake.tint : .secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Backdrop(mode: .wake))
        .preferredColorScheme(.dark)
        .task {
            // The ring the button silenced carries on in here, and keeps
            // going in the background, until the code is scanned.
            siren.start()
            cameraDenied = !(await CodeScanner.requestAccess())
            // The window closes on the clock, not on anything the app sees.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                alarm.refresh()
            }
        }
        .onDisappear { siren.stop() }
    }
}

/// The alarm sound, looped in-app. The same file AlarmKit rings, played
/// over silent mode and under nothing, as loud as the media volume goes.
@MainActor
private final class Siren {
    private var player: AVAudioPlayer?

    func start() {
        guard player == nil, let url = Bundle.main.url(forResource: "Alarm", withExtension: "caf") else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        let player = try? AVAudioPlayer(contentsOf: url)
        player?.numberOfLoops = -1
        player?.volume = 1
        player?.play()
        self.player = player
    }

    func stop() {
        player?.stop()
        player = nil
    }
}

/// Seven circles, Monday first where the locale says so. None selected
/// means the alarm rings once.
private struct WeekdayPicker: View {
    @Binding var selection: Set<Locale.Weekday>

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Locale.Weekday.ordered, id: \.self) { day in
                let on = selection.contains(day)
                Button {
                    if on { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(day.letter)
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .glassEffect(on ? .regular.tint(Mode.wake.tint).interactive() : .regular.interactive(), in: .circle)
                .foregroundStyle(on ? Mode.wake.onTint : .primary)
                .accessibilityLabel(day.shortName)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}
