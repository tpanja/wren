import AVFoundation
import Foundation
import os

/// Translator for the demo. First it checks whether one of the ten bundled
/// dysarthric recordings is playing near the microphone, and if so returns the
/// sentence that speaker meant to say. Anything else goes to Apple's built-in
/// speech recognizer, which transcribes ordinary English. Recordings are
/// checked every half second while listening, so listening can end sooner
/// once one is recognized; nothing is shown until listening ends.
final class ClipTranslator: SpeechTranslator, @unchecked Sendable {
    let displayName = "Demo recordings + Apple speech"
    var onPartial: ((String) -> Void)?

    /// Up to this much recent audio is matched; the clips are 4–10 s long.
    private static let window = Int(14 * ClipRecognizer.sampleRate)
    private static let checkEvery = Int(0.5 * ClipRecognizer.sampleRate)

    private struct State {
        var samples: [Float] = []
        var sinceCheck = 0
        var checking = false
        var best: ClipRecognizer.Match?
        /// When the recognized recording finishes playing.
        var clipEnds: Date?
        var session = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let speech = AppleSpeech()
    private let queue = DispatchQueue(label: "fonos.clips", qos: .userInitiated)
    /// Fingerprinting the clips takes a moment, so it starts at launch.
    private let recognizer = OSAllocatedUnfairLock<ClipRecognizer?>(initialState: nil)

    init() {
        queue.async { [recognizer] in
            let r = ClipRecognizer()
            recognizer.withLock { $0 = r }
        }
    }

    var clipCount: Int { recognizer.withLock { $0?.clipCount } ?? DemoClip.bundled.count }

    var isConfident: Bool { state.withLock { $0.best != nil } }

    var lastWords: Date? { speech.lastWords }

    /// A recognized recording has finished playing (with a short grace).
    var heardEnough: Bool {
        state.withLock { s in s.clipEnds.map { Date.now > $0.addingTimeInterval(0.6) } ?? false }
    }

    func begin() throws {
        state.withLock { s in
            s = State(session: s.session + 1)
        }
        speech.begin()
    }

    /// Audio for Apple's recognizer: the mic's own buffers (best accuracy).
    func appendSpeech(_ buffer: AVAudioPCMBuffer) { speech.append(buffer) }

    /// Audio for Apple's recognizer from the band: 8 kHz samples.
    func appendSpeech(samples: [Float]) { speech.append(samples: samples, sampleRate: ClipRecognizer.sampleRate) }

    func append(mic: [Float]) {
        let job = state.withLock { s -> (Int, [Float], Date)? in
            s.samples += mic
            if s.samples.count > Self.window { s.samples.removeFirst(s.samples.count - Self.window) }
            s.sinceCheck += mic.count
            guard s.sinceCheck >= Self.checkEvery, !s.checking else { return nil }
            s.sinceCheck = 0
            s.checking = true
            return (s.session, s.samples, .now)
        }
        guard let (session, samples, taken) = job else { return }
        queue.async { [weak self] in
            guard let self else { return }
            let match = self.recognizer.withLock { $0 }?.match(samples)
            self.state.withLock { s in
                s.checking = false
                guard s.session == session, let match else { return }
                s.best = Self.better(s.best, match)
                if match.clip.id == s.best?.clip.id { s.clipEnds = taken.addingTimeInterval(match.remaining) }
            }
        }
    }

    func finish() async -> TranslationResult? {
        let (session, samples, live) = state.withLock { ($0.session, $0.samples, $0.best) }
        let final: ClipRecognizer.Match? = await withCheckedContinuation { done in
            queue.async { [recognizer] in
                // Wait for the fingerprints if listening ended very early.
                var r = recognizer.withLock { $0 }
                while r == nil { usleep(20_000); r = recognizer.withLock { $0 } }
                done.resume(returning: r?.match(samples))
            }
        }
        guard state.withLock({ $0.session }) == session else { speech.cancel(); return nil }
        if let best = final.map({ Self.better(live, $0) }) ?? live {
            speech.cancel()
            return TranslationResult(text: best.clip.text, confidence: best.confidence)
        }
        // Not a demo recording: what Apple's recognizer heard.
        guard let heard = await speech.finish(), state.withLock({ $0.session }) == session else { return nil }
        return TranslationResult(text: heard.text, confidence: heard.confidence)
    }

    func cancel() {
        state.withLock { s in s = State(session: s.session + 1) }
        speech.cancel()
    }

    private static func better(_ a: ClipRecognizer.Match?, _ b: ClipRecognizer.Match) -> ClipRecognizer.Match {
        guard let a else { return b }
        return b.votes > a.votes ? b : a
    }
}
