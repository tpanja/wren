import Foundation
import os

/// Translator for the demo: recognizes which of the ten bundled dysarthric
/// recordings is playing near the microphone and returns the sentence the
/// speaker meant to say. It checks every half second while listening, so the
/// words appear as soon as the recording is clear.
final class ClipTranslator: SpeechTranslator, @unchecked Sendable {
    let displayName = "Demo recordings"
    var onPartial: ((String) -> Void)?

    /// Up to this much recent audio is matched; the clips are 4–10 s long.
    private static let window = Int(14 * ClipRecognizer.sampleRate)
    private static let checkEvery = Int(0.5 * ClipRecognizer.sampleRate)

    private struct State {
        var samples: [Float] = []
        var sinceCheck = 0
        var checking = false
        var best: ClipRecognizer.Match?
        var session = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
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

    func begin() throws {
        state.withLock { s in
            s = State(session: s.session + 1)
        }
    }

    func append(mic: [Float]) {
        let job = state.withLock { s -> (Int, [Float])? in
            s.samples += mic
            if s.samples.count > Self.window { s.samples.removeFirst(s.samples.count - Self.window) }
            s.sinceCheck += mic.count
            guard s.sinceCheck >= Self.checkEvery, !s.checking else { return nil }
            s.sinceCheck = 0
            s.checking = true
            return (s.session, s.samples)
        }
        guard let (session, samples) = job else { return }
        queue.async { [weak self] in
            guard let self else { return }
            let match = self.recognizer.withLock { $0 }?.match(samples)
            let changed = self.state.withLock { s -> Bool in
                s.checking = false
                guard s.session == session, let match else { return false }
                defer { s.best = Self.better(s.best, match) }
                return s.best?.clip.id != Self.better(s.best, match).clip.id
            }
            if changed, let text = self.state.withLock({ $0.best?.clip.text }) {
                DispatchQueue.main.async { self.onPartial?(text) }
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
        guard state.withLock({ $0.session }) == session else { return nil }
        guard let best = final.map({ Self.better(live, $0) }) ?? live else { return nil }
        return TranslationResult(text: best.clip.text, confidence: best.confidence)
    }

    func cancel() {
        state.withLock { s in s = State(session: s.session + 1) }
    }

    private static func better(_ a: ClipRecognizer.Match?, _ b: ClipRecognizer.Match) -> ClipRecognizer.Match {
        guard let a else { return b }
        return b.votes > a.votes ? b : a
    }
}
