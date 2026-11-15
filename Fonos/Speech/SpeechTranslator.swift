import AVFoundation
import Foundation
import Speech

struct TranslationResult: Equatable, Sendable {
    var text: String
    /// 0...1
    var confidence: Double
}

/// Turns the throat-mic stream into clear words.
///
/// The app ships `AppleSpeechTranslator` (on-device Apple speech recognition).
/// A dysarthria-specific model (for example a Core ML speech-to-text model
/// fine-tuned on the patient's recordings) can replace it by conforming to
/// this protocol and returning it from `TranslatorFactory`. No UI changes needed.
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

enum TranslatorError: LocalizedError {
    case notAuthorized
    case unavailable

    var errorDescription: String? {
        switch self {
        case .notAuthorized: "Speech recognition is turned off for Fonos. You can allow it in Settings."
        case .unavailable: "Speech recognition isn't available right now. Check your connection or try again shortly."
        }
    }
}

enum TranslatorFactory {
    static func make(for source: SourceKind) -> SpeechTranslator {
        switch source {
        case .demo: DemoTranslator()
        case .band, .phoneMic: AppleSpeechTranslator()
        }
    }
}

// MARK: - Apple on-device recognition

final class AppleSpeechTranslator: SpeechTranslator, @unchecked Sendable {

    let displayName = "On-device recognition"
    var onPartial: ((String) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latest: SFSpeechRecognitionResult?
    private var finalContinuation: CheckedContinuation<SFSpeechRecognitionResult?, Never>?
    private let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private let lock = NSLock()

    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
    }

    func begin() throws {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else { throw TranslatorError.notAuthorized }
        guard let recognizer, recognizer.isAvailable else { throw TranslatorError.unavailable }
        cancel()

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.taskHint = .dictation
        req.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req
        latest = nil

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.lock.withLock { self.latest = result }
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async { self.onPartial?(text) }
            }
            if result?.isFinal == true || error != nil {
                self.lock.withLock {
                    self.finalContinuation?.resume(returning: self.latest)
                    self.finalContinuation = nil
                }
            }
        }
    }

    func append(mic: [Float]) {
        guard let request, !mic.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(mic.count * 2)),
              let out = buffer.floatChannelData?[0] else { return }
        // 8 kHz → 16 kHz by linear interpolation.
        for i in 0..<mic.count {
            let a = mic[i], b = i + 1 < mic.count ? mic[i + 1] : a
            out[2 * i] = a
            out[2 * i + 1] = (a + b) / 2
        }
        buffer.frameLength = AVAudioFrameCount(mic.count * 2)
        request.append(buffer)
    }

    func finish() async -> TranslationResult? {
        guard let request else { return nil }
        request.endAudio()
        let result: SFSpeechRecognitionResult? = await withCheckedContinuation { c in
            lock.withLock {
                if latest?.isFinal == true { c.resume(returning: latest) } else { finalContinuation = c }
            }
            // Do not leave the patient waiting if the recognizer stalls.
            DispatchQueue.global().asyncAfter(deadline: .now() + 4) { [weak self] in
                guard let self else { return }
                self.lock.withLock {
                    self.finalContinuation?.resume(returning: self.latest)
                    self.finalContinuation = nil
                }
            }
        }
        self.request = nil
        task = nil
        guard let result else { return nil }
        let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let segments = result.bestTranscription.segments
        let confs = segments.map { Double($0.confidence) }.filter { $0 > 0 }
        let confidence = confs.isEmpty ? 0.6 : confs.reduce(0, +) / Double(confs.count)
        return TranslationResult(text: text, confidence: confidence)
    }

    func cancel() {
        task?.cancel()
        task = nil
        request = nil
        lock.withLock {
            finalContinuation?.resume(returning: nil)
            finalContinuation = nil
        }
    }
}

// MARK: - Demo

/// Returns scripted phrases so the full Speak flow works in demo mode.
final class DemoTranslator: SpeechTranslator {
    let displayName = "Demo translator"
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
