# Entrain

A macOS menu bar app that plays a generated soundscape with rhythmic amplitude modulation, tuned to nudge your brain toward a target state. No audio files, no network. Everything is synthesized in real time.

## Modes

| Mode     | Rate  | Intended state          |
|----------|-------|-------------------------|
| Focus    | 16 Hz | Alert, task-oriented    |
| Relax    | 10 Hz | Calm, unwinding         |
| Meditate | 6 Hz  | Deep, inward attention  |
| Sleep    | 2 Hz  | Drifting off            |

Each mode sets the modulation rate and depth. On top of that you pick:

- **Soundscape**: Rain, Pad, or Drone
- **Intensity**: Low, Medium, High (scales modulation depth)
- **Length**: Endless, or a 15/30/60/90 minute timer that fades out when it ends
- **Binaural**: optional binaural beat at the same rate (headphones required)

Settings persist between launches. Play/pause works from the menu bar popover, media keys, and Control Center via Now Playing.

## How it works

The engine runs on a dedicated render thread and only reads control values through atomics, so the UI never touches the audio path. Modulation is applied above a 200 Hz crossover so the low end stays steady while the mid band pulses. All transitions (play, pause, switching soundscapes) ramp over roughly a second to avoid clicks.

```
Sources/
  App/       MenuBarExtra entry point
  UI/        SwiftUI popover
  Session/   Session state, modes, Now Playing integration
  Audio/     Engine, synth voices, DSP primitives, shared parameters
```

## Building

Requires macOS 27, Xcode with Swift 6, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
open Entrain.xcodeproj
```

Build and run the `Entrain` scheme. The app has no Dock icon; look for the waveform in the menu bar.

## Caveats

Entrainment effects vary widely between people and the evidence is mixed. Treat this as a pleasant background sound with a rhythm, not a medical device. Keep the volume moderate, and don't use it while driving.
