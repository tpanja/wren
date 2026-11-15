import Foundation
import os

/// Rolling display buffers for the three streams. Written from the frame
/// queue (100 Hz), read by `TimelineView`/`Canvas` at display rate, so it is
/// lock-protected and never published through Observation.
final class StreamStore: @unchecked Sendable {

    static let seconds = 5.0
    private let frameCapacity = Int(seconds * 100)
    private let micDecimation = 10 // 8 kHz → 800 Hz

    private let lock = OSAllocatedUnfairLock()
    private var micWave: Ring
    private var leftWave: Ring
    private var rightWave: Ring
    private var micLevel: Ring
    private var leftLevel: Ring
    private var rightLevel: Ring
    private var hasPiezo = false

    init() {
        micWave = Ring(capacity: Int(Self.seconds * 800))
        leftWave = Ring(capacity: Int(Self.seconds * 1_000))
        rightWave = Ring(capacity: Int(Self.seconds * 1_000))
        micLevel = Ring(capacity: frameCapacity)
        leftLevel = Ring(capacity: frameCapacity)
        rightLevel = Ring(capacity: frameCapacity)
    }

    func append(_ frame: SensorFrame) {
        let decimated = stride(from: 0, to: frame.mic.count, by: micDecimation).map { i -> Float in
            // Keep the sample with the largest magnitude in each bucket so peaks survive.
            let end = min(i + micDecimation, frame.mic.count)
            var best: Float = 0
            for k in i..<end where abs(frame.mic[k]) > abs(best) { best = frame.mic[k] }
            return best
        }
        let m = DSP.rms(frame.mic), l = DSP.rms(frame.left), r = DSP.rms(frame.right)
        lock.withLock {
            micWave.append(contentsOf: decimated)
            micLevel.append(m)
            if !frame.left.isEmpty {
                hasPiezo = true
                leftWave.append(contentsOf: frame.left)
                rightWave.append(contentsOf: frame.right)
                leftLevel.append(l)
                rightLevel.append(r)
            }
        }
    }

    func reset() {
        lock.withLock {
            micWave.clear(); leftWave.clear(); rightWave.clear()
            micLevel.clear(); leftLevel.clear(); rightLevel.clear()
            hasPiezo = false
        }
    }

    /// What the Fold view draws: mic waveform plus both piezo envelopes.
    struct Fold {
        var micWave: [Float] = []
        var leftLevel: [Float] = []
        var rightLevel: [Float] = []
        var hasPiezo = false
    }

    enum Channel { case mic, left, right }

    /// Copies only the Fold view's buffers (no raw piezo waveforms).
    func fold() -> Fold {
        lock.withLock {
            Fold(micWave: micWave.ordered(), leftLevel: leftLevel.ordered(),
                 rightLevel: rightLevel.ordered(), hasPiezo: hasPiezo)
        }
    }

    /// The most recent `seconds` of one raw stream, without copying the rest.
    func trace(_ channel: Channel, seconds: Double) -> [Float] {
        lock.withLock {
            switch channel {
            case .mic: micWave.suffix(Int(seconds * 800))
            case .left: leftWave.suffix(Int(seconds * 1_000))
            case .right: rightWave.suffix(Int(seconds * 1_000))
            }
        }
    }
}

/// Fixed-size ring buffer that always reports `capacity` samples (zero-padded at the start).
struct Ring {
    private var storage: [Float]
    private var head = 0

    init(capacity: Int) { storage = .init(repeating: 0, count: capacity) }

    mutating func append(_ v: Float) {
        storage[head] = v
        head = (head + 1) % storage.count
    }

    mutating func append(contentsOf values: [Float]) {
        for v in values { append(v) }
    }

    mutating func clear() {
        for i in storage.indices { storage[i] = 0 }
        head = 0
    }

    func ordered() -> [Float] {
        Array(storage[head...] + storage[..<head])
    }

    /// The newest `n` samples, oldest first.
    func suffix(_ n: Int) -> [Float] {
        let n = min(n, storage.count)
        let start = (head - n + storage.count) % storage.count
        if start + n <= storage.count { return Array(storage[start..<(start + n)]) }
        return Array(storage[start...] + storage[..<(start + n - storage.count)])
    }
}
