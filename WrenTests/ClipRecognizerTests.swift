import XCTest
@testable import Wren

final class ClipRecognizerTests: XCTestCase {

    private static let recognizer = ClipRecognizer()

    func testBundlesTenClipsWithSentences() {
        XCTAssertEqual(DemoClip.bundled.count, 10)
        XCTAssertEqual(Self.recognizer.clipCount, 10)
        for clip in DemoClip.bundled {
            XCTAssertFalse(clip.text.isEmpty)
            XCTAssertNotNil(clip.url, clip.file)
        }
    }

    /// A few seconds from the middle of each clip, quieter and noisy, still finds that clip.
    func testRecognizesAnExcerptOfEachClip() throws {
        var rng = SystemRandomNumberGenerator()
        for clip in DemoClip.bundled {
            let x = try XCTUnwrap(ClipRecognizer.load(XCTUnwrap(clip.url)))
            let n = min(x.count, 3 * 8_000), start = (x.count - n) / 2
            let excerpt = x[start..<(start + n)].map { 0.3 * $0 + Float.random(in: -0.004...0.004, using: &rng) }
            let match = Self.recognizer.match([Float](repeating: 0, count: 2_000) + excerpt)
            XCTAssertEqual(match?.clip.id, clip.id, clip.text)
        }
    }

    func testIgnoresSilenceAndNoise() {
        XCTAssertNil(Self.recognizer.match([Float](repeating: 0, count: 40_000)))
        var rng = SystemRandomNumberGenerator()
        let noise = (0..<40_000).map { _ in Float.random(in: -0.1...0.1, using: &rng) }
        XCTAssertNil(Self.recognizer.match(noise))
    }
}
