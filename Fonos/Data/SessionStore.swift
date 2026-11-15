import Foundation
import Observation

/// Holds session summaries in memory. Seeded with toy history; sessions
/// recorded from the toy band are appended while the app runs.
@Observable
final class SessionStore {

    private(set) var sessions: [SessionRecord]

    init() {
        sessions = ToyHistory.make()
    }

    var visible: [SessionRecord] { sessions.sorted { $0.date < $1.date } }

    var baseline: Baseline? { Baseline.from(visible) }

    func add(_ record: SessionRecord) {
        sessions.append(record)
    }
}

/// Twelve weeks of toy history, labeled as sample data everywhere it appears.
/// Shapes a slow, realistic change: pace and strength drift down, pauses
/// lengthen, symmetry shifts slightly. Seeded so it is stable between launches.
enum ToyHistory {
    static func make(now: Date = .now) -> [SessionRecord] {
        var rng = SeededGenerator(seed: 7)
        let cal = Calendar.current
        var out: [SessionRecord] = []
        let days = 84
        for d in stride(from: days, through: 0, by: -1) {
            // Most days have one or two sessions; a few have none.
            let n = d % 9 == 4 ? 0 : (d % 3 == 0 ? 2 : 1)
            for k in 0..<n {
                let t = Double(days - d) / Double(days) // 0 → 1 over the window
                let noise = { (scale: Double) in Double.random(in: -scale...scale, using: &rng) }
                let date = cal.date(byAdding: .day, value: -d, to: cal.startOfDay(for: now))!
                    .addingTimeInterval(TimeInterval(9 * 3600 + k * 8 * 3600 + Int.random(in: 0...3600, using: &rng)))
                out.append(SessionRecord(
                    id: UUID(), date: date,
                    duration: 240 + noise(120), speakingSeconds: 150 + noise(60),
                    strengthDb: -21 - 2.6 * t + noise(0.7),
                    pace: 3.9 - 0.55 * t + noise(0.18),
                    pauseRatio: 0.22 + 0.07 * t + noise(0.025),
                    symmetry: 0.95 - 0.06 * t + noise(0.015),
                    pitchVariation: 2.1 + 1.1 * t + noise(0.3),
                    clarity: 0.86 - 0.09 * t + noise(0.03),
                    phrases: 6 + Int(noise(4)),
                    isSample: true
                ))
            }
        }
        return out
    }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 | 1 }
    mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return state
    }
}
