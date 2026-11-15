import SwiftUI

// MARK: - Card

struct CardBackground: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardBackground(padding: padding)) }
}

/// Apple Health–style card header: colored symbol and title, optional trailing detail and chevron.
struct CardHeader: View {
    let title: String
    let icon: Icon
    let color: Color
    var detail: String? = nil
    var chevron = false

    var body: some View {
        HStack(spacing: 6) {
            Label { Text(title) } icon: { FonosIcon(icon, size: 19, relativeTo: .subheadline) }
                .font(.ui(.subheadline, .bold))
                .foregroundStyle(color)
                .labelStyle(.titleAndIcon)
            Spacer(minLength: 8)
            if let detail {
                Text(detail).font(.ui(.footnote)).foregroundStyle(Theme.inkSecondary)
            }
            if chevron {
                FonosIcon(.chevron, size: 14, relativeTo: .footnote)
                    .foregroundStyle(Theme.inkTertiary)
            }
        }
    }
}

// MARK: - Metric ring

/// WHOOP-style ring: thick track, colored arc with a bright end cap, the
/// value and its unit inside (every ring shows its unit).
struct MetricRing: View {
    let metric: MetricID
    let value: Double?
    var diameter: CGFloat = 96
    var lineWidth: CGFloat = 9
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: Double = 0

    var body: some View {
        let fill = value.map { metric.ringScore($0) / 100 } ?? 0
        ZStack {
            Circle().stroke(Theme.hairline, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: drawn)
                .stroke(metric.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            // End cap marks where the value sits.
            if drawn > 0.02 {
                Circle()
                    .fill(Theme.ink)
                    .frame(width: lineWidth * 0.45, height: lineWidth * 0.45)
                    .offset(y: -diameter / 2)
                    .rotationEffect(.degrees(360 * drawn))
            }
            valueText
        }
        .frame(width: diameter, height: diameter)
        .onAppear {
            if reduceMotion { drawn = fill } else {
                withAnimation(.easeOut(duration: 0.9)) { drawn = fill }
            }
        }
        .onChange(of: fill) { _, new in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.5)) { drawn = new }
        }
    }

    @ViewBuilder private var valueText: some View {
        if let value {
            let label = metric.ringLabel(value)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(label.value)
                    .font(.metric(compact ? .callout : .title, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(label.unit)
                    .font(.metric(compact ? .caption2 : .footnote))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            // The ring is a fixed size; numerals stop growing at xxxLarge.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .padding(.horizontal, lineWidth + 3)
        } else {
            Text("–").font(.metric(compact ? .callout : .title)).foregroundStyle(Theme.inkTertiary)
        }
    }
}

/// Small outlined tag for measures still being validated.
struct ExploratoryTag: View {
    var body: some View {
        Text("Exploratory")
            .font(.ui(.caption2, .semibold))
            .foregroundStyle(Theme.inkSecondary)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
            .accessibilityLabel("Exploratory measure")
    }
}

/// Trend vs baseline in ink with an arrow glyph; never color alone.
struct TrendText: View {
    let text: String
    let direction: Int // -1, 0, 1
    var body: some View {
        HStack(spacing: 4) {
            if direction != 0 {
                Text(direction > 0 ? "↑" : "↓").font(.metric(.subheadline, weight: .bold))
            }
            Text(text).font(.ui(.subheadline, .medium))
        }
        .foregroundStyle(Theme.ink)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Status pill

struct StatusPill: View {
    let text: String
    let color: Color
    var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .opacity(pulsing && !reduceMotion ? (on ? 1 : 0.35) : 1)
                .animation(pulsing && !reduceMotion ? .easeInOut(duration: 0.8).repeatForever() : nil, value: on)
            Text(text)
                .font(.metric(.footnote, weight: .semibold))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 34)
        .background(Theme.well, in: Capsule())
        .onAppear { on = true }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Battery

struct BatteryBadge: View {
    let percent: Int?
    var charging = false

    var body: some View {
        HStack(spacing: 4) {
            if let percent {
                Text("\(percent)%").font(.ui(.footnote, .medium)).monospacedDigit()
                    .foregroundStyle(Theme.inkSecondary)
            }
            BatteryGlyph(percent: percent, color: color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(percent.map { "Band battery \($0) percent\(charging ? ", charging" : "")" } ?? "Band battery unknown")
    }

    private var color: Color {
        guard let percent else { return Theme.inkTertiary }
        return percent < 15 ? Theme.alert : Theme.inkSecondary
    }
}

// MARK: - Signal bars

struct SignalBars: View {
    let rssi: Int?
    var body: some View {
        let level = rssi.map { $0 > -60 ? 4 : $0 > -70 ? 3 : $0 > -80 ? 2 : 1 } ?? 0
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i <= level ? Theme.ink : Theme.hairline)
                    .frame(width: 4, height: CGFloat(4 + i * 3))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Signal \(["none", "weak", "fair", "good", "excellent"][level])")
    }
}

// MARK: - Buttons

/// Full-width secondary action in the WHOOP style: tracked caps on a well.
struct WellButtonStyle: ButtonStyle {
    var tint: Color = Theme.ink
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.metric(.subheadline, weight: .semibold))
            .textCase(.uppercase)
            .tracking(1)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Theme.well.opacity(configuration.isPressed ? 0.6 : 1),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == WellButtonStyle {
    static var well: WellButtonStyle { WellButtonStyle() }
    static func well(_ tint: Color) -> WellButtonStyle { WellButtonStyle(tint: tint) }
}

/// Sample-data notice. Shown wherever toy data could be mistaken for a real measurement.
struct SampleBanner: View {
    var text = "Sample data from a simulated band and singer. Numbers show what Fonos will look like with a real band."
    var body: some View {
        Label { Text(text) } icon: { FonosIcon(.info, size: 18, relativeTo: .footnote) }
            .font(.ui(.footnote))
            .foregroundStyle(Theme.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Theme.well, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
