import AVFoundation
import Foundation

/// Uses the iPhone microphone as the mic stream (piezo streams are empty).
/// Lets the translation pipeline be tested without hardware.
final class PhoneMicSource: FrameSource, @unchecked Sendable {

    var onFrame: (@Sendable (SensorFrame) -> Void)?

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 8_000, channels: 1, interleaved: false)!
    private var pending: [Float] = []
    private var sequence: UInt8 = 0
    private var timestampMs: UInt32 = 0
    private(set) var isRunning = false

    func startStreaming() {
        guard !isRunning else { return }
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            guard granted else { return }
            DispatchQueue.main.async { self?.startEngine() }
        }
    }

    func stopStreaming() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }

    private func startEngine() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try? session.setActive(true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }
        converter = AVAudioConverter(from: format, to: target)

        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            self?.convert(buffer)
        }
        do {
            try engine.start()
            isRunning = true
        } catch {
            input.removeTap(onBus: 0)
        }
    }

    private func convert(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var fed = false
        converter.convert(to: out, error: nil) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard let ch = out.floatChannelData?[0] else { return }
        pending.append(contentsOf: UnsafeBufferPointer(start: ch, count: Int(out.frameLength)))
        while pending.count >= 80 {
            let mic = Array(pending.prefix(80))
            pending.removeFirst(80)
            onFrame?(SensorFrame(sequence: sequence, timestamp: timestampMs, mic: mic, left: [], right: []))
            sequence &+= 1
            timestampMs &+= 10
        }
    }
}
