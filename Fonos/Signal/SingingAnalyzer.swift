import Foundation
import os

enum OnsetType: String, Codable, Sendable {
    case balanced, hard, breathy

    var beginnerLabel: String {
        switch self {
        case .balanced: "Easy, clean starts"
        case .hard: "Hard starts"
        case .breathy: "Breathy starts"
        }
    }
}

struct NoteScore: Codable, Hashable, Sendable {
    var midi: Int
    var cents: Int
    var settleMs: Int
}

struct SignalQuality: Codable, Equatable, Sendable {
    enum Level: String, Codable, Sendable { case good, fair, low }
    var overall: Level = .good
    var leftContact = true
    var rightContact = true
    var agreementPct = 100
    var noiseFloorDb = -60
    var clipping = false

    /// One plain sentence about what to fix, or nil when quality is good.
    var advice: String? {
        if !leftContact && !rightContact { return "Fonos couldn't feel the band. Fit it snugly just above your collarbone." }
        if !leftContact { return "Fonos can't feel the band on the left. Adjust it and try again." }
        if !rightContact { return "Fonos can't feel the band on the right. Adjust it and try again." }
        if clipping { return "The microphone was overloaded. Sing a little softer." }
        if overall == .low { return "The signal was weak this take, so feedback is limited." }
        if noiseFloorDb > -45 { return "The room is noisy, so tone measures may be less reliable." }
        return nil
    }
}

/// Everything measured from one take.
struct TakeResult: Sendable {
    var kind: ExerciseKind
    var date: Date
    var duration: Double
    var metrics: [MetricID: Double]
    var onsetType: OnsetType?
    var worstNotes: [NoteScore]
    var quality: SignalQuality
    var lowNote: Int?
    var highNote: Int?
}

/// Turns band frames into singing measurements.
///
/// Live: voicing, fused pitch, and tuning against the current target (for the
/// needle and the pitch lane). Per take: the metrics in Docs/SPEC.md § 5,
/// computed from per-frame features once the take ends.
final class SingingAnalyzer: @unchecked Sendable {

    struct Live: Equatable, Sendable {
        var voiced = false
        var midi: Double?
        var target: Double?
        var cents: Double?
        var inTune = false
        var micDb: Float = -90
        var leftLevel: Float = 0
        var rightLevel: Float = 0
    }

    /// One 10 ms frame, reduced to the features the metrics need.
    struct Feature: Sendable {
        var t: Double
        var voiced: Bool
        var midi: Double?
        var micMidi: Double?
        var accelMidi: Double?
        var micDb: Float
        var micVoicedLevel: Bool
        var accelL: Float
        var accelR: Float
        var motion: Float
        var clarity: Float
        var ringDb: Float?
        var micRms: Float
    }

    private let lock = OSAllocatedUnfairLock()

    // Rolling state
    private var mic8k: [Float] = []
    private var accelWindow: [Float] = []
    private var ringFilter = Biquad(highPass: 2_000, sampleRate: Float(BandRates.mic))
    private var noiseFloor: Float = -60
    private var frameIndex = 0
    private var live = Live()

    // Take state
    private var plan: TakePlan?
    private var takeStartFrame = 0
    private var features: [Feature] = []
    private var clippedSamples = 0
    private var totalSamples = 0
    private var recording = false

    static let voiceThreshold: Float = 0.01

    // MARK: Control

    /// Start a take; `countIn` seconds from now is t = 0.
    func begin(_ plan: TakePlan, countIn: Double) {
        lock.withLock {
            self.plan = plan
            takeStartFrame = frameIndex + Int(countIn * 100)
            features.removeAll(keepingCapacity: true)
            clippedSamples = 0
            totalSamples = 0
            recording = true
        }
    }

    func cancel() {
        lock.withLock { recording = false; plan = nil; features.removeAll() }
    }

    var liveState: Live { lock.withLock { live } }

    /// Seconds since t = 0 of the current take (negative during the count-in).
    var takeTime: Double? {
        lock.withLock { recording ? Double(frameIndex - takeStartFrame) / 100 : nil }
    }

    /// The pitch track of the current take, for the pitch lane.
    func pitchTrack() -> [(t: Double, midi: Double?)] {
        lock.withLock { features.map { ($0.t, $0.midi) } }
    }

    // MARK: Ingest

    func ingest(_ frame: SensorFrame) {
        let micRms = DSP.rms(frame.mic)
        let db = DSP.dbfs(micRms)
        let l = DSP.rms(frame.left), r = DSP.rms(frame.right)

        var hp: Float = 0, total: Float = 0, clipped = 0
        for s in frame.mic {
            let h = ringFilter.process(s)
            hp += h * h
            total += s * s
            if abs(s) > 0.99 { clipped += 1 }
        }
        let low = max(total - hp, 1e-9)
        let ringDb = 10 * log10(max(hp, 1e-9) / low)

        lock.withLock {
            // Adaptive noise floor: follows quiet frames down, rises slowly.
            if db < noiseFloor { noiseFloor = db } else { noiseFloor += 0.02 }
            noiseFloor = min(max(noiseFloor, -85), -30)

            mic8k.append(contentsOf: DSP.halve(frame.mic))
            if mic8k.count > 256 { mic8k.removeFirst(mic8k.count - 256) }
            accelWindow.append(contentsOf: frame.left)
            if accelWindow.count > 128 { accelWindow.removeFirst(accelWindow.count - 128) }

            let micLoud = db > noiseFloor + 12
            let micPitch = (micLoud && mic8k.count == 256) ? DSP.yin(mic8k, sampleRate: 8_000) : nil
            let accelPitch = (l > Self.voiceThreshold && accelWindow.count == 128)
                ? DSP.yin(accelWindow, sampleRate: Float(BandRates.accel), maxHz: 1_000) : nil
            let micMidi = micPitch.flatMap { $0.clarity > 0.75 ? Music.midi(hz: Double($0.hz)) : nil }
            let accelMidi = accelPitch.flatMap { $0.clarity > 0.7 ? Music.midi(hz: Double($0.hz)) : nil }
            // Fuse: the mic by default; the accelerometer when the mic is noisy.
            let midi = micMidi ?? accelMidi
            let voiced = midi != nil && (l > Self.voiceThreshold || micLoud)

            let t = Double(frameIndex - takeStartFrame) / 100
            let target = recording ? plan?.target(at: t) : nil
            var cents: Double?
            if let midi, let target, voiced { cents = Self.foldOctave((midi - target) * 100) }
            live = Live(voiced: voiced, midi: voiced ? midi : nil, target: target, cents: cents,
                        inTune: cents.map { abs($0) <= 25 } ?? false, micDb: db, leftLevel: l, rightLevel: r)

            if recording, t >= -0.2, t <= (plan?.duration ?? 0) + 0.3 {
                features.append(Feature(
                    t: t, voiced: voiced, midi: voiced ? midi : nil, micMidi: micMidi, accelMidi: accelMidi,
                    micDb: db, micVoicedLevel: micLoud, accelL: l, accelR: r,
                    motion: (frame.leftMotion + frame.rightMotion) / 2,
                    clarity: micPitch?.clarity ?? 0, ringDb: voiced ? ringDb : nil, micRms: micRms))
                clippedSamples += clipped
                totalSamples += frame.mic.count
            }
            frameIndex += 1
        }
    }

    /// Octave errors in pitch tracking show up as ±1200 cents; fold them back.
    static func foldOctave(_ cents: Double) -> Double {
        var c = cents
        while c > 600 { c -= 1_200 }
        while c < -600 { c += 1_200 }
        return c
    }

    // MARK: Finish

    func finish(date: Date = .now) -> TakeResult? {
        let (plan, f, clipped, total, floor) = lock.withLock {
            recording = false
            return (self.plan, features, clippedSamples, totalSamples, noiseFloor)
        }
        guard let plan else { return nil }
        return Self.analyze(plan: plan, features: f, clipped: clipped, totalSamples: total, noiseFloor: floor, date: date)
    }

    /// Pure function from features to metrics; tested directly.
    static func analyze(plan: TakePlan, features f: [Feature], clipped: Int, totalSamples: Int, noiseFloor: Float, date: Date) -> TakeResult? {
        let voicedFrames = f.filter(\.voiced)
        guard voicedFrames.count >= 30 else { return nil }
        var m: [MetricID: Double] = [:]

        // Signal quality
        var q = SignalQuality()
        let micVoiced = f.filter(\.micVoicedLevel)
        let medianL = DSP.percentile(micVoiced.map { Double($0.accelL) }, 0.5)
        let medianR = DSP.percentile(micVoiced.map { Double($0.accelR) }, 0.5)
        q.leftContact = micVoiced.count < 10 || medianL > Double(voiceThreshold)
        q.rightContact = micVoiced.count < 10 || medianR > Double(voiceThreshold)
        let both = f.filter { $0.micMidi != nil && $0.accelMidi != nil }
        if both.count > 20 {
            let agree = both.filter { abs(foldOctave(($0.micMidi! - $0.accelMidi!) * 100)) < 50 }.count
            q.agreementPct = Int(Double(agree) / Double(both.count) * 100)
        }
        q.noiseFloorDb = Int(noiseFloor)
        q.clipping = totalSamples > 0 && Double(clipped) / Double(totalSamples) > 0.001
        if !q.leftContact || !q.rightContact || q.clipping || q.agreementPct < 60 { q.overall = .low }
        else if q.agreementPct < 80 || noiseFloor > -45 { q.overall = .fair }

        // Throat vibration (all kinds)
        let accelVoiced = voicedFrames.map { Double($0.accelL + $0.accelR) / 2 }
        m[.throatVibration] = DSP.mean(accelVoiced) * 1_000
        let l = voicedFrames.reduce(0.0) { $0 + Double($1.accelL) }
        let r = voicedFrames.reduce(0.0) { $0 + Double($1.accelR) }
        if l + r > 0 { m[.lrSymmetry] = (1 - abs(l - r) / (l + r)) * 100 }
        let ratios = voicedFrames.filter { $0.micRms > 1e-4 }.map { Double(($0.accelL + $0.accelR) / 2 / $0.micRms) }
        if !ratios.isEmpty { m[.vibrationToSound] = DSP.mean(ratios) }
        m[.larynxRise] = DSP.mean(voicedFrames.map { Double($0.motion) })

        // Loudness and breath
        let levels = voicedFrames.map { Double($0.micDb) }
        m[.dynamicRange] = DSP.percentile(levels, 0.95) - DSP.percentile(levels, 0.05)
        m[.phraseDuration] = longestPhrase(f)

        if plan.kind == .speakingCheck {
            m[.speakingPitch] = DSP.percentile(voicedFrames.compactMap(\.midi), 0.5)
            return TakeResult(kind: plan.kind, date: date, duration: plan.duration, metrics: m, onsetType: nil,
                              worstNotes: [], quality: q, lowNote: nil, highNote: nil)
        }

        if plan.glide {
            let midis = voicedFrames.compactMap(\.midi)
            let lo = Int(DSP.percentile(midis, 0.05).rounded()), hi = Int(DSP.percentile(midis, 0.95).rounded())
            m[.range] = Double(hi - lo)
            return TakeResult(kind: plan.kind, date: date, duration: plan.duration, metrics: m, onsetType: nil,
                              worstNotes: [], quality: q, lowNote: lo, highNote: hi)
        }

        // Per-note analysis
        var inTune = 0, scored = 0
        var errors: [Double] = []
        var settles: [Double] = [], excursions: [Double] = []
        var stabilities: [(Double, Int)] = [], levelSDs: [Double] = []
        var vibRates: [Double] = [], vibExtents: [Double] = [], vibRegs: [Double] = []
        var hnrs: [Double] = [], rings: [Double] = [], jitters: [Double] = []
        var onsets: [OnsetType] = []
        var scores: [NoteScore] = []
        var heldInTune: [Int] = []

        for note in plan.notes {
            let frames = f.filter { $0.t >= note.start - 0.1 && $0.t < note.end + 0.05 }
            let sung = frames.filter { $0.voiced && $0.midi != nil }
            guard sung.count >= 8, let onset = sung.first?.t else { continue }
            let cents = sung.map { foldOctave(($0.midi! - Double(note.midi)) * 100) }
            let times = sung.map(\.t)

            // Onset: excursion in the first 150 ms, then settling.
            let early = zip(times, cents).filter { $0.0 < onset + 0.15 }.map(\.1)
            let excursion = early.max(by: { abs($0) < abs($1) }) ?? 0
            var settleIndex = cents.count
            for i in cents.indices where i + 10 <= cents.count {
                if cents[i..<(i + 10)].allSatisfy({ abs($0) <= 25 }) { settleIndex = i; break }
            }
            let settle = settleIndex < cents.count ? times[settleIndex] - onset : note.duration
            settles.append(settle * 1_000)
            excursions.append(excursion)

            // Accuracy excludes the first 150 ms of each note.
            let judged = zip(times, cents).filter { $0.0 >= onset + 0.15 }.map(\.1)
            inTune += judged.filter { abs($0) <= 25 }.count
            scored += judged.count
            errors.append(contentsOf: judged)

            if judged.filter({ abs($0) <= 25 }).count >= 50 { heldInTune.append(note.midi) }

            // Sustain: frames after settling, on notes long enough to hold.
            if note.duration >= 0.6, settleIndex < cents.count - 20 {
                let held = Array(cents[settleIndex...])
                let slow = DSP.movingAverage(held, width: 30)
                stabilities.append((DSP.sd(slow), held.count))
                let resid = zip(held, slow).map { $0 - $1 }
                if let v = vibrato(resid) {
                    vibRates.append(v.rate); vibExtents.append(v.extent); vibRegs.append(v.regularity)
                }
                let heldFrames = Array(sung[settleIndex...])
                levelSDs.append(DSP.sd(heldFrames.map { Double($0.micDb) }))
                hnrs.append(DSP.mean(heldFrames.map { Double(DSP.hnr(clarity: $0.clarity)) }))
                rings.append(DSP.mean(heldFrames.compactMap { $0.ringDb.map(Double.init) }))
                let hz = heldFrames.compactMap(\.midi).map { Music.hz(midi: $0) }
                if hz.count > 2 {
                    let deltas = zip(hz.dropFirst(), hz).map { abs($0 - $1) / $1 * 100 }
                    jitters.append(DSP.mean(deltas))
                }
            }

            // Onset type: does sound precede vibration (breathy), or does vibration jump on (hard)?
            let micOnset = frames.first(where: \.micVoicedLevel)?.t
            let accelMedian = DSP.percentile(sung.map { Double($0.accelL) }, 0.5)
            let accelOnsetIdx = frames.firstIndex { Double($0.accelL) > 0.25 * accelMedian }
            if let micOnset, let ai = accelOnsetIdx {
                let accelOnset = frames[ai].t
                let rise = frames[ai...].prefix(3).last.map { Double($0.accelL) } ?? 0
                if accelOnset - micOnset >= 0.03 { onsets.append(.breathy) }
                else if ai > 0, Double(frames[ai - 1].accelL) < 0.1 * accelMedian, rise > 0.8 * accelMedian { onsets.append(.hard) }
                else { onsets.append(.balanced) }
            }

            scores.append(NoteScore(midi: note.midi, cents: Int(DSP.mean(judged).rounded()), settleMs: Int(settle * 1_000)))
        }

        if scored > 0 {
            m[.pitchAccuracy] = Double(inTune) / Double(scored) * 100
            m[.pitchError] = DSP.mean(errors)
        }
        if !settles.isEmpty { m[.onsetSettle] = DSP.mean(settles) }
        if !excursions.isEmpty { m[.onsetExcursion] = DSP.mean(excursions) }
        if !stabilities.isEmpty {
            let n = stabilities.reduce(0) { $0 + $1.1 }
            m[.sustainStability] = stabilities.reduce(0.0) { $0 + $1.0 * Double($1.1) } / Double(n)
        }
        if !vibRates.isEmpty {
            m[.vibratoRate] = DSP.mean(vibRates)
            m[.vibratoExtent] = DSP.mean(vibExtents)
            m[.vibratoRegularity] = DSP.mean(vibRegs)
        }
        if !levelSDs.isEmpty { m[.levelStability] = DSP.mean(levelSDs) }
        if !hnrs.isEmpty { m[.hnr] = DSP.mean(hnrs) }
        if !rings.isEmpty { m[.ring] = DSP.mean(rings) }
        if !jitters.isEmpty { m[.jitter] = DSP.mean(jitters) }

        let onsetType = mostCommon(onsets)
        let worst = scores.sorted { abs($0.cents) > abs($1.cents) }.prefix(3)
        let lo = heldInTune.min(), hi = heldInTune.max()
        if let lo, let hi, hi > lo { m[.range] = Double(hi - lo) }

        return TakeResult(kind: plan.kind, date: date, duration: plan.duration, metrics: m, onsetType: onsetType,
                          worstNotes: Array(worst), quality: q, lowNote: lo, highNote: hi)
    }

    /// Vibrato from a detrended pitch residual (cents at 100 Hz).
    static func vibrato(_ resid: [Double]) -> (rate: Double, extent: Double, regularity: Double)? {
        guard resid.count >= 40 else { return nil }
        let extent = (resid.reduce(0) { $0 + $1 * $1 } / Double(resid.count)).squareRoot() * 2.0.squareRoot()
        guard extent >= 10 else { return nil }
        // Upward zero crossings with a little hysteresis.
        var ups: [Int] = []
        var armed = false
        for (i, v) in resid.enumerated() {
            if v < -3 { armed = true }
            if armed, v > 3 { ups.append(i); armed = false }
        }
        guard ups.count >= 3 else { return nil }
        let periods = zip(ups.dropFirst(), ups).map { Double($0 - $1) / 100 }
        let meanPeriod = DSP.mean(periods)
        let rate = 1 / meanPeriod
        guard (3...9).contains(rate) else { return nil }
        return (rate, extent, DSP.sd(periods) / meanPeriod * 100)
    }

    static func longestPhrase(_ f: [Feature]) -> Double {
        var best = 0, run = 0, gap = 0
        for frame in f {
            if frame.voiced { run += 1 + gap; gap = 0; best = max(best, run) }
            else if run > 0 {
                gap += 1
                if gap > 8 { run = 0; gap = 0 }
            }
        }
        return Double(best) / 100
    }

    static func mostCommon<T: Hashable>(_ x: [T]) -> T? {
        Dictionary(grouping: x, by: { $0 }).max { $0.value.count < $1.value.count }?.key
    }
}
