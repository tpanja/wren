import Foundation

/// The feedback card. Same shape whether it comes from the local coach or
/// from Claude via the feedback server (Docs/LLM-FEEDBACK.md § 5).
struct Feedback: Codable, Equatable, Sendable {
    struct Win: Codable, Equatable, Sendable {
        var metric: String
        var observation: String
    }

    struct Focus: Codable, Equatable, Sendable {
        var metric: String
        var observation: String
        var why: String
        var drillId: String
        var drillSteps: [String]
    }

    struct Target: Codable, Equatable, Sendable {
        var metric: String
        var target: Double
        var unit: String
    }

    enum Source: String, Codable, Sendable { case local, claude }

    var headline: String
    var summary: String
    var wins: [Win]
    var focus: Focus
    var nextTarget: Target
    var technicalNote: String?
    var confidence: String
    var source: Source = .local

    enum CodingKeys: String, CodingKey {
        case headline, summary, wins, focus, nextTarget, technicalNote, confidence
    }

    /// Enforce the limits the JSON schema can't express (LLM-FEEDBACK.md § 5).
    func clamped() -> Feedback {
        var f = self
        f.wins = Array(wins.prefix(2))
        f.focus.drillSteps = Array(focus.drillSteps.prefix(4))
        if f.headline.count > 60 { f.headline = String(f.headline.prefix(59)) + "…" }
        if Drill.library[f.focus.drillId] == nil { f.focus.drillId = "target_and_hold" }
        return f
    }

    var focusMetric: MetricID? { MetricID(payloadName: focus.metric) }
    var targetMetric: MetricID? { MetricID(payloadName: nextTarget.metric) }
}

struct Drill: Sendable {
    let id: String
    let name: String
    let steps: [String]

    static let library: [String: Drill] = Dictionary(uniqueKeysWithValues: [
        Drill(id: "lip_trill_slide", name: "Lip-trill slides",
              steps: ["Relax your lips and blow so they buzz.", "Slide gently up five notes and back down.", "Keep the buzz going the whole way."]),
        Drill(id: "hum_to_vowel", name: "Hum to \"ah\"",
              steps: ["Hum the note with your lips closed.", "Open to \"ah\" without changing the pitch.", "Keep the buzz you felt in the hum."]),
        Drill(id: "five_note_slow", name: "Slow five-note scale",
              steps: ["Sing the scale at half speed.", "Pause on each note until it feels settled.", "Then sing it at normal speed."]),
        Drill(id: "target_and_hold", name: "Land and hold",
              steps: ["Hum the target note quietly first.", "Start the note on the hum's pitch, with no slide.", "Hold it for four counts."]),
        Drill(id: "messa_di_voce", name: "Soft–loud–soft",
              steps: ["Start one note softly.", "Grow louder over four counts.", "Fade back to soft over four counts, keeping the pitch."]),
        Drill(id: "straw_phonation", name: "Sing through a straw",
              steps: ["Hum through a drinking straw.", "Glide up and down gently.", "Then sing the phrase without the straw."]),
        Drill(id: "staccato_ah", name: "Light staccato \"ha\"",
              steps: ["Sing short, light \"ha\" sounds on one note.", "Let each one start cleanly, not pushed.", "Do five, rest, repeat."]),
        Drill(id: "sirens_easy", name: "Easy sirens on \"ng\"",
              steps: ["Sing \"ng\" as in \"sing\".", "Glide from low to high and back, softly.", "Go a little higher each time, only while it feels easy."]),
        Drill(id: "breath_four_count", name: "Four-count breath",
              steps: ["Breathe in low for four counts.", "Sing one note while counting slowly.", "Try to add one count each round."]),
        Drill(id: "speak_then_sing", name: "Speak, then sing",
              steps: ["Speak the line on a comfortable pitch.", "Sing it on that same pitch.", "Then sing it with the melody."]),
    ].map { ($0.id, $0) })
}

extension MetricID {
    /// snake_case name used in the feedback payload and schema.
    var payloadName: String {
        switch self {
        case .pitchAccuracy: "pitch_accuracy_pct"
        case .pitchError: "mean_pitch_error_cents"
        case .sustainStability: "sustain_stability_cents"
        case .onsetSettle: "onset_settle_ms"
        case .onsetExcursion: "onset_excursion_cents"
        case .range: "range_semitones"
        case .vibratoRate: "vibrato_rate_hz"
        case .vibratoExtent: "vibrato_extent_cents"
        case .vibratoRegularity: "vibrato_regularity_pct"
        case .dynamicRange: "dynamic_range_db"
        case .levelStability: "sustain_level_sd_db"
        case .phraseDuration: "phrase_duration_s"
        case .hnr: "hnr_db"
        case .ring: "singers_formant_db"
        case .jitter: "jitter_pct"
        case .throatVibration: "throat_vibration_pct_baseline"
        case .lrSymmetry: "lr_symmetry_pct"
        case .vibrationToSound: "vibration_to_sound_ratio_vs_baseline"
        case .larynxRise: "larynx_rise_vs_speaking"
        case .speakingPitch: "speaking_pitch_midi"
        }
    }

    init?(payloadName: String) {
        guard let m = MetricID.allCases.first(where: { $0.payloadName == payloadName }) else { return nil }
        self = m
    }
}
