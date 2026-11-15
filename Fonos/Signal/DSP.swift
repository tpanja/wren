import Foundation

/// Signal-processing building blocks. Plain Swift for readability and
/// testability; the per-frame workloads are small (100 frames per second).
enum DSP {

    static func rms(_ x: ArraySlice<Float>) -> Float {
        guard !x.isEmpty else { return 0 }
        var sum: Float = 0
        for v in x { sum += v * v }
        return (sum / Float(x.count)).squareRoot()
    }

    static func rms(_ x: [Float]) -> Float { rms(x[...]) }

    static func dbfs(_ rms: Float) -> Float { 20 * log10(max(rms, 1e-6)) }

    struct PitchEstimate: Equatable {
        var hz: Float
        /// 0...1, 1 = perfectly periodic (1 − YIN aperiodicity).
        var clarity: Float
    }

    /// YIN fundamental-frequency estimator (de Cheveigné & Kawahara, 2002):
    /// difference function, cumulative-mean normalization, absolute threshold,
    /// then parabolic interpolation. Returns nil for unvoiced windows.
    static func yin(_ x: [Float], sampleRate: Float, minHz: Float = 70, maxHz: Float = 1_100, threshold: Float = 0.2) -> PitchEstimate? {
        let n = x.count
        let tauMax = min(Int(sampleRate / minHz), n / 2)
        let tauMin = max(2, Int(sampleRate / maxHz))
        guard tauMax > tauMin + 2 else { return nil }
        let w = n - tauMax

        var d = [Float](repeating: 0, count: tauMax + 1)
        x.withUnsafeBufferPointer { p in
            for tau in 1...tauMax {
                var s: Float = 0
                for j in 0..<w {
                    let diff = p[j] - p[j + tau]
                    s += diff * diff
                }
                d[tau] = s
            }
        }
        // Cumulative mean normalized difference.
        var cmnd = [Float](repeating: 1, count: tauMax + 1)
        var running: Float = 0
        for tau in 1...tauMax {
            running += d[tau]
            cmnd[tau] = running > 0 ? d[tau] * Float(tau) / running : 1
        }
        // First dip below threshold, then walk to its local minimum.
        var tau = tauMin
        var found = -1
        while tau < tauMax {
            if cmnd[tau] < threshold {
                while tau + 1 < tauMax, cmnd[tau + 1] < cmnd[tau] { tau += 1 }
                found = tau
                break
            }
            tau += 1
        }
        guard found > 0 else { return nil }
        let a = cmnd[found - 1], b = cmnd[found], c = cmnd[min(found + 1, tauMax)]
        let denom = a - 2 * b + c
        let shift = denom != 0 ? 0.5 * (a - c) / denom : 0
        let period = Float(found) + max(-0.5, min(0.5, shift))
        return PitchEstimate(hz: sampleRate / period, clarity: max(0, min(1, 1 - b)))
    }

    /// Harmonics-to-noise ratio from YIN clarity, dB.
    static func hnr(clarity: Float) -> Float {
        let r = max(0.001, min(0.999, clarity))
        return 10 * log10(r / (1 - r))
    }

    /// 2:1 decimation with a two-tap average (adequate before YIN at 8 kHz).
    static func halve(_ x: [Float]) -> [Float] {
        stride(from: 0, to: x.count - 1, by: 2).map { (x[$0] + x[$0 + 1]) * 0.5 }
    }

    static func mean(_ x: [Double]) -> Double { x.isEmpty ? 0 : x.reduce(0, +) / Double(x.count) }

    static func sd(_ x: [Double]) -> Double {
        guard x.count > 1 else { return 0 }
        let m = mean(x)
        return (x.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(x.count - 1)).squareRoot()
    }

    static func percentile(_ x: [Double], _ p: Double) -> Double {
        guard !x.isEmpty else { return 0 }
        let s = x.sorted()
        return s[min(s.count - 1, max(0, Int(Double(s.count - 1) * p)))]
    }

    static func movingAverage(_ x: [Double], width: Int) -> [Double] {
        guard width > 1, x.count > 1 else { return x }
        let half = width / 2
        return x.indices.map { i in
            let lo = max(0, i - half), hi = min(x.count - 1, i + half)
            return x[lo...hi].reduce(0, +) / Double(hi - lo + 1)
        }
    }

    static func movingAverage(_ x: [Float], width: Int) -> [Float] {
        movingAverage(x.map(Double.init), width: width).map(Float.init)
    }
}

/// Second-order high-pass (RBJ cookbook), used to split energy above 2 kHz.
struct Biquad {
    private var b0, b1, b2, a1, a2: Float
    private var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0

    init(highPass cutoff: Float, sampleRate: Float, q: Float = 0.707) {
        let w = 2 * Float.pi * cutoff / sampleRate
        let alpha = sin(w) / (2 * q), cw = cos(w)
        let a0 = 1 + alpha
        b0 = (1 + cw) / 2 / a0
        b1 = -(1 + cw) / a0
        b2 = (1 + cw) / 2 / a0
        a1 = -2 * cw / a0
        a2 = (1 - alpha) / a0
    }

    mutating func process(_ x: Float) -> Float {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x; y2 = y1; y1 = y
        return y
    }
}
