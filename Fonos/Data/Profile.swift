import Foundation
import Observation

enum CoachingLevel: String, CaseIterable, Identifiable, Codable {
    case beginner, technical
    var id: String { rawValue }
    var title: String { self == .beginner ? "Beginner" : "Technical detail" }
}

enum VoiceType: String, CaseIterable, Identifiable, Codable {
    case notSure, soprano, mezzo, alto, tenor, baritone, bass
    var id: String { rawValue }
    var title: String {
        switch self {
        case .notSure: "Not sure"
        case .soprano: "Soprano"
        case .mezzo: "Mezzo-soprano"
        case .alto: "Alto"
        case .tenor: "Tenor"
        case .baritone: "Baritone"
        case .bass: "Bass"
        }
    }
}

enum SingingGoal: String, CaseIterable, Identifiable, Codable {
    case inTune, stronger, widerRange, steadier, vibrato, justForFun
    var id: String { rawValue }
    var title: String {
        switch self {
        case .inTune: "Sing in tune"
        case .stronger: "Stronger voice"
        case .widerRange: "Wider range"
        case .steadier: "Steadier notes"
        case .vibrato: "Vibrato"
        case .justForFun: "Just for fun"
        }
    }
    /// Snake-case name for the feedback payload.
    var payloadName: String {
        switch self {
        case .inTune: "in_tune"
        case .stronger: "stronger"
        case .widerRange: "wider_range"
        case .steadier: "steadier"
        case .vibrato: "vibrato"
        case .justForFun: "just_for_fun"
        }
    }
}

/// The singer's settings. Stored on the device only.
@Observable
final class Profile {
    private let d = UserDefaults.standard

    var level: CoachingLevel { didSet { d.set(level.rawValue, forKey: "fonos.level") } }
    var voiceType: VoiceType { didSet { d.set(voiceType.rawValue, forKey: "fonos.voiceType") } }
    var goals: Set<SingingGoal> { didSet { d.set(goals.map(\.rawValue), forKey: "fonos.goals") } }
    /// Comfortable range used to pitch exercises (MIDI).
    var rangeLow: Int { didSet { d.set(rangeLow, forKey: "fonos.rangeLow") } }
    var rangeHigh: Int { didSet { d.set(rangeHigh, forKey: "fonos.rangeHigh") } }
    /// Consent: personal feedback with Claude. Off until the singer turns it on.
    var llmFeedback: Bool { didSet { d.set(llmFeedback, forKey: "fonos.llm") } }
    var useGoalsInFeedback: Bool { didSet { d.set(useGoalsInFeedback, forKey: "fonos.useGoals") } }
    var referenceTone: Bool { didSet { d.set(referenceTone, forKey: "fonos.refTone") } }
    var countIn: Bool { didSet { d.set(countIn, forKey: "fonos.countIn") } }
    var tuneHaptics: Bool { didSet { d.set(tuneHaptics, forKey: "fonos.haptics") } }
    var saveTakes: Bool { didSet { d.set(saveTakes, forKey: "fonos.saveTakes") } }
    var onboarded: Bool { didSet { d.set(onboarded, forKey: "fonos.onboarded") } }

    var isTechnical: Bool { level == .technical }
    var range: ClosedRange<Int> { rangeLow...max(rangeLow + 12, rangeHigh) }

    init() {
        level = CoachingLevel(rawValue: d.string(forKey: "fonos.level") ?? "") ?? .beginner
        voiceType = VoiceType(rawValue: d.string(forKey: "fonos.voiceType") ?? "") ?? .notSure
        goals = Set((d.stringArray(forKey: "fonos.goals") ?? ["inTune", "steadier"]).compactMap(SingingGoal.init))
        rangeLow = d.object(forKey: "fonos.rangeLow") as? Int ?? 43
        rangeHigh = d.object(forKey: "fonos.rangeHigh") as? Int ?? 66
        llmFeedback = d.bool(forKey: "fonos.llm")
        useGoalsInFeedback = d.bool(forKey: "fonos.useGoals")
        referenceTone = d.object(forKey: "fonos.refTone") as? Bool ?? true
        countIn = d.object(forKey: "fonos.countIn") as? Bool ?? true
        tuneHaptics = d.object(forKey: "fonos.haptics") as? Bool ?? true
        saveTakes = d.bool(forKey: "fonos.saveTakes")
        onboarded = d.bool(forKey: "fonos.onboarded")
    }
}
