import XCTest
@testable import Wren

final class VoiceOutputTests: XCTestCase {

    func testPausesAtCommasAndBetweenSentences() {
        let s = VoiceOutput.ssml(for: "Well, he is nearly ninety-three years old. Thank you.", rate: 0.5)
        XCTAssertTrue(s.contains("Well,<break time=\"120ms\"/>"))
        XCTAssertTrue(s.contains("old.<break time=\"280ms\"/>"))
        // No pause after the last word.
        XCTAssertTrue(s.hasSuffix("Thank you.</prosody></speak>"))
        XCTAssertTrue(s.contains("<prosody rate=\"100%\">"))
    }

    func testNoExtraBreathBeforeConjunctions() {
        let s = VoiceOutput.ssml(for: "We have often urged him to walk more and smoke less.", rate: 0.5)
        XCTAssertFalse(s.contains("<break"))
    }

    func testEscapesMarkupAndFollowsSpeed() {
        let s = VoiceOutput.ssml(for: "Nancy's grades <3 & more", rate: 0.4)
        XCTAssertTrue(s.contains("Nancy&apos;s grades &lt;3 &amp; more"))
        XCTAssertTrue(s.contains("<prosody rate=\"80%\">"))
    }
}
