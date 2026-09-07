import Foundation
import SwiftUI

enum Mode: String, CaseIterable, Identifiable, Codable, Sendable {
    case focus, gamma, relax, meditate, sleep, deepSleep, windDown, wake

    var id: Self { self }
    var title: String { String(localized: name) }
    /// The same keys as the App Intents display representations, so one
    /// catalog entry covers the menu, the widget and Shortcuts.
    var name: LocalizedStringResource {
        switch self {
        case .focus: "Focus"
        case .gamma: "Gamma"
        case .relax: "Relax"
        case .meditate: "Meditate"
        case .sleep: "Sleep"
        case .deepSleep: "Deep Sleep"
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
        case .focus, .windDown: [.rain]
        case .gamma, .relax, .meditate, .wake: [.pad]
        case .sleep, .deepSleep: [.noise]
        }
    }

    /// Whether head tracking may run. Not in bed: rolling over would swing
    /// the room, and the sensors cost power over an eight-hour session.
    var tracksHead: Bool { !isSleep && self != .windDown }

    /// Whether a timed session tapers over its last minutes rather than
    /// stopping. Wind Down tapers like the sleep modes: its timer ends in bed.
    var tapers: Bool { isSleep || self == .windDown }

    /// Seconds over which a timed session fades to silence before it ends.
    var fadeOut: Double { tapers ? 300 : 1 }

    /// Binaural carrier frequency in Hz for the left ear. Right ear is carrier + rate.
    var carrier: Double { isSleep ? 100 : 200 }

    /// What the mode is for, in a line a first-time user understands
    /// without knowing what 40 Hz does.
    var blurb: LocalizedStringResource {
        switch self {
        case .focus: "Deep work"
        case .gamma: "Memory and recall"
        case .relax: "Unwind"
        case .meditate: "Stillness"
        case .sleep: "Fall asleep"
        case .deepSleep: "Stay asleep"
        case .windDown: "Ease toward bed"
        case .wake: "Gentle rise"
        }
    }

    var purpose: Purpose {
        switch self {
        case .focus, .gamma: .work
        case .relax, .meditate: .rest
        case .windDown, .sleep, .deepSleep, .wake: .sleep
        }
    }

    var symbol: String {
        switch self {
        case .focus: "scope"
        case .gamma: "bolt"
        case .relax: "leaf"
        case .meditate: "circle.dotted"
        case .sleep: "moon"
        case .deepSleep: "moon.zzz"
        case .windDown: "sunset"
        case .wake: "sunrise"
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
    case low, medium, high

    var id: Self { self }
    var title: String {
        switch self {
        case .low: String(localized: "Low")
        case .medium: String(localized: "Medium")
        case .high: String(localized: "High")
        }
    }

    /// High is a small step above medium: medium depth tested best, and deep
    /// modulation was counterproductive.
    var multiplier: Double {
        switch self {
        case .low: 0.6
        case .medium: 1.0
        case .high: 1.2
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
        case .relax: Color(red: 0.45, green: 0.85, blue: 0.62)
        case .meditate: Color(red: 0.72, green: 0.55, blue: 1.0)
        case .sleep: Color(red: 0.45, green: 0.50, blue: 0.95)
        case .deepSleep: Color(red: 0.30, green: 0.32, blue: 0.75)
        case .windDown: Color(red: 0.95, green: 0.55, blue: 0.50)
        case .wake: Color(red: 1.0, green: 0.85, blue: 0.45)
        }
    }

    /// Text on top of the tint. The warm end is pale enough that white
    /// washes out, so it gets the night blue from the backdrop.
    var onTint: Color {
        switch self {
        case .gamma, .wake: Color(red: 0.07, green: 0.06, blue: 0.20)
        default: .white
        }
    }
}
