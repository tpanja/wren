import Foundation
import Observation

/// Persists session summaries as JSON in Application Support.
/// Demo sessions live in memory only and are never written to disk.
@Observable
final class SessionStore {

    private(set) var sessions: [SessionRecord] = []
    private(set) var demoSessions: [SessionRecord] = []
    var showDemo = false

    private let url: URL

    init(fileName: String = "sessions.json") {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent(fileName)
        load()
        demoSessions = DemoHistory.make()
    }

    /// What the Progress screen reads.
    var visible: [SessionRecord] {
        (showDemo ? demoSessions : sessions).sorted { $0.date < $1.date }
    }

    var baseline: Baseline? { Baseline.from(visible) }

    func add(_ record: SessionRecord) {
        if record.isDemo {
            demoSessions.append(record)
        } else {
            sessions.append(record)
            save()
        }
    }

    func deleteAll() {
        sessions = []
        save()
    }

    func exportCSV() -> URL? {
        var lines = ["date,duration_s,speaking_s,strength_dbfs,pace_syl_s,pause_ratio,symmetry,pitch_variation_pct,clarity,phrases"]
        let iso = ISO8601DateFormatter()
        for s in sessions.sorted(by: { $0.date < $1.date }) {
            func o(_ v: Double?) -> String { v.map { String(format: "%.4f", $0) } ?? "" }
            lines.append([iso.string(from: s.date), o(s.duration), o(s.speakingSeconds), o(s.strengthDb), o(s.pace),
                          o(s.pauseRatio), o(s.symmetry), o(s.pitchVariation), o(s.clarity), "\(s.phrases)"].joined(separator: ","))
        }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("fonos-sessions.csv")
        do {
            try lines.joined(separator: "\n").write(to: out, atomically: true, encoding: .utf8)
            return out
        } catch {
            return nil
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        sessions = (try? decoder.decode([SessionRecord].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(sessions) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }
}

/// Twelve weeks of synthetic history, labeled as demo everywhere it appears.
/// Shapes a slow, realistic change: pace and strength drift down, pauses
/// lengthen, symmetry shifts slightly. Seeded so it is stable between launches.
enum DemoHistory {
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
                    isDemo: true
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
