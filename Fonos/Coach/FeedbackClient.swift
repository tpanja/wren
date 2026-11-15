import Foundation

/// Talks to the Fonos feedback server, which calls Claude (Docs/LLM-FEEDBACK.md).
/// Sends only rounded metrics, never audio or vibration. The server URL comes
/// from the `FonosFeedbackURL` Info.plist key; when it's empty, the local
/// coach's card is final.
enum FeedbackClient {

    static var endpoint: URL? {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "FonosFeedbackURL") as? String, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    static var isConfigured: Bool { endpoint != nil }

    enum ClientError: Error { case notConfigured, badStatus(Int) }

    static func request(take: TakeRecord, store: TakeStore, profile: Profile, takeNumber: Int) async throws -> Feedback {
        guard let endpoint else { throw ClientError.notConfigured }
        var req = URLRequest(url: endpoint, timeoutInterval: 12)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try payload(take: take, store: store, profile: profile, takeNumber: takeNumber)
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw ClientError.badStatus(status) }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        var feedback = try decoder.decode(Feedback.self, from: data).clamped()
        feedback.source = .claude
        if profile.level == .beginner { feedback.technicalNote = nil }
        return feedback
    }

    /// The take payload (Docs/LLM-FEEDBACK.md § 4).
    static func payload(take: TakeRecord, store: TakeStore, profile: Profile, takeNumber: Int) throws -> Data {
        let plan = take.kind.plan(range: profile.range)
        var singer: [String: Any] = [
            "voice_type": profile.voiceType.payloadName,
            "range": ["low": Music.name(profile.rangeLow), "high": Music.name(profile.rangeHigh)],
        ]
        if profile.useGoalsInFeedback { singer["goals"] = profile.goals.map(\.payloadName).sorted() }

        var metrics: [String: Any] = [:]
        for m in MetricID.allCases {
            guard let raw = take.value(m) else { continue }
            let value = store.display(m, in: take) ?? raw
            var entry: [String: Any] = [
                "value": round(m, value),
                "trend_4w": trend(m, store: store),
                "status": m.status == .established ? "established" : "exploratory",
            ]
            if let b = store.baseline(m) { entry["baseline"] = round(m, m.display(b, baseline: b)) }
            metrics[m.payloadName] = entry
        }
        if let onset = take.onsetType { metrics["onset_type"] = ["value": onset.rawValue, "status": "exploratory"] }

        let body: [String: Any] = [
            "coaching_level": profile.level == .technical ? "technical" : "beginner",
            "singer": singer,
            "exercise": [
                "id": take.kind.payloadName,
                "key": plan.notes.first.map { Music.name($0.midi) } ?? "",
                "pattern": plan.notes.map { Music.name($0.midi) },
                "duration_s": (plan.duration * 10).rounded() / 10,
                "take_number": takeNumber,
            ] as [String: Any],
            "signal_quality": [
                "overall": take.quality.overall.rawValue,
                "left_contact": take.quality.leftContact,
                "right_contact": take.quality.rightContact,
                "mic_accel_pitch_agreement_pct": take.quality.agreementPct,
                "room_noise_dbfs": take.quality.noiseFloorDb,
                "clipping": take.quality.clipping,
            ] as [String: Any],
            "metrics": metrics,
            "worst_notes": take.worstNotes.map {
                ["note": Music.name($0.midi), "pitch_error_cents": $0.cents, "settle_ms": $0.settleMs] as [String: Any]
            },
        ]
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    /// Integers for cents, %, ms; one decimal for everything else.
    private static func round(_ m: MetricID, _ v: Double) -> Double {
        switch m.unit {
        case "cents", "%", "ms", "semitones", "% of usual": v.rounded()
        default: (v * 10).rounded() / 10
        }
    }

    private static func trend(_ m: MetricID, store: TakeStore) -> String {
        let now = Date.now
        guard let recent = store.mean(m, days: 28, now: now),
              let earlier = store.mean(m, days: 28, now: Calendar.current.date(byAdding: .day, value: -28, to: now)!),
              earlier != 0 else { return "flat" }
        let change = (recent - earlier) / abs(earlier)
        return abs(change) < 0.03 ? "flat" : (change > 0 ? "up" : "down")
    }
}

extension ExerciseKind {
    var payloadName: String {
        switch self {
        case .siren: "siren"
        case .fiveNoteScale: "five_note_scale"
        case .sustained: "sustained_note"
        case .arpeggio: "arpeggio"
        case .songPhrase: "song_phrase"
        case .speakingCheck: "speaking_check"
        }
    }
}

extension VoiceType {
    var payloadName: String {
        switch self {
        case .notSure: "not_sure"
        default: rawValue
        }
    }
}
