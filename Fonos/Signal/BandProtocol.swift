import CoreBluetooth
import Foundation

/// The Fonos band's Bluetooth Low Energy protocol, version 1. The firmware in
/// `firmware/fonos_band` implements the other side; keep the two in step.
///
/// The band advertises as "Wren Band" with `service` in its advertisement
/// (firmware before the rename says "Fonos Band"; the app shows it as Wren Band).
/// The `frames` characteristic notifies one or more 126-byte frames back to
/// back, each 10 ms of signal, all little-endian:
///
/// | Bytes   | Field                                                     |
/// |---------|-----------------------------------------------------------|
/// | 0       | Protocol version (1)                                      |
/// | 1       | Flags: bit 0 left contact, bit 1 right contact,           |
/// |         | bit 2 contact is reported, bit 3 charging                 |
/// | 2–3     | Frame sequence, UInt16, wraps                             |
/// | 4       | Battery percent 0–100, or 255 when unknown                |
/// | 5       | Reserved (0)                                              |
/// | 6–85    | 80 microphone samples, 8 kHz, G.711 µ-law                 |
/// | 86–105  | 10 left piezo samples, 1 kHz, Int16                       |
/// | 106–125 | 10 right piezo samples, 1 kHz, Int16                      |
///
/// µ-law keeps the mic's dynamic range in 8 bits, so a frame fits one
/// notification at the MTU iPhones negotiate (185 or more).
enum BandProtocol {
    static let service = CBUUID(string: "079A0425-8A6E-4126-91C5-A5B5B2525F6B")
    static let frames = CBUUID(string: "B5CFF4BC-810E-4AF7-8262-5F5F5D057AC5")
    static let advertisedName = "Wren Band"
    /// What bands flashed before the rename advertise.
    static let legacyNames: Set<String> = ["Fonos Band"]

    static let version: UInt8 = 1
    static let frameSize = 126
    static let micSamples = 80
    static let piezoSamples = 10

    /// One decoded frame and the band's state when it was sent.
    struct Packet: Equatable {
        var frame: SensorFrame
        var sequence: UInt16
        /// Nil when the band doesn't measure its battery.
        var battery: Int?
        /// Nil when the band doesn't report skin contact.
        var leftContact: Bool?
        var rightContact: Bool?
        var charging: Bool
    }

    enum DecodeError: Error, Equatable {
        case length(Int)
        case version(UInt8)
    }

    /// Splits a notification into frames. Fails on a length that isn't a
    /// whole number of frames or on an unknown protocol version.
    static func decode(_ data: Data) throws -> [Packet] {
        guard !data.isEmpty, data.count % frameSize == 0 else { throw DecodeError.length(data.count) }
        let bytes = [UInt8](data)
        var out: [Packet] = []
        out.reserveCapacity(bytes.count / frameSize)
        var o = 0
        while o < bytes.count {
            guard bytes[o] == version else { throw DecodeError.version(bytes[o]) }
            let flags = bytes[o + 1]
            let seq = UInt16(bytes[o + 2]) | UInt16(bytes[o + 3]) << 8
            let battery = bytes[o + 4] == 255 ? nil : Int(min(bytes[o + 4], 100))
            let contactReported = flags & 0b100 != 0

            let mic = (0..<micSamples).map { Float(muLawDecode(bytes[o + 6 + $0])) / 32_768 }
            func piezo(_ start: Int) -> [Float] {
                (0..<piezoSamples).map { i in
                    let lo = UInt16(bytes[start + 2 * i]), hi = UInt16(bytes[start + 2 * i + 1])
                    return Float(Int16(bitPattern: lo | hi << 8)) / 32_768
                }
            }
            out.append(Packet(
                frame: SensorFrame(mic: mic, left: piezo(o + 86), right: piezo(o + 106)),
                sequence: seq,
                battery: battery,
                leftContact: contactReported ? flags & 0b1 != 0 : nil,
                rightContact: contactReported ? flags & 0b10 != 0 : nil,
                charging: flags & 0b1000 != 0
            ))
            o += frameSize
        }
        return out
    }

    /// Frames lost between two sequence numbers (0 when `next` follows `last`).
    /// A jump of more than half the range is treated as the band restarting.
    static func missing(after last: UInt16, next: UInt16) -> Int {
        let gap = Int(next &- last) - 1
        return gap < 0 || gap > 32_767 ? 0 : gap
    }

    // MARK: µ-law (ITU-T G.711)

    private static let bias: Int32 = 0x84
    private static let clip: Int32 = 32_635

    static func muLawEncode(_ sample: Int16) -> UInt8 {
        var s = Int32(sample)
        let sign: UInt8 = s < 0 ? 0x80 : 0
        if s < 0 { s = -s }
        s = min(s, clip) + bias
        var exponent: UInt8 = 7
        var mask: Int32 = 0x4000
        while exponent > 0 && s & mask == 0 { exponent -= 1; mask >>= 1 }
        let mantissa = UInt8((s >> (Int32(exponent) + 3)) & 0x0F)
        return ~(sign | exponent << 4 | mantissa)
    }

    static func muLawDecode(_ byte: UInt8) -> Int16 {
        let u = ~byte
        let sign = u & 0x80
        let exponent = Int32((u >> 4) & 0x07)
        let mantissa = Int32(u & 0x0F)
        let magnitude = ((mantissa << 3) + bias) << exponent - bias
        return Int16(sign != 0 ? -magnitude : magnitude)
    }

    /// Builds a frame the way the firmware does. Used by tests and previews.
    static func encode(mic: [Int16], left: [Int16], right: [Int16], sequence: UInt16,
                       battery: Int? = nil, leftContact: Bool? = nil, rightContact: Bool? = nil, charging: Bool = false) -> Data {
        precondition(mic.count == micSamples && left.count == piezoSamples && right.count == piezoSamples)
        var flags: UInt8 = 0
        if let leftContact, let rightContact {
            flags |= 0b100
            if leftContact { flags |= 0b1 }
            if rightContact { flags |= 0b10 }
        }
        if charging { flags |= 0b1000 }
        var b: [UInt8] = [version, flags, UInt8(sequence & 0xFF), UInt8(sequence >> 8),
                          battery.map { UInt8(max(0, min($0, 100))) } ?? 255, 0]
        b += mic.map(muLawEncode)
        for v in left + right {
            let u = UInt16(bitPattern: v)
            b += [UInt8(u & 0xFF), UInt8(u >> 8)]
        }
        return Data(b)
    }
}
