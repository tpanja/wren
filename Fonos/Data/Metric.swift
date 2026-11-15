import SwiftUI

/// The six measures, with how each is read, colored, and explained.
enum Metric: String, CaseIterable, Identifiable, Codable {
    case clarity, strength, pace, symmetry, steadiness, pauses

    var id: String { rawValue }

    /// The three headline rings.
    static let rings: [Metric] = [.clarity, .strength, .pace]

    var title: String {
        switch self {
        case .clarity: "Clarity"
        case .strength: "Strength"
        case .pace: "Pace"
        case .symmetry: "Symmetry"
        case .steadiness: "Pitch variation"
        case .pauses: "Pauses"
        }
    }

    var icon: Icon {
        switch self {
        case .clarity: .clarity
        case .strength: .strength
        case .pace: .pace
        case .symmetry: .symmetry
        case .steadiness: .variation
        case .pauses: .pauses
        }
    }

    var color: Color {
        switch self {
        case .clarity: Theme.clarity
        case .strength: Theme.strength
        case .pace: Theme.pace
        case .symmetry: Theme.symmetry
        case .steadiness: Theme.steadiness
        case .pauses: Theme.pauses
        }
    }

    var unit: String {
        switch self {
        case .clarity, .strength, .symmetry, .pauses: "%"
        case .pace: "syl/s"
        case .steadiness: "% var"
        }
    }

    /// Whether a higher number is the better direction, for trend wording.
    var higherIsBetter: Bool {
        switch self {
        case .steadiness, .pauses: false
        default: true
        }
    }

    var explanation: String {
        switch self {
        case .clarity:
            "How confidently Fonos understood your words, averaged across what you said. It reflects the translator as well as your speech, so it can change when the translator is updated."
        case .strength:
            "How loudly your throat vibrates while you speak, compared with your first sessions. 100% means the same strength as your baseline."
        case .pace:
            "Syllables per second while you are actually speaking. Typical conversational speech is around 4 to 5."
        case .symmetry:
            "How evenly the left and right sides of your throat vibrate, from the two piezo sensors. 100% means both sides are equal."
        case .steadiness:
            "How much your pitch wobbles from one moment to the next. Lower numbers mean a steadier voice."
        case .pauses:
            "The share of your speaking time that is silent between sounds."
        }
    }

    var howMeasured: String {
        switch self {
        case .clarity: "Translator confidence, per phrase"
        case .strength: "Contact microphone level, voiced frames only"
        case .pace: "Syllable peaks in the microphone envelope"
        case .symmetry: "Left vs right piezo vibration energy"
        case .steadiness: "Pitch tracked from the contact microphone"
        case .pauses: "Silent frames between first and last sound"
        }
    }

    /// The value shown to the user for a session, in this metric's unit.
    func value(_ s: SessionRecord, baseline: Baseline?) -> Double? {
        switch self {
        case .clarity: s.clarity.map { $0 * 100 }
        case .strength:
            // Percent of baseline amplitude (dB difference → linear ratio).
            baseline.map { 100 * pow(10, (s.strengthDb - $0.strengthDb) / 20) } ?? 100
        case .pace: s.pace
        case .symmetry: s.symmetry.map { $0 * 100 }
        case .steadiness: s.pitchVariation
        case .pauses: s.pauseRatio * 100
        }
    }

    /// 0...1 fill for a ring.
    func ringFill(_ value: Double) -> Double {
        switch self {
        case .pace: min(value / 5, 1)
        case .steadiness: min(max(1 - value / 10, 0), 1)
        default: min(max(value / 100, 0), 1)
        }
    }

    func format(_ value: Double) -> String {
        switch self {
        case .pace: value.formatted(.number.precision(.fractionLength(1)))
        case .steadiness: value.formatted(.number.precision(.fractionLength(1)))
        default: value.formatted(.number.precision(.fractionLength(0)))
        }
    }
}
