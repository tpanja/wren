import XCTest
@testable import Fonos

final class NeuralVoiceTests: XCTestCase {

    func testSplitsAtSentencesWithShortPauses() {
        let p = NeuralVoice.phrases(in: "Well, he is nearly ninety-three years old. Thank you.")
        XCTAssertEqual(p, [
            .init(text: "Well, he is nearly ninety-three years old.", pauseMs: 250),
            .init(text: "Thank you.", pauseMs: 250),
        ])
    }

    func testCommasAndConjunctionsStayInOnePhrase() {
        XCTAssertEqual(NeuralVoice.phrases(in: "We have often urged him to walk more and smoke less.").count, 1)
        XCTAssertEqual(NeuralVoice.phrases(in: "Salt and pepper, please.").map(\.text), ["Salt and pepper, please."])
        XCTAssertEqual(NeuralVoice.phrases(in: "One thing: water.").map(\.pauseMs), [150, 250])
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
