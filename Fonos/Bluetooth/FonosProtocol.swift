import CoreBluetooth
import Foundation

/// The Fonos band GATT contract. Mirrors `Firmware/fonos_band/fonos_band.ino`
/// and `Docs/BLUETOOTH.md`; change all three together.
enum FonosProtocol {
    static let serviceUUID   = CBUUID(string: "6F6E6F73-0001-4A2B-9C3D-5E6F70819203")
    /// Notify. One `SensorFrame` per notification (10 ms of signal).
    static let streamUUID    = CBUUID(string: "6F6E6F73-0002-4A2B-9C3D-5E6F70819203")
    /// Read + notify. `BandStatus`, sent on change and every 5 s.
    static let statusUUID    = CBUUID(string: "6F6E6F73-0003-4A2B-9C3D-5E6F70819203")
    /// Write with response. One-byte opcode plus optional argument.
    static let controlUUID   = CBUUID(string: "6F6E6F73-0004-4A2B-9C3D-5E6F70819203")
    /// Standard Battery Service, so system UI can also show band battery.
    static let batteryServiceUUID = CBUUID(string: "180F")

    static let frameMagic: UInt8 = 0xF1
    static let headerSize = 8
    static let micRate = 8_000
    static let piezoRate = 1_000

    enum Command: UInt8 {
        case startStream = 0x01
        case stopStream  = 0x02
        /// Re-measure the resting noise floor of all three sensors.
        case calibrate   = 0x03
        /// Argument: gain step 0...7 for the mic preamp.
        case setMicGain  = 0x04
    }
}

/// 10 ms of synchronized signal from the band.
struct SensorFrame: Sendable {
    var sequence: UInt8
    /// Milliseconds since the band started streaming.
    var timestamp: UInt32
    /// Contact mic, 8 kHz, normalized to -1...1.
    var mic: [Float]
    /// Left piezo, 1 kHz, normalized to -1...1.
    var left: [Float]
    /// Right piezo, 1 kHz, normalized to -1...1.
    var right: [Float]
}

struct BandStatus: Equatable, Sendable {
    var battery: Int = 0
    var isStreaming = false
    var leftContact = false
    var rightContact = false
    var isCharging = false
    var firmware = "–"
    var micRate = FonosProtocol.micRate
    var piezoRate = FonosProtocol.piezoRate
}

enum FrameParseError: Error, Equatable {
    case tooShort
    case badMagic(UInt8)
    case lengthMismatch(expected: Int, actual: Int)
}

enum FrameParser {

    /// Layout (little endian):
    /// ```
    /// [0]      magic 0xF1
    /// [1]      sequence (wraps at 255)
    /// [2..5]   timestamp ms, uint32
    /// [6]      mic sample count M (µ-law bytes)
    /// [7]      piezo sample count P (per side)
    /// [8..]    M bytes µ-law mic
    ///          P × int16 left piezo
    ///          P × int16 right piezo
    /// ```
    static func parseFrame(_ data: Data) throws -> SensorFrame {
        let bytes = [UInt8](data)
        guard bytes.count >= FonosProtocol.headerSize else { throw FrameParseError.tooShort }
        guard bytes[0] == FonosProtocol.frameMagic else { throw FrameParseError.badMagic(bytes[0]) }

        let seq = bytes[1]
        let ts = UInt32(bytes[2]) | UInt32(bytes[3]) << 8 | UInt32(bytes[4]) << 16 | UInt32(bytes[5]) << 24
        let m = Int(bytes[6])
        let p = Int(bytes[7])
        let expected = FonosProtocol.headerSize + m + p * 4
        guard bytes.count == expected else {
            throw FrameParseError.lengthMismatch(expected: expected, actual: bytes.count)
        }

        var i = FonosProtocol.headerSize
        var mic = [Float](repeating: 0, count: m)
        for k in 0..<m {
            mic[k] = Float(MuLaw.decode(bytes[i + k])) / 32_768
        }
        i += m

        func int16s(at start: Int) -> [Float] {
            (0..<p).map { k in
                let lo = UInt16(bytes[start + 2 * k])
                let hi = UInt16(bytes[start + 2 * k + 1])
                return Float(Int16(bitPattern: lo | hi << 8)) / 32_768
            }
        }
        let left = int16s(at: i)
        let right = int16s(at: i + p * 2)
        return SensorFrame(sequence: seq, timestamp: ts, mic: mic, left: left, right: right)
    }

    /// Layout:
    /// ```
    /// [0]     battery percent 0...100
    /// [1]     flags: bit0 streaming, bit1 left contact, bit2 right contact, bit3 charging
    /// [2]     firmware major   [3] firmware minor
    /// [4..5]  mic rate Hz, uint16   [6..7] piezo rate Hz, uint16
    /// ```
    static func parseStatus(_ data: Data) -> BandStatus? {
        let b = [UInt8](data)
        guard b.count >= 4 else { return nil }
        var s = BandStatus()
        s.battery = Int(min(b[0], 100))
        s.isStreaming = b[1] & 0x01 != 0
        s.leftContact = b[1] & 0x02 != 0
        s.rightContact = b[1] & 0x04 != 0
        s.isCharging = b[1] & 0x08 != 0
        s.firmware = "\(b[2]).\(b[3])"
        if b.count >= 8 {
            s.micRate = Int(UInt16(b[4]) | UInt16(b[5]) << 8)
            s.piezoRate = Int(UInt16(b[6]) | UInt16(b[7]) << 8)
        }
        return s
    }

    /// Builds a frame. Used by tests and the demo band so both exercise the parser.
    static func encodeFrame(sequence: UInt8, timestamp: UInt32, mic: [Float], left: [Float], right: [Float]) -> Data {
        precondition(left.count == right.count)
        var out: [UInt8] = [FonosProtocol.frameMagic, sequence,
                            UInt8(timestamp & 0xFF), UInt8(timestamp >> 8 & 0xFF),
                            UInt8(timestamp >> 16 & 0xFF), UInt8(timestamp >> 24 & 0xFF),
                            UInt8(mic.count), UInt8(left.count)]
        out.reserveCapacity(8 + mic.count + left.count * 4)
        for s in mic { out.append(MuLaw.encode(Int16(clamping: Int(s * 32_767)))) }
        for channel in [left, right] {
            for s in channel {
                let v = UInt16(bitPattern: Int16(clamping: Int(s * 32_767)))
                out.append(UInt8(v & 0xFF)); out.append(UInt8(v >> 8))
            }
        }
        return Data(out)
    }
}

/// ITU-T G.711 µ-law. The band compresses the 8 kHz mic to 8 bits per sample
/// so a 10 ms frame fits in one BLE notification at the default iOS MTU.
enum MuLaw {
    private static let bias: Int32 = 0x84
    private static let clip: Int32 = 32_635

    static func encode(_ sample: Int16) -> UInt8 {
        var s = Int32(sample)
        let sign: Int32 = s < 0 ? 0x80 : 0
        if s < 0 { s = -s }
        s = min(s, clip) + bias
        var exponent: Int32 = 7
        var mask: Int32 = 0x4000
        while exponent > 0 && s & mask == 0 { exponent -= 1; mask >>= 1 }
        let mantissa = (s >> (exponent + 3)) & 0x0F
        return UInt8(truncatingIfNeeded: ~(sign | exponent << 4 | mantissa))
    }

    static func decode(_ byte: UInt8) -> Int16 {
        let u = Int32(~byte & 0xFF)
        let sign = u & 0x80
        let exponent = (u >> 4) & 0x07
        let mantissa = u & 0x0F
        let magnitude = ((mantissa << 3) + bias) << exponent
        let value = magnitude - bias
        return Int16(sign != 0 ? -value : value)
    }
}
