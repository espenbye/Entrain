# Entrain

A macOS menu bar app that plays a generated soundscape with rhythmic amplitude modulation, tuned to nudge your brain toward a target state. No audio files, no network. Everything is synthesized in real time.

## Modes

| Mode       | Rate  | Depth  | Intended state          |
|------------|-------|--------|-------------------------|
| Focus      | 16 Hz | 0.5    | Alert, task-oriented    |
| Gamma      | 40 Hz | 0.3    | Alert; 40 Hz steady-state response |
| Relax      | 10 Hz | 0.4    | Calm, unwinding         |
| Meditate   | 6 Hz  | 0.5    | Deep, inward attention  |
| Sleep      | 2 Hz  | steady | Drifting off            |
| Deep Sleep | 1 Hz  | 0.5    | Slow-wave sleep         |

Each mode sets the modulation rate and depth. On top of that you pick:

- **Sound**: any combination of Rain, Pad, Drone and Noise, remembered per mode. Focus starts on Rain, Gamma, Relax and Meditate on Pad. A mix is scaled so it sits at the level of a single sound.
- **Intensity**: Low, Medium, High (scales modulation depth; High is a small step above Medium)
- **Timer**: Endless, 15 to 90 minutes, or 2, 4 or 8 hours. A timed session fades out when it ends. Pausing keeps the countdown; it resumes where it stopped.
- **Binaural**: optional binaural beat at the same rate (headphones required)
- **Volume**: an app-level volume on top of the system level, so the soundscape can sit under music or a call

Gamma is shallow on purpose: 40 Hz is the most reproducible rate for driving a steady-state response on EEG, but at ordinary depth it sounds like a buzz.

The two sleep modes play a fixed brown noise bed, ignore intensity, and taper over the last five minutes of a timed session instead of stopping. Sleep is unmodulated; its 2 Hz rate only matters if binaural is on. Deep Sleep swells the bed once a second, the slow-oscillation rate that rhythmic sound studies use to deepen slow-wave sleep. When the Mac goes to sleep the session pauses, so it does not resume on wake.

Settings persist between launches. Play/pause works from the menu bar menu, from Shortcuts and Siri ("Start Focus in Entrain", "Stop Entrain"), from a desktop or Notification Center widget, and optionally from a system-wide ⌃⌥E shortcut. The small widget shows the mode, sound and countdown with a play/pause button; the medium one adds a button per mode. Control Center offers a toggle per mode, lit while that mode plays. The media keys work through Now Playing, which shows the timer's progress; it can be turned off so the media keys stay with the music Entrain is sitting under. The app can show in the Dock and launch at login; both are off by default.

## How it works

The engine is created on first play, so a login item does not touch audio hardware at launch. It runs on a dedicated render thread and only reads control values through atomics, so the UI never touches the audio path. Modulation is confined to the 200 Hz to 1 kHz band: the bass stays steady and the highs (rain droplets, pad harmonics) do not flutter. The modulation rate is fixed; instead the texture drifts slowly, one filter and pan cycle every 15 minutes, to counter habituation. All transitions (play, pause, switching soundscapes) ramp over roughly a second to avoid clicks. If the output device changes mid-session (headphones plugged in, a display with speakers connected), the engine restarts itself; if it cannot, the session stops and says so rather than showing Pause over silence.

The four soundscapes are trimmed to the same K-weighted loudness (-22 LUFS, ITU-R BS.1770) so switching does not invite a volume change. The test target renders each voice offline and fails if one drifts more than 1 LU from the target, so touching a voice means re-running the tests and adjusting `Trim` in `Voices.swift`.

```
Sources/
  App/       MenuBarExtra entry point, App Intents, global shortcut
  UI/        SwiftUI menu bar menu and player window
  Session/   Session state, modes, Now Playing and widget snapshot
  Audio/     Engine, synth voices, DSP primitives, shared parameters
Widget/      WidgetKit extension; shares Mode, Intents and WidgetState with the app
Tests/       Loudness, synth and session tests (Swift Testing)
Tools/
  icon.swift   Renders the app icon set into Resources/
Scripts/
  run.sh       Debug build, widget re-registered, app relaunched
  release.sh   Developer ID build, notarization and stapling
```

## Building

Requires macOS 27 (the app will not run on earlier releases), Xcode with Swift 6, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
open Entrain.xcodeproj
```

Build and run the `Entrain` scheme, or run `Scripts/run.sh` (also wired up as "Build & Run" in `t3.json`), which rebuilds, re-registers the widget extension and relaunches. The app has no Dock icon by default; look for the waveform in the menu bar. Run the tests with Cmd-U, or:

```sh
xcodebuild -project Entrain.xcodeproj -scheme Entrain test
```

Launch at Login uses `SMAppService`, which needs the app to run from a stable location such as `/Applications`; from a DerivedData build the toggle shows an error instead. The widget appears in the widget gallery once the app has been launched. Its buttons run the app's intents inside the app process (`allowedExecutionTargets = .main`), and the app publishes a snapshot to `~/Library/Application Support/Entrain/widget.json` on every change, so the widget never touches audio or the session directly. Both sandboxes reach that folder through a path exception rather than an App Group, because group containers need a certificate-backed identity that a development build does not have.

Session logic is tested against a fake engine and a throwaway defaults suite; `Session` takes both in its initializer. CI runs the full test suite on every push.

## Releasing

`Scripts/release.sh` archives a Release build signed with a Developer ID certificate, submits it to Apple's notary service, staples the ticket and zips the result. It needs `DEVELOPMENT_TEAM` in the environment and notarytool credentials stored under the `entrain` keychain profile.

## Caveats

Entrainment effects vary widely between people and the evidence is mixed. Treat this as a pleasant background sound with a rhythm, not a medical device. Keep the volume moderate, and don't use it while driving.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
