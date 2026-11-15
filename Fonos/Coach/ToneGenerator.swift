import AVFoundation
import os

/// Reference tones and count-in clicks, synthesized on the fly.
final class ToneGenerator: @unchecked Sendable {

    private struct State {
        var frequency: Double = 440
        var amplitude: Double = 0
        var target: Double = 0
        var phase: Double = 0
        var clickSamples = 0
    }

    private let engine = AVAudioEngine()
    private let state = OSAllocatedUnfairLock(initialState: State())
    private var started = false

    private func start() {
        guard !started else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        let format = engine.outputNode.inputFormat(forBus: 0)
        let rate = format.sampleRate > 0 ? format.sampleRate : 48_000
        let mono = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let node = AVAudioSourceNode(format: mono) { [state] _, _, frameCount, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard let out = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            state.withLock { s in
                for i in 0..<Int(frameCount) {
                    // Smooth amplitude to avoid clicks at note edges.
                    s.amplitude += (s.target - s.amplitude) * 0.0015
                    s.phase += 2 * .pi * s.frequency / rate
                    if s.phase > 2 * .pi { s.phase -= 2 * .pi }
                    // Soft tone: fundamental plus a quiet octave.
                    var v = s.amplitude * (sin(s.phase) + 0.2 * sin(2 * s.phase))
                    if s.clickSamples > 0 {
                        let k = Double(s.clickSamples) / 900
                        v += 0.25 * k * sin(Double(s.clickSamples) * 0.35)
                        s.clickSamples -= 1
                    }
                    out[i] = Float(v * 0.25)
                }
            }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: mono)
        do { try engine.start(); started = true } catch { started = false }
    }

    func play(midi: Int, duration: Double) {
        start()
        state.withLock { $0.frequency = Music.hz(midi: Double(midi)); $0.target = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.state.withLock { $0.target = 0 }
        }
    }

    func click() {
        start()
        state.withLock { $0.clickSamples = 900 }
    }

    func stop() {
        state.withLock { $0.target = 0 }
    }
}
