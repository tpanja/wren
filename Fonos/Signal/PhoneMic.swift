import AVFoundation
import Foundation
import os

/// The iPhone's own microphone, as 10 ms chunks of 8 kHz mono audio (the
/// band mic's format). Used for listening when no real band is connected,
/// for example to recognize a demo recording played nearby.
final class PhoneMic: @unchecked Sendable {

    enum MicError: LocalizedError {
        case notAllowed, noInput
        var errorDescription: String? {
            switch self {
            case .notAllowed: "Fonos needs the microphone. Allow it in Settings > Privacy & Security > Microphone."
            case .noInput: "No microphone is available."
            }
        }
    }

    /// Called on the audio thread with 80-sample chunks.
    var onSamples: (@Sendable ([Float]) -> Void)?
    /// Called on the audio thread with each buffer at the mic's own rate,
    /// for Apple's speech recognizer.
    var onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?

    private let engine = AVAudioEngine()
    private let level = OSAllocatedUnfairLock(initialState: Float(-90))
    private var pending: [Float] = []
    private(set) var isRunning = false

    /// Loudness over about the last 100 ms, dBFS.
    var levelDb: Float { level.withLock { $0 } }

    static func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func start() throws {
        guard !isRunning else { return }
        let session = AVAudioSession.sharedInstance()
        // Measurement mode turns off voice processing, which would treat a
        // recording played nearby as background noise.
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try session.setActive(true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0,
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 8_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: format, to: target) else { throw MicError.noInput }
        pending.removeAll()

        input.installTap(onBus: 0, bufferSize: 2_048, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.onBuffer?(buffer)
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * 8_000 / format.sampleRate) + 32
            guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var fed = false
            converter.convert(to: out, error: nil) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true
                status.pointee = .haveData
                return buffer
            }
            guard let data = out.floatChannelData, out.frameLength > 0 else { return }
            self.pending += UnsafeBufferPointer(start: data[0], count: Int(out.frameLength))
            while self.pending.count >= 80 {
                let chunk = Array(self.pending.prefix(80))
                self.pending.removeFirst(80)
                let db = DSP.dbfs(DSP.rms(chunk))
                // Smooth over ~100 ms (10 chunks), rising faster than it falls.
                self.level.withLock { $0 += (db - $0) * (db > $0 ? 0.3 : 0.1) }
                self.onSamples?(chunk)
            }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        level.withLock { $0 = -90 }
        // Back to playback so the spoken result comes out at full volume.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
    }
}
