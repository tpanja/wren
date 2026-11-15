import AVFoundation
import Foundation
import os
import SherpaOnnx

/// Wren's own voice: Kokoro v1.0 (full precision), an open neural text-to-speech model
/// that runs entirely on the iPhone through sherpa-onnx. It ships in the app
/// (BundledModels/Kokoro, from tools/fetch-tts-model.sh), so it sounds the
/// same on every phone with no download in Settings.
///
/// Sentences are spoken one at a time with short silences between them; the
/// next one is rendered while the current one plays, so the gaps are only the
/// intended pauses.
@MainActor
final class NeuralVoice {

    struct Speaker: Identifiable, Hashable, Sendable {
        let id: Int32
        let name: String
        let accent: String
    }

    /// The best-rated English Kokoro voices; IDs are the model's speaker IDs.
    nonisolated static let speakers: [Speaker] = [
        Speaker(id: 3, name: "Heart", accent: "American"),
        Speaker(id: 2, name: "Bella", accent: "American"),
        Speaker(id: 6, name: "Nicole", accent: "American"),
        Speaker(id: 16, name: "Michael", accent: "American"),
        Speaker(id: 21, name: "Emma", accent: "British"),
        Speaker(id: 26, name: "George", accent: "British"),
    ]

    /// Called on the main actor when speaking starts or stops.
    var onSpeakingChanged: ((Bool) -> Void)?
    private(set) var isSpeaking = false {
        didSet { if isSpeaking != oldValue { onSpeakingChanged?(isSpeaking) } }
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var attached = false
    private var task: Task<Void, Never>?
    private nonisolated static let log = Logger(subsystem: "com.wren.app", category: "voice")

    nonisolated static var isAvailable: Bool { modelFolder != nil }

    private nonisolated static var modelFolder: URL? {
        guard let url = Bundle.main.url(forResource: "Kokoro", withExtension: nil),
              ["model.onnx", "voices.bin", "tokens.txt", "lexicon-us-en.txt", "espeak-ng-data"]
                .allSatisfy({ FileManager.default.fileExists(atPath: url.appendingPathComponent($0).path) })
        else { return nil }
        return url
    }

    // MARK: Model

    /// Loaded once, on a background queue (a second or two), then kept.
    private nonisolated(unsafe) static var tts: SherpaOnnxOfflineTtsWrapper?
    private nonisolated static let queue = DispatchQueue(label: "wren.tts", qos: .userInitiated)

    private nonisolated static func loadTTS() -> SherpaOnnxOfflineTtsWrapper? {
        if let tts { return tts }
        guard let folder = modelFolder else { return nil }
        func path(_ name: String) -> String { folder.appendingPathComponent(name).path }
        let kokoro = sherpaOnnxOfflineTtsKokoroModelConfig(
            model: path("model.onnx"), voices: path("voices.bin"), tokens: path("tokens.txt"),
            dataDir: path("espeak-ng-data"), lexicon: path("lexicon-us-en.txt"), lang: "en-us")
        let threads = max(2, min(4, ProcessInfo.processInfo.activeProcessorCount - 2))
        let model = sherpaOnnxOfflineTtsModelConfig(kokoro: kokoro, numThreads: threads)
        var config = sherpaOnnxOfflineTtsConfig(model: model)
        let started = Date()
        tts = SherpaOnnxOfflineTtsWrapper(config: &config)
        log.info("Kokoro loaded in \(Date().timeIntervalSince(started), format: .fixed(precision: 2)) s")
        return tts
    }

    /// Renders one phrase to mono PCM (blocking; call off the main thread).
    nonisolated static func render(_ text: String, speaker: Int32, speed: Float) -> (pcm: [Float], rate: Int32)? {
        guard let tts = loadTTS() else { return nil }
        let started = Date()
        let out = tts.generate(text: text, sid: Int(speaker), speed: speed)
        let seconds = Double(out.samples.count) / Double(max(out.sampleRate, 1))
        log.info("rendered \(seconds, format: .fixed(precision: 2)) s of speech in \(Date().timeIntervalSince(started), format: .fixed(precision: 2)) s")
        return (out.samples, out.sampleRate)
    }

    /// Starts loading the model so the first sentence isn't delayed.
    nonisolated static func preload() {
        queue.async { _ = loadTTS() }
    }

    // MARK: Speaking

    /// Speaks `text` with Kokoro speaker `speaker`. `speed` 1 is normal.
    func speak(_ text: String, speaker: Int32, speed: Float) {
        stop()
        let phrases = Self.phrases(in: text)
        guard !phrases.isEmpty else { return }
        isSpeaking = true
        task = Task { [weak self] in
            guard let self else { return }
            // Render phrase by phrase; each is queued as soon as it's ready,
            // so the next one renders while the previous one plays.
            var lastPlayed: Task<Void, Never>?
            for (i, phrase) in phrases.enumerated() {
                guard !Task.isCancelled else { break }
                let audio: (pcm: [Float], rate: Int32)? = await withCheckedContinuation { done in
                    Self.queue.async {
                        guard let out = Self.render(phrase.text, speaker: speaker, speed: speed) else { done.resume(returning: nil); return }
                        done.resume(returning: (Self.polished(Self.trimmed(out.pcm), rate: Int(out.rate)), out.rate))
                    }
                }
                guard let audio, !audio.pcm.isEmpty, !Task.isCancelled else { continue }
                let pause = i == phrases.count - 1 ? 0 : phrase.pauseMs
                let pcm = audio.pcm + [Float](repeating: 0, count: Int(audio.rate) * pause / 1000)
                lastPlayed = self.enqueue(pcm, rate: Double(audio.rate))
            }
            await lastPlayed?.value
            if !Task.isCancelled { self.isSpeaking = false }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        player.stop()
        isSpeaking = false
    }

    /// Schedules audio on the player; the returned task finishes when it has played.
    private func enqueue(_ pcm: [Float], rate: Double) -> Task<Void, Never>? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(pcm.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(pcm.count)
        pcm.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: pcm.count) }

        let session = AVAudioSession.sharedInstance()
        // Listening uses .playAndRecord (to the speaker); otherwise plain playback.
        if session.category != .playAndRecord { try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers]) }
        try? session.setActive(true)
        if !attached {
            engine.attach(player)
            attached = true
        }
        if !engine.isRunning {
            engine.connect(player, to: engine.mainMixerNode, format: format)
            do { try engine.start() } catch { Self.log.error("audio engine: \(error.localizedDescription)"); return nil }
        }
        // Scheduled right away, in order; the task only waits for playback to end.
        let (finished, signal) = AsyncStream<Void>.makeStream()
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in signal.finish() }
        if !player.isPlaying { player.play() }
        return Task { for await _ in finished {} }
    }

    // MARK: Phrasing

    struct Phrase: Equatable {
        let text: String
        /// Silence after this phrase, in milliseconds.
        let pauseMs: Int
    }

    /// Splits text into sentences (and at semicolons, colons and dashes) with
    /// short silences between them: ~250 ms after a sentence, ~150 ms after
    /// ; : or a dash. Commas stay inside a phrase, where Kokoro already makes
    /// a brief, natural pause; cutting there sounds choppy.
    nonisolated static func phrases(in text: String) -> [Phrase] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var out: [Phrase] = []
        var current: [String] = []
        func flush(_ pause: Int) {
            guard !current.isEmpty else { return }
            out.append(Phrase(text: current.joined(separator: " "), pauseMs: pause))
            current = []
        }
        for word in words {
            current.append(word)
            switch word.last {
            case ";", ":", "—", "–": flush(150)
            case ".", "?", "!": flush(250)
            default: break
            }
        }
        flush(0)
        return out
    }

    /// Cleans the model's output for a phone speaker. Kokoro's audio carries a
    /// DC offset and sub-100 Hz rumble that the speaker turns into a low buzz
    /// and clicks at phrase edges; this removes them:
    /// 1. a 70 Hz high-pass (2nd-order Butterworth),
    /// 2. a gentle downward expander that takes the faint residue in pauses
    ///    to silence without touching speech (below -50 dBFS, up to 24 dB),
    /// 3. 6 ms fades at both ends so phrases start and stop without a click.
    nonisolated static func polished(_ input: [Float], rate: Int) -> [Float] {
        guard input.count > 32, rate > 0 else { return input }
        var x = input

        // 1. High-pass, RBJ biquad.
        let w0 = 2 * Double.pi * 70 / Double(rate), q = 0.7071
        let alpha = sin(w0) / (2 * q), c = cos(w0), a0 = 1 + alpha
        let b0 = (1 + c) / 2 / a0, b1 = -(1 + c) / a0, b2 = (1 + c) / 2 / a0
        let a1 = -2 * c / a0, a2 = (1 - alpha) / a0
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        for i in x.indices {
            let xi = Double(x[i])
            let yi = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = xi; y2 = y1; y1 = yi
            x[i] = Float(yi)
        }

        // 2. Downward expander on a smoothed envelope.
        let threshold: Float = 0.00316      // -50 dBFS
        let floorGain: Float = 0.063        // -24 dB at most
        let attack = Float(exp(-1.0 / (0.002 * Double(rate))))
        let release = Float(exp(-1.0 / (0.060 * Double(rate))))
        var env: Float = 0, gain: Float = 1
        for i in x.indices {
            let a = abs(x[i])
            env = a > env ? a : env * release + a * (1 - release)
            // 1:3 expansion below the threshold.
            let target = env >= threshold ? 1 : max(floorGain, pow(env / threshold, 2))
            gain = target > gain ? target + (gain - target) * attack : target + (gain - target) * release
            x[i] *= gain
        }

        // 3. Fades.
        let fade = min(x.count / 2, rate * 6 / 1000)
        for i in 0..<fade {
            let g = Float(i) / Float(fade)
            x[i] *= g
            x[x.count - 1 - i] *= g
        }
        return x
    }

    /// Drops the model's leading and trailing near-silence, so the pauses
    /// between phrases are exactly the ones chosen above.
    nonisolated static func trimmed(_ pcm: [Float]) -> [Float] {
        let threshold: Float = 0.003
        guard let first = pcm.firstIndex(where: { abs($0) > threshold }),
              let last = pcm.lastIndex(where: { abs($0) > threshold }) else { return pcm }
        // Keep a few milliseconds either side so consonants aren't clipped.
        let pad = 480
        return Array(pcm[max(0, first - pad)...min(pcm.count - 1, last + pad)])
    }
}
