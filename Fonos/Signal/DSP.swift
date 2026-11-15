import Foundation

/// Small signal-processing helpers. Plain Swift on purpose: the workloads are
/// tiny (100 frames per second) and this keeps the math readable and testable.
enum DSP {

    static func rms(_ x: [Float]) -> Float {
        guard !x.isEmpty else { return 0 }
        var sum: Float = 0
        for v in x { sum += v * v }
        return (sum / Float(x.count)).squareRoot()
    }

    static func dbfs(_ rms: Float) -> Float {
        20 * log10(max(rms, 1e-6))
    }

    /// Fundamental frequency by normalized autocorrelation.
    /// Returns nil for unvoiced or ambiguous windows.
    static func pitch(_ x: [Float], sampleRate: Float, minHz: Float = 70, maxHz: Float = 400) -> Float? {
        let n = x.count
        let minLag = Int(sampleRate / maxHz)
        let maxLag = min(Int(sampleRate / minHz), n - 1)
        guard maxLag > minLag + 2 else { return nil }

        var energy: Float = 0
        for v in x { energy += v * v }
        guard energy > 1e-6 else { return nil }

        // Walk lags upward and stop at the first strong local maximum. This
        // avoids octave errors from later peaks and skips most of the lags,
        // with no allocation (this runs ~50 times a second).
        var prevPrev: Float = 0, prev: Float = 0
        for lag in minLag...maxLag {
            var s: Float = 0
            for i in 0..<(n - lag) { s += x[i] * x[i + lag] }
            let c = s / energy
            if lag >= minLag + 2, prev > prevPrev, prev >= c, prev > 0.45 {
                // Peak at lag - 1. Parabolic interpolation for sub-sample precision.
                let denom = prevPrev - 2 * prev + c
                let shift = denom != 0 ? 0.5 * (prevPrev - c) / denom : 0
                return sampleRate / (Float(lag - 1) + shift)
            }
            prevPrev = prev; prev = c
        }
        return nil
    }

    /// Counts syllable nuclei in an energy envelope (dB, 100 Hz):
    /// local peaks that rise at least `prominence` dB above the lowest point
    /// since the previous peak and are at least `minGap` frames apart.
    static func syllablePeaks(_ envelopeDb: [Float], floorDb: Float, prominence: Float = 4, minGap: Int = 10) -> Int {
        peakIndices(envelopeDb, floorDb: floorDb, prominence: prominence, minGap: minGap, smoothing: 5).count
    }

    /// Frame indices of the nuclei counted by `syllablePeaks`.
    static func peakIndices(_ envelopeDb: [Float], floorDb: Float, prominence: Float, minGap: Int, smoothing: Int) -> [Int] {
        guard envelopeDb.count > 2 else { return [] }
        let smooth = movingAverage(envelopeDb, width: smoothing)
        var out: [Int] = []
        var valley = smooth[0]
        var lastPeak = -minGap
        for i in 1..<(smooth.count - 1) {
            let v = smooth[i]
            valley = min(valley, v)
            let isPeak = v >= smooth[i - 1] && v > smooth[i + 1]
            if isPeak, v > floorDb, v - valley >= prominence, i - lastPeak >= minGap {
                out.append(i)
                lastPeak = i
                valley = v
            }
        }
        return out
    }

    /// Strongest normalized autocorrelation in the 70–400 Hz lag range,
    /// normalized by the overlap energy at each lag (Boersma-style), for
    /// harmonics-to-noise estimates. 1 = perfectly periodic.
    static func periodicity(_ x: [Float], sampleRate: Float, minHz: Float = 70, maxHz: Float = 400) -> Float? {
        let n = x.count
        let minLag = Int(sampleRate / maxHz), maxLag = min(Int(sampleRate / minHz), n / 2)
        guard maxLag > minLag else { return nil }
        var best: Float = 0
        for lag in minLag...maxLag {
            var s: Float = 0, e1: Float = 0, e2: Float = 0
            for i in 0..<(n - lag) {
                s += x[i] * x[i + lag]; e1 += x[i] * x[i]; e2 += x[i + lag] * x[i + lag]
            }
            let d = (e1 * e2).squareRoot()
            if d > 1e-9 { best = max(best, s / d) }
        }
        return best > 0 ? best : nil
    }

    static func movingAverage(_ x: [Float], width: Int) -> [Float] {
        guard width > 1, x.count > width else { return x }
        var out = [Float](repeating: 0, count: x.count)
        var acc: Float = 0
        let half = width / 2
        for i in 0..<x.count {
            acc += x[i]
            if i >= width { acc -= x[i - width] }
            let idx = i - half
            if idx >= 0 { out[idx] = acc / Float(min(i + 1, width)) }
        }
        for i in max(0, x.count - half)..<x.count { out[i] = x[i] }
        return out
    }
}
