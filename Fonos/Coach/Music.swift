import Foundation

/// Pitch arithmetic. MIDI note numbers throughout; A4 = 69 = 440 Hz.
enum Music {
    static func hz(midi: Double) -> Double { 440 * pow(2, (midi - 69) / 12) }
    static func midi(hz: Double) -> Double { 69 + 12 * log2(hz / 440) }

    private static let sharps = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    private static let spoken = ["C", "C sharp", "D", "D sharp", "E", "F", "F sharp", "G", "G sharp", "A", "A sharp", "B"]

    /// "F#3"
    static func name(_ midi: Int) -> String {
        sharps[((midi % 12) + 12) % 12] + "\(midi / 12 - 1)"
    }

    /// Note letter without octave, "F#".
    static func letter(_ midi: Int) -> String { sharps[((midi % 12) + 12) % 12] }

    static func octave(_ midi: Int) -> Int { midi / 12 - 1 }

    /// "F sharp 3", for VoiceOver.
    static func spokenName(_ midi: Int) -> String {
        spoken[((midi % 12) + 12) % 12] + " \(midi / 12 - 1)"
    }

    static func isBlackKey(_ midi: Int) -> Bool {
        [1, 3, 6, 8, 10].contains(((midi % 12) + 12) % 12)
    }
}
