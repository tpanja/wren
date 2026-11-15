import Foundation

struct TranslationResult: Equatable, Sendable {
    var text: String
    /// 0...1
    var confidence: Double
}

/// Turns the throat-mic stream into clear words.
///
/// The app currently ships only `ToyTranslator`, which returns scripted
/// phrases so the Speak flow can be seen end to end. A real translator (for
/// example on-device speech recognition, or a Core ML model fine-tuned on the
/// patient's recordings) replaces it by conforming to this protocol.
protocol SpeechTranslator: AnyObject {
    var displayName: String { get }
    /// Partial text while the patient is still speaking.
    var onPartial: ((String) -> Void)? { get set }
    func begin() throws
    /// Contact-mic samples, 8 kHz, -1...1. Called off the main thread.
    func append(mic: [Float])
    func finish() async -> TranslationResult?
    func cancel()
}

// MARK: - Demo

/// Toy translator: returns scripted phrases so the full Speak flow works.
final class ToyTranslator: SpeechTranslator {
    let displayName = "Toy translator"
    var onPartial: ((String) -> Void)?

    private static let phrases = [
        "Could you open the window a little?",
        "I'd like some water, please.",
        "Thank you for coming today.",
        "Can we talk about this after lunch?",
        "I'm comfortable, just a bit tired.",
        "Please call my sister this evening.",
    ]
    private static var index = 0
    private var samples = 0
    private var shown = 0

    func begin() throws { samples = 0; shown = 0 }

    func append(mic: [Float]) {
        samples += mic.count
        let phrase = Self.phrases[Self.index % Self.phrases.count]
        let words = phrase.split(separator: " ")
        // Reveal about two words per second, like live recognition.
        let count = min(words.count, samples / 4_000)
        if count != shown {
            shown = count
            let partial = words.prefix(count).joined(separator: " ")
            DispatchQueue.main.async { self.onPartial?(partial) }
        }
    }

    func finish() async -> TranslationResult? {
        try? await Task.sleep(for: .milliseconds(350))
        let phrase = Self.phrases[Self.index % Self.phrases.count]
        Self.index += 1
        return TranslationResult(text: phrase, confidence: Double.random(in: 0.74...0.9))
    }

    func cancel() {}
}
