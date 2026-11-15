import Foundation
import os

/// Band sample rates. See Docs/HARDWARE-INTEGRATION.md.
enum BandRates {
    static let mic = 16_000
    static let accel = 4_000
    /// Samples per 10 ms frame.
    static let micPerFrame = 160
    static let accelPerFrame = 40
}

/// 10 ms of synchronized signal from the throat band.
struct SensorFrame: Sendable {
    /// Microphone, 16 kHz, -1...1.
    var mic: [Float]
    /// Left accelerometer, voice band, 4 kHz, normalized -1...1.
    var left: [Float]
    /// Right accelerometer, voice band, 4 kHz.
    var right: [Float]
    /// Slow laryngeal motion from each accelerometer (below 15 Hz), arbitrary units.
    var leftMotion: Float
    var rightMotion: Float
}

struct BandStatus: Equatable, Sendable {
    var battery = 82
    var leftContact = true
    var rightContact = true
    var isCharging = false
}

/// The seam for the real hardware. Today only `ToyBand` conforms; a Bluetooth
/// band plugs in here without touching the analyzer or the UI.
/// Frames arrive on a background queue, 100 per second.
protocol FrameSource: AnyObject {
    var onFrame: (@Sendable (SensorFrame) -> Void)? { get set }
    var status: BandStatus { get }
    func startStreaming()
    func stopStreaming()
}

/// How the toy singer sings one take. Randomized per take within realistic bounds.
struct ToySingerStyle: Sendable {
    /// Average tuning offset, cents (negative = flat).
    var offsetCents: Double
    /// Note-to-note tuning spread, cents.
    var noteSpread: Double
    /// Pitch at onset relative to target, cents (negative = scoop from below).
    var scoopCents: Double
    /// Time constant for settling onto the note, s.
    var settleTau: Double
    var vibratoRate: Double
    var vibratoExtent: Double
    /// Slow wobble on held notes, cents.
    var wobbleCents: Double
    /// Chance that a note starts breathy (air before vibration).
    var breathyChance: Double
    var rightBalance: Double

    static func random() -> ToySingerStyle {
        ToySingerStyle(
            offsetCents: .random(in: -16 ... -2),
            noteSpread: .random(in: 4...12),
            scoopCents: .random(in: -45 ... -15),
            settleTau: .random(in: 0.05...0.11),
            vibratoRate: .random(in: 5.0...6.2),
            vibratoExtent: .random(in: 25...55),
            wobbleCents: .random(in: 4...12),
            breathyChance: .random(in: 0.15...0.5),
            rightBalance: .random(in: 0.86...0.96)
        )
    }
}

/// Toy data: a simulated band worn by a simulated singer. It hums softly now
/// and then while idle, sings the exact plan of a take when asked (with
/// realistic scoops, drift, and vibrato), and speaks for the speaking check.
/// Nothing here is a real measurement.
final class ToyBand: FrameSource, @unchecked Sendable {

    var onFrame: (@Sendable (SensorFrame) -> Void)?

    private let queue = DispatchQueue(label: "fonos.toyband", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private let statusLock = OSAllocatedUnfairLock(initialState: BandStatus())
    private var rng = SystemRandomNumberGenerator()

    // Script state (guarded by `queue`).
    private var plan: TakePlan?
    private var planStartFrame = 0
    private var style = ToySingerStyle.random()
    private var noteOffsets: [Double] = []
    private var noteBreathy: [Bool] = []
    private var humming = false
    private var frame = 0

    // Oscillator state.
    private var phase = 0.0
    private var accelPhase = 0.0
    private var envelope = 0.0
    private var noise = 0.0

    var status: BandStatus { statusLock.withLock { $0 } }

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

    /// Sing `plan` starting `delay` seconds from now (the count-in).
    func sing(_ plan: TakePlan, after delay: Double) {
        queue.async { [self] in
            self.plan = plan
            planStartFrame = frame + Int(delay * 100)
            style = .random()
            noteOffsets = plan.notes.map { _ in style.offsetCents + Double.random(in: -style.noteSpread...style.noteSpread, using: &rng) }
            noteBreathy = plan.notes.map { _ in Double.random(in: 0...1, using: &rng) < style.breathyChance }
        }
    }

    func stopSinging() {
        queue.async { [self] in plan = nil }
    }

    /// Hold a comfortable note (used by the fit check).
    func setHumming(_ on: Bool) {
        queue.async { [self] in humming = on }
    }

    // MARK: Synthesis

    private struct Voice {
        var midi: Double
        var amplitude: Double
        var breathNoise: Double
        var speech: Bool
    }

    /// What the toy singer is doing at the current frame.
    private func voice() -> Voice? {
        if let plan, frame >= planStartFrame {
            let t = Double(frame - planStartFrame) / 100
            if t > plan.duration + 0.2 { self.plan = nil; return nil }
            if plan.kind == .speakingCheck {
                // Speech: syllables at ~4/s with a falling, wandering pitch.
                guard t < 4.6 else { return nil }
                let syl = max(0, sin(.pi * (t * 4.2).truncatingRemainder(dividingBy: 1)))
                let f0 = 49 + 2.2 * sin(t * 1.7) - 1.2 * t / 4.6
                return Voice(midi: f0, amplitude: 0.5 * syl, breathNoise: 0.02, speech: true)
            }
            if plan.glide {
                guard let target = plan.target(at: t) else { return nil }
                return Voice(midi: target + style.offsetCents / 100 + 0.1 * sin(t * 3), amplitude: 0.55, breathNoise: 0.01, speech: false)
            }
            guard let index = plan.notes.firstIndex(where: { t >= $0.start - 0.02 && t < $0.end }) else { return nil }
            let note = plan.notes[index]
            let dt = max(0, t - note.start)
            var cents = noteOffsets[index]
            cents += style.scoopCents * exp(-dt / style.settleTau)
            cents += style.wobbleCents * sin(2 * .pi * 0.7 * t + Double(index))
            if note.duration >= 0.6, dt > 0.3 {
                let fade = min(1, (dt - 0.3) / 0.4)
                cents += fade * style.vibratoExtent * sin(2 * .pi * style.vibratoRate * dt)
            }
            // Breathy onsets: air noise for 40 ms before the folds vibrate.
            let breathy = noteBreathy[index] && dt < 0.04
            let attack = min(1, dt / 0.05), release = min(1, (note.end - t) / 0.05)
            return Voice(midi: Double(note.midi) + cents / 100,
                         amplitude: breathy ? 0 : 0.6 * attack * max(0, release),
                         breathNoise: breathy ? 0.08 : 0.01, speech: false)
        }
        if humming {
            return Voice(midi: 52 + 0.08 * sin(Double(frame) / 40), amplitude: 0.35, breathNoise: 0.005, speech: false)
        }
        // Idle: an occasional soft hum so the throat strip shows the band is alive.
        let cycle = frame % 900
        if cycle < 140 {
            let x = Double(cycle) / 140
            return Voice(midi: 50 + 2 * x, amplitude: 0.18 * sin(.pi * x), breathNoise: 0.004, speech: false)
        }
        return nil
    }

    private func tick() {
        let v = voice()
        let targetEnv = v?.amplitude ?? 0
        let f0 = Music.hz(midi: v?.midi ?? 50)
        let breath = v?.breathNoise ?? 0.002

        var mic = [Float](repeating: 0, count: BandRates.micPerFrame)
        var left = [Float](repeating: 0, count: BandRates.accelPerFrame)
        var right = [Float](repeating: 0, count: BandRates.accelPerFrame)

        let micDt = 1.0 / Double(BandRates.mic)
        let harmonics = min(24, Int(3_800 / f0))
        for i in 0..<BandRates.micPerFrame {
            envelope += (targetEnv - envelope) * 0.004
            phase += 2 * .pi * f0 * micDt
            if phase > 2 * .pi * 1_000 { phase -= 2 * .pi * 1_000 }
            var s = 0.0
            if envelope > 0.001 {
                for h in 1...max(1, harmonics) {
                    let hz = Double(h) * f0
                    // Falling spectrum plus a "ring" bump near 3 kHz.
                    let w = 1 / Double(h) + 0.25 * exp(-pow((hz - 3_000) / 500, 2))
                    s += w * sin(phase * Double(h))
                }
            }
            noise = 0.7 * noise + 0.3 * Double.random(in: -1...1, using: &rng)
            mic[i] = Float(0.35 * envelope * s + breath * noise)
        }
        let accelDt = 1.0 / Double(BandRates.accel)
        for i in 0..<BandRates.accelPerFrame {
            accelPhase += 2 * .pi * f0 * accelDt
            if accelPhase > 2 * .pi * 1_000 { accelPhase -= 2 * .pi * 1_000 }
            let base = envelope * (sin(accelPhase) + 0.3 * sin(2 * accelPhase))
            left[i] = Float(0.5 * base + 0.002 * Double.random(in: -1...1, using: &rng))
            right[i] = Float(0.5 * base * style.rightBalance + 0.002 * Double.random(in: -1...1, using: &rng))
        }
        // Larynx rises a little with pitch while voicing.
        let motion = Float(envelope > 0.05 ? 0.15 + 0.025 * ((v?.midi ?? 50) - 48) : 0)

        frame += 1
        if frame % 18_000 == 0 { statusLock.withLock { $0.battery = max(5, $0.battery - 1) } }
        onFrame?(SensorFrame(mic: mic, left: left, right: right, leftMotion: motion, rightMotion: motion * 0.97))
    }
}
