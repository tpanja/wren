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
/// It can also "perform" each Speech check task. Nothing here is a real
/// measurement.
final class ToyBand: FrameSource, @unchecked Sendable {

    /// What the simulated wearer is doing.
    enum Mode: Equatable, Sendable {
        /// Free conversation: utterances with silences between them.
        case conversation
        /// One sustained vowel until the breath runs out, then silence.
        case vowel
        /// Fast repeated syllables. `smr` is "pa-ta-ka" (slightly slower).
        case ddk(smr: Bool)
        /// Reading a passage: phrases with breath pauses, slowly tiring.
        case passage
    }

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
    private let modeLock = OSAllocatedUnfairLock(initialState: Mode.conversation)
    private var activeMode = Mode.conversation
    private var modeElapsed = 0.0
    private var modeLength = 0.0

    /// Left/right balance of the simulated throat. 1 = symmetric.
    var asymmetry: Double = 0.86

    var status: BandStatus { statusLock.withLock { $0 } }

    func setTalking(_ on: Bool) {
        forceSpeech.withLock { $0 = on }
    }

    func setMode(_ mode: Mode) {
        modeLock.withLock { $0 = mode }
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

    /// Resets per-mode state when the requested mode changes.
    private func enter(_ mode: Mode) {
        activeMode = mode
        modeElapsed = 0
        syllablePhase = 0
        switch mode {
        case .conversation:
            segmentRemaining = 0.6; speaking = false
        case .vowel:
            // Silence first (the wearer takes a breath), then the vowel.
            modeLength = .random(in: 10.5...13.5, using: &rng)
            f0 = .random(in: 112...124, using: &rng)
            speaking = false; segmentRemaining = 0.8
        case .ddk(let smr):
            syllableRate = smr ? 5.3 : 6.1
            f0 = .random(in: 115...125, using: &rng)
            speaking = false; segmentRemaining = 0.5
        case .passage:
            modeLength = .random(in: 17...20, using: &rng)
            syllableRate = .random(in: 3.8...4.2, using: &rng)
            f0 = .random(in: 112...128, using: &rng)
            speaking = false; segmentRemaining = 0.7
        }
    }

    private func tick() {
        let dt = 0.010
        let requested = modeLock.withLock { $0 }
        if requested != activeMode { enter(requested) }
        modeElapsed += dt
        let forced = forceSpeech.withLock { $0 }

        // Decide whether the wearer is voicing this frame, the syllable shape, and loudness.
        var envShape = 0.78       // share of each syllable cycle that is voiced
        var amp = 0.42
        var sustained = false     // vowel: no syllable envelope
        segmentRemaining -= dt
        switch activeMode {
        case .conversation:
            if segmentRemaining <= 0 {
                speaking.toggle()
                segmentRemaining = speaking ? .random(in: 1.4...3.2, using: &rng) : .random(in: 0.7...1.6, using: &rng)
                syllableRate = .random(in: 2.9...3.8, using: &rng)
                f0 = .random(in: 108...132, using: &rng)
            }
        case .vowel:
            if segmentRemaining <= 0, !speaking, modeElapsed < 2 { speaking = true }
            let voicedFor = modeElapsed - 0.8
            if voicedFor > modeLength { speaking = false }
            sustained = true
            // Loudness sags slightly as breath runs out.
            amp = 0.42 * (1 - 0.3 * max(0, min(1, voicedFor / max(modeLength, 1))))
        case .ddk(let smr):
            if segmentRemaining <= 0 { speaking = true }
            envShape = 0.55
            // Small cycle-to-cycle timing irregularity, more for pa-ta-ka.
            if Int(modeElapsed * 100) % 10 == 0 {
                syllableRate = (smr ? 5.3 : 6.1) * (1 + .random(in: -(smr ? 0.06 : 0.035)...(smr ? 0.06 : 0.035), using: &rng))
            }
        case .passage:
            if segmentRemaining <= 0 {
                speaking.toggle()
                segmentRemaining = speaking ? .random(in: 2.2...3.6, using: &rng) : .random(in: 0.35...0.8, using: &rng)
            }
            if modeElapsed > modeLength { speaking = false; segmentRemaining = 10 }
            // Reading tires the voice: about 15% weaker by the end.
            amp = 0.42 * (1 - 0.15 * min(1, modeElapsed / max(modeLength, 1)))
        }
        let voiced = speaking || (forced && activeMode == .conversation)

        var mic = [Float](repeating: 0, count: 80)
        var left = [Float](repeating: 0, count: 10)
        var right = [Float](repeating: 0, count: 10)

        for i in 0..<80 {
            let t = 1.0 / 8_000
            syllablePhase += syllableRate * t
            let s = syllablePhase.truncatingRemainder(dividingBy: 1)
            let env: Double
            if !voiced { env = 0 }
            else if sustained { env = 1 }
            else { env = max(0, sin(.pi * min(1, s / envShape))) }
            let jitter = 1 + Double.random(in: -0.012...0.012, using: &rng)
            phase += 2 * .pi * f0 * jitter * t
            var v = 0.0
            for h in 1...6 { v += sin(phase * Double(h)) / Double(h * h) }
            let noise = Double.random(in: -1...1, using: &rng)
            mic[i] = Float(amp * env * v + 0.006 * noise)
            if i % 8 == 0 {
                let k = i / 8
                let base = env * sin(phase) * 0.55 * (amp / 0.42)
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
