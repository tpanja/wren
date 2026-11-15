import Foundation

/// Rule-based coach. Produces the same feedback shape as the LLM, instantly
/// and offline. Its priority order and drill mapping mirror the LLM prompt
/// (Docs/LLM-FEEDBACK.md § 3) so both coaches agree on what matters.
enum LocalCoach {

    /// Candidate focuses in priority order, with when each is worth working on.
    private struct Rule {
        let metric: MetricID
        let needsWork: (Double, Double?) -> Bool
        let drill: String
    }

    private static let rules: [Rule] = [
        Rule(metric: .pitchAccuracy, needsWork: { v, b in v < 80 || (b.map { v < $0 - 3 } ?? false) }, drill: "five_note_slow"),
        Rule(metric: .onsetExcursion, needsWork: { v, _ in abs(v) > 25 }, drill: "target_and_hold"),
        Rule(metric: .sustainStability, needsWork: { v, _ in v > 12 }, drill: "lip_trill_slide"),
        Rule(metric: .onsetSettle, needsWork: { v, _ in v > 150 }, drill: "target_and_hold"),
        Rule(metric: .levelStability, needsWork: { v, _ in v > 2.5 }, drill: "messa_di_voce"),
        Rule(metric: .hnr, needsWork: { v, _ in v < 12 }, drill: "hum_to_vowel"),
        Rule(metric: .phraseDuration, needsWork: { v, _ in v < 6 }, drill: "breath_four_count"),
        Rule(metric: .vibratoRegularity, needsWork: { v, _ in v > 20 }, drill: "messa_di_voce"),
    ]

    static func feedback(for take: TakeRecord, store: TakeStore, level: CoachingLevel) -> Feedback {
        let technical = level == .technical
        func v(_ m: MetricID) -> Double? { store.display(m, in: take) }
        func b(_ m: MetricID) -> Double? { store.baseline(m).map { m.display($0, baseline: store.baseline(m)) } }

        // Weak signal: say so and coach on fit, nothing else.
        if take.quality.overall == .low {
            return Feedback(
                headline: "Let's check the band fit",
                summary: take.quality.advice ?? "The signal was weak this take, so feedback is limited.",
                wins: [],
                focus: .init(metric: MetricID.lrSymmetry.payloadName,
                             observation: "Fonos couldn't measure this take reliably.",
                             why: "A snug, centered band lets Fonos hear and feel your voice.",
                             drillId: "hum_to_vowel", drillSteps: Drill.library["hum_to_vowel"]!.steps),
                nextTarget: .init(metric: MetricID.lrSymmetry.payloadName, target: 85, unit: "%"),
                technicalNote: nil, confidence: "low")
        }

        if take.kind == .speakingCheck {
            let pitch = v(.speakingPitch).map { Music.name(Int($0.rounded())) } ?? "–"
            return Feedback(
                headline: "Speaking voice recorded",
                summary: "Your speaking pitch sits around \(pitch). Fonos uses it to compare how you speak with how you sing.",
                wins: [],
                focus: .init(metric: MetricID.speakingPitch.payloadName,
                             observation: "Singing near your speaking pitch usually feels easiest.",
                             why: "Starting from a comfortable pitch helps you sing without pushing.",
                             drillId: "speak_then_sing", drillSteps: Drill.library["speak_then_sing"]!.steps),
                nextTarget: .init(metric: MetricID.speakingPitch.payloadName, target: v(.speakingPitch) ?? 49, unit: "note"),
                technicalNote: technical ? "Median speaking F0 \(pitch); throat vibration \(v(.throatVibration).map { Int($0) } ?? 100)% of your usual." : nil,
                confidence: take.quality.overall == .good ? "high" : "medium")
        }

        if take.kind == .siren {
            let span = v(.range).map { Int($0) } ?? 0
            let low = take.lowNote.map(Music.name) ?? "–", high = take.highNote.map(Music.name) ?? "–"
            let prev = b(.range).map { Int($0) }
            let better = prev.map { span > $0 } ?? false
            return Feedback(
                headline: better ? "Your range is opening up" : "Warm-up done",
                summary: "You glided from \(low) to \(high), \(span) semitones. Keep sirens gentle; range grows from ease, not force.",
                wins: better ? [.init(metric: MetricID.range.payloadName, observation: "That's wider than your usual \(prev!) semitones.")] : [],
                focus: .init(metric: MetricID.range.payloadName,
                             observation: "The top of the siren is where voices tend to tighten.",
                             why: "Staying easy at the top keeps your range growing safely.",
                             drillId: "sirens_easy", drillSteps: Drill.library["sirens_easy"]!.steps),
                nextTarget: .init(metric: MetricID.range.payloadName, target: Double(span + 1), unit: "semitones"),
                technicalNote: technical ? "Glide span \(low)–\(high) (5th–95th percentile of voiced F0)." : nil,
                confidence: take.quality.overall == .good ? "high" : "medium")
        }

        // Wins: established measures at or better than baseline.
        var wins: [Feedback.Win] = []
        for m in [MetricID.pitchAccuracy, .sustainStability, .onsetSettle, .levelStability, .phraseDuration, .hnr] {
            guard wins.count < 2, let value = v(m), let base = b(m) else { continue }
            let improved: Bool
            switch m.better {
            case .higher: improved = value > base * 1.03
            case .lower: improved = value < base * 0.97
            default: improved = false
            }
            if improved { wins.append(.init(metric: m.payloadName, observation: winText(m, value, base, technical))) }
        }

        // Focus: first rule that needs work; otherwise keep polishing accuracy.
        let rule = rules.first { r in v(r.metric).map { r.needsWork($0, b(r.metric)) } ?? false } ?? rules[0]
        let value = v(rule.metric) ?? 0
        let drill = Drill.library[rule.drill]!
        let focus = Feedback.Focus(metric: rule.metric.payloadName,
                                   observation: focusText(rule.metric, value, take, technical),
                                   why: whyText(rule.metric),
                                   drillId: drill.id, drillSteps: drill.steps)

        let headline: String
        if let first = wins.first, let m = MetricID(payloadName: first.metric) {
            headline = m == .pitchAccuracy ? "More in tune than your usual" : "\(m.title) is improving"
        } else {
            headline = "Good work. One thing to try next"
        }
        let summary = wins.isEmpty
            ? "\(focus.observation) Try the drill, then sing it again."
            : "\(wins[0].observation) Next, one thing to work on: \(rule.metric.title.lowercased())."

        return Feedback(
            headline: headline, summary: summary, wins: wins, focus: focus,
            nextTarget: target(for: rule.metric, value),
            technicalNote: technical ? technicalNote(take, v) : nil,
            confidence: take.quality.overall == .good ? "high" : "medium"
        ).clamped()
    }

    // MARK: Wording

    private static func winText(_ m: MetricID, _ v: Double, _ b: Double, _ technical: Bool) -> String {
        switch m {
        case .pitchAccuracy: "You were in tune \(Int(v))% of the time, up from your usual \(Int(b))%."
        case .sustainStability: technical ? "Held notes wandered \(m.format(v)) cents, steadier than your usual \(m.format(b))." : "Your held notes were steadier than usual."
        case .onsetSettle: technical ? "Notes settled in \(Int(v)) ms, faster than your usual \(Int(b))." : "You landed notes faster than usual."
        case .levelStability: "Your volume stayed steadier on held notes."
        case .phraseDuration: "You sang \(m.format(v)) seconds in one breath, longer than usual."
        case .hnr: "Your tone was clearer than usual."
        default: "\(m.title) improved."
        }
    }

    private static func focusText(_ m: MetricID, _ v: Double, _ take: TakeRecord, _ technical: Bool) -> String {
        let worst = take.worstNotes.first.map { Music.name($0.midi) }
        switch m {
        case .pitchAccuracy:
            let dir = (take.value(.pitchError) ?? 0) < 0 ? "a little flat" : "a little sharp"
            return technical
                ? "Pitch accuracy was \(Int(v))%, averaging \(MetricID.pitchError.format(take.value(.pitchError) ?? 0)) cents\(worst.map { ", worst on \($0)" } ?? "")."
                : "Some notes were \(dir)\(worst.map { ", especially \($0)" } ?? "")."
        case .onsetExcursion:
            return v < 0
                ? (technical ? "Onsets scoop up from about \(Int(-v)) cents below the note." : "Most notes start a little below and slide up into it.")
                : (technical ? "Onsets overshoot by about \(Int(v)) cents." : "Most notes start a little above and settle down.")
        case .sustainStability:
            return technical ? "Held notes wandered \(MetricID.sustainStability.format(v)) cents with vibrato removed." : "Your held notes wobble a little."
        case .onsetSettle:
            return technical ? "Notes took \(Int(v)) ms to settle within ±25 cents." : "Notes take a moment to settle once you start them."
        case .levelStability:
            return "Your volume rises and falls on held notes."
        case .hnr:
            return "Your tone is a little breathy on held notes."
        case .phraseDuration:
            return "You're running out of breath before the end of the phrase."
        case .vibratoRegularity:
            return "Your vibrato is a little uneven."
        default:
            return "\(m.title) has room to grow."
        }
    }

    private static func whyText(_ m: MetricID) -> String {
        switch m {
        case .pitchAccuracy: "Landing in tune is what listeners notice first."
        case .onsetExcursion, .onsetSettle: "Landing right on the note makes the whole line sound more in tune."
        case .sustainStability: "Steady notes sound confident and make vibrato possible later."
        case .levelStability: "Even volume makes held notes sound controlled."
        case .hnr: "A clearer tone carries further with less effort."
        case .phraseDuration: "More breath support lets you finish phrases comfortably."
        case .vibratoRegularity: "An even vibrato sounds relaxed and free."
        default: "Small, steady gains add up."
        }
    }

    private static func target(for m: MetricID, _ v: Double) -> Feedback.Target {
        let t: Double
        switch m {
        case .pitchAccuracy: t = min(95, (v + 5).rounded())
        case .onsetSettle: t = max(120, (v * 0.8 / 10).rounded() * 10)
        case .onsetExcursion: t = v < 0 ? min(-10, (v * 0.7).rounded()) : max(10, (v * 0.7).rounded())
        case .sustainStability: t = max(8, (v - 2).rounded())
        case .levelStability: t = max(1.5, ((v - 0.5) * 10).rounded() / 10)
        case .hnr: t = (v + 2).rounded()
        case .phraseDuration: t = (v + 1).rounded()
        default: t = v
        }
        return .init(metric: m.payloadName, target: t, unit: m.unit)
    }

    private static func technicalNote(_ take: TakeRecord, _ v: (MetricID) -> Double?) -> String {
        var parts: [String] = []
        if let e = take.value(.onsetExcursion), let s = take.value(.onsetSettle) {
            parts.append("Onsets average \(MetricID.onsetExcursion.format(e)) cents with \(Int(s)) ms settling")
        }
        if let rate = take.value(.vibratoRate), let ext = take.value(.vibratoExtent) {
            parts.append("vibrato \(MetricID.vibratoRate.format(rate)) Hz at ±\(Int(ext)) cents")
        }
        if let onset = take.onsetType {
            parts.append("accelerometer onset reads \(onset.rawValue) (exploratory)")
        }
        return parts.isEmpty ? "No technical outliers this take." : parts.joined(separator: "; ") + "."
    }
}
