import XCTest
@testable import Wren

final class SignalTests: XCTestCase {

    func testRMSOfSineIsAmplitudeOverRootTwo() {
        let x = (0..<800).map { Float(sin(2 * .pi * 100 * Double($0) / 8_000)) }
        XCTAssertEqual(DSP.rms(x), 1 / 2.0.squareRoot().float, accuracy: 0.01)
    }

    func testPitchFindsFundamentalOfHarmonicTone() {
        let f0 = 125.0
        let x = (0..<240).map { i -> Float in
            let t = Double(i) / 8_000
            return Float(sin(2 * .pi * f0 * t) + 0.5 * sin(4 * .pi * f0 * t) + 0.25 * sin(6 * .pi * f0 * t))
        }
        let p = DSP.pitch(x, sampleRate: 8_000)
        XCTAssertNotNil(p)
        XCTAssertEqual(Double(p ?? 0), f0, accuracy: 3)
    }

    func testPitchRejectsNoise() {
        var g = SeededGenerator(seed: 3)
        let x = (0..<240).map { _ in Float.random(in: -1...1, using: &g) }
        XCTAssertNil(DSP.pitch(x, sampleRate: 8_000))
    }

    func testSyllablePeaksCountsBumps() {
        // Four 250 ms bumps at 100 Hz frame rate.
        let env = (0..<100).map { i -> Float in
            let s = Double(i % 25) / 25
            return Float(-60 + 40 * sin(.pi * s))
        }
        XCTAssertEqual(DSP.syllablePeaks(env, floorDb: -50), 4)
    }

    func testAnalyzerSummarizesToyBand() throws {
        let band = ToyBand()
        let analyzer = SpeechAnalyzer()
        let done = expectation(description: "frames")
        let counter = Counter()
        band.setTalking(true)
        band.onFrame = { frame in
            analyzer.ingest(frame)
            if counter.increment() == 300 { done.fulfill() }
        }
        band.startStreaming()
        wait(for: [done], timeout: 10)
        band.stopStreaming()

        let s = try XCTUnwrap(analyzer.summary(started: .now, isSample: true, phrases: 0))
        XCTAssertGreaterThan(s.pace, 1.5)
        XCTAssertLessThan(s.pace, 6)
        // Toy band is built with right = 0.86 × left.
        XCTAssertEqual(try XCTUnwrap(s.symmetry), 1 - 0.14 / 1.86, accuracy: 0.03)
        XCTAssertLessThan(s.strengthDb, 0)
    }
}

final class InsightTests: XCTestCase {

    func testBaselineNeedsThreeSessions() {
        let few = Array(ToyHistory.make().prefix(2))
        XCTAssertNil(Baseline.from(few))
        XCTAssertNotNil(Baseline.from(ToyHistory.make()))
    }

    func testToyHistoryShowsSlowerPace() {
        let sessions = ToyHistory.make()
        let trends = Insights.trends(sessions, baseline: Baseline.from(sessions))
        let pace = try? XCTUnwrap(trends.first { $0.metric == .pace })
        XCTAssertEqual(pace?.direction, .lower)
        XCTAssertNotNil(Insights.headline(trends))
    }

    func testStrengthIsHundredAtBaseline() {
        var s = ToyHistory.make()[0]
        let b = Baseline(strengthDb: s.strengthDb, pace: 4, pauseRatio: 0.2, symmetry: 1, pitchVariation: 2, clarity: 0.9, establishedOn: .now)
        XCTAssertEqual(Metric.strength.value(s, baseline: b) ?? 0, 100, accuracy: 0.001)
        s.strengthDb -= 6
        XCTAssertEqual(Metric.strength.value(s, baseline: b) ?? 0, 50.1, accuracy: 0.5)
    }
}

private final class Counter: @unchecked Sendable {
    private var n = 0
    private let lock = NSLock()
    func increment() -> Int { lock.withLock { n += 1; return n } }
}

private extension Double { var float: Float { Float(self) } }
