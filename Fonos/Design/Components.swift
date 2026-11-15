import SwiftUI

// MARK: - Ground

/// The app background: warm porcelain that brightens toward the top edge.
struct GroundBackground: View {
    var body: some View {
        LinearGradient(colors: [Theme.groundHigh, Theme.ground], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.45))
            .ignoresSafeArea()
    }
}

extension View {
    /// Screen chrome shared by every tab: the porcelain ground behind the
    /// content and a matching navigation bar.
    func fonosScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background { GroundBackground() }
            .toolbarBackground(Theme.groundHigh, for: .navigationBar)
    }
}

// MARK: - Surface

/// A Fonos surface: white, a 1 pt warm edge, and a two-layer shadow (a tight
/// contact shadow and a wide, soft lift). In dark, tone alone separates it.
struct Surface: View {
    var radius: CGFloat = Theme.cardRadius
    var fill: Color = Theme.card
    var lift: CGFloat = 1

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape
            .fill(fill)
            .overlay(shape.strokeBorder(Theme.edge, lineWidth: 1))
            .shadow(color: Theme.shadow.opacity(0.05), radius: 1, y: 1)
            .shadow(color: Theme.shadow.opacity(0.07 * lift), radius: 18 * lift, y: 8 * lift)
    }
}

struct CardBackground: ViewModifier {
    var padding: CGFloat = 18
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { Surface() }
    }
}

extension View {
    func card(padding: CGFloat = 18) -> some View { modifier(CardBackground(padding: padding)) }
}

/// Apple Health–style card header: colored symbol and title, optional trailing detail and chevron.
struct CardHeader: View {
    let title: String
    let icon: Icon
    let color: Color
    /// Title color; defaults to `color`. Pass the `…Ink` shade so small text stays readable.
    var ink: Color? = nil
    var detail: String? = nil
    var chevron = false

    var body: some View {
        HStack(spacing: 8) {
            Label { Text(title).foregroundStyle(ink ?? color) } icon: {
                FonosIcon(icon, size: 16, relativeTo: .subheadline)
                    .foregroundStyle(color)
                    .padding(5)
                    .background(color.opacity(0.14), in: Circle())
            }
            .font(.ui(.subheadline, .bold))
            .labelStyle(.titleAndIcon)
            Spacer(minLength: 8)
            if let detail {
                Text(detail).font(.ui(.footnote)).foregroundStyle(Theme.inkTertiary)
            }
            if chevron {
                FonosIcon(.chevron, size: 13, relativeTo: .footnote)
                    .foregroundStyle(Theme.inkTertiary)
            }
        }
    }
}

// MARK: - Orb

/// A filled circle with a soft top-left sheen and a bright rim, the Fonos
/// treatment for the Speak button and the band's device badge.
struct Orb: View {
    let color: Color
    var glow: Bool = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Circle()
            .fill(color)
            .overlay(
                Circle().fill(LinearGradient(
                    colors: [.white.opacity(0.30), .white.opacity(0.0), .black.opacity(0.12)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(
                Circle().strokeBorder(LinearGradient(
                    colors: [.white.opacity(0.55), .white.opacity(0.0)],
                    startPoint: .top, endPoint: .center), lineWidth: 1.2)
            )
            .shadow(color: color.opacity(glow ? (scheme == .dark ? 0.28 : 0.34) : 0), radius: 22, y: 12)
    }
}

// MARK: - Segmented control

/// Fonos's own segmented control: a warm well with a raised thumb that glides
/// between options. Each option is a full-height button with the selected trait.
struct SegmentedPicker<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    var label = "Range"
    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let on = option == selection
                Button {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.32)) { selection = option }
                } label: {
                    Text(title(option))
                        .font(.ui(.subheadline, on ? .bold : .medium))
                        .foregroundStyle(on ? Theme.ink : Theme.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background {
                            if on {
                                Capsule()
                                    .fill(Theme.thumb)
                                    .shadow(color: Theme.shadow.opacity(0.12), radius: 6, y: 2)
                                    .matchedGeometryEffect(id: "thumb", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.well, in: Capsule())
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

// MARK: - Metric ring

/// WHOOP-style ring: a tinted track, a colored arc, and the value in Sora numerals.
struct MetricRing: View {
    let metric: Metric
    let value: Double?
    var diameter: CGFloat = 96
    var lineWidth: CGFloat = 9
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: Double = 0

    var body: some View {
        let fill = value.map(metric.ringFill) ?? 0
        ZStack {
            Circle().stroke(metric.color.opacity(0.14), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: drawn)
                .stroke(metric.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            valueText
        }
        .frame(width: diameter, height: diameter)
        .onAppear {
            if reduceMotion { drawn = fill } else {
                withAnimation(.smooth(duration: 1.0)) { drawn = fill }
            }
        }
        .onChange(of: fill) { _, new in
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.6)) { drawn = new }
        }
    }

    @ViewBuilder private var valueText: some View {
        if let value {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(metric.format(value))
                    .font(.metric(.title, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                if metric.unit == "%" {
                    Text("%").font(.metric(.footnote)).foregroundStyle(Theme.inkTertiary)
                }
            }
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            // The ring is a fixed size; numerals stop growing at xxxLarge.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .padding(.horizontal, lineWidth + 4)
        } else {
            Text("–").font(.metric(.title)).foregroundStyle(Theme.inkTertiary)
        }
    }
}

// MARK: - Status pill

struct StatusPill: View {
    let text: String
    let color: Color
    var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                if pulsing && !reduceMotion {
                    // A soft ripple leaving the dot while listening.
                    Circle().fill(color.opacity(0.35)).frame(width: 18, height: 18)
                        .phaseAnimator([false, true]) { ring, grow in
                            ring.scaleEffect(grow ? 1 : 0.45).opacity(grow ? 0 : 1)
                        } animation: { grow in
                            grow ? .easeOut(duration: 1.1) : nil
                        }
                } else {
                    Circle().fill(color.opacity(0.18)).frame(width: 16, height: 16)
                }
                Circle().fill(color).frame(width: 8, height: 8)
            }
            .frame(width: 18, height: 18)
            Text(text)
                .font(.metric(.caption, weight: .semibold))
                .textCase(.uppercase)
                .tracking(1.4)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .contentTransition(.opacity)
        }
        .padding(.leading, 10)
        .padding(.trailing, 14)
        .frame(minHeight: 34)
        .background {
            Capsule().fill(Theme.card)
                .overlay(Capsule().strokeBorder(Theme.edge, lineWidth: 1))
                .shadow(color: Theme.shadow.opacity(0.07), radius: 8, y: 3)
        }
        .animation(.smooth(duration: 0.3), value: text)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Battery

struct BatteryBadge: View {
    let percent: Int?
    var charging = false

    var body: some View {
        HStack(spacing: 5) {
            if let percent {
                Text("\(percent)%").font(.metric(.caption, weight: .semibold)).monospacedDigit()
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

/// Full-width secondary action: tracked caps on a well.
struct WellButtonStyle: ButtonStyle {
    var tint: Color = Theme.ink
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.metric(.subheadline, weight: .semibold))
            .textCase(.uppercase)
            .tracking(1.2)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Theme.well, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.smooth(duration: 0.18), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == WellButtonStyle {
    static var well: WellButtonStyle { WellButtonStyle() }
    static func well(_ tint: Color) -> WellButtonStyle { WellButtonStyle(tint: tint) }
}

/// A tappable surface (quick phrases, summary cards): settles in slightly
/// when pressed, so every tap is acknowledged without needing precision.
struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .brightness(configuration.isPressed ? -0.02 : 0)
            .animation(.smooth(duration: 0.18), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == TileButtonStyle {
    static var tile: TileButtonStyle { TileButtonStyle() }
}

/// Sample-data notice. Shown wherever toy data could be mistaken for a real measurement.
struct SampleBanner: View {
    var text = "Sample data. These numbers show what Fonos will look like with a real band."
    var body: some View {
        Label { Text(text) } icon: { FonosIcon(.info, size: 18, relativeTo: .footnote) }
            .font(.ui(.footnote))
            .foregroundStyle(Theme.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Theme.well.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
