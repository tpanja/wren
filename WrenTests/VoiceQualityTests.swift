import XCTest
@testable import Wren

/// Renders a sentence with the bundled voice, cleans it the way playback does,
/// and checks that it's clean for a phone speaker: no DC or sub-bass rumble
/// (heard as a buzz), silent pauses, and click-free edges. Writes both
/// versions to WAV files for listening.
final class VoiceQualityTests: XCTestCase {

    func testRenderedSpeechIsClean() throws {
        let text = "Well, he is nearly ninety-three years old. Could you please bring me a glass of water?"
        let out = try XCTUnwrap(NeuralVoice.render(text, speaker: 3, speed: 1.0))
        let rate = Int(out.rate)
        let raw = NeuralVoice.trimmed(out.pcm)
        let clean = NeuralVoice.polished(raw, rate: rate)
        XCTAssertGreaterThan(clean.count, rate * 2)

        let before = Self.measure(raw, rate: rate), after = Self.measure(clean, rate: rate)
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        try Self.wav(raw, rate: rate).write(to: dir.appendingPathComponent("wren-voice-raw.wav"))
        try Self.wav(clean, rate: rate).write(to: dir.appendingPathComponent("wren-voice-clean.wav"))
        print("VOICEQ dir=\(dir.path) before=\(before) after=\(after)")

        XCTAssertLessThan(after.lowShare, 0.002, "rumble below 50 Hz")
        XCTAssertLessThan(after.pauseFloor, -65, "pauses should be silent")
        XCTAssertGreaterThan(after.speech, before.speech - 1.5, "speech level kept")
        XCTAssertLessThan(abs(clean.first ?? 1) + abs(clean.last ?? 1), 0.002, "edges fade to zero")
    }

    struct Measure: CustomStringConvertible {
        let lowShare: Double, pauseFloor: Float, speech: Float
        var description: String { String(format: "{below50Hz %.3f%%, pauses %.1f dB, speech %.1f dB}", lowShare * 100, pauseFloor, speech) }
    }

    static func measure(_ x: [Float], rate: Int) -> Measure {
        let n = rate / 50
        let frames = stride(from: 0, to: x.count - n, by: n).map { i -> Float in
            10 * log10(x[i..<(i + n)].reduce(0) { $0 + $1 * $1 } / Float(n) + 1e-12)
        }.sorted()
        // Share of energy below 50 Hz, from a plain DFT on 1 s blocks.
        var low = 0.0, total = 0.0
        let block = rate
        for start in stride(from: 0, to: x.count - block, by: block) {
            let seg = Array(x[start..<(start + block)])
            total += seg.reduce(0) { $0 + Double($1 * $1) } * Double(block) / 2
            for k in 0..<50 {   // 1 Hz bins
                var re = 0.0, im = 0.0
                for (i, v) in seg.enumerated() { let ph = 2 * Double.pi * Double(k * i) / Double(block); re += Double(v) * cos(ph); im -= Double(v) * sin(ph) }
                low += (re * re + im * im) * (k == 0 ? 0.5 : 1)
            }
        }
        return Measure(lowShare: total > 0 ? low / total : 0, pauseFloor: frames[frames.count / 20], speech: frames[frames.count * 3 / 4])
    }

    static func wav(_ pcm: [Float], rate: Int) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let samples = pcm.map { Int16(max(-1, min(1, $0)) * 32767) }
        d.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + samples.count * 2))
        d.append(contentsOf: Array("WAVEfmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(UInt32(samples.count * 2))
        samples.forEach { withUnsafeBytes(of: $0.littleEndian) { d.append(contentsOf: $0) } }
        return d
    }
}
