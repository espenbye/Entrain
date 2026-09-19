import Foundation
import SwiftUI

enum Mode: String, CaseIterable, Identifiable, Codable, Sendable {
    case focus, gamma, sprint, relax, meditate, restore, sleep, deepSleep, nap, windDown, wake

    var id: Self { self }
    var title: String { String(localized: name) }
    /// The state, secondary to what the mode is for. Display only: the raw
    /// values are what shortcuts, Focus filters, `entrain://` URLs and the
    /// synced settings are written in, and they never move. "Gamma" is the
    /// one name here that asked the reader to know what a frequency band is,
    /// so it is called what it is for; the 40 Hz is still a line away, in
    /// `reason`. The same keys as the App Intents display representations,
    /// so one catalog entry covers the menu, the widget and Shortcuts.
    var name: LocalizedStringResource {
        switch self {
        case .focus: "Focus"
        case .gamma: "Recall"
        case .sprint: "Sprint"
        case .relax: "Relax"
        case .meditate: "Meditate"
        case .restore: "Restore"
        case .sleep: "Sleep"
        case .deepSleep: "Deep Sleep"
        case .nap: "Nap"
        case .windDown: "Wind Down"
        case .wake: "Wake"
        }
    }

    /// Sleep modes play a fixed noise bed that walks its own arc over the
    /// night, so soundscape and intensity are not tunable, the adaptive
    /// inputs stay out, and a timed session tapers rather than stops.
    var isSleep: Bool { self == .sleep || self == .deepSleep }

    /// Where a mode starts before the user picks. Steady-state carriers for
    /// Focus, since a walking pad is a mild irrelevant-sound risk while reading.
    /// Gamma starts on the pad: a smooth carrier keeps 40 Hz from sounding rough.
    var defaultLayers: Set<Soundscape> {
        switch self {
        case .focus, .sprint, .windDown: [.rain]
        case .gamma, .relax, .meditate, .restore, .wake: [.pad]
        case .sleep, .deepSleep, .nap: [.noise]
        }
    }

    /// Whether a breathing exercise may run over the mode. The rest shelf,
    /// which is Relax, Meditate and Restore: a paced breath belongs where
    /// the listener is already sitting still with nothing else to do. It
    /// was Meditate alone, which left `HeartRateSection`'s offer to show
    /// the heart through "Meditate and Relax" unreachable in the Relax half.
    /// Not the work modes, where counting a breath is the distraction
    /// Focus exists to keep out, and not the sleep ones, where the point is
    /// to stop paying attention rather than to pay it to a count.
    var guidesBreath: Bool { purpose == .rest }

    /// Whether a stretch of this mode is a mindful session in the sense
    /// Health means. Meditate is the obvious one; Restore is yoga nidra and
    /// non-sleep deep rest, which is the same category and belongs on the
    /// same chart. Relax is not: unwinding with a sound on is not a
    /// practice, and logging it would quietly inflate the figure.
    var isMindful: Bool { self == .meditate || self == .restore }

    /// Whether head tracking may run. Not in bed: rolling over would swing
    /// the room, and the sensors cost power over an eight-hour session. A
    /// nap is lying down too.
    var tracksHead: Bool { !isSleep && self != .windDown && self != .nap }

    /// Whether a timed session tapers over its last minutes rather than
    /// stopping. Wind Down tapers like the sleep modes: its timer ends in bed.
    var tapers: Bool { isSleep || self == .windDown }

    /// Seconds over which a timed session fades to silence before it ends.
    var fadeOut: Double { tapers ? 300 : 1 }

    /// Binaural carrier frequency in Hz for the left ear. Right ear is carrier + rate.
    var carrier: Double { isSleep ? 100 : 200 }

    /// What the mode is for, in a line a first-time user understands
    /// without knowing what 40 Hz does. This is what the player leads with:
    /// somebody choosing a sound is choosing what they are about to do, not
    /// which steady-state response they would like driven.
    var blurb: LocalizedStringResource {
        switch self {
        case .focus: "Deep work"
        case .gamma: "Memory and learning"
        case .sprint: "Work in rounds"
        case .relax: "Unwind"
        case .meditate: "Stillness"
        case .restore: "Rest without sleeping"
        case .sleep: "Fall asleep"
        case .deepSleep: "Stay asleep"
        case .nap: "Short sleep, then up"
        case .windDown: "Ease toward bed"
        case .wake: "Gentle rise"
        }
    }

    /// Why the mode is the way it is, in one line. The reasoning in
    /// `Arc.swift` and `Circadian.swift` is not decoration; a listener who
    /// wants to know why a sound pulses forty times a second should be able
    /// to find out inside the app rather than in the source.
    var reason: LocalizedStringResource {
        switch self {
        case .focus:
            "16 Hz is beta, where alert attention sits. Each cycle drops sharply and recovers, so there is a transient to lock to rather than a wobble."
        case .gamma:
            "40 Hz is the best-replicated rate for driving an auditory steady-state response. It stays shallow because 40 Hz modulation sits in the range the ear hears as roughness, and turns into a buzz at ordinary depth."
        case .sprint:
            "Twenty-five minutes at 16 Hz, five at 10 Hz, and round again. The rate walks down into the break and back up for the next round, so the sound keeps the rhythm of the work instead of a clock doing it."
        case .relax:
            "10 Hz is alpha, the rhythm of a calm and open mind. The swell stays close to a plain sine, so nothing in it pulls at attention."
        case .meditate:
            "6 Hz is theta, the rate of inward attention, and slow enough to breathe along with."
        case .restore:
            "4 Hz is the edge of theta and delta, where the body rests deeply without sleeping: the state a yoga nidra or a non-sleep deep rest aims for. Slow enough to feel as well as hear."
        case .sleep:
            "A little 2 Hz to follow while you are still awake, fading to a steady bed over the time it takes you to fall asleep. Sound that stays busy past onset lifts arousals for the rest of the night."
        case .deepSleep:
            "The bed swells once a second, the slow-oscillation rate, and follows the ninety-minute sleep cycle: deepest around its forty-fifth minute where slow-wave sleep peaks, shallow toward the REM end, so it never pushes all night."
        case .nap:
            "2 Hz to drift on, then delta walked up to beta over the last third of the timer, so the nap ends awake instead of groggy. Keep it under thirty minutes to stay out of deep sleep, or take a full ninety for a whole cycle."
        case .windDown:
            "Alpha walked down to delta over the session, the way an evening should go, arriving in delta as the taper begins."
        case .wake:
            "Delta walked back up to beta, so a nap ends where the day does rather than in a jolt."
        }
    }

    var purpose: Purpose {
        switch self {
        case .focus, .gamma, .sprint: .work
        case .relax, .meditate, .restore: .rest
        case .windDown, .sleep, .deepSleep, .nap, .wake: .sleep
        }
    }

    var symbol: String {
        switch self {
        case .focus: "scope"
        case .gamma: "bolt"
        case .sprint: "timer"
        case .relax: "leaf"
        case .meditate: "circle.dotted"
        case .restore: "figure.mind.and.body"
        case .sleep: "moon"
        case .deepSleep: "moon.zzz"
        case .nap: "powersleep"
        case .windDown: "sunset"
        case .wake: "sunrise"
        }
    }
}

/// What the listener picks in a mode list: a mode, or the day itself. The
/// program is not a `Mode` — it plays one of them — but it sits in the same
/// list because it answers the same question, what should be playing.
enum ModeChoice: Hashable, Sendable {
    case day
    case mode(Mode)

    static let symbol = "sun.horizon"

    /// Every choice in the list, the day last: it is the one that is not a
    /// mode, and putting it after the eleven keeps the modes in the order
    /// everything else draws them in. Twelve also fills a three-across grid
    /// exactly, which is what the widget lays them out on.
    static var all: [ModeChoice] { Mode.allCases.map { ModeChoice.mode($0) } + [ModeChoice.day] }

    /// The name and the symbol, so a list can draw a row without knowing
    /// which of the two kinds it has.
    var title: String {
        switch self {
        case .day: String(localized: "Follow the Day")
        case .mode(let mode): mode.title
        }
    }

    var symbol: String {
        switch self {
        case .day: Self.symbol
        case .mode(let mode): mode.symbol
        }
    }
}

/// The three shelves the modes sit on in the player. Wake is on the sleep
/// shelf as the bookend to Wind Down.
enum Purpose: CaseIterable, Identifiable, Sendable {
    case work, rest, sleep

    var id: Self { self }
    var title: LocalizedStringResource {
        switch self {
        case .work: "Work"
        case .rest: "Rest"
        case .sleep: "Sleep"
        }
    }
    var modes: [Mode] { Mode.allCases.filter { $0.purpose == self } }
}

enum Intensity: String, CaseIterable, Identifiable, Sendable {
    case low, medium, high, strong

    var id: Self { self }
    var title: String {
        switch self {
        case .low: String(localized: "Low")
        case .medium: String(localized: "Medium")
        case .high: String(localized: "High")
        case .strong: String(localized: "Strong")
        }
    }

    /// How a listener answers `Onboarding`, in the same words. The setting
    /// and the first-launch question are one thing, so Settings shows this
    /// under each step rather than a second explanation of its own.
    var blurb: LocalizedStringResource {
        switch self {
        case .low: "Background sound distracts me"
        case .medium: "It sits nicely in the background"
        case .high: "I like it noticeable"
        case .strong: "Quiet backgrounds do nothing for me"
        }
    }

    /// High is a small step above medium: medium depth tested best, and deep
    /// modulation was counterproductive. Strong goes further for the
    /// listener who under-responds to ordinary background sound and finds
    /// the medium version does nothing at all — for them the choice is not
    /// between medium and strong, it is between strong and closing the app.
    /// It stops at 1.45 rather than going on to 1.5 or 2 because roughness
    /// grows with depth: `EnvelopeTests` holds every mode, at every rate it
    /// passes through and every intensity it can be played at, under the
    /// roughness of Gamma's own 40 Hz sine, and 1.45 is where Focus's deep
    /// 16 Hz pulse reaches that ceiling.
    var multiplier: Double {
        switch self {
        case .low: 0.6
        case .medium: 1.0
        case .high: 1.2
        case .strong: 1.45
        }
    }
}

enum Soundscape: String, CaseIterable, Identifiable {
    case rain, pad, drone, noise

    var id: Self { self }
    var title: String {
        switch self {
        case .rain: String(localized: "Rain")
        case .pad: String(localized: "Pad")
        case .drone: String(localized: "Drone")
        case .noise: String(localized: "Noise")
        }
    }
    /// The two that play notes, and so carry the mode's `Tonality`.
    static var tuned: [Soundscape] { [.pad, .drone] }
    var index: Int { Self.allCases.firstIndex(of: self)! }
    var bit: Int { 1 << index }
}

extension Set<Soundscape> {
    var mask: Int { reduce(0) { $0 | $1.bit } }
    /// In display order: "Rain + Pad".
    var title: String { Soundscape.allCases.filter(contains).map(\.title).joined(separator: " + ") }
}

enum SessionLength: Int, CaseIterable, Identifiable, Sendable {
    case endless = 0
    case fifteen = 15
    case thirty = 30
    case sixty = 60
    case ninety = 90
    case twoHours = 120
    case fourHours = 240
    case eightHours = 480

    var id: Self { self }
    var title: String {
        switch self {
        case .endless: String(localized: "Endless")
        case .fifteen, .thirty, .sixty, .ninety: String(localized: "\(rawValue) min")
        case .twoHours, .fourHours, .eightHours: String(localized: "\(rawValue / 60) h")
        }
    }
    var seconds: Int { rawValue * 60 }
}

extension Int {
    /// A countdown in seconds as "14:59", growing to "1:14:59" past an hour.
    var countdown: String {
        Duration.seconds(self).formatted(.time(pattern: self >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }
}

extension Mode {
    /// One colour per mode, cool for the calm end and warm for the alert end.
    var tint: Color {
        switch self {
        case .focus: Color(red: 0.35, green: 0.62, blue: 1.0)
        case .gamma: Color(red: 1.0, green: 0.72, blue: 0.30)
        case .sprint: Color(red: 0.30, green: 0.80, blue: 0.88)
        case .relax: Color(red: 0.45, green: 0.85, blue: 0.62)
        case .meditate: Color(red: 0.72, green: 0.55, blue: 1.0)
        case .restore: Color(red: 0.55, green: 0.72, blue: 0.78)
        case .sleep: Color(red: 0.45, green: 0.50, blue: 0.95)
        case .deepSleep: Color(red: 0.30, green: 0.32, blue: 0.75)
        case .nap: Color(red: 0.65, green: 0.72, blue: 1.0)
        case .windDown: Color(red: 0.95, green: 0.55, blue: 0.50)
        case .wake: Color(red: 1.0, green: 0.85, blue: 0.45)
        }
    }

    /// Text on top of the tint. The warm end is pale enough that white
    /// washes out, so it gets the night blue from the backdrop.
    var onTint: Color {
        switch self {
        case .gamma, .wake, .nap: Color(red: 0.07, green: 0.06, blue: 0.20)
        default: .white
        }
    }
}
