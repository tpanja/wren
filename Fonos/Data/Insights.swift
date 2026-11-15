import Foundation

/// The weekly insight on Progress, written by the local coach from trends.
/// Wording rules: compare with the singer's own baseline; under 5% change is
/// "about the same"; name one strength and one next gain.
enum Insights {

    struct Change {
        let metric: MetricID
        let recent: Double
        let baseline: Double
        /// Positive = better, as a fraction of baseline.
        let improvement: Double
    }

    static func changes(_ store: TakeStore, days: Int = 7) -> [Change] {
        [MetricID.pitchAccuracy, .sustainStability, .onsetSettle, .range, .levelStability, .phraseDuration].compactMap { m in
            guard let recent = store.mean(m, days: days) else { return nil }
            let base: Double?
            if m == .range {
                base = store.sorted.prefix(5).compactMap { $0.value(.range) }.max()
            } else {
                base = store.baseline(m)
            }
            guard let b = base, b != 0 else { return nil }
            let raw = (recent - b) / abs(b)
            let improvement: Double
            switch m.better {
            case .higher: improvement = raw
            case .lower: improvement = -raw
            default: improvement = 0
            }
            return Change(metric: m, recent: recent, baseline: b, improvement: improvement)
        }
    }

    static func weekly(_ store: TakeStore) -> (title: String, body: String)? {
        let c = changes(store)
        guard !c.isEmpty else { return nil }
        let best = c.max { $0.improvement < $1.improvement }!
        let gap = c.filter { $0.metric != best.metric }.min { $0.improvement < $1.improvement }
        guard best.improvement >= 0.05 else {
            return ("About the same as when you started", "Your measures are close to your first sessions. Short, regular practice is what moves them.")
        }
        let pct = Int((best.improvement * 100).rounded())
        let title: String
        switch best.metric {
        case .pitchAccuracy: title = "You're singing more in tune"
        case .sustainStability: title = "Your held notes are steadier"
        case .onsetSettle: title = "You're landing notes faster"
        case .range: title = "Your range is wider"
        case .levelStability: title = "Your volume is steadier"
        case .phraseDuration: title = "Your phrases are longer"
        default: title = "\(best.metric.title) is improving"
        }
        var body = "\(best.metric.title) is \(pct)% better than in your first sessions."
        if let gap {
            body += " \(gap.metric.title) is your next biggest gain."
        }
        return (title, body)
    }
}
