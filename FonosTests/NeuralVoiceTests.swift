import XCTest
@testable import Fonos

final class NeuralVoiceTests: XCTestCase {

    func testSplitsAtCommasAndSentencesWithPauses() {
        let p = NeuralVoice.phrases(in: "Well, he is nearly ninety-three years old. Thank you.")
        XCTAssertEqual(p, [
            .init(text: "Well,", pauseMs: 220),
            .init(text: "he is nearly ninety-three years old.", pauseMs: 480),
            .init(text: "Thank you.", pauseMs: 480),
        ])
    }

    func testBreathBeforeAClauseInLongSentencesOnly() {
        let long = NeuralVoice.phrases(in: "We have often urged him to walk more and smoke less.")
        XCTAssertEqual(long.map(\.text), ["We have often urged him to walk more", "and smoke less."])
        XCTAssertEqual(long.first?.pauseMs, 140)
        XCTAssertEqual(NeuralVoice.phrases(in: "Salt and pepper, please.").map(\.text), ["Salt and pepper,", "please."])
    }

    func testTrimKeepsSpeechAndDropsSilence() {
        let pcm = [Float](repeating: 0, count: 5_000) + [Float](repeating: 0.2, count: 1_000) + [Float](repeating: 0, count: 5_000)
        let t = NeuralVoice.trimmed(pcm)
        XCTAssertEqual(t.count, 1_000 + 2 * 480)
        XCTAssertEqual(t.filter { $0 != 0 }.count, 1_000)
    }

    func testBundledModelLoads() {
        XCTAssertTrue(NeuralVoice.isAvailable, "Run tools/fetch-tts-model.sh to download the voice model")
    }
}
