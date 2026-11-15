import SwiftUI

/// Drives a live view only while it is on screen and the app is active.
/// Hidden tabs in a TabView stay alive, so without this every live chart
/// keeps redrawing at full rate behind whatever the patient is looking at.
private struct LiveVisibility: ViewModifier {
    @Binding var visible: Bool
    @Environment(\.scenePhase) private var phase
    @State private var onScreen = false

    func body(content: Content) -> some View {
        content
            .onAppear { onScreen = true; update() }
            .onDisappear { onScreen = false; update() }
            .onChange(of: phase) { _, _ in update() }
    }

    private func update() { visible = onScreen && phase == .active }
}

/// The signature view: one throat signal. The contact-mic waveform runs along
/// the midline inside a single vibration envelope (both piezos combined),
/// mirrored above and below it.
struct FoldView: View {
    let streams: StreamStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var visible = false

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 / 10 : 1.0 / 30, paused: !visible)) { timeline in
            // One snapshot per tick feeds both the drawing and VoiceOver.
            let s = streams.fold()
            let _ = timeline.date
            let light = scheme == .light
            Canvas { ctx, size in draw(s, in: &ctx, size: size, light: light) }
                .accessibilityElement()
                .accessibilityLabel("Live throat signal")
                .accessibilityValue(summary(s))
        }
        .modifier(LiveVisibility(visible: $visible))
    }

    private func summary(_ s: StreamStore.Fold) -> String {
        let vibration = s.leftLevel.suffix(50).reduce(0, +) + s.rightLevel.suffix(50).reduce(0, +)
        let mic = s.micWave.suffix(400).reduce(Float(0)) { max($0, abs($1)) }
        return vibration > 0.01 || mic > 0.05 ? "Voice detected" : "Quiet"
    }

    /// Both piezos averaged into one throat-vibration level.
    private func combined(_ s: StreamStore.Fold) -> [Float] {
        let n = min(s.leftLevel.count, s.rightLevel.count)
        guard n > 0 else { return s.leftLevel.isEmpty ? s.rightLevel : s.leftLevel }
        let l = s.leftLevel.suffix(n), r = s.rightLevel.suffix(n)
        return zip(l, r).map { ($0 + $1) / 2 }
    }

    private func draw(_ s: StreamStore.Fold, in ctx: inout GraphicsContext, size: CGSize, light: Bool) {
        let mid = size.height / 2
        let half = size.height / 2 - 2

        var line = Path()
        line.move(to: CGPoint(x: 0, y: mid)); line.addLine(to: CGPoint(x: size.width, y: mid))
        ctx.stroke(line, with: .color(Theme.hairline), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))

        let level = combined(s)
        let peak = max(level.max() ?? 0, 0.08)
        let gain = Double(half) * 0.92 / Double(peak)
        let smooth = DSP.movingAverage(level, width: 5)

        func envelope(up: Bool) -> Path {
            var p = Path()
            let n = smooth.count
            guard n > 1 else { return p }
            // At most one point per horizontal point; the buffer holds 500.
            let step = max(1, n / Int(max(size.width, 1)))
            p.move(to: CGPoint(x: 0, y: mid))
            for i in stride(from: 0, to: n, by: step) {
                let x = size.width * CGFloat(i) / CGFloat(n - 1)
                let dy = CGFloat(min(Double(smooth[i]) * gain, Double(half)))
                p.addLine(to: CGPoint(x: x, y: up ? mid - dy : mid + dy))
            }
            p.addLine(to: CGPoint(x: size.width, y: mid))
            p.closeSubpath()
            return p
        }

        if s.hasPiezo {
            let top = envelope(up: true)
            let bottom = envelope(up: false)
            // Softer washes on white so the outline carries the shape.
            let outer = light ? 0.30 : 0.55, inner = light ? 0.03 : 0.12
            let edge = StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
            ctx.fill(top, with: .linearGradient(
                Gradient(colors: [Theme.left.opacity(outer), Theme.left.opacity(inner)]),
                startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: mid)))
            ctx.fill(bottom, with: .linearGradient(
                Gradient(colors: [Theme.left.opacity(inner), Theme.left.opacity(outer)]),
                startPoint: CGPoint(x: 0, y: mid), endPoint: CGPoint(x: 0, y: size.height)))
            ctx.stroke(top, with: .color(Theme.left), style: edge)
            ctx.stroke(bottom, with: .color(Theme.left), style: edge)
        }

        // Mic waveform: one min/max bar per 3 pt column, on top of the fold.
        let wave = s.micWave
        guard !wave.isEmpty else { return }
        let columns = max(Int(size.width / 3), 1)
        let per = max(wave.count / columns, 1)
        var micPeak: Float = 0.05
        for v in wave where abs(v) > micPeak { micPeak = abs(v) }
        let micGain = Double(half) * 0.5 / Double(micPeak)
        var bars = Path()
        for c in 0..<columns {
            let start = c * per
            guard start < wave.count else { break }
            var lo: Float = 0, hi: Float = 0
            for k in start..<min(start + per, wave.count) { lo = min(lo, wave[k]); hi = max(hi, wave[k]) }
            let x = CGFloat(c) * 3 + 1.5
            bars.move(to: CGPoint(x: x, y: mid - CGFloat(Double(hi) * micGain)))
            bars.addLine(to: CGPoint(x: x, y: mid - CGFloat(Double(lo) * micGain) + 0.5))
        }
        ctx.stroke(bars, with: .color(Theme.mic.opacity(light ? 0.9 : 1)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
    }
}

/// A single stream drawn as an oscilloscope trace, for the Band screen.
struct StreamTrace: View {
    let streams: StreamStore
    let channel: StreamStore.Channel
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 / 10 : 1.0 / 30, paused: !visible)) { timeline in
            // Last 1.5 s only, so individual syllables are visible.
            let data = streams.trace(channel, seconds: 1.5)
            let _ = timeline.date
            Canvas { ctx, size in
                guard data.count > 1 else { return }
                let mid = size.height / 2
                var peak: Float = 0.05
                for v in data where abs(v) > peak { peak = abs(v) }
                let gain = (size.height / 2 - 2) / CGFloat(peak)
                // About two points per horizontal point.
                let step = max(1, data.count / Int(max(size.width * 2, 1)))
                var p = Path()
                for i in stride(from: 0, to: data.count, by: step) {
                    let pt = CGPoint(x: size.width * CGFloat(i) / CGFloat(data.count - 1), y: mid - CGFloat(data[i]) * gain)
                    i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                }
                ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
        .modifier(LiveVisibility(visible: $visible))
    }
}
