import AVFoundation
import Foundation
import os
import Speech

/// Apple's built-in English speech recognizer (the Speech framework), used for
/// anything that isn't one of the demo recordings. Runs on the device when the
/// iPhone supports it. Audio is streamed in while listening; the transcript is
/// read once, when listening ends.
final class AppleSpeech: @unchecked Sendable {

    private struct State {
        var request: SFSpeechAudioBufferRecognitionRequest?
        var task: SFSpeechRecognitionTask?
        var best: SFTranscription?
        var lastWords: Date?
        var done = false
    }

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let log = Logger(subsystem: "com.fonos.app", category: "speech")
    private let state = OSAllocatedUnfairLock(initialState: State())

    static var isAuthorized: Bool { SFSpeechRecognizer.authorizationStatus() == .authorized }

    /// Asks once; later calls return the saved answer.
    static func requestAuthorization() async -> Bool {
        if SFSpeechRecognizer.authorizationStatus() != .notDetermined { return isAuthorized }
        return await withCheckedContinuation { done in
            SFSpeechRecognizer.requestAuthorization { done.resume(returning: $0 == .authorized) }
        }
    }

    func begin() {
        cancel()
        guard Self.isAuthorized, let recognizer, recognizer.isAvailable else {
            log.error("speech unavailable: authorized \(Self.isAuthorized) available \(self.recognizer?.isAvailable ?? false)")
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        state.withLock { $0 = State(request: request) }
        log.info("speech begin, on-device \(request.requiresOnDeviceRecognition)")
        let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let error { self?.log.error("speech error: \(error.localizedDescription)") }
            self?.state.withLock { s in
                guard s.request === request else { return }
                // After a pause the final result can come back empty, so keep
                // the last transcript that had words in it.
                if let result, !result.bestTranscription.formattedString.isEmpty {
                    if result.bestTranscription.formattedString != s.best?.formattedString { s.lastWords = .now }
                    s.best = result.bestTranscription
                }
                if result?.isFinal == true || error != nil { s.done = true }
            }
        }
        state.withLock { s in if s.request === request { s.task = task } }
    }

    /// When the transcript last gained words; nil before any.
    var lastWords: Date? { state.withLock { $0.lastWords } }

    func append(_ buffer: AVAudioPCMBuffer) {
        state.withLock { $0.request }?.append(buffer)
    }

    func append(samples: [Float], sampleRate: Double) {
        guard state.withLock({ $0.request }) != nil,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        append(buffer)
    }

    /// Ends the audio and waits (up to `timeout` seconds) for the final transcript.
    func finish(timeout: Double = 4) async -> (text: String, confidence: Double)? {
        guard let request = state.withLock({ $0.request }) else { return nil }
        request.endAudio()
        let deadline = Date.now.addingTimeInterval(timeout)
        while !state.withLock({ $0.done }), Date.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        let best = state.withLock { s -> SFTranscription? in
            defer { s = State() }
            return s.best
        }
        guard let best else { return nil }
        var text = best.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        text = text.prefix(1).uppercased() + text.dropFirst()
        if let last = text.last, !".?!".contains(last) { text += "." }
        // Segment confidence is only filled in on the final result.
        let scores = best.segments.map { Double($0.confidence) }.filter { $0 > 0 }
        let confidence = scores.isEmpty ? 0.75 : scores.reduce(0, +) / Double(scores.count)
        return (text, confidence)
    }

    func cancel() {
        let task = state.withLock { s -> SFSpeechRecognitionTask? in
            defer { s = State() }
            return s.task
        }
        task?.cancel()
    }
}
