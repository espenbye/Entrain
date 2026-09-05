import Foundation

enum Mode: String, CaseIterable, Identifiable, Codable, Sendable {
    case focus, gamma, relax, meditate, sleep, deepSleep

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
        }
    }

    /// Modulation rate in Hz. Drives both the amplitude LFO and the binaural beat.
    /// Gamma sits at 40 Hz, the best-replicated auditory steady-state response;
    /// Deep Sleep at the ~1 Hz slow-oscillation rate used in sleep-sound studies.
    var rate: Double {
        switch self {
        case .focus: 16
        case .gamma: 40
        case .relax: 10
        case .meditate: 6
        case .sleep: 2
        case .deepSleep: 1
        }
    }

    /// Amplitude modulation depth at medium intensity, 0...1.
    /// Sleep is unmodulated: a steady bed habituates, which is the goal.
    /// Gamma is shallow because 40 Hz modulation sits in the roughness range
    /// and turns into a buzz at ordinary depth.
    var depth: Double {
        switch self {
        case .focus: 0.5
        case .gamma: 0.3
        case .relax: 0.4
        case .meditate: 0.5
        case .sleep: 0
        case .deepSleep: 0.5
        }
    }

    /// Sleep modes play a fixed noise bed, so soundscape and intensity are
    /// not tunable, and a timed session tapers rather than stops.
    var isSleep: Bool { self == .sleep || self == .deepSleep }

    /// Where a mode starts before the user picks. Steady-state carriers for
    /// Focus, since a walking pad is a mild irrelevant-sound risk while reading.
    /// Gamma starts on the pad: a smooth carrier keeps 40 Hz from sounding rough.
    var defaultLayers: Set<Soundscape> {
        switch self {
        case .focus: [.rain]
        case .gamma, .relax, .meditate: [.pad]
        case .sleep, .deepSleep: [.noise]
        }
    }

    /// Seconds over which a timed session tapers to silence before it ends.
    var fadeOut: Double { isSleep ? 300 : 1 }

    /// Binaural carrier frequency in Hz for the left ear. Right ear is carrier + rate.
    var carrier: Double { isSleep ? 100 : 200 }

    var symbol: String {
        switch self {
        case .focus: "scope"
        case .gamma: "bolt"
        case .relax: "leaf"
        case .meditate: "circle.dotted"
        case .sleep: "moon"
        case .deepSleep: "moon.zzz"
        }
    }
}

enum Intensity: String, CaseIterable, Identifiable {
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
