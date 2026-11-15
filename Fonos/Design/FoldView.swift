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

/// The throat strip. The mic waveform runs along the midline; the left
/// accelerometer's vibration envelope rises above it and the right one's falls
/// below it, so left/right balance reads as a shape. It doubles as a live fit check.
struct FoldView: View {
    let streams: StreamStore
    var showsLabels = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    var body: some View {
        HStack(spacing: 8) {
            if showsLabels {
                // Labels live in a gutter so they never sit on the trace.
                VStack(alignment: .leading) {
                    sideLabel("Left", Theme.left)
                    Spacer(minLength: 0)
                    sideLabel("Right", Theme.right)
                }
                .frame(width: 46, alignment: .leading)
            }
            TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 / 10 : 1.0 / 30, paused: !visible)) { timeline in
                // One snapshot per tick feeds both the drawing and VoiceOver.
                let s = streams.fold()
                let _ = timeline.date
                Canvas { ctx, size in draw(s, in: &ctx, size: size) }
                    .accessibilityElement()
                    .accessibilityLabel("Live throat vibration")
                    .accessibilityValue(summary(s))
            }
        }
        .modifier(LiveVisibility(visible: $visible))
    }

    private func sideLabel(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.metric(.caption2, weight: .semibold))
            .textCase(.uppercase)
            .tracking(1.2)
            .foregroundStyle(color)
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
            .accessibilityHidden(true)
    }

    private func summary(_ s: StreamStore.Fold) -> String {
        let l = s.leftLevel.suffix(50).reduce(0, +), r = s.rightLevel.suffix(50).reduce(0, +)
        guard l + r > 0.01 else { return "Quiet" }
        let balance = 1 - abs(l - r) / (l + r)
        return "Voice detected. Left and right are \(Int(balance * 100)) percent even."
    }

    private func draw(_ s: StreamStore.Fold, in ctx: inout GraphicsContext, size: CGSize) {
        let mid = size.height / 2
        let half = size.height / 2 - 2

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
        ctx.stroke(bars, with: .color(Theme.mic), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
    }
}

/// One raw stream as an oscilloscope trace, for the Band screen.
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
                ctx.stroke(p, with: .color(color), lineWidth: 1.2)
            }
        }
        .accessibilityHidden(true)
        .modifier(LiveVisibility(visible: $visible))
    }
}
