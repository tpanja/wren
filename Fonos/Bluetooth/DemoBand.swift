import Foundation

/// A synthetic band. Generates speech-shaped signals (voiced syllables with
/// pitch jitter, pauses, a slightly stronger left side) and routes them
/// through the real frame encoder and parser, so demo mode exercises the
/// same code path as hardware.
final class DemoBand: FrameSource, @unchecked Sendable {

    var onFrame: (@Sendable (SensorFrame) -> Void)?

    private let queue = DispatchQueue(label: "fonos.demo", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private var sequence: UInt8 = 0
    private var timestampMs: UInt32 = 0
    private var phase: Double = 0
    private var rng = SystemRandomNumberGenerator()

    // Utterance scheduler
    private var speaking = false
    private var segmentRemaining = 0.6
    private var syllablePhase = 0.0
    private var syllableRate = 3.4
    private var f0 = 118.0

    /// Left/right balance of the simulated throat. 1 = symmetric.
    var asymmetry: Double = 0.86

    func startStreaming() {
        queue.async { [self] in
            guard timer == nil else { return }
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now(), repeating: .milliseconds(10), leeway: .milliseconds(2))
            t.setEventHandler { [weak self] in self?.tick() }
            t.resume()
            timer = t
        }
    }

    func stopStreaming() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
        }
    }

    private func tick() {
        let dt = 0.010
        segmentRemaining -= dt
        if segmentRemaining <= 0 {
            speaking.toggle()
            segmentRemaining = speaking ? Double.random(in: 1.4...3.2, using: &rng) : Double.random(in: 0.7...1.6, using: &rng)
            syllableRate = Double.random(in: 2.9...3.8, using: &rng)
            f0 = Double.random(in: 108...132, using: &rng)
        }

        let micCount = 80, piezoCount = 10
        var mic = [Float](repeating: 0, count: micCount)
        var left = [Float](repeating: 0, count: piezoCount)
        var right = [Float](repeating: 0, count: piezoCount)

        for i in 0..<micCount {
            let t = 1.0 / 8_000
            syllablePhase += syllableRate * t
            // Raised-cosine syllable envelope with a short gap between syllables.
            let s = syllablePhase.truncatingRemainder(dividingBy: 1)
            let env = speaking ? max(0, sin(.pi * min(1, s / 0.78))) : 0
            let jitter = 1 + Double.random(in: -0.012...0.012, using: &rng)
            phase += 2 * .pi * f0 * jitter * t
            var v = 0.0
            for h in 1...6 { v += sin(phase * Double(h)) / Double(h * h) }
            let noise = Double.random(in: -1...1, using: &rng)
            mic[i] = Float(0.42 * env * v + 0.006 * noise)
            if i % 8 == 0 {
                let k = i / 8
                let base = env * sin(phase) * 0.55
                left[k] = Float(base + 0.004 * noise)
                right[k] = Float(base * asymmetry + 0.004 * Double.random(in: -1...1, using: &rng))
            }
        }

        let data = FrameParser.encodeFrame(sequence: sequence, timestamp: timestampMs, mic: mic, left: left, right: right)
        sequence &+= 1
        timestampMs &+= 10
        if let frame = try? FrameParser.parseFrame(data) { onFrame?(frame) }
    }
}
