import Foundation

/// One target note in a take, in seconds from the end of the count-in.
struct ScheduledNote: Codable, Hashable, Sendable {
    var midi: Int
    var start: Double
    var duration: Double
    var end: Double { start + duration }
}

/// What the singer is asked to sing for one take.
struct TakePlan: Sendable {
    let kind: ExerciseKind
    let notes: [ScheduledNote]
    /// Siren: the target glides between the notes instead of stepping.
    let glide: Bool
    /// Text to read for the speaking-voice check.
    let script: String?
    let duration: Double

    /// Target pitch (MIDI, fractional for glides) at time `t`, or nil between notes.
    func target(at t: Double) -> Double? {
        if glide, let first = notes.first, let last = notes.last {
            guard t >= first.start, t <= last.end else { return nil }
            // Up over the first half, back down over the second.
            let low = Double(first.midi), high = Double(last.midi)
            let half = (last.end - first.start) / 2
            let x = t - first.start
            return x <= half ? low + (high - low) * x / half : high - (high - low) * (x - half) / half
        }
        return notes.first(where: { t >= $0.start && t < $0.end }).map { Double($0.midi) }
    }

    func note(at t: Double) -> ScheduledNote? {
        notes.first(where: { t >= $0.start && t < $0.end })
    }
}

enum ExerciseKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case siren, fiveNoteScale, sustained, arpeggio, songPhrase, speakingCheck

    var id: String { rawValue }

    var title: String {
        switch self {
        case .siren: "Warm-up siren"
        case .fiveNoteScale: "Five-note scale"
        case .sustained: "Sustained note"
        case .arpeggio: "Arpeggio"
        case .songPhrase: "Song phrase"
        case .speakingCheck: "Speaking-voice check"
        }
    }

    var icon: Icon {
        switch self {
        case .siren: .siren
        case .fiveNoteScale: .scale
        case .sustained: .sustained
        case .arpeggio: .arpeggio
        case .songPhrase: .song
        case .speakingCheck: .speak
        }
    }

    var instruction: String {
        switch self {
        case .siren: "Glide on \"ng\" from low to high and back down, gently."
        case .fiveNoteScale: "Sing each note on \"ah\" and land right on it."
        case .sustained: "Hold one note on \"ah\" as steadily as you can."
        case .arpeggio: "Skip up and down the chord on \"ah\"."
        case .songPhrase: "Sing \"Twinkle, twinkle, little star\" at an easy volume."
        case .speakingCheck: "Read the sentence in your normal speaking voice."
        }
    }

    /// What this exercise is mostly for, shown on its tile.
    var purpose: String {
        switch self {
        case .siren: "Range and easy shifts"
        case .fiveNoteScale: "Landing notes in tune"
        case .sustained: "Steady pitch, breath, tone"
        case .arpeggio: "Intervals"
        case .songPhrase: "Putting it together"
        case .speakingCheck: "Your speaking baseline"
        }
    }

    var isSung: Bool { self != .speakingCheck }

    /// Builds the take, pitched to the singer's comfortable range.
    func plan(range: ClosedRange<Int>) -> TakePlan {
        let low = range.lowerBound, high = range.upperBound
        func sequence(_ key: Int, _ steps: [Int], _ dur: [Double], gap: Double = 0.06) -> [ScheduledNote] {
            var t = 0.0
            return zip(steps, dur).map { step, d in
                defer { t += d + gap }
                return ScheduledNote(midi: key + step, start: t, duration: d)
            }
        }
        switch self {
        case .siren:
            let a = low + 2, b = max(low + 7, high - 2)
            let notes = [ScheduledNote(midi: a, start: 0, duration: 2.5), ScheduledNote(midi: b, start: 2.5, duration: 2.5)]
            return TakePlan(kind: self, notes: notes, glide: true, script: nil, duration: 5.3)
        case .fiveNoteScale:
            let key = min(low + 4, high - 7)
            let steps = [0, 2, 4, 5, 7, 5, 4, 2, 0]
            let notes = sequence(key, steps, Array(repeating: 0.62, count: 8) + [1.4])
            return TakePlan(kind: self, notes: notes, glide: false, script: nil, duration: notes.last!.end + 0.4)
        case .sustained:
            let note = (low + high) / 2 - 1
            let notes = [ScheduledNote(midi: note, start: 0, duration: 5.0)]
            return TakePlan(kind: self, notes: notes, glide: false, script: nil, duration: 5.4)
        case .arpeggio:
            let key = min(low + 3, high - 12)
            let notes = sequence(key, [0, 4, 7, 12, 7, 4, 0], [0.58, 0.58, 0.58, 1.0, 0.58, 0.58, 1.4])
            return TakePlan(kind: self, notes: notes, glide: false, script: nil, duration: notes.last!.end + 0.4)
        case .songPhrase:
            // "Twinkle, Twinkle, Little Star" (traditional, public domain), first phrase.
            let key = min(low + 5, high - 9)
            let notes = sequence(key, [0, 0, 7, 7, 9, 9, 7], [0.55, 0.55, 0.55, 0.55, 0.55, 0.55, 1.3], gap: 0.08)
            return TakePlan(kind: self, notes: notes, glide: false, script: nil, duration: notes.last!.end + 0.4)
        case .speakingCheck:
            return TakePlan(kind: self, notes: [], glide: false,
                            script: "Could you bring the blue notebook and a glass of water from the kitchen?",
                            duration: 5.0)
        }
    }
}
