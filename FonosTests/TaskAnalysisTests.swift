import XCTest
@testable import Fonos

/// Task analysis against hand-built signals with known answers, then against
/// the toy band performing each task.
final class TaskAnalysisTests: XCTestCase {

    // MARK: Synthetic frames

    /// One 10 ms frame of a harmonic tone at `amp`, plus white noise.
    private func frame(amp: Float, f0: Double = 120, noise: Float = 0.002, t0: Int, rng: inout SeededGenerator) -> SensorFrame {
        let mic = (0..<80).map { i -> Float in
            let t = Double(t0 * 80 + i) / 8_000
            let v = sin(2 * .pi * f0 * t) + 0.5 * sin(4 * .pi * f0 * t) + 0.25 * sin(6 * .pi * f0 * t)
            return amp * Float(v) + noise * Float.random(in: -1...1, using: &rng)
        }
        return SensorFrame(mic: mic, left: Array(repeating: 0, count: 10), right: Array(repeating: 0, count: 10))
    }

    /// Frames from a per-frame amplitude envelope.
    private func frames(_ env: [Float], noise: Float = 0.002) -> [SensorFrame] {
        var rng = SeededGenerator(seed: 5)
        return env.enumerated().map { frame(amp: $1, noise: noise, t0: $0, rng: &rng) }
    }

    // MARK: Vowel

    func testVowelMeasuresLongestVoicing() throws {
        // 1 s silence, 8 s vowel, 1 s silence.
        let env = [Float](repeating: 0, count: 100) + [Float](repeating: 0.3, count: 800) + [Float](repeating: 0, count: 100)
        let v = try XCTUnwrap(TaskAnalysis.vowel(frames(env)))
        XCTAssertEqual(v.mpt, 8, accuracy: 0.05)
        // A clean tone is highly periodic.
        XCTAssertGreaterThan(try XCTUnwrap(v.hnr), 20)
    }

    func testVowelBridgesShortGapsButNotLongOnes() throws {
        let on = [Float](repeating: 0.3, count: 300), off = [Float](repeating: 0, count: 100)
        // 3 s + 100 ms gap + 3 s = one 6.1 s breath.
        let short = off + on + [Float](repeating: 0, count: 10) + on + off
        XCTAssertEqual(try XCTUnwrap(TaskAnalysis.vowel(frames(short))).mpt, 6.1, accuracy: 0.05)
        // 3 s + 500 ms gap + 3 s = two breaths; MPT is the longer one.
        let long = off + on + [Float](repeating: 0, count: 50) + on + off
        XCTAssertEqual(try XCTUnwrap(TaskAnalysis.vowel(frames(long))).mpt, 3, accuracy: 0.05)
    }

    func testNoisierVowelHasLowerHNR() throws {
        let env = [Float](repeating: 0, count: 50) + [Float](repeating: 0.3, count: 400) + [Float](repeating: 0, count: 50)
        let clean = try XCTUnwrap(TaskAnalysis.vowel(frames(env, noise: 0.002))?.hnr)
        let noisy = try XCTUnwrap(TaskAnalysis.vowel(frames(env, noise: 0.06))?.hnr)
        XCTAssertGreaterThan(clean, noisy + 5)
    }

    func testVowelRejectsSilence() {
        XCTAssertNil(TaskAnalysis.vowel(frames([Float](repeating: 0, count: 500))))
    }

    // MARK: DDK

    /// Syllable bursts every `period` frames, each `width` frames long.
    private func bursts(count: Int, period: [Int], width: Int = 7) -> [Float] {
        var env = [Float](repeating: 0, count: 30)
        for k in 0..<count {
            let p = period[k % period.count]
            env += (0..<p).map { i in i < width ? Float(0.3 * sin(.pi * Double(i) / Double(width))) : 0 }
        }
        return env + [Float](repeating: 0, count: 30)
    }

    func testDDKRateAndRegularity() throws {
        // 30 syllables, one every 180 ms → 5.6 per second, perfectly even.
        let d = try XCTUnwrap(TaskAnalysis.ddk(frames(bursts(count: 30, period: [18]))))
        XCTAssertEqual(d.syllables, 30)
        XCTAssertEqual(d.rate, 100.0 / 18, accuracy: 0.05)
        XCTAssertLessThan(d.regularity, 2)
    }

    func testUnevenDDKIsLessRegular() throws {
        let even = try XCTUnwrap(TaskAnalysis.ddk(frames(bursts(count: 30, period: [18]))))
        let uneven = try XCTUnwrap(TaskAnalysis.ddk(frames(bursts(count: 30, period: [14, 22, 16, 20]))))
        XCTAssertGreaterThan(uneven.regularity, even.regularity + 10)
        // Same mean period, so about the same rate.
        XCTAssertEqual(uneven.rate, even.rate, accuracy: 0.3)
    }

    // MARK: Passage

    func testPassageRemovesOnlyLongPauses() throws {
        // 4 phrases of 8 syllables at 4 per second (25 frames each),
        // separated by 400 ms pauses; syllables have 80 ms gaps inside.
        var env = [Float](repeating: 0, count: 30)
        for p in 0..<4 {
            for _ in 0..<8 {
                env += (0..<25).map { i in i < 17 ? Float(0.3 * sin(.pi * Double(i) / 17)) : 0 }
            }
            if p < 3 { env += [Float](repeating: 0, count: 40) }
        }
        env += [Float](repeating: 0, count: 30)
        let r = try XCTUnwrap(TaskAnalysis.passage(frames(env)))
        XCTAssertEqual(r.syllables, 32, accuracy: 1)
        XCTAssertEqual(r.pauses, 3)
        XCTAssertEqual(r.syllablesPerBreathGroup, 8, accuracy: 0.5)
        // Gaps under 250 ms count as speaking time, so the rate is the
        // phrase rate (4 / s), not the voiced-only rate.
        XCTAssertEqual(r.rate, 4, accuracy: 0.4)
    }

    func testPassageFatigueIsNegativeWhenVoiceWeakens() throws {
        var env = [Float](repeating: 0, count: 30)
        for k in 0..<60 {
            let a = Float(0.4 * (1 - 0.5 * Double(k) / 60))
            env += (0..<25).map { i in i < 17 ? a * Float(sin(.pi * Double(i) / 17)) : 0 }
        }
        env += [Float](repeating: 0, count: 30)
        let r = try XCTUnwrap(TaskAnalysis.passage(frames(env)))
        XCTAssertLessThan(r.fatigueDb, -2)
    }

    // MARK: Toy band performs each task

    /// The toy band's results should land near the recent end of the sample
    /// history, so a live check continues the chart instead of jumping.
    func testToyBandTasksMatchRecentSampleHistory() throws {
        let recent = ToyCheckHistory.make().suffix(3)
        func mean(_ k: KeyPath<SpeechCheckRecord, Double?>) -> Double {
            let v = recent.compactMap { $0[keyPath: k] }
            return v.reduce(0, +) / Double(v.count)
        }

        let vowel = try XCTUnwrap(TaskAnalysis.vowel(ToyBand().render(.vowel, seconds: 16)))
        XCTAssertEqual(vowel.mpt, mean(\.mpt), accuracy: 2)
        XCTAssertEqual(try XCTUnwrap(vowel.hnr), mean(\.hnr), accuracy: 3)

        let amr = try XCTUnwrap(TaskAnalysis.ddk(ToyBand().render(.ddk(smr: false), seconds: 6)))
        XCTAssertEqual(amr.rate, mean(\.amrRate), accuracy: 0.5)

        let smr = try XCTUnwrap(TaskAnalysis.ddk(ToyBand().render(.ddk(smr: true), seconds: 6)))
        XCTAssertEqual(smr.rate, mean(\.smrRate), accuracy: 0.5)
        XCTAssertLessThan(smr.rate, amr.rate)
        XCTAssertEqual(amr.regularity, mean(\.amrRegularity), accuracy: 3)
        XCTAssertEqual(smr.regularity, mean(\.smrRegularity), accuracy: 4)

        let read = try XCTUnwrap(TaskAnalysis.passage(ToyBand().render(.passage, seconds: 24)))
        XCTAssertEqual(read.rate, mean(\.readingRate), accuracy: 0.6)
        XCTAssertEqual(read.syllablesPerBreathGroup, mean(\.syllablesPerBreathGroup), accuracy: 2.5)
        XCTAssertEqual(read.fatigueDb, mean(\.fatigueDb), accuracy: 1.5)

        print("toy vowel", vowel, "amr", amr, "smr", smr, "read", read)
    }

    // MARK: Check records and measures

    func testEveryMeasureBelongsToExactlyOneSystem() {
        let all = SpeechSystem.allCases.flatMap(\.measures)
        XCTAssertEqual(all.count, Set(all).count)
        XCTAssertEqual(all.count, Metric.allCases.count + CheckMetric.allCases.count)
    }

    func testSampleHistoryTrendsAreUnfavorable() {
        let checks = ToyCheckHistory.make()
        for c in [CheckMetric.mpt, .amrRate, .smrRate, .readingRate, .hnr] {
            let t = MeasureTrend.compute(.check(c), sessions: [], checks: checks, baseline: nil)
            XCTAssertEqual(t?.direction, .lower, "\(c)")
        }
    }

    func testSkippedTaskLeavesMeasuresNil() {
        var r = SpeechCheckRecord(date: .now, isSample: true)
        XCTAssertEqual(r.completedTasks, 0)
        r.mpt = 10
        XCTAssertEqual(r.completedTasks, 1)
        XCTAssertNil(CheckMetric.amrRate.value(r))
    }
}
