import SwiftUI

/// The signature view: the singer's pitch line laid over the target notes.
/// Landing a note shows as the line settling onto its bar; vibrato shows as
/// a wave around it. Thicker and colored where it's within ±25 cents.
struct PitchLane: View {
    let analyzer: SingingAnalyzer
    let plan: TakePlan
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    /// Seconds visible behind and ahead of "now".
    private let past = 3.2
    private let ahead = 1.6

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 / 8 : 1.0 / 30)) { timeline in
            let _ = timeline.date
            let now = analyzer.takeTime ?? 0
            let track = analyzer.pitchTrack()
            Canvas { ctx, size in draw(&ctx, size: size, now: now, track: track) }
        }
        .accessibilityHidden(true)
    }

    private var midiRange: ClosedRange<Double> {
        let notes = plan.notes.map { Double($0.midi) }
        let lo = (notes.min() ?? 48) - 2.5, hi = (notes.max() ?? 60) + 2.5
        return lo...max(hi, lo + 9)
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, now: Double, track: [(t: Double, midi: Double?)]) {
        let gutter: CGFloat = 40
        let width = size.width - gutter
        let range = midiRange
        // Reduce Motion: the lane holds still and "now" walks across instead.
        let start: Double = reduceMotion ? -0.2 : now - past
        let span: Double = reduceMotion ? plan.duration + 0.4 : past + ahead
        func x(_ t: Double) -> CGFloat { gutter + CGFloat((t - start) / span) * width }
        func y(_ m: Double) -> CGFloat { size.height * CGFloat(1 - (m - range.lowerBound) / (range.upperBound - range.lowerBound)) }
        let semitone = size.height / CGFloat(range.upperBound - range.lowerBound)

        // Semitone guides and note names for the target notes.
        let names = Set(plan.notes.map(\.midi))
        for m in Int(range.lowerBound.rounded(.up))...Int(range.upperBound) {
            var line = Path()
            line.move(to: CGPoint(x: gutter, y: y(Double(m))))
            line.addLine(to: CGPoint(x: size.width, y: y(Double(m))))
            ctx.stroke(line, with: .color(Theme.hairline.opacity(names.contains(m) ? 0.9 : 0.35)), lineWidth: 0.5)
            if names.contains(m) {
                ctx.draw(Text(Music.name(m)).font(.metric(.caption2, weight: .semibold)).foregroundStyle(Theme.inkSecondary),
                         at: CGPoint(x: 2, y: y(Double(m))), anchor: .leading)
            }
        }

        // Target bars (±25 cents tall), or the glide path for a siren.
        let current = plan.note(at: now)
        if plan.glide {
            var p = Path()
            var first = true
            for t in stride(from: max(0, start), to: min(plan.duration, start + span), by: 0.05) {
                guard let m = plan.target(at: t) else { continue }
                let pt = CGPoint(x: x(t), y: y(m))
                if first { p.move(to: pt); first = false } else { p.addLine(to: pt) }
            }
            ctx.stroke(p, with: .color(Theme.well), style: StrokeStyle(lineWidth: semitone * 0.5, lineCap: .round))
        } else {
            for note in plan.notes where note.end > start && note.start < start + span {
                let rect = CGRect(x: x(note.start), y: y(Double(note.midi)) - semitone * 0.25,
                                  width: x(note.end) - x(note.start), height: semitone * 0.5)
                let isCurrent = note == current
                ctx.fill(Path(roundedRect: rect, cornerRadius: semitone * 0.25),
                         with: .color(isCurrent ? Theme.tune.opacity(0.28) : Theme.well))
                ctx.stroke(Path(roundedRect: rect, cornerRadius: semitone * 0.25),
                           with: .color(isCurrent ? Theme.tune.opacity(0.7) : Theme.hairline), lineWidth: 1)
            }
        }

        // Pitch line: broken at silences, thicker where in tune.
        var all = Path(), tuned = Path()
        var lastPoint: CGPoint?
        var lastTuned = false
        for sample in track where sample.t >= start {
            guard let m = sample.midi else { lastPoint = nil; continue }
            let pt = CGPoint(x: x(sample.t), y: y(m))
            let target = plan.target(at: sample.t)
            let inTune = target.map { abs(SingingAnalyzer.foldOctave((m - $0) * 100)) <= 25 } ?? false
            if let last = lastPoint {
                all.move(to: last); all.addLine(to: pt)
                if inTune && lastTuned { tuned.move(to: last); tuned.addLine(to: pt) }
            }
            lastPoint = pt
            lastTuned = inTune
        }
        ctx.stroke(all, with: .color(Theme.ink.opacity(0.75)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        ctx.stroke(tuned, with: .color(Theme.tune), style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))

        // "Now" marker.
        var nowLine = Path()
        nowLine.move(to: CGPoint(x: x(now), y: 0))
        nowLine.addLine(to: CGPoint(x: x(now), y: size.height))
        ctx.stroke(nowLine, with: .color(Theme.inkTertiary.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
        if let last = track.last, let m = last.midi, last.t >= start {
            let dot = CGRect(x: x(last.t) - 5, y: y(m) - 5, width: 10, height: 10)
            ctx.fill(Path(ellipseIn: dot), with: .color(Theme.ink))
        }
    }
}

/// A ±50 cent tuning arc. The center zone is the in-tune band; a check mark
/// appears there while the singer is inside it, so color is never the only cue.
struct TuningNeedle: View {
    let cents: Double?
    let inTune: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let r = min(w / 2, h) - 6
            let center = CGPoint(x: w / 2, y: h - 2)
            let angle = Angle.degrees(max(-50, min(50, cents ?? 0)) / 50 * 80)
            ZStack {
                ArcShape(center: center, radius: r, from: -80, to: 80)
                    .stroke(Theme.hairline, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                ArcShape(center: center, radius: r, from: -40, to: 40)
                    .stroke(Theme.tune.opacity(inTune ? 0.9 : 0.3), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                if cents != nil {
                    NeedleShape(center: center, length: r - 8, degrees: angle.degrees)
                        .stroke(Theme.ink, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .animation(reduceMotion ? nil : .interpolatingSpring(stiffness: 140, damping: 18), value: angle)
                }
                Circle().fill(Theme.ink).frame(width: 12, height: 12).position(center)
                if inTune {
                    FonosIcon(.check, size: 22, relativeTo: .title3)
                        .foregroundStyle(Theme.tune)
                        .position(x: center.x, y: center.y - r - 4)
                        .transition(.opacity)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Tuning")
        .accessibilityValue(accessibilityText)
    }

    private var accessibilityText: String {
        guard let cents else { return "Not singing" }
        if inTune { return "In tune" }
        return "\(Int(abs(cents))) cents \(cents < 0 ? "low" : "high")"
    }
}

struct NeedleShape: Shape {
    let center: CGPoint
    let length: CGFloat
    var degrees: Double

    var animatableData: Double {
        get { degrees }
        set { degrees = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let a = (degrees - 90) * .pi / 180
        var p = Path()
        p.move(to: center)
        p.addLine(to: CGPoint(x: center.x + length * cos(a), y: center.y + length * sin(a)))
        return p
    }
}

struct ArcShape: Shape {
    let center: CGPoint
    let radius: CGFloat
    /// Degrees from straight up; negative is left.
    let from: Double
    let to: Double

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addArc(center: center, radius: radius,
                 startAngle: .degrees(from - 90), endAngle: .degrees(to - 90), clockwise: false)
        return p
    }
}

/// Keyboard strip from C2 to C6 with the comfortable range highlighted and
/// last month's range as a dashed outline, so growth is visible.
struct VoiceRangeStrip: View {
    let low: Int?
    let high: Int?
    var previousLow: Int?
    var previousHigh: Int?

    private let first = 36, last = 84 // C2...C6

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Canvas { ctx, size in
                let whites = (first...last).filter { !Music.isBlackKey($0) }
                let keyW = size.width / CGFloat(whites.count)
                func xFor(_ midi: Int) -> CGFloat {
                    let idx = whites.firstIndex(where: { $0 >= midi }) ?? whites.count - 1
                    return CGFloat(idx) * keyW + (Music.isBlackKey(midi) ? 0 : keyW / 2)
                }
                for (i, k) in whites.enumerated() {
                    let rect = CGRect(x: CGFloat(i) * keyW + 0.5, y: 0, width: keyW - 1, height: size.height)
                    let inRange = low.map { k >= $0 } == true && high.map { k <= $0 } == true
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(inRange ? Theme.rangeHue.opacity(0.85) : Theme.well))
                }
                for k in first...last where Music.isBlackKey(k) {
                    let idx = whites.firstIndex(where: { $0 > k }) ?? 0
                    let rect = CGRect(x: CGFloat(idx) * keyW - keyW * 0.3, y: 0, width: keyW * 0.6, height: size.height * 0.58)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(Theme.ground))
                }
                if let pl = previousLow, let ph = previousHigh {
                    let rect = CGRect(x: xFor(pl) - keyW / 2, y: -3, width: xFor(ph) - xFor(pl) + keyW, height: size.height + 6)
                    ctx.stroke(Path(roundedRect: rect, cornerRadius: 4), with: .color(Theme.inkSecondary),
                               style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                }
            }
            .frame(height: 44)
            HStack {
                Text("C2").font(.ui(.caption)).foregroundStyle(Theme.inkTertiary)
                Spacer()
                if let low, let high {
                    Text("\(Music.name(low)) – \(Music.name(high))")
                        .font(.metric(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
                Spacer()
                Text("C6").font(.ui(.caption)).foregroundStyle(Theme.inkTertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Voice range")
        .accessibilityValue(low.flatMap { l in high.map { "\(Music.spokenName(l)) to \(Music.spokenName($0)), \($0 - l) semitones" } } ?? "Not measured yet")
    }
}
