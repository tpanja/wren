import Foundation

struct TranslationResult: Equatable, Sendable {
    var text: String
    /// 0...1
    var confidence: Double
}

/// Turns the throat-mic stream into clear words.
///
/// The app currently ships `ClipTranslator`, which recognizes the ten bundled
/// demo recordings. A real translator (for example a Core ML model fine-tuned
/// on the patient's recordings) replaces it by conforming to this protocol.
protocol SpeechTranslator: AnyObject {
    var displayName: String { get }
    /// Partial text while the patient is still speaking.
    var onPartial: ((String) -> Void)? { get set }
    /// True once the words are clear before listening ends, so it can end sooner.
    var isConfident: Bool { get }
    /// When new words were last heard, if the translator can tell; listening
    /// ends once no new words arrive for a while.
    var lastWords: Date? { get }
    /// True when the translator already has everything it needs, for
    /// example a recognized recording that has finished playing.
    var heardEnough: Bool { get }
    func begin() throws
    /// Mic samples, 8 kHz, -1...1. Called off the main thread.
    func append(mic: [Float])
    func finish() async -> TranslationResult?
    func cancel()
}
