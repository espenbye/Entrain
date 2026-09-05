import Foundation

enum Mode: String, CaseIterable, Identifiable {
    case focus, relax, meditate, sleep

    var id: Self { self }
    var title: String { rawValue.capitalized }

    /// Modulation rate in Hz. Drives both the amplitude LFO and the binaural beat.
    var rate: Double {
        switch self {
        case .focus: 16
        case .relax: 10
        case .meditate: 6
        case .sleep: 2
        }
    }

    /// Amplitude modulation depth at medium intensity, 0...1.
    /// Sleep is unmodulated: a steady bed habituates, which is the goal.
    var depth: Double {
        switch self {
        case .focus: 0.5
        case .relax: 0.4
        case .meditate: 0.5
        case .sleep: 0
        }
    }

    /// Sleep plays a fixed steady bed, so soundscape and intensity are not tunable.
    var isSteady: Bool { self == .sleep }

    /// Where a mode starts before the user picks. Steady-state carriers for
    /// Focus, since a walking pad is a mild irrelevant-sound risk while reading.
    var defaultSoundscape: Soundscape {
        switch self {
        case .focus: .rain
        case .relax, .meditate: .pad
        case .sleep: .noise
        }
    }

    /// Seconds over which a timed session tapers to silence before it ends.
    var fadeOut: Double { isSteady ? 300 : 1 }

    /// Binaural carrier frequency in Hz for the left ear. Right ear is carrier + rate.
    var carrier: Double { isSteady ? 100 : 200 }

    var symbol: String {
        switch self {
        case .focus: "scope"
        case .relax: "leaf"
        case .meditate: "circle.dotted"
        case .sleep: "moon"
        }
    }
}

enum Intensity: String, CaseIterable, Identifiable {
    case low, medium, high

    var id: Self { self }
    var title: String { rawValue.capitalized }

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
    var title: String { rawValue.capitalized }
    var index: Int { Self.allCases.firstIndex(of: self)! }
}

enum SessionLength: Int, CaseIterable, Identifiable {
    case endless = 0
    case fifteen = 15
    case thirty = 30
    case sixty = 60
    case ninety = 90

    var id: Self { self }
    var title: String { self == .endless ? "Endless" : "\(rawValue) min" }
    var seconds: Int { rawValue * 60 }
}
