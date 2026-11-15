import SwiftUI

/// The signature view. The contact-mic waveform runs along the midline; the
/// left piezo's vibration envelope rises above it and the right piezo's falls
/// below it, so left/right throat symmetry reads as a shape: a mirror image
/// when balanced, lopsided when one side vibrates less.
struct FoldView: View {
    let streams: StreamStore
    var showsLabels = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 / 10 : 1.0 / 30)) { _ in
            Canvas { ctx, size in
                draw(streams.snapshot(), in: &ctx, size: size)
            }
        }
        .overlay(alignment: .topLeading) { if showsLabels { sideLabel("Left", Theme.left) } }
        .overlay(alignment: .bottomLeading) { if showsLabels { sideLabel("Right", Theme.right) } }
        .accessibilityElement()
        .accessibilityLabel("Live throat signal")
        .accessibilityValue(accessibilitySummary)
    }

    private func sideLabel(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .tracking(1)
            .foregroundStyle(color)
            .padding(4)
    }

    private var accessibilitySummary: String {
        let s = streams.snapshot()
        let l = s.leftLevel.suffix(50).reduce(0, +), r = s.rightLevel.suffix(50).reduce(0, +)
        guard l + r > 0.01 else { return "Quiet" }
        let balance = 1 - abs(l - r) / (l + r)
        return "Voice detected. Left and right are \(Int(balance * 100)) percent balanced."
    }

    private func draw(_ s: StreamStore.Snapshot, in ctx: inout GraphicsContext, size: CGSize) {
        let mid = size.height / 2
        let half = size.height / 2 - 2

        // Midline.
        var line = Path()
        line.move(to: CGPoint(x: 0, y: mid)); line.addLine(to: CGPoint(x: size.width, y: mid))
        ctx.stroke(line, with: .color(Theme.hairline), lineWidth: 1)

        // Shared gain so left and right are directly comparable.
        let peak = max(s.leftLevel.max() ?? 0, s.rightLevel.max() ?? 0, 0.08)
        let gain = Double(half) * 0.92 / Double(peak)

        func envelope(_ levels: [Float], up: Bool) -> Path {
            let smooth = DSP.movingAverage(levels, width: 5)
            var p = Path()
            let n = smooth.count
            guard n > 1 else { return p }
            p.move(to: CGPoint(x: 0, y: mid))
            for (i, v) in smooth.enumerated() {
                let x = size.width * CGFloat(i) / CGFloat(n - 1)
                let dy = CGFloat(min(Double(v) * gain, Double(half)))
                p.addLine(to: CGPoint(x: x, y: up ? mid - dy : mid + dy))
            }
            p.addLine(to: CGPoint(x: size.width, y: mid))
            p.closeSubpath()
            return p
        }

        if s.hasPiezo {
            let top = envelope(s.leftLevel, up: true)
            let bottom = envelope(s.rightLevel, up: false)
            ctx.fill(top, with: .linearGradient(
                Gradient(colors: [Theme.left.opacity(0.55), Theme.left.opacity(0.12)]),
                startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: mid)))
            ctx.fill(bottom, with: .linearGradient(
                Gradient(colors: [Theme.right.opacity(0.12), Theme.right.opacity(0.55)]),
                startPoint: CGPoint(x: 0, y: mid), endPoint: CGPoint(x: 0, y: size.height)))
            ctx.stroke(top, with: .color(Theme.left), lineWidth: 1.5)
            ctx.stroke(bottom, with: .color(Theme.right), lineWidth: 1.5)
        }

        // Mic waveform: one min/max bar per 2 pt column, on top of the fold.
        let wave = s.micWave
        guard !wave.isEmpty else { return }
        let columns = max(Int(size.width / 2), 1)
        let per = max(wave.count / columns, 1)
        let micPeak = max(wave.map(abs).max() ?? 0, 0.05)
        let micGain = Double(half) * 0.55 / Double(micPeak)
        var bars = Path()
        for c in 0..<columns {
            let start = c * per
            guard start < wave.count else { break }
            let slice = wave[start..<min(start + per, wave.count)]
            let lo = Double(slice.min() ?? 0) * micGain, hi = Double(slice.max() ?? 0) * micGain
            let x = CGFloat(c) * 2 + 1
            bars.move(to: CGPoint(x: x, y: mid - CGFloat(hi)))
            bars.addLine(to: CGPoint(x: x, y: mid - CGFloat(lo) + 0.5))
        }
        ctx.stroke(bars, with: .color(Theme.mic), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
    }
}

/// A single stream drawn as an oscilloscope trace, for the Band screen.
struct StreamTrace: View {
    enum Channel { case mic, left, right }
    let streams: StreamStore
    let channel: Channel
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 / 10 : 1.0 / 30)) { _ in
            Canvas { ctx, size in
                let s = streams.snapshot()
                let raw: [Float] = switch channel {
                case .mic: s.micWave
                case .left: s.leftWave
                case .right: s.rightWave
                }
                // Last 1.5 s only, so individual syllables are visible.
                let rate = channel == .mic ? 800 : 1_000
                let data = Array(raw.suffix(Int(1.5 * Double(rate))))
                guard data.count > 1 else { return }
                let mid = size.height / 2
                let peak = max(data.map(abs).max() ?? 0, 0.05)
                let gain = (size.height / 2 - 2) / CGFloat(peak)
                var p = Path()
                for (i, v) in data.enumerated() {
                    let pt = CGPoint(x: size.width * CGFloat(i) / CGFloat(data.count - 1), y: mid - CGFloat(v) * gain)
                    i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                }
                ctx.stroke(p, with: .color(color), lineWidth: 1.2)
            }
        }
        .accessibilityHidden(true)
    }
}
