import Foundation
import os

/// Turns the three live streams into the per-session speech measures.
///
/// Every measure is descriptive. None of them is a diagnosis, and the UI
/// presents them as trends against the patient's own baseline.
///
/// | Measure      | Source           | Definition |
/// |--------------|------------------|------------|
/// | Strength     | mic              | Mean level of voiced 10 ms frames, dBFS |
/// | Pace         | mic envelope     | Syllable nuclei per second of speaking time |
/// | Pauses       | mic              | Share of speaking time that is silent |
/// | Symmetry     | left/right piezo | 1 − |L − R| / (L + R) over voiced frames |
/// | Steadiness   | mic pitch        | Frame-to-frame F0 change, % of mean F0 |
/// | Clarity      | translator       | Mean recognizer confidence of segments |
final class SpeechAnalyzer: @unchecked Sendable {

    struct Live: Equatable {
        var isVoicing = false
        var micDb: Float = -90
        var leftLevel: Float = 0
        var rightLevel: Float = 0
        var pitchHz: Float?
    }

    private let lock = OSAllocatedUnfairLock()

    // Adaptive noise floor (dBFS); rises slowly, falls fast.
    private var noiseFloor: Float = -60
    private let voicingMargin: Float = 12

    private var frames = 0
    private var voicedFrames = 0
    private var voicedDbSum: Double = 0
    private var envelope: [Float] = []
    private var firstVoiced: Int?
    private var lastVoiced: Int?
    private var leftEnergy: Double = 0
    private var rightEnergy: Double = 0
    private var piezoFrames = 0
    private var pitches: [Float] = []
    private var pitchDeltas: [Float] = []
    private var pitchSum: Float = 0
    private var pitchCount = 0
    private var micWindow: [Float] = []
    private var clarity: [Double] = []
    private var live = Live()

    func reset() {
        lock.withLock {
            frames = 0; voicedFrames = 0; voicedDbSum = 0
            envelope.removeAll(keepingCapacity: true)
            firstVoiced = nil; lastVoiced = nil
            leftEnergy = 0; rightEnergy = 0; piezoFrames = 0
            pitches.removeAll(); pitchDeltas.removeAll(); pitchSum = 0; pitchCount = 0
            micWindow.removeAll(); clarity.removeAll()
            live = Live()
        }
    }

    func ingest(_ frame: SensorFrame) {
        let micRms = DSP.rms(frame.mic)
        let db = DSP.dbfs(micRms)
        let l = DSP.rms(frame.left), r = DSP.rms(frame.right)

        lock.withLock {
            // Noise floor tracker.
            if db < noiseFloor { noiseFloor = db } else { noiseFloor += 0.02 }
            noiseFloor = min(max(noiseFloor, -80), -25)

            let voiced = db > noiseFloor + voicingMargin
            envelope.append(db)
            if voiced {
                voicedFrames += 1
                voicedDbSum += Double(db)
                if firstVoiced == nil { firstVoiced = frames }
                lastVoiced = frames
                if !frame.left.isEmpty {
                    leftEnergy += Double(l)
                    rightEnergy += Double(r)
                    piezoFrames += 1
                }
            }

            // Pitch on a 30 ms sliding window, every other frame.
            micWindow.append(contentsOf: frame.mic)
            if micWindow.count > 240 { micWindow.removeFirst(micWindow.count - 240) }
            var f0: Float?
            if voiced, frames % 2 == 0, micWindow.count == 240 {
                f0 = DSP.pitch(micWindow, sampleRate: 8_000)
                if let f0 {
                    if let last = pitches.last { pitchDeltas.append(abs(f0 - last)) }
                    pitches.append(f0)
                    pitchSum += f0; pitchCount += 1
                }
            } else if !voiced, !pitches.isEmpty {
                // Do not count the jump across a pause as instability.
                pitches.removeAll(keepingCapacity: true)
            }

            frames += 1
            live = Live(isVoicing: voiced, micDb: db, leftLevel: l, rightLevel: r, pitchHz: f0 ?? (voiced ? live.pitchHz : nil))
        }
    }

    func addClarity(_ confidence: Double) {
        lock.withLock { clarity.append(confidence) }
    }

    var liveState: Live { lock.withLock { live } }

    /// Seconds of signal received in this session.
    var elapsed: Double { lock.withLock { Double(frames) / 100 } }

    func summary(started: Date, isSample: Bool, phrases: Int) -> SessionRecord? {
        lock.withLock {
            guard voicedFrames >= 50, let first = firstVoiced, let last = lastVoiced else { return nil }
            let span = Array(envelope[first...last])
            let spanSeconds = Double(span.count) / 100
            let syllables = DSP.syllablePeaks(span, floorDb: noiseFloor + voicingMargin)
            let pauseRatio = 1 - Double(voicedFrames) / Double(max(span.count, 1))
            let meanF0 = pitchCount > 0 ? pitchSum / Float(pitchCount) : 0
            let variation: Double? = (pitchDeltas.count > 10 && meanF0 > 0)
                ? Double(pitchDeltas.reduce(0, +) / Float(pitchDeltas.count) / meanF0 * 100) : nil
            let symmetry: Double? = piezoFrames > 20
                ? 1 - abs(leftEnergy - rightEnergy) / max(leftEnergy + rightEnergy, 1e-9) : nil

            return SessionRecord(
                id: UUID(), date: started,
                duration: Double(frames) / 100,
                speakingSeconds: spanSeconds,
                strengthDb: voicedDbSum / Double(voicedFrames),
                pace: Double(syllables) / max(spanSeconds * (1 - pauseRatio), 0.5),
                pauseRatio: pauseRatio,
                symmetry: symmetry,
                pitchVariation: variation,
                clarity: clarity.isEmpty ? nil : clarity.reduce(0, +) / Double(clarity.count),
                phrases: phrases,
                isSample: isSample
            )
        }
    }
}
