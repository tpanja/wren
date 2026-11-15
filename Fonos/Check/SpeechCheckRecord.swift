import Foundation

/// The patient's own rating of three bulbar functions, 0–4, modeled on the
/// bulbar items of the ALSFRS-R (speech, salivation, swallowing). Answer
/// wording is paraphrased in plain language; this is not the official
/// instrument and is not scored as one.
struct BulbarSelfReport: Codable, Equatable, Sendable {
    var speech: Int
    var salivation: Int
    var swallowing: Int

    var total: Int { speech + salivation + swallowing }

    enum Item: String, CaseIterable, Identifiable {
        case speech, salivation, swallowing
        var id: String { rawValue }

        var question: String {
            switch self {
            case .speech: "How is your speech this week?"
            case .salivation: "How is saliva this week?"
            case .swallowing: "How is swallowing this week?"
            }
        }

        /// Options from 4 (no change) to 0, in plain words.
        var options: [String] {
            switch self {
            case .speech: [
                "Normal",
                "Noticeably different, but people understand me",
                "People understand me if I repeat myself",
                "I often need writing or a device as well",
                "I can't be understood by speech",
            ]
            case .salivation: [
                "Normal",
                "A little extra saliva, maybe some drooling at night",
                "Some extra saliva, a little drooling",
                "Clearly more saliva, some drooling",
                "Constant drooling, I need a tissue all the time",
            ]
            case .swallowing: [
                "Normal",
                "Some trouble, I choke now and then",
                "I've changed what I eat or how it's prepared",
                "I need tube feeding as well",
                "I take nothing by mouth",
            ]
            }
        }

        var shortTitle: String {
            switch self {
            case .speech: "Speech"
            case .salivation: "Saliva"
            case .swallowing: "Swallowing"
            }
        }
    }

    func score(_ item: Item) -> Int {
        switch item {
        case .speech: speech
        case .salivation: salivation
        case .swallowing: swallowing
        }
    }
}

/// One weekly Speech check: the measures from each task, plus the optional
/// self-report. A skipped task leaves its measures nil.
struct SpeechCheckRecord: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var date: Date
    // Breath task ("ahh")
    var mpt: Double?
    var hnr: Double?
    var vowelPitchVariation: Double?
    // "pa-pa-pa"
    var amrRate: Double?
    var amrRegularity: Double?
    // "pa-ta-ka"
    var smrRate: Double?
    var smrRegularity: Double?
    // Reading
    var readingRate: Double?
    var readingPauseShare: Double?
    var syllablesPerBreathGroup: Double?
    var fatigueDb: Double?
    var selfReport: BulbarSelfReport?
    var isSample: Bool

    var completedTasks: Int {
        [mpt != nil, amrRate != nil, smrRate != nil, readingRate != nil].filter { $0 }.count
    }
}

/// Twelve weeks of weekly checks, labeled as sample data wherever shown.
/// Every task measure drifts slowly in the direction ALS speech changes,
/// and the self-reported speech item drops from 4 to 3 partway through.
enum ToyCheckHistory {
    static func make(now: Date = .now) -> [SpeechCheckRecord] {
        var rng = SeededGenerator(seed: 11)
        let cal = Calendar.current
        let weeks = 12
        return (0...weeks).map { w in
            let t = Double(w) / Double(weeks)
            func n(_ s: Double) -> Double { Double.random(in: -s...s, using: &rng) }
            let date = cal.date(byAdding: .day, value: -7 * (weeks - w), to: cal.startOfDay(for: now))!
                .addingTimeInterval(10 * 3600 + Double(Int.random(in: 0...3600, using: &rng)))
            return SpeechCheckRecord(
                date: date,
                mpt: 16.5 - 4.5 * t + n(0.8),
                hnr: 18 - 3.5 * t + n(0.8),
                vowelPitchVariation: 0.6 + 0.5 * t + n(0.08),
                amrRate: 6.3 - 1.0 * t + n(0.15),
                amrRegularity: 4 + 3 * t + n(0.6),
                smrRate: 5.5 - 1.1 * t + n(0.18),
                smrRegularity: 6 + 5 * t + n(1),
                readingRate: 4.3 - 0.6 * t + n(0.12),
                readingPauseShare: 0.15 + 0.09 * t + n(0.02),
                syllablesPerBreathGroup: 11 - 3.5 * t + n(0.7),
                fatigueDb: -0.8 - 1.8 * t + n(0.3),
                selfReport: BulbarSelfReport(speech: t < 0.45 ? 4 : 3, salivation: t < 0.7 ? 4 : 3, swallowing: 4),
                isSample: true
            )
        }
    }
}
