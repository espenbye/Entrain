# Entrain

A Mac, iPhone, iPad and Apple Watch app that plays a generated soundscape with rhythmic amplitude modulation, tuned to nudge your brain toward a target state. No audio files, no network. Everything is synthesized in real time. On the Mac it lives in the menu bar.

## Modes

| For                | Mode       | Rate                  | Depth  | Intended state                     |
| ------------------ | ---------- | --------------------- | ------ | ---------------------------------- |
| Deep work          | Focus      | 16 Hz                 | 0.5    | Alert, task-oriented               |
| Memory and learning | Recall    | 40 Hz                 | 0.3    | Alert; 40 Hz steady-state response |
| Unwind             | Relax      | 10 Hz                 | 0.4    | Calm, unwinding                    |
| Stillness          | Meditate   | 6 Hz                  | 0.5    | Deep, inward attention             |
| Fall asleep        | Sleep      | 2 Hz                  | 0.3 → 0 over 20 min | Drifting off          |
| Stay asleep        | Deep Sleep | 1 Hz                  | 0.15 → 0.5 per sleep cycle | Slow-wave sleep |
| Ease toward bed    | Wind Down  | 10 → 2 Hz over the timer | 0.4    | Bedtime, alpha down to delta       |
| Gentle rise        | Wake       | 2 → 16 Hz over the timer | 0.5    | After a nap, delta back up to beta |

The player leads with the first column: someone choosing a sound is choosing what they are about to do, not which steady-state response they would like driven, so the task is the heading and the state name sits under it. Recall is the one mode named for its task rather than its band — "Gamma" asks the reader to know what a frequency band is, and 40 Hz is a line away in the player's "Why this works" disclosure, which shows every mode's rate, its deepest modulation and one line on why it is that way. The stored names never move: `gamma` is still what shortcuts, Focus filters, `entrain://` URLs and the synced settings are written in, so nothing anyone saved breaks over a label.

Each mode sets the modulation rate and depth. On top of that you pick:

- **Sound**: any combination of Rain, Pad, Drone and Noise, remembered per mode. Focus and Wind Down start on Rain, Gamma, Relax, Meditate and Wake on Pad. A mix is scaled so it sits at the level of a single sound.
- **Intensity**: Low, Medium, High, Strong (scales modulation depth). Medium is right for most people; Strong exists for the listener who under-responds to ordinary background sound and finds the quiet version does nothing at all. It stops at 1.45× rather than going further because roughness grows with depth, and the envelope tests hold every mode, at every rate it passes through and every intensity it can be played at, under the roughness of Gamma's own 40 Hz sine. Entrain asks about this once on first launch, in one skippable question about how background sound works for you, and the answer sets the default; Settings shows the same setting afterwards, in the same words
- **Timer**: Endless, 15 to 90 minutes, or 2, 4 or 8 hours. A timed session fades out when it ends. Pausing keeps the countdown; it resumes where it stopped.
- **Binaural**: optional binaural beat at the same rate. It needs headphones: over speakers the app says so and mutes the beat until headphones come back, leaving the setting on
- **Follow the Day**: off by default. On, the session walks the day by itself, moving between modes without stopping the sound; see Adaptive below
- **Volume**: an app-level volume on top of the system level, so the soundscape can sit under music or a call

Gamma is shallow on purpose: 40 Hz is the most reproducible rate for driving a steady-state response on EEG, but at ordinary depth it sounds like a buzz.

Wind Down and Wake ramp their rate linearly over play time, then hold; pausing stops the clock, and switching mode restarts it. A timed session ramps over the whole timer: Wake arrives at 16 Hz as the timer ends, Wind Down at 2 Hz as its five-minute taper begins, so a 30-minute Wind Down walks 10 to 2 Hz in 25 minutes. Endless sessions ramp over 20 minutes (Wind Down) and 15 (Wake). Wind Down starts on Rain and tapers over the last five minutes of a timed session like the sleep modes; Wake starts on Pad.

Meditate can guide the breath. Pick a breathing pattern and a length in the session card: Coherent (5 in, 5 out), Box (4-4-4-4), 4-7-8 or Long Exhale (4 in, 6 out), for 1, 3, 5 or 10 minutes or the whole session. While it runs, a circle in the player swells over the inhale, holds and shrinks over the exhale, naming the phase and counting its seconds, and a short tone marks each phase: rising to breathe in, steady to hold, falling to breathe out, with a longer note when the exercise is over. A timed exercise rounds to whole breaths, and the soundscape keeps playing after it ends. Pausing, or changing the pattern or length, starts the exercise over from the first breath. The pattern and length sync between devices like the mode.

The two sleep modes play a fixed noise bed, brown with a little pink over it so it masks voices and traffic as well as rumble, ignore intensity and the adaptive inputs, and taper over the last five minutes of a timed session instead of stopping. Both walk an arc over the night instead of holding still. The first stretch is the onset, sized to how long a healthy adult takes to fall asleep — twenty minutes, or the sleeper's own figure where Health knows it: the bed starts brighter and at full level, and settles to a darker bed a few decibels down, where it stays. Sleep adds a little 2 Hz modulation at the start and lets it fade to nothing over the onset, so there is something to follow while awake and a steady bed once asleep. Deep Sleep swells the bed once a second, the slow-oscillation rate that rhythmic sound studies use to deepen slow-wave sleep, but follows the ninety-minute sleep cycle: shallow at the start, deepest around the forty-fifth minute of each cycle where slow-wave sleep peaks, and shallow again toward the REM end of it, so it never pushes all night; the cycle is counted from sleep onset rather than from the tap that started the sound, so it waits out the onset first. Every mode's behaviour over time is one keyframe table in `Arc.swift` — time, rate, depth, brightness, level — compiled to a curve per channel and blended with a raised cosine, except the rate ramps, which are linear in hertz. A keyframe names only the channels that move at that time, so Deep Sleep's ninety-minute depth cycle and the onset before it sit in the same table without either bending the other. The arc runs on play time, like the rate ramps: pausing holds it, and switching mode starts it over. When the Mac goes to sleep the session pauses, so it does not resume on wake.

Sleep, Deep Sleep and Wind Down open with the same short signature, a low note sinking an octave over a few seconds, and nothing else in the app ever plays it. A sound that reliably comes right before sleep becomes a cue for it after a few nights, the way a fixed bedtime routine does, so the signature never changes and never appears in the daytime modes.

Settings persist between launches, and the mode, sound, intensity, timer, binaural, volume and Follow the Day sync between devices through iCloud; each device still keeps its own session, so a change on the phone does not start the Mac (though one that is playing hears it). Play/pause works from the menu bar menu, from Shortcuts and Siri ("Start Focus in Entrain", "Stop Entrain"), from a desktop or Notification Center widget, from `entrain://` URLs, and optionally from a system-wide ⌃⌥E shortcut. Shortcuts can also set the timer, intensity, volume and binaural beats, and ask for the current state ("What is Entrain playing"): mode, whether it is playing, the sound, the seconds left, intensity and binaural, so an automation can branch on them.

Entrain is a Focus filter. In a Focus's settings (Work, Sleep, ...) add the Entrain filter and pick a mode and optionally a length; the mode starts when the Focus turns on. "Stop when this Focus turns off" pauses the session when the Focus ends. With no mode the Focus leaves the session alone. The small widget shows the mode, sound and countdown with a play/pause button; the medium one adds a button per mode. A second widget shows Your Day: the ring, the phase you are in and, at medium, the next one and when it starts. Control Center offers a toggle per mode, lit while that mode plays. The media keys work through Now Playing, which shows the mode's symbol on its tint as artwork and the timer's progress; it can be turned off so the media keys stay with the music Entrain is sitting under. The app can show in the Dock and launch at login; both are off by default. The UI is in English and Norwegian.

For Raycast, Alfred and shell scripts, the app answers `entrain://` URLs on Mac, iPhone and iPad, using the same mode and length values as the intents:

```
open "entrain://play?mode=focus&length=30"
open entrain://pause
open entrain://toggle
```

## Adaptive

**Your Day.** The second tab on iPhone and iPad — a clock button opposite the gear on the Mac, whose window is two columns wide and has no tab bar to put anything in — shows the day Entrain is already reading, as a twenty-four hour ring: one arc per stretch, in that stretch's mode colour, midnight at the top, a marker at now, and ticks for the sun — or, where Health has a settled signature, for this person's own bedtime and wake instead. The six phases are the six branches `Suggestion` already has, named — Morning, Midday, Afternoon, the Wind-Down Window, Night and Before Waking — each with a line on what the body is doing through it. There is deliberately no seventh: a post-lunch dip at wake plus seven hours, or a temperature minimum two hours before it, would be a second table in a second file saying almost what the first says, and the two would drift the first time either was touched. `CircadianDay` samples `Suggestion` forward at the same five-minute step `Program` walks it and collects equal neighbours into spans, so the ring and the mode the program plays cannot disagree — one opinion, two ways of reading it.

There is a widget for it too, in the Home Screen sizes, on the Lock Screen and on the watch face. The widget computes nothing: its process has neither HealthKit nor Core Location, so the day it worked out alone would be a worse day than the app's. `DayPublisher` writes a snapshot and the widget reads it, exactly as `WidgetState` already works for the session. That snapshot holds times of day rather than dates, because a widget outlives the launch that fed it — an extension drawing on a morning the app has not opened yet would otherwise hold yesterday's dates and put the marker off the end of the ring, whereas what the day is made of moves slowly enough that a snapshot a few days stale is still right to within minutes. From one snapshot the widget builds an entry per phase boundary, a dozen at most, so the ring turns without the app being involved again, and reloads at midnight for tomorrow's sun.

It is a tab rather than a button because a corner button reads as an accessory to what is on screen, and the day is not an accessory to the player: one screen is this session, the other is the twenty-four hours the session sits in.

A phase is not a mode. On a day well below this person's own baseline the morning is still the morning; it is simply suggested as Relax, and a ring that collapsed the two would report a body with no morning at all, so both are carried and the list shows both. Tapping a stretch starts its mode, sleep beds included: a tap is exactly the deliberate step the program refuses to take on its own.

It is not a score, and it does not pretend to be a measurement. Nothing on a wrist can measure circadian phase. Entrain measures the two things that set it and track it — when you actually sleep, and how much daylight you got — and estimates the rest from the sun, which the screen says in as many words rather than letting a ring imply otherwise.

**Follow the Day.** One switch in the player, on the watch and in the menu bar turns the mode into something the app can choose. The schedule is the same `Suggestion` the player already offers as a tap — the solar day, the habitual bedtime from Health and the strain signals — read forward rather than asked once, so there is no second opinion in a second file to drift from the first. It is not a ninth mode: it is a session-level program that owns the mode over time, so the modes, the intents, the widget, the Focus filter and `entrain://` are untouched by it.

The program will not put anyone to bed. Walking Focus to Relax changes the background; starting an eight-hour sleep bed at eleven at night unasked is a different promise, so where the day says Sleep the program holds Wind Down and names the bed it is holding back — the last step into bed stays a tap. Wake is not held: it is a fifteen-minute ramp out of a nap, not a night.

Picking a mode by hand ends the program — here, in Shortcuts, from a widget, from a Focus filter or on another device — and the switch goes off with it. The other reading, an override the program quietly took back at the next boundary, is invisible state: you would have no way to tell how long your own choice was going to last.

A transition is meant not to be caught happening. The room cross-fades and the key glides as they do for any mode change, audio never stops, and the modulation rate walks from where the outgoing mode left it to the incoming mode's over three minutes rather than stepping — under a hertz a minute for every pair of modes the day puts next to each other. That walk is `RateGlide` in `Arc.swift`, next to the ramps, because it is the same kind of thing they are. The program runs as one task that sleeps until the next boundary rather than polling, and it runs only while something is playing: pausing holds it like everything else holds, and no clock or sensor of its own runs while paused. The switch survives relaunch and syncs with the other settings.

On top of the mode, inputs shape the sound while it plays. Each input is one module that yields a small adjustment; the session composes them onto the mode's own parameters, and none runs while the session is paused.

**Health.** On iPhone, iPad and Apple Watch, Entrain reads Health as well as writing to it. It only ever reads; the mindful-minutes write is unchanged.

_Sleep._ The last fourteen nights become a bedtime signature: the habitual bedtime and wake time, and how long this person takes to fall asleep. Health is not a tidy record of nights — a watch writes staged sleep, a phone writes time in bed from the Sleep Focus, a third-party app may write its own take on the same hours, and all three overlap — so each night is reduced to the account of the single source that recorded most of it, and the others are dropped rather than summed. Wakenings in the middle are not sleep and do not bound the night; time in bed is not sleep either and only supplies the onset latency; naps are separate episodes and too short to count; a night with nothing recorded is absent rather than a night of no sleep. Bedtimes are averaged around the clock face, so half past eleven and half past midnight average to midnight and not to noon. That signature replaces sunset and sunrise as the two edges of the night: Wind Down opens three hours before the habitual bedtime instead of three hours after sunset, and Wake covers the two hours before the habitual wake. It is used only where it says something — five nights or more, bedtimes within two hours of each other, and an evening-to-morning shape — and the sleep arc uses the measured onset latency in place of the twenty-minute average. The daylight hours keep the sun. Without it, which is what a Mac, a fresh install and a refusal all look like, everything works exactly as before.

_Resting heart rate and variability._ Both are baselined against this person's own last sixty days, the window iOS's own Vitals uses, and exposed as a deviation in standard deviations rather than an absolute number: 48 bpm is a runner's ordinary morning and a warning in someone else. Variability is baselined on the log, since SDNN is right-skewed and a proportional change is what "down 20 %" means for it. Fourteen days of history are needed before anything is published at all. There is no recovery score: the signal is exposed and the adaptive layer decides what to do with it, which is one thing and only over the two work modes — on a day more than one and a half standard deviations below your own variability, or that far above your own resting heart rate, the morning and midday suggestions become Relax instead of Focus and Gamma. Nothing else moves; an unusual day is no reason to change what a night should sound like. Settings shows what was read.

_Daylight._ Time in daylight, which the watch writes from its ambient light sensor, is the one signal here that is a cause rather than a consequence: light is what sets circadian phase, while sleep timing and resting heart rate only track what the clock and the night before did to the body. It is baselined against this person's own sixty days like the other two, but summed over the day rather than averaged — averaging the samples would report the length of a typical walk rather than how long the day was spent outside — and a day of zero minutes is a real reading rather than a gap, so it is not filtered out as one. Nothing acts on it. It is shown in Settings with the figure beside the deviation, because "twenty minutes more tomorrow" is a thing a person can do and 48 bpm is not, and it is shown in Your Day. `Suggestion.isStrained` names its two metrics and is not widened by this one.

_Bedtime regularity._ Two figures fall out of nights already read, and neither costs another query. How far the bedtimes scatter is the circular standard deviation the signature already computes to decide whether it is settled at all. How far the middle of sleep moves between working nights and free ones is social jetlag (Wittmann et al. 2006) — a body kept on one schedule five nights and another two is doing a small time-zone change every week. Mid-sleep, not bedtime: a late night that still ends at an alarm has moved the middle half as far as its bedtime suggests. Both means are circular, so 03:40 and 04:20 are forty minutes apart and not twenty-three hours. Free nights are taken to be Friday and Saturday, which is an assumption a weekend worker breaks, so the figure is shown in Your Day and never acted on.

_Live heart rate (watch)._ During a Meditate or Relax session the watch can run a mind and body workout session to keep the heart sensor streaming, and compare the reading against the breathing pattern: breathing moves heart rate, most strongly around six breaths a minute where the Coherent pattern sits, so a listener on the pace shows a heart swinging with the cue. It is off by default because it costs battery, it saves no workout, and it changes nothing about the sound — a workout session delivers a heart rate only every few seconds, which is enough to say "in phase" and nowhere near enough to steer anything with.

Health asks for permission the first time a mode that ends in bed starts, and on the watch the first time a Meditate or Relax session runs with Heart Rate on — the moments where reading is obviously the point. It asks once and fails silently: HealthKit deliberately never tells an app whether a read was allowed, so a refusal and an empty Health store are the same thing here, and both simply leave the signals empty.

**Daylight.** The carrier is brighter and the modulation a little deeper through the morning, warmer and shallower after sunset: the voice filters move up to half an octave, the depth up to a fifth. The arc is measured against sunrise and sunset, so a winter afternoon already sounds like evening and the same mode never sounds identical across a day. Off, the day is assumed to run 7 to 19. With the Daylight switch on, sunrise and sunset are computed on the device from one approximate location fix, a tenth of a degree, kept in defaults and refreshed once per launch; nothing is sent anywhere. The system asks for location the first time the switch goes on. Above the polar circles the day is clamped between four and twenty hours around solar noon. The sleep beds ignore the inputs and walk their own arc.

## Haptics

The amplitude LFO that swells the bed also drives a continuous Core Haptics event, so the beat felt through the mattress or at the wrist is the same waveform as the beat heard: strongest where the bed is loudest, silent half a cycle later, and scaled by the mode's own modulation depth, so Sleep's haptics fade out over the onset exactly as its modulation does. The phase comes from the audio render clock rather than a timer of its own, published once per render block by the voice that leads the bed, so over a ninety-minute session touch cannot drift away from sound. Only the resolution of the taps is the driver's: `sendParameters` takes locks and has no business on the render thread, so a task sends them about once per audio block.

Haptics run only where the beat is slow enough for the actuator to resolve a cycle, four hertz and under. Gamma at 40 Hz would alias into a flat buzz and goes without; Wind Down picks the haptics up as its rate ramp crosses down into delta, and Wake drops them as it climbs back out. Reduce Motion turns them off, an unmodulated bed sends nothing and releases the engine with it, and the Haptics switch is on by default on the iPhone and the watch. Core Haptics does not exist on watchOS, so the watch taps once a cycle with `WKHapticType` instead.

## iPhone, iPad and Apple Watch

The same session, synth and intents run on every platform; the shell differs, and the watch skips the effects chain (see below). On iPhone and iPad the player window is the app, playback continues in the background, and the widget comes in Home Screen sizes, as Lock Screen accessories and as Control Center toggles. Entrain blends under music and podcasts by default. The "Lock Screen Controls" toggle is the Mac's Now Playing toggle under another name: on, Entrain takes the Lock Screen and Control Center playback controls and pauses other audio, because iOS gives those controls only to an app that does not mix. A timed session also shows a Live Activity on the Lock Screen and in the Dynamic Island: the mode, its sound, the time left counting down and a play/pause button. Pausing freezes the countdown and says so; the activity goes when the timer ends. Endless sessions get none, and the watch shows the phone's in its Smart Stack. A phone call pauses the session; when the call ends and the system says to resume, it picks up where it stopped. An interruption that ends without that, or a stop of your own, leaves it paused. On iPhone, iPad and the watch, each stretch of Meditate play a minute or longer is logged to Health as mindful minutes; Health asks for permission the first time Meditate starts. Those platforms also read sleep, resting heart rate and heart rate variability back out of Health; see Adaptive above.

Wake has an alarm on iPhone and iPad, built on AlarmKit. Pick a time, optionally some weekdays, and switch it on; it rings through silent mode and Focus like a Clock alarm. With no days it rings once at the next occurrence and shows a Live Activity counting down until then, with a Cancel button. With days it repeats weekly, and the system re-arms it after each ring. The alarm's Start Wake button opens Entrain and plays the ramp, for 30 minutes when the timer is endless; Dismiss just silences it. It needs the alarm permission the first time.

The watch app is embedded in the iPhone app but plays on its own, through paired headphones: it uses the long-form audio policy so the session continues with the wrist down, and asks which headphones to use when none are connected. The Smart Stack widget shows the mode and countdown with a play/pause button; the corner and inline ones open the app. The watch has no environment node and no reverb or EQ units, so it cannot place a source in a room at all. Rather than leave it flat, the bed passes through a small diffuser on the way to the mixer: a pre-delay into two allpasses per ear, at lengths that share no factors between the two, which decorrelates the channels and puts a short scatter behind the bed for four multiply-adds a sample. It is not a reverb and does not pretend to be one, but it gives the watch somewhere for the sound to be, and it follows the same per-mode wetness the room does elsewhere. Each device keeps its own session; only the settings sync between the phone and the watch. Volume on the watch is the Digital Crown in the system Now Playing view.

## How it works

The engine is created on first play, so a login item does not touch audio hardware at launch. It runs on a dedicated render thread and only reads control values through atomics, so the UI never touches the audio path. Modulation is confined to the 200 Hz to 1 kHz band: the bass stays steady and the highs (rain droplets, pad harmonics) do not flutter. The shape of each modulation cycle belongs to the mode. Focus, Gamma and Wake drop the gain sharply and let it recover over the rest of the cycle, so every cycle carries a transient to lock to instead of the wobble a symmetric swell gives; Relax, Meditate and Wind Down stay close to a plain sine, and the sleep beds are one exactly. A sharp onset spreads the modulation over harmonics of the rate, and those land in the band around 70 Hz the ear hears as rough, so how sharp a mode can go depends on where its rate sits. The tests hold every mode under the roughness of Gamma's own 40 Hz sine, which is the roughest modulation the app has ever played. Each soundscape also sits at its own point in that cycle — Pad opposite Rain, Drone a quarter turn along — so two layers never fall together. The clocks stay shared, so a rate change still lands identically on all four; only where each one lands in the turn differs. With two layers on, the bed's overall level moves less than either layer's does alone, and what you hear is the emphasis rotating between them rather than one louder pulse. The modulation rate is fixed; instead the texture drifts slowly, one filter and pan cycle every 15 minutes, to counter habituation. All transitions (play, pause, switching soundscapes) ramp over roughly a second to avoid clicks. If the output device changes mid-session (headphones plugged in, a display with speakers connected), the engine restarts itself; if it cannot, the session stops and says so rather than showing Pause over silence.

The pad and the drone share a key, and which key belongs to the mode. Work gets fourths and fifths with no third in them, so there is nothing to read as happy or sad and little of the pad lands where speech does; rest and waking get a major pentatonic; what ends in bed keeps a minor one, low and narrow. The drone holds the tonic and the pad walks the scale an octave above it, so the two can no longer sit a fourth apart by accident. Changing mode fades each pad voice out and back one after another rather than all four at once, and glides the drone over two seconds, so the key changes without a gap and without a click.

The room is part of the mode too. Focus and Gamma are heard in a small room with almost nothing coming back, so no reflection arrives late enough to pull at attention; Relax, Meditate and Wind Down are larger and further away, where a sound has somewhere to go; the sleep beds are drier than any of them, so nothing swims. Changing mode cross-fades the room instead of cutting to it, and when the room itself changes rather than just its level, the send is taken down to silence, swapped underneath, and brought back up, since a reverb preset cannot be blended into another.

Rain falls as impacts rather than pings. Each drop is a short burst of noise through a two-pole resonator, which lands as a click coloured by whatever it fell on; a sine is the one thing a raindrop never sounds like. One heavy-tailed draw sets the drop's level, its pitch and how long it lasts together, because a fat drop is louder, lower and longer for the same physical reason, and a second draw loosens that so it does not read as a single knob being turned — about 18 dB between the finest drop and the fattest. The arrival rate drifts every few seconds as well, so the fall thickens and thins instead of ticking. Eight drops can sound at once, from a pool that is allocated when the voice is built and never grows; past that the fall simply skips one, which is what a downpour does to your hearing anyway.

The four soundscapes are trimmed to the same K-weighted loudness (-22 LUFS, ITU-R BS.1770) so switching does not invite a volume change. The test target renders each voice offline and fails if one drifts more than 1 LU from the target, so touching a voice means re-running the tests and adjusting `Trim` in `Voices.swift`.

```
Sources/
  App/       One entry point per platform: macOS (MenuBarExtra, global shortcut), iOS, watchOS
  UI/        PlayerScreen and DayScreen (Mac window, iPhone, iPad), the two iOS tabs in RootTabs, and the pieces the watch reuses; the menu bar menu under macOS/, the watch screen under watchOS/
  Session/   Session state, modes, App Intents, entrain:// URL commands, Now Playing and widget snapshot
  Audio/     Engine, audio session, synth voices, DSP primitives, shared parameters
  Adaptive/  Inputs that shape the sound while it plays: the daylight arc, the sun behind it, the suggested mode, the day's phases and the program that walks it
  Haptics/   The modulation as touch: the LFO to intensity mapping and the Core Haptics player behind it
  Health/    Reads from HealthKit: the bedtime signature, the resting-heart-rate and variability baselines, live heart rate on the watch
Resources/   Asset catalog and the English/Norwegian string catalogs
Widget/      WidgetKit extension built once per platform; shares Mode, Intents and WidgetState with the app
iOS/, watchOS/  Generated Info.plist and entitlements for those targets
Tests/       Loudness, synth, session, program and Health-reduction tests (Swift Testing, run on macOS)
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

On iOS and watchOS the snapshot lives in the `group.no.espenbye.entrain` App Group instead, so device builds there need a development team; simulator builds do not. App Review rejects the path exception, so a Mac App Store archive signs with the App Group entitlements in `AppStore/` instead, and the app then uses the group container at runtime. The iCloud key-value store needs a paid team the same way (personal teams cannot provision it), so on every platform only the `AppStore/` entitlements carry it: a development build keeps its settings to itself, an archive signed with them syncs:

```sh
xcodebuild -project Entrain.xcodeproj -scheme Entrain -configuration Release archive \
  CODE_SIGN_ENTITLEMENTS='AppStore/$(TARGET_NAME).entitlements'
```

Session logic is tested against a fake engine and a throwaway defaults suite; `Session` takes both in its initializer. CI runs the full test suite on macOS and builds the iOS and watch apps on every push and pull request, with code signing disabled.

## Releasing

`Scripts/release.sh` archives a Release build signed with a Developer ID certificate, submits it to Apple's notary service, staples the ticket and zips the result. It needs `DEVELOPMENT_TEAM` in the environment and notarytool credentials stored under the `entrain` keychain profile.

## Caveats

Entrainment effects vary widely between people and the evidence is mixed. Treat this as a pleasant background sound with a rhythm, not a medical device. Keep the volume moderate, and don't use it while driving.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
