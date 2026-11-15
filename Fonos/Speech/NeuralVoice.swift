import AVFoundation
import Foundation
import os
import SherpaOnnx

/// Wren's own voice: Kokoro v1.0 (int8), an open neural text-to-speech model
/// that runs entirely on the iPhone through sherpa-onnx. It ships in the app
/// (BundledModels/Kokoro, from tools/fetch-tts-model.sh), so it sounds the
/// same on every phone with no download in Settings.
///
/// Sentences are spoken phrase by phrase with real silences between them,
/// the way people pause: after commas, between sentences, and before a new
/// clause in a long one. The next phrase is rendered while the current one
/// plays, so the gaps are only the intended pauses.
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
    private nonisolated static let log = Logger(subsystem: "com.fonos.app", category: "voice")

    nonisolated static var isAvailable: Bool { modelFolder != nil }

    private nonisolated static var modelFolder: URL? {
        guard let url = Bundle.main.url(forResource: "Kokoro", withExtension: nil),
              ["model.int8.onnx", "voices.bin", "tokens.txt", "lexicon-us-en.txt", "espeak-ng-data"]
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
            model: path("model.int8.onnx"), voices: path("voices.bin"), tokens: path("tokens.txt"),
            dataDir: path("espeak-ng-data"), lexicon: path("lexicon-us-en.txt"), lang: "en-us")
        let threads = max(2, min(4, ProcessInfo.processInfo.activeProcessorCount - 2))
        let model = sherpaOnnxOfflineTtsModelConfig(kokoro: kokoro, numThreads: threads)
        var config = sherpaOnnxOfflineTtsConfig(model: model)
        let started = Date()
        tts = SherpaOnnxOfflineTtsWrapper(config: &config)
        log.info("Kokoro loaded in \(Date().timeIntervalSince(started), format: .fixed(precision: 2)) s")
        return tts
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
                        guard let tts = Self.loadTTS() else { done.resume(returning: nil); return }
                        let started = Date()
                        let out = tts.generate(text: phrase.text, sid: Int(speaker), speed: speed)
                        let seconds = Double(out.samples.count) / Double(max(out.sampleRate, 1))
                        Self.log.info("rendered \(seconds, format: .fixed(precision: 2)) s of speech in \(Date().timeIntervalSince(started), format: .fixed(precision: 2)) s")
                        done.resume(returning: (Self.trimmed(out.samples), out.sampleRate))
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

    /// Splits text where a speaker would pause: commas (~220 ms), semicolons,
    /// colons and dashes (~320 ms), sentence ends (~480 ms), and before a new
    /// clause ("and", "but", "because"…) once a long phrase has run 6+ words.
    nonisolated static func phrases(in text: String) -> [Phrase] {
        let conjunctions: Set<String> = ["and", "but", "because", "so", "or", "then", "when", "while", "although", "unless"]
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var out: [Phrase] = []
        var current: [String] = []
        func flush(_ pause: Int) {
            guard !current.isEmpty else { return }
            out.append(Phrase(text: current.joined(separator: " "), pauseMs: pause))
            current = []
        }
        for (i, word) in words.enumerated() {
            let bare = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            if current.count >= 6, conjunctions.contains(bare), words.count - i >= 3 { flush(140) }
            current.append(word)
            switch word.last {
            case ",": flush(220)
            case ";", ":", "—", "–": flush(320)
            case ".", "?", "!": flush(480)
            default: break
            }
        }
        flush(0)
        return out
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
