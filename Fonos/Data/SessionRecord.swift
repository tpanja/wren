import Foundation

/// One speaking session, summarized. Raw signals are never stored.
struct SessionRecord: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var date: Date
    /// Seconds of signal received.
    var duration: Double
    /// Seconds from first to last voiced frame.
    var speakingSeconds: Double
    /// Mean voiced level, dBFS.
    var strengthDb: Double
    /// Syllables per second of voiced time.
    var pace: Double
    /// 0...1 share of speaking time that is silent.
    var pauseRatio: Double
    /// 0...1, 1 = left and right vibrate equally. Nil without piezo data.
    var symmetry: Double?
    /// Mean frame-to-frame pitch change, % of mean pitch. Lower is steadier.
    var pitchVariation: Double?
    /// 0...1 mean recognizer confidence. Nil when nothing was translated.
    var clarity: Double?
    var phrases: Int
    var isDemo: Bool
}

/// The patient's own reference point. Every ring and trend is read against it.
struct Baseline: Codable, Equatable, Sendable {
    var strengthDb: Double
    var pace: Double
    var pauseRatio: Double
    var symmetry: Double
    var pitchVariation: Double
    var clarity: Double
    var establishedOn: Date

    /// Mean of the first sessions (up to `count`) that carry each measure.
    static func from(_ sessions: [SessionRecord], count: Int = 5) -> Baseline? {
        let first = sessions.sorted { $0.date < $1.date }.prefix(count)
        guard first.count >= 3, let date = first.last?.date else { return nil }
        func mean(_ values: [Double]) -> Double { values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count) }
        return Baseline(
            strengthDb: mean(first.map(\.strengthDb)),
            pace: mean(first.map(\.pace)),
            pauseRatio: mean(first.map(\.pauseRatio)),
            symmetry: mean(first.compactMap(\.symmetry)),
            pitchVariation: mean(first.compactMap(\.pitchVariation)),
            clarity: mean(first.compactMap(\.clarity)),
            establishedOn: date
        )
    }
}
