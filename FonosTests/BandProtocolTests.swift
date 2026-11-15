import XCTest
@testable import Fonos

/// The band's wire format. The firmware's encoder mirrors `BandProtocol.encode`.
final class BandProtocolTests: XCTestCase {

    private func frame(seq: UInt16 = 7, battery: Int? = 64, contact: (Bool, Bool)? = (true, false), charging: Bool = false) -> Data {
        let mic = (0..<80).map { Int16(12_000 * sin(2 * .pi * 125 * Double($0) / 8_000)) }
        let left = (0..<10).map { Int16($0 * 1_000) }
        let right = (0..<10).map { Int16(-$0 * 2_000) }
        return BandProtocol.encode(mic: mic, left: left, right: right, sequence: seq, battery: battery,
                                   leftContact: contact?.0, rightContact: contact?.1, charging: charging)
    }

    func testFrameIs126Bytes() {
        XCTAssertEqual(frame().count, BandProtocol.frameSize)
        XCTAssertEqual(BandProtocol.frameSize, 6 + 80 + 20 + 20)
    }

    func testDecodeRecoversHeaderAndPiezoSamplesExactly() throws {
        let p = try XCTUnwrap(BandProtocol.decode(frame(seq: 513, battery: 64, contact: (true, false), charging: true)).first)
        XCTAssertEqual(p.sequence, 513)
        XCTAssertEqual(p.battery, 64)
        XCTAssertEqual(p.leftContact, true)
        XCTAssertEqual(p.rightContact, false)
        XCTAssertTrue(p.charging)
        XCTAssertEqual(p.frame.mic.count, 80)
        XCTAssertEqual(p.frame.left.count, 10)
        XCTAssertEqual(p.frame.left[3], 3_000 / 32_768, accuracy: 1e-6)
        XCTAssertEqual(p.frame.right[9], -18_000 / 32_768, accuracy: 1e-6)
    }

    func testUnreportedBatteryAndContactAreNil() throws {
        let p = try XCTUnwrap(BandProtocol.decode(frame(battery: nil, contact: nil)).first)
        XCTAssertNil(p.battery)
        XCTAssertNil(p.leftContact)
        XCTAssertNil(p.rightContact)
    }

    func testMuLawRoundTripWithinQuantization() {
        for s: Int16 in [0, 1, -1, 100, -100, 1_000, -5_000, 12_345, -32_000, 32_767, -32_768] {
            let back = Int(BandProtocol.muLawDecode(BandProtocol.muLawEncode(s)))
            // µ-law step grows with level: about 3% of the magnitude, at least 8.
            XCTAssertEqual(back, Int(s), accuracy: max(8, abs(Int(s)) / 30 + 8), "\(s)")
        }
    }

    func testMuLawMatchesG711ReferenceValues() {
        // Standard G.711 µ-law codes: silence is 0xFF, full-scale positive 0x80, negative 0x00.
        XCTAssertEqual(BandProtocol.muLawEncode(0), 0xFF)
        XCTAssertEqual(BandProtocol.muLawEncode(32_767), 0x80)
        XCTAssertEqual(BandProtocol.muLawEncode(-32_768), 0x00)
        XCTAssertEqual(BandProtocol.muLawDecode(0xFF), 0)
    }

    func testDecodesSeveralFramesInOneNotification() throws {
        var data = frame(seq: 1)
        data.append(frame(seq: 2))
        data.append(frame(seq: 3))
        XCTAssertEqual(try BandProtocol.decode(data).map(\.sequence), [1, 2, 3])
    }

    func testRejectsPartialFramesAndOtherVersions() {
        XCTAssertThrowsError(try BandProtocol.decode(frame().dropLast()))
        XCTAssertThrowsError(try BandProtocol.decode(Data()))
        var v2 = frame()
        v2[0] = 2
        XCTAssertThrowsError(try BandProtocol.decode(v2)) { XCTAssertEqual($0 as? BandProtocol.DecodeError, .version(2)) }
    }

    func testMissingFramesCountsGapsAcrossWrap() {
        XCTAssertEqual(BandProtocol.missing(after: 10, next: 11), 0)
        XCTAssertEqual(BandProtocol.missing(after: 10, next: 14), 3)
        XCTAssertEqual(BandProtocol.missing(after: 65_535, next: 0), 0)
        XCTAssertEqual(BandProtocol.missing(after: 65_534, next: 1), 2)
        // A backwards jump means the band restarted, not 65 000 lost frames.
        XCTAssertEqual(BandProtocol.missing(after: 500, next: 3), 0)
        XCTAssertEqual(BandProtocol.missing(after: 7, next: 7), 0)
    }

    func testDecodedToneKeepsItsPitch() throws {
        // 125 Hz through µ-law should still read as 125 Hz in the app's pitch tracker.
        var frames: [SensorFrame] = []
        for k in 0..<3 {
            let mic = (0..<80).map { i in Int16(12_000 * sin(2 * .pi * 125 * Double(k * 80 + i) / 8_000)) }
            let d = BandProtocol.encode(mic: mic, left: .init(repeating: 0, count: 10), right: .init(repeating: 0, count: 10), sequence: UInt16(k))
            frames.append(try XCTUnwrap(BandProtocol.decode(d).first).frame)
        }
        let p = try XCTUnwrap(DSP.pitch(frames.flatMap(\.mic), sampleRate: 8_000))
        XCTAssertEqual(Double(p), 125, accuracy: 3)
    }
}
