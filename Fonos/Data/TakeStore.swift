import Foundation
import Observation

/// One completed take, summarized. Raw audio and vibration are never kept here.
struct TakeRecord: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var date: Date
    var kind: ExerciseKind
    /// Raw metric values keyed by `MetricID.rawValue`.
    var metrics: [String: Double]
    var onsetType: OnsetType?
    var worstNotes: [NoteScore]
    var quality: SignalQuality
    var lowNote: Int?
    var highNote: Int?
    var feedback: Feedback?
    var isSample: Bool

    func value(_ m: MetricID) -> Double? { metrics[m.rawValue] }

    init(result: TakeResult, isSample: Bool) {
        date = result.date
        kind = result.kind
        metrics = Dictionary(uniqueKeysWithValues: result.metrics.map { ($0.key.rawValue, $0.value) })
        onsetType = result.onsetType
        worstNotes = result.worstNotes
        quality = result.quality
        lowNote = result.lowNote
        highNote = result.highNote
        self.isSample = isSample
    }

    init(date: Date, kind: ExerciseKind, metrics: [MetricID: Double], onsetType: OnsetType?, lowNote: Int?, highNote: Int?) {
        self.date = date
        self.kind = kind
        self.metrics = Dictionary(uniqueKeysWithValues: metrics.map { ($0.key.rawValue, $0.value) })
        self.onsetType = onsetType
        worstNotes = []
        quality = SignalQuality()
        self.lowNote = lowNote
        self.highNote = highNote
        isSample = true
    }
}

/// All takes, in memory. Seeded with toy history; takes sung in the app are
/// appended while it runs. Every value here is sample data.
@Observable
final class TakeStore {

    private(set) var takes: [TakeRecord]

    init(seed: Bool = true) {
        takes = seed ? ToyHistory.make() : []
    }

    func add(_ take: TakeRecord) { takes.append(take) }

    func update(_ take: TakeRecord) {
        if let i = takes.firstIndex(where: { $0.id == take.id }) { takes[i] = take }
    }

    func deleteAll() { takes.removeAll() }

    var sorted: [TakeRecord] { takes.sorted { $0.date < $1.date } }

    func takes(days: Int, now: Date = .now) -> [TakeRecord] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now)!
        return sorted.filter { $0.date >= cutoff }
    }

    var today: [TakeRecord] {
        sorted.filter { Calendar.current.isDateInToday($0.date) }
    }

    /// The singer's own reference: mean of the first five takes carrying the metric.
    func baseline(_ m: MetricID) -> Double? {
        let values = sorted.compactMap { $0.value(m) }.prefix(5)
        guard values.count >= 3 else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Displayed value (baseline-relative for throat measures) for one take.
    func display(_ m: MetricID, in take: TakeRecord) -> Double? {
        take.value(m).map { m.display($0, baseline: baseline(m)) }
    }

    /// Mean displayed value over the last `days`.
    func mean(_ m: MetricID, days: Int, now: Date = .now) -> Double? {
        if m == .range { return rangeSpan(days: days, now: now).map { Double($0.high - $0.low) } }
        let values = takes(days: days, now: now).compactMap { display(m, in: $0) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Lowest and highest notes held in tune within the window.
    func rangeSpan(days: Int, now: Date = .now) -> (low: Int, high: Int)? {
        let window = takes(days: days, now: now)
        guard let low = window.compactMap(\.lowNote).min(), let high = window.compactMap(\.highNote).max(), high > low else { return nil }
        return (low, high)
    }

    /// Range in the window that ended `days` ago, for the "last month" outline.
    func previousRangeSpan(days: Int, now: Date = .now) -> (low: Int, high: Int)? {
        let end = Calendar.current.date(byAdding: .day, value: -days, to: now)!
        return rangeSpan(days: days, now: end)
    }

    /// Per-day mean of a metric, for charts.
    func daily(_ m: MetricID, days: Int, now: Date = .now) -> [(day: Date, value: Double)] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: takes(days: days, now: now)) { cal.startOfDay(for: $0.date) }
        return grouped.compactMap { day, list in
            let v = list.compactMap { display(m, in: $0) }
            return v.isEmpty ? nil : (day, v.reduce(0, +) / Double(v.count))
        }
        .sorted { $0.day < $1.day }
    }

    var practicedDays: Set<Date> {
        Set(takes.map { Calendar.current.startOfDay(for: $0.date) })
    }

    /// Minutes of practice today (take durations plus a little setup).
    var minutesToday: Int {
        Int((Double(today.count) * 0.9).rounded(.up))
    }
}

/// Twelve weeks of toy practice for a beginner who is slowly improving:
/// pitch accuracy climbs, notes steady, onsets settle faster, range widens.
/// Seeded so it's stable between launches. Illustrative only.
enum ToyHistory {
    static func make(now: Date = .now) -> [TakeRecord] {
        var rng = SeededGenerator(seed: 11)
        let cal = Calendar.current
        var out: [TakeRecord] = []
        let days = 84
        let kinds: [ExerciseKind] = [.siren, .fiveNoteScale, .sustained, .arpeggio, .songPhrase]
        for d in stride(from: days, through: 1, by: -1) {
            if d % 7 == 3 || d % 11 == 5 { continue } // rest days
            let t = Double(days - d) / Double(days)
            let n = 2 + Int.random(in: 0...2, using: &rng)
            for k in 0..<n {
                func r(_ s: Double) -> Double { Double.random(in: -s...s, using: &rng) }
                let kind = k == 0 ? .siren : kinds[Int.random(in: 1..<kinds.count, using: &rng)]
                let date = cal.date(byAdding: .day, value: -d, to: cal.startOfDay(for: now))!
                    .addingTimeInterval(TimeInterval(18 * 3600 + k * 300 + Int.random(in: 0...1200, using: &rng)))
                var m: [MetricID: Double] = [
                    .throatVibration: 42 + r(5),
                    .lrSymmetry: 92 + r(3),
                    .vibrationToSound: 1.05 - 0.08 * t + r(0.05),
                    .larynxRise: 0.36 - 0.05 * t + r(0.03),
                    .dynamicRange: 9 + 3 * t + r(1.5),
                    .phraseDuration: 5.5 + 3 * t + r(0.8),
                ]
                var low: Int?, high: Int?
                if kind == .siren {
                    low = 45 - Int((2 * t).rounded()) + Int(r(0.6).rounded())
                    high = 63 + Int((3 * t).rounded()) + Int(r(0.6).rounded())
                    m[.range] = Double(high! - low!)
                } else {
                    m[.pitchAccuracy] = 61 + 15 * t + r(4)
                    m[.pitchError] = -19 + 9 * t + r(3)
                    m[.sustainStability] = 17 - 6 * t + r(1.5)
                    m[.onsetSettle] = 265 - 75 * t + r(20)
                    m[.onsetExcursion] = -36 + 12 * t + r(4)
                    m[.levelStability] = 2.9 - 0.8 * t + r(0.3)
                    m[.hnr] = 13 + 3 * t + r(1)
                    m[.ring] = -22 + 3 * t + r(1.2)
                    m[.jitter] = 0.9 - 0.25 * t + r(0.1)
                    if kind == .sustained || kind == .songPhrase, t > 0.35 {
                        m[.vibratoRate] = 5.3 + r(0.3)
                        m[.vibratoExtent] = 22 + 18 * t + r(4)
                        m[.vibratoRegularity] = 24 - 8 * t + r(3)
                    }
                }
                let onset: OnsetType? = kind == .siren ? nil : (Double.random(in: 0...1, using: &rng) < 0.55 - 0.3 * t ? .breathy : .balanced)
                out.append(TakeRecord(date: date, kind: kind, metrics: m, onsetType: onset, lowNote: low, highNote: high))
            }
        }
        // One speaking check early on.
        out.append(TakeRecord(date: cal.date(byAdding: .day, value: -83, to: now)!, kind: .speakingCheck,
                              metrics: [.speakingPitch: 49, .throatVibration: 38, .larynxRise: 0.3],
                              onsetType: nil, lowNote: nil, highNote: nil))
        return out
    }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }
    mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return state
    }
}
