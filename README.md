# Entrain

A Mac, iPhone, iPad and Apple Watch app that plays a generated soundscape with rhythmic amplitude modulation, tuned to nudge your brain toward a target state. No audio files, no network. Everything is synthesized in real time. On the Mac it lives in the menu bar.

## Modes

| Mode       | Rate  | Depth  | Intended state          |
|------------|-------|--------|-------------------------|
| Focus      | 16 Hz | 0.5    | Alert, task-oriented    |
| Gamma      | 40 Hz | 0.3    | Alert; 40 Hz steady-state response |
| Relax      | 10 Hz | 0.4    | Calm, unwinding         |
| Meditate   | 6 Hz  | 0.5    | Deep, inward attention  |
| Sleep      | 2 Hz  | steady | Drifting off            |
| Deep Sleep | 1 Hz  | 0.5    | Slow-wave sleep         |
| Wind Down  | 10 → 2 Hz over 20 min | 0.4 | Bedtime, alpha down to delta |
| Wake       | 2 → 16 Hz over 15 min | 0.5 | After a nap, delta back up to beta |

Each mode sets the modulation rate and depth. On top of that you pick:

- **Sound**: any combination of Rain, Pad, Drone and Noise, remembered per mode. Focus and Wind Down start on Rain, Gamma, Relax, Meditate and Wake on Pad. A mix is scaled so it sits at the level of a single sound.
- **Intensity**: Low, Medium, High (scales modulation depth; High is a small step above Medium)
- **Timer**: Endless, 15 to 90 minutes, or 2, 4 or 8 hours. A timed session fades out when it ends. Pausing keeps the countdown; it resumes where it stopped.
- **Binaural**: optional binaural beat at the same rate (headphones required)
- **Volume**: an app-level volume on top of the system level, so the soundscape can sit under music or a call

Gamma is shallow on purpose: 40 Hz is the most reproducible rate for driving a steady-state response on EEG, but at ordinary depth it sounds like a buzz.

Wind Down and Wake ramp their rate linearly over play time, then hold; pausing stops the clock, and switching mode restarts it. Wind Down starts on Rain and tapers over the last five minutes of a timed session like the sleep modes; Wake starts on Pad.

The two sleep modes play a fixed brown noise bed, ignore intensity, and taper over the last five minutes of a timed session instead of stopping. Sleep is unmodulated; its 2 Hz rate only matters if binaural is on. Deep Sleep swells the bed once a second, the slow-oscillation rate that rhythmic sound studies use to deepen slow-wave sleep. When the Mac goes to sleep the session pauses, so it does not resume on wake.

Settings persist between launches. Play/pause works from the menu bar menu, from Shortcuts and Siri ("Start Focus in Entrain", "Stop Entrain"), from a desktop or Notification Center widget, from `entrain://` URLs, and optionally from a system-wide ⌃⌥E shortcut. The small widget shows the mode, sound and countdown with a play/pause button; the medium one adds a button per mode. Control Center offers a toggle per mode, lit while that mode plays. The media keys work through Now Playing, which shows the timer's progress; it can be turned off so the media keys stay with the music Entrain is sitting under. The app can show in the Dock and launch at login; both are off by default. The UI is in English and Norwegian.

For Raycast, Alfred and shell scripts, the app answers `entrain://` URLs on Mac, iPhone and iPad, using the same mode and length values as the intents:

```
open "entrain://play?mode=focus&length=30"
open entrain://pause
open entrain://toggle
```

## iPhone, iPad and Apple Watch

The same session, synth and intents run on every platform; only the shell differs. On iPhone and iPad the player window is the app, playback continues in the background, and the widget comes in Home Screen sizes, as Lock Screen accessories and as Control Center toggles. Entrain blends under music and podcasts by default. The "Lock Screen Controls" toggle is the Mac's Now Playing toggle under another name: on, Entrain takes the Lock Screen and Control Center playback controls and pauses other audio, because iOS gives those controls only to an app that does not mix. A phone call pauses the session, and it stays paused.

The watch app is embedded in the iPhone app but plays on its own, through paired headphones: it uses the long-form audio policy so the session continues with the wrist down, and asks which headphones to use when none are connected. The Smart Stack widget shows the mode and countdown; tapping it opens the app. The watch has no reverb or EQ units, so the bed goes straight to the mixer there. Each device keeps its own session; nothing syncs between the phone and the watch. Volume on the watch is the Digital Crown in the system Now Playing view.

## How it works

The engine is created on first play, so a login item does not touch audio hardware at launch. It runs on a dedicated render thread and only reads control values through atomics, so the UI never touches the audio path. Modulation is confined to the 200 Hz to 1 kHz band: the bass stays steady and the highs (rain droplets, pad harmonics) do not flutter. The modulation rate is fixed; instead the texture drifts slowly, one filter and pan cycle every 15 minutes, to counter habituation. All transitions (play, pause, switching soundscapes) ramp over roughly a second to avoid clicks. If the output device changes mid-session (headphones plugged in, a display with speakers connected), the engine restarts itself; if it cannot, the session stops and says so rather than showing Pause over silence.

The four soundscapes are trimmed to the same K-weighted loudness (-22 LUFS, ITU-R BS.1770) so switching does not invite a volume change. The test target renders each voice offline and fails if one drifts more than 1 LU from the target, so touching a voice means re-running the tests and adjusting `Trim` in `Voices.swift`.

```
Sources/
  App/       One entry point per platform: macOS (MenuBarExtra, global shortcut), iOS, watchOS
  UI/        PlayerScreen (Mac window, iPhone, iPad) and the pieces the watch reuses; the menu bar menu under macOS/, the watch screen under watchOS/
  Session/   Session state, modes, App Intents, entrain:// URL commands, Now Playing and widget snapshot
  Audio/     Engine, audio session, synth voices, DSP primitives, shared parameters
Resources/   Asset catalog and the English/Norwegian string catalogs
Widget/      WidgetKit extension built once per platform; shares Mode, Intents and WidgetState with the app
iOS/, watchOS/  Generated Info.plist and entitlements for those targets
Tests/       Loudness, synth and session tests (Swift Testing, run on macOS)
Tools/
  icon.swift   Renders the app icon set into Resources/
Scripts/
  run.sh       Debug build, widget re-registered, app relaunched
  release.sh   Developer ID build, notarization and stapling
```

## Building

Requires macOS 26, iOS 26 or watchOS 26 (the apps will not run on earlier releases), Xcode with Swift 6, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
open Entrain.xcodeproj
```

The project signs to run locally by default. To sign with your own team (needed for the widget's buttons), add a gitignored `Local.xcconfig` next to `project.yml` before generating; `Signing.xcconfig` includes it when present:

```
DEVELOPMENT_TEAM = ABCDE12345
CODE_SIGN_IDENTITY = Apple Development
```

Build and run the `Entrain` scheme, or run `Scripts/run.sh` (also wired up as "Build & Run" in `t3.json`), which rebuilds, re-registers the widget extension and relaunches. The app has no Dock icon by default; look for the waveform in the menu bar. The `EntrainiOS` scheme builds the iPhone and iPad app with the watch app embedded; run it on a simulator or, with a team set, on a device. Run the tests with Cmd-U, or:

```sh
xcodebuild -project Entrain.xcodeproj -scheme Entrain test
```

Launch at Login uses `SMAppService`, which needs the app to run from a stable location such as `/Applications`; from a DerivedData build the toggle shows an error instead. The widget appears in the widget gallery once the app has been launched. Its buttons run the app's intents inside the app process (`allowedExecutionTargets = .main`), and the app publishes a snapshot to `~/Library/Application Support/Entrain/widget.json` on every change, so the widget never touches audio or the session directly. Both sandboxes reach that folder through a path exception rather than an App Group, because group containers need a certificate-backed identity that a development build does not have.

On iOS and watchOS the snapshot lives in the `group.no.espenbye.entrain` App Group instead, so device builds there need a development team; simulator builds do not.

Session logic is tested against a fake engine and a throwaway defaults suite; `Session` takes both in its initializer. CI runs the full test suite on macOS and builds the iOS and watch apps on every push and pull request, with code signing disabled.

## Releasing

`Scripts/release.sh` archives a Release build signed with a Developer ID certificate, submits it to Apple's notary service, staples the ticket and zips the result. It needs `DEVELOPMENT_TEAM` in the environment and notarytool credentials stored under the `entrain` keychain profile.

## Caveats

Entrainment effects vary widely between people and the evidence is mixed. Treat this as a pleasant background sound with a rhythm, not a medical device. Keep the volume moderate, and don't use it while driving.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
