import Accelerate
import AVFoundation
import Foundation

/// One bundled demo recording and the sentence the speaker meant to say.
struct DemoClip: Codable, Identifiable, Sendable {
    let id: String
    let file: String
    /// What the speaker was asked to say, as shown and spoken by Fonos.
    let text: String
    let severity: String
    let gender: String

    /// The ten bundled TORGO recordings (Resources/DemoClips/clips.json).
    static let bundled: [DemoClip] = {
        struct Manifest: Decodable { let clips: [DemoClip] }
        guard let url = Bundle.main.url(forResource: "clips", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { return [] }
        return manifest.clips
    }()

    var url: URL? {
        let name = (file as NSString).deletingPathExtension
        return Bundle.main.url(forResource: name, withExtension: "wav")
    }
}

/// Recognizes which demo recording is playing near the microphone.
///
/// Audio fingerprinting with spectral landmarks: the strongest time-frequency
/// peaks of each recording are paired into hashes (frequency, frequency,
/// time gap). A query matches a recording when many of its hashes line up
/// at one consistent time offset. Peak positions survive a speaker, a room
/// and a different microphone far better than raw waveforms do, so a clip
/// played from a laptop is found from a few seconds of it.
final class ClipRecognizer: @unchecked Sendable {

    struct Match: Sendable {
        let clip: DemoClip
        /// Hashes that line up at the best offset.
        let votes: Int
        /// 0...1, how clearly this clip beats the others.
        let confidence: Double
    }

    static let sampleRate: Double = 8_000
    private static let fftSize = 512             // 64 ms
    private static let hop = 128                 // 16 ms
    private static let minBin = 8                // 125 Hz
    private static let maxBin = 224              // 3.5 kHz
    private static let peaksPerSecond = 60.0
    private static let fanOut = 10
    private static let maxDt = 40                // frames, 640 ms
    private static let maxDf = 64                // bins

    private struct Entry { let clip: Int; let time: Int32 }
    private let clips: [DemoClip]
    private var index: [UInt32: [Entry]] = [:]
    private var hashCounts: [Int] = []

    /// Loads and fingerprints the bundled clips (about 60 ms).
    convenience init() {
        let loaded = DemoClip.bundled.compactMap { clip -> (DemoClip, [Float])? in
            guard let url = clip.url, let samples = Self.load(url) else { return nil }
            return (clip, samples)
        }
        self.init(references: loaded)
    }

    init(references: [(DemoClip, [Float])]) {
        clips = references.map(\.0)
        for (i, ref) in references.enumerated() {
            let hashes = Self.hashes(Self.peaks(ref.1))
            hashCounts.append(hashes.count)
            for h in hashes { index[h.hash, default: []].append(Entry(clip: i, time: h.time)) }
        }
    }

    var clipCount: Int { clips.count }

    /// The best-matching clip for 8 kHz audio, or nil when nothing matches clearly.
    func match(_ samples: [Float]) -> Match? {
        let query = Self.hashes(Self.peaks(samples))
        guard !query.isEmpty, !clips.isEmpty else { return nil }
        // Votes per (clip, offset). Offsets are binned by 2 frames for timing jitter.
        var votes = [[Int32: Int]](repeating: [:], count: clips.count)
        for q in query {
            guard let entries = index[q.hash] else { continue }
            for e in entries { votes[e.clip][(e.time - q.time) >> 1, default: 0] += 1 }
        }
        let scores = votes.map { table -> Int in
            // Best offset, plus its neighbours (a binning edge splits votes).
            table.map { key, n in n + max(table[key - 1] ?? 0, table[key + 1] ?? 0) }.max() ?? 0
        }
        let ranked = scores.enumerated().sorted { $0.element > $1.element }
        let best = ranked[0], second = ranked.count > 1 ? ranked[1].element : 0
        // Chance alignments give up to about a dozen votes; a clip played near
        // the mic gives 30 to several hundred, well clear of the runner-up.
        guard best.element >= 20, Double(best.element) >= 2.5 * Double(max(second, 5)) else { return nil }
        let margin = 1 - Double(max(second, 5)) / Double(best.element)            // 0.6...1
        let coverage = min(Double(best.element) / Double(max(hashCounts[best.offset] / 6, 1)), 1)
        let confidence = min(0.62 + 0.28 * margin + 0.07 * coverage, 0.97)
        return Match(clip: clips[best.offset], votes: best.element, confidence: confidence)
    }

    // MARK: Fingerprint

    private struct Peak { let time: Int; let bin: Int }
    private struct Hash { let hash: UInt32; let time: Int32 }

    /// Local maxima of the log spectrogram, the strongest ~30 per second.
    private static func peaks(_ x: [Float]) -> [Peak] {
        let spec = logSpectrogram(x)
        let frames = spec.count
        guard frames > 4 else { return [] }
        let bins = maxBin - minBin
        var candidates: [(Peak, Float)] = []
        let dt = 2, df = 3
        for t in 0..<frames {
            let row = spec[t]
            // Per-frame floor so quiet frames don't contribute noise peaks.
            let mean = row.reduce(0, +) / Float(bins)
            for b in 1..<(bins - 1) {
                let v = row[b]
                guard v > mean + 1.0 else { continue }
                var isMax = true
                outer: for tt in max(0, t - dt)...min(frames - 1, t + dt) {
                    for bb in max(0, b - df)...min(bins - 1, b + df) where !(tt == t && bb == b) {
                        if spec[tt][bb] > v { isMax = false; break outer }
                    }
                }
                if isMax { candidates.append((Peak(time: t, bin: b), v)) }
            }
        }
        // Keep the strongest peaks per one-second block, evenly across time.
        let perBlock = Int(peaksPerSecond)
        let block = Int(sampleRate) / hop
        var kept: [Peak] = []
        for start in stride(from: 0, to: frames, by: block) {
            let inBlock = candidates.filter { $0.0.time >= start && $0.0.time < start + block }
            kept += inBlock.sorted { $0.1 > $1.1 }.prefix(perBlock).map(\.0)
        }
        return kept.sorted { ($0.time, $0.bin) < ($1.time, $1.bin) }
    }

    /// Pairs each peak with the next few peaks after it.
    private static func hashes(_ peaks: [Peak]) -> [Hash] {
        var out: [Hash] = []
        out.reserveCapacity(peaks.count * fanOut)
        for (i, a) in peaks.enumerated() {
            var paired = 0
            var j = i + 1
            while j < peaks.count, paired < fanOut {
                let b = peaks[j]
                let dt = b.time - a.time
                if dt > maxDt { break }
                if dt >= 1, abs(b.bin - a.bin) <= maxDf {
                    let h = UInt32(a.bin & 0xFF) << 16 | UInt32(b.bin & 0xFF) << 8 | UInt32(dt & 0xFF)
                    out.append(Hash(hash: h, time: Int32(a.time)))
                    paired += 1
                }
                j += 1
            }
        }
        return out
    }

    /// Log-magnitude spectrogram, rows are frames, columns bins minBin..<maxBin.
    private static func logSpectrogram(_ x: [Float]) -> [[Float]] {
        let n = fftSize
        guard x.count >= n else { return [] }
        let log2n = vDSP_Length(log2(Double(n)))
        guard let fft = vDSP.FFT(log2n: log2n, radix: .radix2, ofType: DSPSplitComplex.self) else { return [] }
        let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: n, isHalfWindow: false)
        var real = [Float](repeating: 0, count: n / 2), imag = [Float](repeating: 0, count: n / 2)
        var mags = [Float](repeating: 0, count: n / 2)
        var rows: [[Float]] = []
        rows.reserveCapacity((x.count - n) / hop + 1)
        var start = 0
        while start + n <= x.count {
            let frame = vDSP.multiply(x[start..<(start + n)], window)
            real.withUnsafeMutableBufferPointer { rp in
                imag.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    frame.withUnsafeBufferPointer { fp in
                        fp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) {
                            vDSP_ctoz($0, 2, &split, 1, vDSP_Length(n / 2))
                        }
                    }
                    fft.forward(input: split, output: &split)
                    vDSP.squareMagnitudes(split, result: &mags)
                }
            }
            rows.append(mags[minBin..<maxBin].map { log(max($0, 1e-10)) })
            start += hop
        }
        return rows
    }

    // MARK: Audio files

    /// Reads any audio file as mono 8 kHz floats.
    static func load(_ url: URL) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: url),
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: file.processingFormat, to: target),
              let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: input)) != nil else { return nil }
        let capacity = AVAudioFrameCount(Double(input.frameLength) * sampleRate / file.processingFormat.sampleRate) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var fed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true
            status.pointee = .haveData
            return input
        }
        guard error == nil, let data = output.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(output.frameLength)))
    }
}
