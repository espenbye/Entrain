# Entrain

A macOS menu bar app that plays a generated soundscape with rhythmic amplitude modulation, tuned to nudge your brain toward a target state. No audio files, no network. Everything is synthesized in real time.

## Modes

| Mode     | Rate  | Depth  | Intended state          |
|----------|-------|--------|-------------------------|
| Focus    | 16 Hz | 0.5    | Alert, task-oriented    |
| Relax    | 10 Hz | 0.4    | Calm, unwinding         |
| Meditate | 6 Hz  | 0.5    | Deep, inward attention  |
| Sleep    | 2 Hz  | steady | Drifting off            |

Each mode sets the modulation rate and depth. On top of that you pick:

- **Soundscape**: Rain, Pad, Drone, or Noise. Remembered per mode. Focus starts on Rain, Relax and Meditate on Pad.
- **Intensity**: Low, Medium, High (scales modulation depth; High is a small step above Medium)
- **Length**: Endless, or a 15/30/60/90 minute timer that fades out when it ends. Pausing keeps the countdown; it resumes where it stopped.
- **Binaural**: optional binaural beat at the same rate (headphones required)
- **Volume**: an app-level volume on top of the system level, so the soundscape can sit under music or a call

Sleep is different on purpose. It plays steady brown noise with no modulation, and a timed sleep session tapers over its last five minutes instead of stopping. The 2 Hz rate only matters if binaural is on.

Settings persist between launches. Play/pause works from the menu bar menu, media keys, and Control Center via Now Playing, which shows the timer's progress. The app can show in the Dock and launch at login; both are off by default.

## How it works

The engine runs on a dedicated render thread and only reads control values through atomics, so the UI never touches the audio path. Modulation is confined to the 200 Hz to 1 kHz band: the bass stays steady and the highs (rain droplets, pad harmonics) do not flutter. The modulation rate is fixed; instead the texture drifts slowly, one filter and pan cycle every 15 minutes, to counter habituation. All transitions (play, pause, switching soundscapes) ramp over roughly a second to avoid clicks. If the output device changes mid-session (headphones plugged in, a display with speakers connected), the engine restarts itself.

The four soundscapes are trimmed to the same K-weighted loudness (-22 LUFS, ITU-R BS.1770) so switching does not invite a volume change. The test target renders each voice offline and fails if one drifts more than 1 LU from the target, so touching a voice means re-running the tests and adjusting `Trim` in `Voices.swift`.

```
Sources/
  App/       MenuBarExtra entry point
  UI/        SwiftUI menu bar menu
  Session/   Session state, modes, Now Playing integration
  Audio/     Engine, synth voices, DSP primitives, shared parameters
Tests/       Loudness and synth invariants (Swift Testing)
Tools/
  icon.swift   Renders the app icon set into Resources/
```

## Building

Requires macOS 27, Xcode with Swift 6, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
open Entrain.xcodeproj
```

Build and run the `Entrain` scheme. The app has no Dock icon by default; look for the waveform in the menu bar. Run the tests with Cmd-U, or:

```sh
xcodebuild -project Entrain.xcodeproj -scheme Entrain test
```

Launch at Login uses `SMAppService`, which needs the app to run from a stable location such as `/Applications`; from a DerivedData build the toggle may not stick.

## Caveats

Entrainment effects vary widely between people and the evidence is mixed. Treat this as a pleasant background sound with a rhythm, not a medical device. Keep the volume moderate, and don't use it while driving.
