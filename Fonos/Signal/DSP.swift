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

        var bestLag = 0
        var best: Float = 0
        var prev: Float = 0, prevPrev: Float = 0
        var corr = [Float](repeating: 0, count: maxLag + 1)
        for lag in minLag...maxLag {
            var s: Float = 0
            for i in 0..<(n - lag) { s += x[i] * x[i + lag] }
            let c = s / energy
            corr[lag] = c
            // Take the first strong local maximum; avoids octave errors from later peaks.
            if lag > minLag + 1, prev > prevPrev, prev >= c, prev > 0.45, best == 0 {
                best = prev; bestLag = lag - 1
            }
            prevPrev = prev; prev = c
        }
        guard bestLag > 0 else { return nil }

        // Parabolic interpolation around the peak for sub-sample precision.
        let a = corr[bestLag - 1], b = corr[bestLag], c = corr[min(bestLag + 1, maxLag)]
        let denom = a - 2 * b + c
        let shift = denom != 0 ? 0.5 * (a - c) / denom : 0
        return sampleRate / (Float(bestLag) + shift)
    }

    /// Counts syllable nuclei in an energy envelope (dB, 100 Hz):
    /// local peaks that rise at least `prominence` dB above the lowest point
    /// since the previous peak and are at least `minGap` frames apart.
    static func syllablePeaks(_ envelopeDb: [Float], floorDb: Float, prominence: Float = 4, minGap: Int = 10) -> Int {
        guard envelopeDb.count > 2 else { return 0 }
        let smooth = movingAverage(envelopeDb, width: 5)
        var count = 0
        var valley = smooth[0]
        var lastPeak = -minGap
        for i in 1..<(smooth.count - 1) {
            let v = smooth[i]
            valley = min(valley, v)
            let isPeak = v >= smooth[i - 1] && v > smooth[i + 1]
            if isPeak, v > floorDb, v - valley >= prominence, i - lastPeak >= minGap {
                count += 1
                lastPeak = i
                valley = v
            }
        }
        return count
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
