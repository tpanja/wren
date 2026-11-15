import SwiftUI

enum MetricGroup: String, CaseIterable, Identifiable {
    case pitch, vibrato, loudness, tone, throat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pitch: "Pitch"
        case .vibrato: "Vibrato"
        case .loudness: "Loudness and breath"
        case .tone: "Tone"
        case .throat: "Throat vibration"
        }
    }
}

/// Every measure in Docs/SPEC.md § 5.
enum MetricID: String, CaseIterable, Identifiable, Codable, Sendable {
    case pitchAccuracy, pitchError, sustainStability, onsetSettle, onsetExcursion, range
    case vibratoRate, vibratoExtent, vibratoRegularity
    case dynamicRange, levelStability, phraseDuration
    case hnr, ring, jitter
    case throatVibration, lrSymmetry, vibrationToSound, larynxRise
    case speakingPitch

    var id: String { rawValue }

    enum Better { case higher, lower, nearZero, none }
    enum Status { case established, exploratory }

    /// The three headline rings.
    static let rings: [MetricID] = [.pitchAccuracy, .sustainStability, .range]

    var title: String {
        switch self {
        case .pitchAccuracy: "In tune"
        case .pitchError: "How far off"
        case .sustainStability: "Steady notes"
        case .onsetSettle: "Landing the note"
        case .onsetExcursion: "Scoops and overshoots"
        case .range: "Range"
        case .vibratoRate: "Vibrato speed"
        case .vibratoExtent: "Vibrato width"
        case .vibratoRegularity: "Even vibrato"
        case .dynamicRange: "Volume control"
        case .levelStability: "Steady volume"
        case .phraseDuration: "Breath length"
        case .hnr: "Clear tone"
        case .ring: "Ring"
        case .jitter: "Roughness"
        case .throatVibration: "Throat vibration"
        case .lrSymmetry: "Even both sides"
        case .vibrationToSound: "Effort for the sound"
        case .larynxRise: "Larynx rising"
        case .speakingPitch: "Speaking pitch"
        }
    }

    var technicalTitle: String {
        switch self {
        case .pitchAccuracy: "Pitch accuracy"
        case .pitchError: "Mean pitch error"
        case .sustainStability: "Sustain stability"
        case .onsetSettle: "Onset settling time"
        case .onsetExcursion: "Onset pitch excursion"
        case .range: "Comfortable range"
        case .vibratoRate: "Vibrato rate"
        case .vibratoExtent: "Vibrato extent"
        case .vibratoRegularity: "Vibrato regularity"
        case .dynamicRange: "Dynamic range"
        case .levelStability: "Sustain level stability"
        case .phraseDuration: "Phrase duration"
        case .hnr: "Harmonics-to-noise ratio"
        case .ring: "Singer's formant energy"
        case .jitter: "Pitch jitter"
        case .throatVibration: "Neck surface vibration"
        case .lrSymmetry: "Left/right symmetry"
        case .vibrationToSound: "Vibration-to-sound ratio"
        case .larynxRise: "Laryngeal elevation"
        case .speakingPitch: "Habitual speaking F0"
        }
    }

    func name(technical: Bool) -> String { technical ? technicalTitle : title }

    var group: MetricGroup {
        switch self {
        case .pitchAccuracy, .pitchError, .sustainStability, .onsetSettle, .onsetExcursion, .range, .speakingPitch: .pitch
        case .vibratoRate, .vibratoExtent, .vibratoRegularity: .vibrato
        case .dynamicRange, .levelStability, .phraseDuration: .loudness
        case .hnr, .ring, .jitter: .tone
        case .throatVibration, .lrSymmetry, .vibrationToSound, .larynxRise: .throat
        }
    }

    var status: Status {
        switch self {
        case .lrSymmetry, .vibrationToSound, .larynxRise: .exploratory
        default: .established
        }
    }

    /// Shown at the beginner coaching level; the rest only with Technical detail.
    var isBeginner: Bool {
        switch self {
        case .pitchAccuracy, .sustainStability, .onsetSettle, .range, .vibratoRate, .levelStability,
             .phraseDuration, .hnr, .throatVibration, .lrSymmetry: true
        default: false
        }
    }

    var better: Better {
        switch self {
        case .pitchAccuracy, .phraseDuration, .hnr, .ring, .range, .lrSymmetry, .dynamicRange: .higher
        case .sustainStability, .onsetSettle, .vibratoRegularity, .levelStability, .jitter, .vibrationToSound, .larynxRise: .lower
        case .pitchError, .onsetExcursion: .nearZero
        case .vibratoRate, .vibratoExtent, .throatVibration, .speakingPitch: .none
        }
    }

    var icon: Icon {
        switch self {
        case .pitchAccuracy, .pitchError: .tune
        case .sustainStability, .levelStability: .steady
        case .onsetSettle, .onsetExcursion: .onset
        case .range: .range
        case .vibratoRate, .vibratoExtent, .vibratoRegularity: .vibrato
        case .dynamicRange: .strength
        case .phraseDuration: .breath
        case .hnr, .ring, .jitter: .tone
        case .throatVibration, .vibrationToSound, .larynxRise: .band
        case .lrSymmetry: .symmetry
        case .speakingPitch: .speak
        }
    }

    /// Whether this measure has its own hue (ring metrics and their family).
    var hasHue: Bool {
        switch self {
        case .pitchAccuracy, .pitchError, .sustainStability, .vibratoRate, .vibratoExtent, .vibratoRegularity, .range: true
        default: false
        }
    }

    /// Ring metrics carry their own hue; every other measure is ink with its icon.
    var color: Color {
        switch self {
        case .pitchAccuracy, .pitchError: Theme.tune
        case .sustainStability, .vibratoRate, .vibratoExtent, .vibratoRegularity: Theme.steady
        case .range: Theme.rangeHue
        default: Theme.ink
        }
    }

    /// Unit as displayed.
    var unit: String {
        switch self {
        case .pitchAccuracy, .lrSymmetry, .vibratoRegularity, .jitter: "%"
        case .pitchError, .sustainStability, .onsetExcursion, .vibratoExtent: "cents"
        case .onsetSettle: "ms"
        case .range: "semitones"
        case .vibratoRate: "Hz"
        case .dynamicRange, .levelStability, .hnr, .ring: "dB"
        case .phraseDuration: "s"
        case .throatVibration: "% of usual"
        case .vibrationToSound, .larynxRise: "× usual"
        case .speakingPitch: ""
        }
    }

    var shortUnit: String {
        switch self {
        case .range: "st"
        case .throatVibration: "%"
        case .vibrationToSound, .larynxRise: "×"
        default: unit
        }
    }

    /// Converts a stored raw value into what the singer sees. Throat measures
    /// are relative to the singer's own baseline.
    func display(_ raw: Double, baseline: Double?) -> Double {
        switch self {
        case .throatVibration:
            guard let b = baseline, b > 0 else { return 100 }
            return raw / b * 100
        case .vibrationToSound, .larynxRise:
            guard let b = baseline, b > 0 else { return 1 }
            return raw / b
        default:
            return raw
        }
    }

    func format(_ v: Double) -> String {
        switch self {
        case .vibratoRate, .phraseDuration, .vibrationToSound, .larynxRise, .hnr, .ring, .dynamicRange, .levelStability, .jitter:
            return v.formatted(.number.precision(.fractionLength(1)))
        case .speakingPitch:
            return Music.name(Int(v.rounded()))
        case .pitchError, .onsetExcursion:
            let n = Int(v.rounded())
            return n > 0 ? "+\(n)" : "\(n)"
        default:
            return v.formatted(.number.precision(.fractionLength(0)))
        }
    }

    /// Ring score (0...100) for the three headline metrics.
    func ringScore(_ v: Double) -> Double {
        switch self {
        case .pitchAccuracy: min(max(v, 0), 100)
        case .sustainStability: min(max((40 - v) / 35, 0), 1) * 100
        case .range: min(max(v / 24, 0), 1) * 100
        default: 0
        }
    }

    /// Value inside a ring (In tune %, Steady %, Range semitones).
    func ringLabel(_ v: Double) -> (value: String, unit: String) {
        switch self {
        case .pitchAccuracy: (format(v), "%")
        case .sustainStability: (Int(ringScore(v).rounded()).formatted(), "%")
        case .range: (format(v), "st")
        default: (format(v), shortUnit)
        }
    }

    var ringTitle: String {
        switch self {
        case .pitchAccuracy: "In tune"
        case .sustainStability: "Steady"
        case .range: "Range"
        default: title
        }
    }

    var explanation: String {
        switch self {
        case .pitchAccuracy: "How much of the time your voice sits within a quarter of a semitone of the target note, once you've landed it."
        case .pitchError: "Your average distance from the target. Negative means flat, positive means sharp."
        case .sustainStability: "How much your pitch wanders on held notes, with vibrato taken out. Lower is steadier; the Steady ring turns this into a score."
        case .onsetSettle: "How long it takes to land on a note and stay there."
        case .onsetExcursion: "How far you start from the note: a scoop from below or an overshoot from above. Sometimes a style choice in pop and jazz."
        case .range: "The span between the lowest and highest notes you held in tune for at least half a second."
        case .vibratoRate: "How fast your vibrato pulses. Around 5 to 7 per second is typical in classical singing; many styles use little or none."
        case .vibratoExtent: "How wide your vibrato swings above and below the note."
        case .vibratoRegularity: "How evenly your vibrato pulses from cycle to cycle. Lower is more even."
        case .dynamicRange: "The span between your softest and loudest singing in a take."
        case .levelStability: "How steady your volume stays on held notes."
        case .phraseDuration: "Your longest stretch of continuous singing in a take."
        case .hnr: "How clear your tone is compared with breathy noise. Higher is clearer."
        case .ring: "Energy in the 2–4 kHz band that helps a voice carry."
        case .jitter: "Tiny moment-to-moment pitch roughness on held notes."
        case .throatVibration: "How strongly your throat vibrates while singing, compared with your usual."
        case .lrSymmetry: "How evenly both sides of your throat vibrate. Mostly a check that the band fits well."
        case .vibrationToSound: "How much throat vibration you use for the sound you make, compared with your usual. Rising may mean extra effort."
        case .larynxRise: "How much your larynx lifts while singing, compared with your usual."
        case .speakingPitch: "The middle of your normal speaking pitch, from the speaking-voice check."
        }
    }

    var howMeasured: (text: String, sensors: [Icon]) {
        switch group {
        case .pitch where self == .speakingPitch: ("Microphone and accelerometers while you speak", [.mic, .accelLeft])
        case .pitch: ("Pitch from the microphone, cross-checked with the accelerometers", [.mic, .accelLeft, .accelRight])
        case .vibrato: ("Pitch movement on held notes, from the microphone", [.mic])
        case .loudness: ("Microphone level while you sing", [.mic])
        case .tone: ("Microphone spectrum on held notes", [.mic])
        case .throat: ("Both throat accelerometers", [.accelLeft, .accelRight])
        }
    }

    static let exploratoryNote = "Fonos is still testing how well this measure matches what voice teachers hear, so it's shown for interest and never chosen as your focus."
}
