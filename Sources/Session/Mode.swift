import SwiftUI

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
    var depth: Double {
        switch self {
        case .focus: 0.5
        case .relax: 0.4
        case .meditate: 0.5
        case .sleep: 0.7
        }
    }

    /// Binaural carrier frequency in Hz for the left ear. Right ear is carrier + rate.
    var carrier: Double { self == .sleep ? 100 : 200 }

    var tint: Color {
        switch self {
        case .focus: .orange
        case .relax: .teal
        case .meditate: .purple
        case .sleep: .indigo
        }
    }

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

    var multiplier: Double {
        switch self {
        case .low: 0.6
        case .medium: 1.0
        case .high: 1.4
        }
    }
}

enum Soundscape: String, CaseIterable, Identifiable {
    case rain, pad, drone

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
}
