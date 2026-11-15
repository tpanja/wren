import Foundation

/// Measures for each Speech check task, computed from the raw frames of
/// that task. Unlike conversation, each task has a known structure, so
/// the measures can follow the ones used in ALS speech research:
/// maximum phonation time, diadochokinetic rate and regularity, and
/// reading rate with pauses of at least 250 ms.
enum TaskAnalysis {

    struct Vowel: Equatable {
        /// Maximum phonation time: longest continuous voicing, seconds.
        var mpt: Double
        /// Harmonics-to-noise ratio estimated from autocorrelation, dB.
        var hnr: Double?
        /// Frame-to-frame pitch change as % of mean F0 (as in Pitch variation).
        var pitchVariation: Double?
    }

    struct DDK: Equatable {
        /// Syllables per second between the first and last syllable.
        var rate: Double
        /// Coefficient of variation of syllable intervals, %. Lower is more regular.
        var regularity: Double
        var syllables: Int
    }

    struct Passage: Equatable {
        /// Syllables per second of speaking time (pauses of 250 ms or more removed).
        var rate: Double
        /// Share of the reading span spent in pauses of 250 ms or more.
        var pauseShare: Double
        /// Syllables between pauses (breath groups).
        var syllablesPerBreathGroup: Double
        /// Voiced level in the last third minus the first third, dB. Negative = weaker by the end.
        var fatigueDb: Double
        var syllables: Int
        var pauses: Int
    }

    // MARK: Shared framing

    /// Frame levels (dBFS), voiced flags, and the threshold used.
    /// The floor is the 10th percentile of the task's own frame levels, so
    /// it is calibrated per task instead of tracked from a cold start.
    struct Framed {
        var db: [Float]
        var voiced: [Bool]
        var threshold: Float
    }

    static func frame(_ frames: [SensorFrame], margin: Float = 12) -> Framed {
        let db = frames.map { DSP.dbfs(DSP.rms($0.mic)) }
        let sorted = db.sorted()
        let floor = sorted.isEmpty ? -60 : sorted[min(sorted.count - 1, sorted.count / 10)]
        let thr = max(floor, -80) + margin
        return Framed(db: db, voiced: db.map { $0 > thr }, threshold: thr)
    }

    /// Voiced flags with unvoiced gaps shorter than `maxGap` frames filled in.
    static func bridged(_ v: [Bool], maxGap: Int) -> [Bool] {
        var out = v
        var i = 0
        while i < v.count {
            if !v[i] {
                var j = i
                while j < v.count && !v[j] { j += 1 }
                let inside = i > 0 && j < v.count
                if inside && j - i < maxGap { for k in i..<j { out[k] = true } }
                i = j
            } else { i += 1 }
        }
        return out
    }

    /// Runs of `true` as half-open index ranges.
    static func runs(_ v: [Bool]) -> [Range<Int>] {
        var out: [Range<Int>] = []
        var start: Int?
        for (i, x) in v.enumerated() {
            if x, start == nil { start = i }
            if !x, let s = start { out.append(s..<i); start = nil }
        }
        if let s = start { out.append(s..<v.count) }
        return out
    }

    // MARK: Tasks

    static func vowel(_ frames: [SensorFrame]) -> Vowel? {
        let f = frame(frames)
        // Gaps under 150 ms are treated as the same breath.
        guard let run = runs(bridged(f.voiced, maxGap: 15)).max(by: { $0.count < $1.count }), run.count >= 30 else { return nil }
        let mpt = Double(run.count) / 100

        // Steady middle of the vowel only: skip 100 ms at each end.
        let core = (run.lowerBound + 10)..<max(run.lowerBound + 11, run.upperBound - 10)
        var rs: [Float] = [], f0s: [Float] = []
        var k = core.lowerBound + 2
        while k < core.upperBound {
            let window = frames[(k - 2)...k].flatMap(\.mic)
            if let r = DSP.periodicity(window, sampleRate: 8_000) { rs.append(r) }
            if let p = DSP.pitch(window, sampleRate: 8_000) { f0s.append(p) }
            k += 4
        }
        let hnr: Double? = rs.isEmpty ? nil : {
            let r = Double(min(rs.reduce(0, +) / Float(rs.count), 0.9999))
            return 10 * log10(r / (1 - r))
        }()
        var pv: Double?
        if f0s.count > 10 {
            let deltas = zip(f0s, f0s.dropFirst()).map { abs($1 - $0) }
            let mean = f0s.reduce(0, +) / Float(f0s.count)
            pv = Double(deltas.reduce(0, +) / Float(deltas.count) / mean * 100)
        }
        return Vowel(mpt: mpt, hnr: hnr, pitchVariation: pv)
    }

    static func ddk(_ frames: [SensorFrame]) -> DDK? {
        let f = frame(frames)
        // DDK syllables are fast (5–7 per second): a 30 ms smoother and an
        // 80 ms minimum spacing (caps at 12.5 per second).
        let peaks = DSP.peakIndices(f.db, floorDb: f.threshold, prominence: 4, minGap: 8, smoothing: 3)
        guard peaks.count >= 4 else { return nil }
        // Refine each peak to a fraction of a frame with a parabola through
        // its neighbors; at 5–7 syllables per second a whole 10 ms frame is
        // about 6% of an interval, which would swamp the regularity measure.
        let smooth = DSP.movingAverage(f.db, width: 3)
        let times = peaks.map { i -> Double in
            guard i > 0, i < smooth.count - 1 else { return Double(i) }
            let a = Double(smooth[i - 1]), b = Double(smooth[i]), c = Double(smooth[i + 1])
            let d = a - 2 * b + c
            return Double(i) + (d < 0 ? max(-0.5, min(0.5, 0.5 * (a - c) / d)) : 0)
        }
        guard let first = times.first, let last = times.last, last > first else { return nil }
        let intervals = zip(times, times.dropFirst()).map { $1 - $0 }
        let mean = intervals.reduce(0, +) / Double(intervals.count)
        let sd = (intervals.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(intervals.count)).squareRoot()
        return DDK(rate: Double(peaks.count - 1) / ((last - first) / 100),
                   regularity: sd / mean * 100,
                   syllables: peaks.count)
    }

    static func passage(_ frames: [SensorFrame]) -> Passage? {
        let f = frame(frames)
        guard let first = f.voiced.firstIndex(of: true), let last = f.voiced.lastIndex(of: true), last - first >= 200 else { return nil }
        let span = Array(f.voiced[first...last])
        // Pauses: silences of 250 ms (25 frames) or more inside the span.
        let silences = runs(span.map { !$0 }).filter { $0.count >= 25 }
        let pauseFrames = silences.reduce(0) { $0 + $1.count }
        let peaks = DSP.peakIndices(Array(f.db[first...last]), floorDb: f.threshold, prominence: 4, minGap: 10, smoothing: 5)
        let speakingSeconds = Double(span.count - pauseFrames) / 100
        guard speakingSeconds > 0.5, !peaks.isEmpty else { return nil }

        let third = span.count / 3
        let voicedDb: (Range<Int>) -> Double? = { r in
            let vals = r.compactMap { i -> Double? in span[i] ? Double(f.db[first + i]) : nil }
            return vals.isEmpty ? nil : vals.reduce(0, +) / Double(vals.count)
        }
        let fatigue = (voicedDb((span.count - third)..<span.count) ?? 0) - (voicedDb(0..<third) ?? 0)

        return Passage(
            rate: Double(peaks.count) / speakingSeconds,
            pauseShare: Double(pauseFrames) / Double(span.count),
            syllablesPerBreathGroup: Double(peaks.count) / Double(silences.count + 1),
            fatigueDb: fatigue,
            syllables: peaks.count,
            pauses: silences.count
        )
    }
}
