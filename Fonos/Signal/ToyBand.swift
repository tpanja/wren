import Foundation
import os

/// 10 ms of synchronized signal from the three throat-band sensors.
struct SensorFrame: Sendable {
    /// Contact microphone, 8 kHz, -1...1 (80 samples per frame).
    var mic: [Float]
    /// Left piezo, 1 kHz, -1...1 (10 samples per frame).
    var left: [Float]
    /// Right piezo, 1 kHz, -1...1 (10 samples per frame).
    var right: [Float]
}

/// What the band reports about itself.
struct BandStatus: Equatable, Sendable {
    var battery = 82
    var leftContact = true
    var rightContact = true
    var isCharging = false
}

/// The seam for the real hardware. Today only `ToyBand` conforms; a future
/// Bluetooth source plugs in here without touching the analyzer or the UI.
/// Frames are delivered on a background queue, about 100 per second.
protocol FrameSource: AnyObject {
    var onFrame: (@Sendable (SensorFrame) -> Void)? { get set }
    var status: BandStatus { get }
    func startStreaming()
    func stopStreaming()
}

/// Toy data. Generates speech-shaped signals (voiced syllables with pitch
/// jitter and pauses, a slightly stronger left side) at the rates the real
/// band will use, so every screen shows what it would look like in real life.
/// Nothing here is a real measurement.
final class ToyBand: FrameSource, @unchecked Sendable {

    var onFrame: (@Sendable (SensorFrame) -> Void)?

    private let queue = DispatchQueue(label: "fonos.toyband", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private let statusLock = OSAllocatedUnfairLock(initialState: BandStatus())
    private var rng = SystemRandomNumberGenerator()

    private var phase: Double = 0
    private var speaking = false
    private var segmentRemaining = 0.6
    private var syllablePhase = 0.0
    private var syllableRate = 3.4
    private var f0 = 118.0
    private var ticks = 0
    /// When true, the toy wearer is "talking" continuously (used while the Speak button listens).
    private let forceSpeech = OSAllocatedUnfairLock(initialState: false)

    /// Left/right balance of the simulated throat. 1 = symmetric.
    var asymmetry: Double = 0.86

    var status: BandStatus { statusLock.withLock { $0 } }

    func setTalking(_ on: Bool) {
        forceSpeech.withLock { $0 = on }
    }

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
        let forced = forceSpeech.withLock { $0 }
        segmentRemaining -= dt
        if segmentRemaining <= 0 {
            speaking.toggle()
            segmentRemaining = speaking ? .random(in: 1.4...3.2, using: &rng) : .random(in: 0.7...1.6, using: &rng)
            syllableRate = .random(in: 2.9...3.8, using: &rng)
            f0 = .random(in: 108...132, using: &rng)
        }
        let voiced = speaking || forced

        var mic = [Float](repeating: 0, count: 80)
        var left = [Float](repeating: 0, count: 10)
        var right = [Float](repeating: 0, count: 10)

        for i in 0..<80 {
            let t = 1.0 / 8_000
            syllablePhase += syllableRate * t
            // Raised-cosine syllable envelope with a short gap between syllables.
            let s = syllablePhase.truncatingRemainder(dividingBy: 1)
            let env = voiced ? max(0, sin(.pi * min(1, s / 0.78))) : 0
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

        // Battery drains one point every ~3 minutes of streaming.
        ticks += 1
        if ticks % 18_000 == 0 {
            statusLock.withLock { $0.battery = max(5, $0.battery - 1) }
        }

        onFrame?(SensorFrame(mic: mic, left: left, right: right))
    }
}
