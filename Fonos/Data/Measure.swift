import SwiftUI

/// Measures that come from the weekly Speech check (tasks and self-report).
enum CheckMetric: String, CaseIterable, Identifiable, Codable {
    case mpt, breathGroup, fatigue
    case hnr
    case amrRate, smrRate, ddkRegularity
    case readingRate
    case selfSpeech, selfSalivation, selfSwallowing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mpt: "Longest “ahh”"
        case .breathGroup: "Syllables per breath"
        case .fatigue: "Reading stamina"
        case .hnr: "Voice clarity"
        case .amrRate: "“pa-pa-pa” speed"
        case .smrRate: "“pa-ta-ka” speed"
        case .ddkRegularity: "“pa-ta-ka” evenness"
        case .readingRate: "Reading rate"
        case .selfSpeech: "Your speech rating"
        case .selfSalivation: "Your saliva rating"
        case .selfSwallowing: "Your swallowing rating"
        }
    }

    /// Clinical name, used in the clinic summary.
    var reportName: String {
        switch self {
        case .mpt: "Max. phonation time"
        case .breathGroup: "Breath group length"
        case .fatigue: "Reading fatigue"
        case .hnr: "Harmonics-to-noise"
        case .amrRate: "AMR rate (pa)"
        case .smrRate: "SMR rate (pa-ta-ka)"
        case .ddkRegularity: "SMR irregularity"
        case .readingRate: "Reading rate"
        case .selfSpeech: "Speech (self)"
        case .selfSalivation: "Salivation (self)"
        case .selfSwallowing: "Swallowing (self)"
        }
    }

    var unit: String {
        switch self {
        case .mpt: "s"
        case .breathGroup: "syl"
        case .fatigue: "dB"
        case .hnr: "dB"
        case .amrRate, .smrRate, .readingRate: "syl/s"
        case .ddkRegularity: "% CV"
        case .selfSpeech, .selfSalivation, .selfSwallowing: "of 4"
        }
    }

    var reportUnit: String {
        switch self {
        case .breathGroup: "syl/group"
        case .fatigue: "dB, last − first third"
        case .ddkRegularity: "% CV of intervals"
        case .selfSpeech, .selfSalivation, .selfSwallowing: "0–4"
        default: unit
        }
    }

    var icon: Icon {
        switch self {
        case .mpt, .breathGroup, .fatigue: .breath
        case .hnr: .variation
        case .amrRate, .smrRate, .ddkRegularity: .ddk
        case .readingRate: .pace
        case .selfSpeech, .selfSalivation, .selfSwallowing: .checklist
        }
    }

    var higherIsBetter: Bool { self != .ddkRegularity }

    var explanation: String {
        switch self {
        case .mpt:
            "How long you can hold “ahh” on one breath. It reflects breath support and how well the vocal folds close."
        case .breathGroup:
            "How many syllables you read between pauses. Fewer syllables per breath can mean breath support is changing."
        case .fatigue:
            "How much your voice weakens from the start to the end of the reading passage. Values near 0 mean steady stamina; more negative means your voice tires."
        case .hnr:
            "How clear and steady your voice sounds on a held “ahh”. Higher means a clearer, less breathy or rough voice."
        case .amrRate:
            "How quickly you can repeat “pa”. It reflects how fast your lips can move."
        case .smrRate:
            "How quickly you can repeat “pa-ta-ka”. It reflects how well your lips and tongue work together."
        case .ddkRegularity:
            "How even the timing of your “pa-ta-ka” syllables is. Lower is more even."
        case .readingRate:
            "Syllables per second while reading the same passage each week, not counting pauses."
        case .selfSpeech, .selfSalivation, .selfSwallowing:
            "Your own rating from the weekly check, from 4 (normal) to 0. The questions are based on the bulbar items of the ALSFRS-R, a scale ALS clinics use."
        }
    }

    var howMeasured: String {
        switch self {
        case .mpt: "Longest voicing in the “ahh” task, gaps under 150 ms bridged"
        case .breathGroup: "Syllables divided by (pauses of 250 ms or more + 1)"
        case .fatigue: "Voiced level, last third minus first third of the reading"
        case .hnr: "Autocorrelation peak of the steady part of “ahh”"
        case .amrRate, .smrRate: "Syllable peaks in 6 s of repetition"
        case .ddkRegularity: "Spread of the gaps between “pa-ta-ka” syllables"
        case .readingRate: "Syllable peaks over speaking time, pauses of 250 ms or more removed"
        case .selfSpeech, .selfSalivation, .selfSwallowing: "Your answer in the weekly check"
        }
    }

    var reportDefinition: String {
        switch self {
        case .mpt: "Longest sustained /a/, gaps < 150 ms bridged."
        case .breathGroup: "Syllables per breath group in the reading passage (pauses ≥ 250 ms)."
        case .fatigue: "Voiced mic level, last third minus first third of the reading."
        case .hnr: "Mean harmonics-to-noise ratio of the steady part of /a/, from autocorrelation."
        case .amrRate: "Alternating motion rate: /pa/ syllables per second over 6 s."
        case .smrRate: "Sequential motion rate: /pataka/ syllables per second over 6 s."
        case .ddkRegularity: "Coefficient of variation of /pataka/ syllable intervals."
        case .readingRate: "Syllables per second of speaking time in a fixed passage, pauses ≥ 250 ms removed."
        case .selfSpeech, .selfSalivation, .selfSwallowing: "Patient self-rating, 0–4, modeled on ALSFRS-R bulbar items (paraphrased)."
        }
    }

    func value(_ c: SpeechCheckRecord) -> Double? {
        switch self {
        case .mpt: c.mpt
        case .breathGroup: c.syllablesPerBreathGroup
        case .fatigue: c.fatigueDb
        case .hnr: c.hnr
        case .amrRate: c.amrRate
        case .smrRate: c.smrRate
        case .ddkRegularity: c.smrRegularity
        case .readingRate: c.readingRate
        case .selfSpeech: c.selfReport.map { Double($0.speech) }
        case .selfSalivation: c.selfReport.map { Double($0.salivation) }
        case .selfSwallowing: c.selfReport.map { Double($0.swallowing) }
        }
    }

    func format(_ v: Double) -> String {
        switch self {
        case .selfSpeech, .selfSalivation, .selfSwallowing: String(format: "%.0f", v)
        case .amrRate, .smrRate, .readingRate: String(format: "%.1f", v)
        default: String(format: "%.1f", v)
        }
    }

    func reportFormat(_ v: Double) -> String {
        switch self {
        case .selfSpeech, .selfSalivation, .selfSwallowing: String(format: "%.1f", v)
        case .amrRate, .smrRate, .readingRate: String(format: "%.2f", v)
        default: String(format: "%.1f", v)
        }
    }
}

/// Any measure the app tracks: from conversation sessions or from the weekly check.
enum Measure: Hashable, Identifiable {
    case session(Metric)
    case check(CheckMetric)

    var id: String {
        switch self {
        case .session(let m): "s." + m.rawValue
        case .check(let c): "c." + c.rawValue
        }
    }

    var title: String {
        switch self { case .session(let m): m.title; case .check(let c): c.title }
    }
    var reportName: String {
        switch self { case .session(let m): m.reportName; case .check(let c): c.reportName }
    }
    var unit: String {
        switch self { case .session(let m): m.unit; case .check(let c): c.unit }
    }
    var reportUnit: String {
        switch self { case .session(let m): m.reportUnit; case .check(let c): c.reportUnit }
    }
    var icon: Icon {
        switch self { case .session(let m): m.icon; case .check(let c): c.icon }
    }
    var higherIsBetter: Bool {
        switch self { case .session(let m): m.higherIsBetter; case .check(let c): c.higherIsBetter }
    }
    var explanation: String {
        switch self { case .session(let m): m.explanation; case .check(let c): c.explanation }
    }
    var howMeasured: String {
        switch self { case .session(let m): m.howMeasured; case .check(let c): c.howMeasured }
    }
    var reportDefinition: String {
        switch self { case .session(let m): m.reportDefinition; case .check(let c): c.reportDefinition }
    }
    func format(_ v: Double) -> String {
        switch self { case .session(let m): m.format(v); case .check(let c): c.format(v) }
    }
    func reportFormat(_ v: Double) -> String {
        switch self { case .session(let m): m.reportFormat(v); case .check(let c): c.reportFormat(v) }
    }

    var isCheck: Bool { if case .check = self { true } else { false } }

    /// Measures whose values sit near zero or on a short ordinal scale are
    /// compared by absolute difference; a percentage of them means nothing
    /// (−0.8 dB to −2.4 dB is not "down 200%").
    var changeIsAbsolute: Bool {
        if case .check(let c) = self { return [.fatigue, .selfSpeech, .selfSalivation, .selfSwallowing].contains(c) }
        return false
    }

    /// Change treated as day-to-day variation: ±5% for relative measures,
    /// 1 dB for reading stamina, half a point for the 0–4 ratings.
    var steadyBand: Double {
        guard changeIsAbsolute, case .check(let c) = self else { return 0.05 }
        return c == .fatigue ? 1 : 0.5
    }

    /// Scale that puts an absolute change on roughly the same footing as a
    /// relative one when ranking which change to headline: 2 dB of stamina
    /// or half a rating point counts like 20% or 12.5%.
    var severityScale: Double {
        guard changeIsAbsolute, case .check(let c) = self else { return 1 }
        return c == .fatigue ? 10 : 4
    }

    var color: Color {
        switch self {
        case .session(let m): m.color
        case .check: SpeechSystem.of(self).color
        }
    }

    /// Where the values come from, in plain words.
    var sourceLabel: String {
        switch self {
        case .session: "From conversation"
        case .check(let c): [.selfSpeech, .selfSalivation, .selfSwallowing].contains(c) ? "Your weekly rating" : "From the weekly check"
        }
    }

    /// Weekly checks have fewer points, so the baseline uses the first 3, not 5.
    var baselineCount: Int {
        switch self { case .session: 5; case .check: 3 }
    }

    /// Window for "recent" in trend wording: a week of sessions, two weekly checks.
    var recentDays: Int {
        switch self { case .session: 7; case .check: 14 }
    }

    func series(sessions: [SessionRecord], checks: [SpeechCheckRecord], baseline: Baseline?) -> [ClinicReport.Point] {
        switch self {
        case .session(let m):
            return sessions.sorted { $0.date < $1.date }
                .compactMap { s in m.value(s, baseline: baseline).map { ClinicReport.Point(date: s.date, value: $0) } }
        case .check(let c):
            return checks.sorted { $0.date < $1.date }
                .compactMap { r in c.value(r).map { ClinicReport.Point(date: r.date, value: $0) } }
        }
    }

    /// Mean of the first `baselineCount` points; needs at least 2 (checks) or 3 (sessions).
    func baselineValue(_ pts: [ClinicReport.Point]) -> Double? {
        let need = self.baselineCount == 5 ? 3 : 2
        guard pts.count >= need else { return nil }
        let first = pts.prefix(baselineCount).map(\.value)
        return first.reduce(0, +) / Double(first.count)
    }

    /// Why the change might matter, in gentle plain language, for the Progress headline.
    var lowerHeadlineBody: String {
        switch self {
        case .session(let m):
            switch m {
            case .pace: "You're speaking a little more slowly than in your first sessions. Fonos adjusts automatically, and slower speech often translates more accurately."
            case .strength: "Your voice is vibrating less strongly than at your baseline. Speaking in shorter phrases and resting between them can help the band pick up more of each word."
            case .pauses: "There's more silence between your sounds than at your baseline. Fonos waits for you, so there's no need to rush."
            case .symmetry: "One side of your throat is vibrating more than the other compared with your baseline. Check that the band sits centered and both sensors touch your skin."
            case .steadiness: "Your pitch varies more from moment to moment than at your baseline. This is worth mentioning at your next clinic visit."
            case .clarity: "Fonos is less confident about your words than in your first sessions. Recording a few practice phrases can help."
            }
        case .check(let c):
            switch c {
            case .mpt, .breathGroup: "Your breath support in the weekly check is lower than at your baseline. Your care team may want to know about this."
            case .fatigue: "Your voice tires more over the reading passage than it used to. Resting your voice before long conversations can help."
            case .hnr: "Your held “ahh” sounds less clear than at your baseline. This is worth mentioning at your next clinic visit."
            case .amrRate, .smrRate, .ddkRegularity: "Your syllable repetitions are slower or less even than at your baseline. Your speech therapist can tell you what this means for you."
            case .readingRate: "You're reading the weekly passage more slowly than at first. That's fine; speaking at a comfortable pace helps people understand you."
            case .selfSpeech, .selfSalivation, .selfSwallowing: "Your own weekly rating has changed. Share this with your care team at your next visit."
            }
        }
    }
}

/// The five groups clinicians use to describe speech in ALS.
enum SpeechSystem: String, CaseIterable, Identifiable {
    case breathing, voice, articulation, rhythm, selfReport

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breathing: "Breathing"
        case .voice: "Voice"
        case .articulation: "Articulation"
        case .rhythm: "Rhythm and intelligibility"
        case .selfReport: "Your own rating"
        }
    }

    var summary: String {
        switch self {
        case .breathing: "Breath support for speech."
        case .voice: "How the vocal folds vibrate."
        case .articulation: "How quickly and evenly lips and tongue move."
        case .rhythm: "Speaking rate, pauses, and how well Fonos understands you."
        case .selfReport: "How you rate speech, saliva, and swallowing each week."
        }
    }

    /// Title in the clinic report, written for a clinician.
    var reportTitle: String { self == .selfReport ? "Self-report" : title }

    /// Where the system's measures come from, for the report's group rows.
    var reportNote: String {
        switch self {
        case .breathing: "Sustained /a/, reading passage, conversation level"
        case .voice: "Sustained /a/, conversation pitch, piezo balance"
        case .articulation: "Diadochokinetic tasks"
        case .rhythm: "Reading passage, conversation, translator"
        case .selfReport: "Weekly self-rating, 4 = normal, 0 = most affected"
        }
    }

    var color: Color {
        switch self {
        case .breathing: Theme.pauses
        case .voice: Theme.strength
        case .articulation: Theme.pace
        case .rhythm: Theme.clarity
        case .selfReport: Theme.symmetry
        }
    }

    var measures: [Measure] {
        switch self {
        case .breathing: [.check(.mpt), .check(.breathGroup), .check(.fatigue), .session(.strength)]
        case .voice: [.check(.hnr), .session(.steadiness), .session(.symmetry)]
        case .articulation: [.check(.amrRate), .check(.smrRate), .check(.ddkRegularity)]
        case .rhythm: [.check(.readingRate), .session(.pace), .session(.pauses), .session(.clarity)]
        case .selfReport: [.check(.selfSpeech), .check(.selfSalivation), .check(.selfSwallowing)]
        }
    }

    static func of(_ m: Measure) -> SpeechSystem {
        allCases.first { $0.measures.contains(m) } ?? .rhythm
    }
}

/// Relative change of the recent mean against baseline, for any measure.
struct MeasureTrend: Identifiable {
    let measure: Measure
    let recent: Double
    let baseline: Double
    /// Relative change, or the absolute difference for `changeIsAbsolute` measures.
    let change: Double
    var id: String { measure.id }

    var direction: Trend.Direction {
        guard abs(change) >= measure.steadyBand else { return .steady }
        return (change > 0) == measure.higherIsBetter ? .better : .lower
    }

    /// For choosing the headline across measures of different kinds.
    var severity: Double { abs(change) / measure.severityScale }

    var phrase: String {
        guard direction != .steady else { return "\(measure.title) is steady" }
        let amount = measure.changeIsAbsolute
            ? "\(measure.format(abs(change))) \(measure.unit == "of 4" ? "point\(measure.format(abs(change)) == "1" ? "" : "s")" : measure.unit)"
            : "\(Int((abs(change) * 100).rounded()))%"
        return "\(measure.title) is \(change > 0 ? "up" : "down") \(amount)"
    }

    static func compute(_ m: Measure, sessions: [SessionRecord], checks: [SpeechCheckRecord],
                        baseline: Baseline?, now: Date = .now) -> MeasureTrend? {
        let pts = m.series(sessions: sessions, checks: checks, baseline: baseline)
        guard let b = m.baselineValue(pts), m.changeIsAbsolute || b != 0 else { return nil }
        let cutoff = Calendar.current.date(byAdding: .day, value: -m.recentDays, to: now)!
        let recent = pts.filter { $0.date >= cutoff && $0.date <= now }.map(\.value)
        guard !recent.isEmpty else { return nil }
        let r = recent.reduce(0, +) / Double(recent.count)
        return MeasureTrend(measure: m, recent: r, baseline: b,
                            change: m.changeIsAbsolute ? r - b : (r - b) / abs(b))
    }
}
