import Foundation

/// One weekly Speech check: the measures from each task. A skipped task
/// leaves its measures nil.
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
    var isSample: Bool

    var completedTasks: Int {
        [mpt != nil, amrRate != nil, smrRate != nil, readingRate != nil].filter { $0 }.count
    }
}

/// Twelve weeks of weekly checks, labeled as sample data wherever shown.
/// Every task measure drifts slowly in the direction ALS speech changes.
enum ToyCheckHistory {
    static func make(now: Date = .now) -> [SpeechCheckRecord] {
        var rng = SeededGenerator(seed: 11)
        let cal = Calendar.current
        let weeks = 12
        return (0...weeks).map { w in
            let t = Double(w) / Double(weeks)
            func n(_ s: Double) -> Double { Double.random(in: -s...s, using: &rng) }
            // The last sample check is a week ago, so this week's check is due.
            let date = cal.date(byAdding: .day, value: -7 * (weeks - w + 1), to: cal.startOfDay(for: now))!
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
                isSample: true
            )
        }
    }
}
