import Foundation

/// The four tasks of the weekly Speech check, in the order they run.
/// Each targets one speech subsystem that ALS affects, and each is a task
/// commonly used in bulbar ALS speech assessment.
enum CheckTask: Int, CaseIterable, Identifiable, Codable {
    case breath, amr, smr, passage

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .breath: "Long “ahh”"
        case .amr: "“pa-pa-pa”"
        case .smr: "“pa-ta-ka”"
        case .passage: "Read aloud"
        }
    }

    /// The subsystem it measures, as shown to the user.
    var measures: String {
        switch self {
        case .breath: "Breath support and voice"
        case .amr: "Lip speed"
        case .smr: "Lip and tongue coordination"
        case .passage: "Speaking rate, pauses, and stamina"
        }
    }

    /// Spoken and shown before the task starts.
    var instruction: String {
        switch self {
        case .breath:
            "Take a deep breath, then say “ahh” at a comfortable pitch for as long as you can. Stop when you run out of breath."
        case .amr:
            "Say “pa-pa-pa” as quickly and clearly as you can until Fonos stops you."
        case .smr:
            "Say “pa-ta-ka” over and over, as quickly and clearly as you can, until Fonos stops you."
        case .passage:
            "Read the passage aloud at your usual pace. Tap Done when you finish."
        }
    }

    /// Longest the recording runs before stopping on its own.
    var maxSeconds: Double {
        switch self {
        case .breath: 30
        case .amr, .smr: 6
        case .passage: 60
        }
    }

    /// Whether the task ends on its own when the voice stops.
    var stopsOnSilence: Bool { self == .breath || self == .passage }

    /// What the simulated band does for this task.
    var toyMode: ToyBand.Mode {
        switch self {
        case .breath: .vowel
        case .amr: .ddk(smr: false)
        case .smr: .ddk(smr: true)
        case .passage: .passage
        }
    }

    var icon: Icon {
        switch self {
        case .breath: .breath
        case .amr, .smr: .ddk
        case .passage: .report
        }
    }

    /// An original reading passage (about 75 syllables) with plain words,
    /// a mix of consonants, and natural places to breathe.
    static let passageText = """
    Every morning I open the window and listen to the birds. My neighbor waves from her garden, and we talk about the weather. Later we walk to the bakery on the corner, buy warm bread, and share it with the family.
    """
}
