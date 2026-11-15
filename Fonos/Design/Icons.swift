import SwiftUI

/// Fonos's own icon set (Resources/Assets.xcassets/Icons): 24 pt grid,
/// 1.8 pt rounded stroke, drawn from the product's motifs (rings, the
/// neck band, mirrored lobes for symmetry). Template images, so they take
/// the foreground color like text.
enum Icon: String {
    case speak, progress, band, settings
    case clarity, strength, pace, symmetry, variation, pauses
    case replay, stop, chevron, info, check, warning, plus
    case mic, piezoLeft, piezoRight, slow, fast, report

    var image: Image { Image("Icons/\(rawValue)") }
}

/// An icon that scales with Dynamic Type alongside the text it sits next to.
struct FonosIcon: View {
    let icon: Icon
    var size: CGFloat = 20
    var relativeTo: Font.TextStyle = .body
    @ScaledMetric private var scale: CGFloat = 1

    init(_ icon: Icon, size: CGFloat = 20, relativeTo: Font.TextStyle = .body) {
        self.icon = icon
        self.size = size
        self.relativeTo = relativeTo
        _scale = ScaledMetric(wrappedValue: 1, relativeTo: relativeTo)
    }

    var body: some View {
        icon.image
            .resizable()
            .scaledToFit()
            .frame(width: size * scale, height: size * scale)
            .accessibilityHidden(true)
    }
}

/// Filled status disc with a knocked-out check (template SVGs can't carry a cutout).
struct CheckDisc: View {
    var color: Color = Theme.good
    var size: CGFloat = 22
    @ScaledMetric private var scale: CGFloat = 1

    var body: some View {
        ZStack {
            Circle().fill(color)
            Icon.check.image.resizable().scaledToFit()
                .foregroundStyle(Theme.card)
                .padding(size * scale * 0.2)
        }
        .frame(width: size * scale, height: size * scale)
        .accessibilityHidden(true)
    }
}

/// Band battery drawn to match the icon stroke, with a proportional fill.
struct BatteryGlyph: View {
    let percent: Int?
    var color: Color
    @ScaledMetric(relativeTo: .footnote) private var w: CGFloat = 24

    var body: some View {
        let h = w * 0.5
        HStack(spacing: 1.5) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: h * 0.3, style: .continuous)
                    .stroke(color.opacity(0.6), lineWidth: 1.5)
                RoundedRectangle(cornerRadius: h * 0.18, style: .continuous)
                    .fill(color)
                    .frame(width: max(0, (w - 5) * CGFloat(percent ?? 0) / 100))
                    .padding(2.5)
            }
            .frame(width: w, height: h)
            RoundedRectangle(cornerRadius: 1).fill(color.opacity(0.6)).frame(width: 2, height: h * 0.4)
        }
        .accessibilityHidden(true)
    }
}
