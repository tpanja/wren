import Foundation

/// Plain-language trend summaries for the Progress screen.
/// Wording rules: describe, never diagnose; compare to the patient's own
/// baseline; say "steady" when the change is inside normal day-to-day noise.
struct Trend: Identifiable {
    let metric: Metric
    let recent: Double
    let baseline: Double
    /// Signed relative change, recent vs baseline.
    let change: Double

    var id: Metric { metric }

    enum Direction { case steady, better, lower }

    var direction: Direction {
        // Treat changes under 5% as day-to-day variation.
        guard abs(change) >= 0.05 else { return .steady }
        let up = change > 0
        return up == metric.higherIsBetter ? .better : .lower
    }

    var phrase: String {
        let pct = Int((abs(change) * 100).rounded())
        switch direction {
        case .steady: return "\(metric.title) is steady"
        case .better: return "\(metric.title) is up \(pct)%"
        case .lower:
            return metric.higherIsBetter ? "\(metric.title) is down \(pct)%" : "\(metric.title) is up \(pct)%"
        }
    }
}

enum Insights {

    /// Mean value of `metric` over sessions in the last `days`.
    static func mean(_ metric: Metric, in sessions: [SessionRecord], baseline: Baseline?, days: Int, now: Date = .now) -> Double? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now)!
        let values = sessions.filter { $0.date >= cutoff }.compactMap { metric.value($0, baseline: baseline) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    static func trends(_ sessions: [SessionRecord], baseline: Baseline?, now: Date = .now) -> [Trend] {
        guard let baseline else { return [] }
        let firstDates = Set(sessions.sorted { $0.date < $1.date }.prefix(5).map(\.id))
        let base = sessions.filter { firstDates.contains($0.id) }
        return Metric.allCases.compactMap { m in
            guard let recent = mean(m, in: sessions, baseline: baseline, days: 7, now: now) else { return nil }
            let bvals = base.compactMap { m.value($0, baseline: baseline) }
            guard !bvals.isEmpty else { return nil }
            let b = bvals.reduce(0, +) / Double(bvals.count)
            guard b != 0 else { return nil }
            return Trend(metric: m, recent: recent, baseline: b, change: (recent - b) / abs(b))
        }
    }

    /// The headline card: the single most notable change, written gently.
    static func headline(_ trends: [Trend]) -> (title: String, body: String)? {
        guard !trends.isEmpty else { return nil }
        let notable = trends.filter { $0.direction == .lower }.max { abs($0.change) < abs($1.change) }
        if let t = notable {
            let title = "\(t.phrase) since your baseline"
            let body: String
            switch t.metric {
            case .pace:
                body = "You're speaking a little more slowly than in your first sessions. Fonos adjusts automatically, and slower speech often translates more accurately."
            case .strength:
                body = "Your voice is vibrating less strongly than at your baseline. Speaking in shorter phrases and resting between them can help the band pick up more of each word."
            case .pauses:
                body = "There's more silence between your sounds than at your baseline. Fonos waits for you, so there's no need to rush."
            case .symmetry:
                body = "One side of your throat is vibrating more than the other compared with your baseline. Check that the band sits centered and both sensors touch your skin."
            case .steadiness:
                body = "Your pitch varies more from moment to moment than at your baseline. This is worth mentioning at your next clinic visit."
            case .clarity:
                body = "Fonos is less confident about your words than in your first sessions. Recording a few practice phrases can help."
            }
            return (title, body)
        }
        return ("Your speech is holding steady", "This week's measures are close to your baseline across the board.")
    }
}
